-- Stage 18: the parents' portal (client/ on the site, "Батьки" in the app).
--
-- Parents are NOT Supabase Auth users. A parent account is a phone number
-- plus a password the superadmin generates; the parent signs in with
-- parent_login(), gets back a random session token, and every read goes
-- through parent_portal(token). All of it is security definer and returns
-- only that parent's own children — the anon key alone never reaches a
-- table: the three new tables have RLS on, and the two that hold secrets
-- (credentials, sessions) have no policies at all.
--
--   parent_accounts     — one per phone; superadmin manages (RLS)
--   parent_students     — which children each account sees; linked by hand
--                         by the superadmin (RLS), never matched by phone
--   parent_credentials  — bcrypt hash + lockout counters (no policies)
--   parent_sessions     — sha256 of each issued token (no policies)
--
-- Run once in Supabase → SQL Editor, after 0001-0017. One transaction.

begin;

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Phone numbers: stored as digits only, Ukrainian numbers always with
--    the 380 prefix, so "067 123 45 67", "+380671234567" and
--    "380 (67) 123-45-67" are the same login.
-- ---------------------------------------------------------------------
create or replace function public.parent_normalize_phone(p_phone text)
returns text
language sql
immutable
as $function$
  select case
    when d ~ '^0\d{9}$' then '38' || d
    when d ~ '^\d{9}$' then '380' || d
    when d ~ '^80\d{9}$' then '3' || d
    else d
  end
  from (select regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') as d) x;
$function$;

-- ---------------------------------------------------------------------
-- 2. Tables.
-- ---------------------------------------------------------------------
create table if not exists public.parent_accounts (
  id uuid primary key default gen_random_uuid(),
  phone text not null unique,
  name text,
  active boolean not null default true,
  password_set_at timestamptz,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

alter table public.parent_accounts drop constraint if exists parent_accounts_phone_check;
alter table public.parent_accounts
  add constraint parent_accounts_phone_check check (phone ~ '^\d{10,15}$');

create or replace function public.parent_accounts_normalize()
returns trigger
language plpgsql
as $function$
begin
  new.phone := public.parent_normalize_phone(new.phone);
  new.name := nullif(btrim(coalesce(new.name, '')), '');
  return new;
end;
$function$;

drop trigger if exists trg_parent_accounts_normalize on public.parent_accounts;
create trigger trg_parent_accounts_normalize
  before insert or update of phone, name on public.parent_accounts
  for each row execute function public.parent_accounts_normalize();

create table if not exists public.parent_students (
  parent_id uuid not null references public.parent_accounts(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (parent_id, student_id)
);
create index if not exists parent_students_student_idx on public.parent_students(student_id);

create table if not exists public.parent_credentials (
  parent_id uuid primary key references public.parent_accounts(id) on delete cascade,
  password_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz
);

create table if not exists public.parent_sessions (
  token_hash text primary key,
  parent_id uuid not null references public.parent_accounts(id) on delete cascade,
  client text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists parent_sessions_parent_idx on public.parent_sessions(parent_id);

alter table public.parent_accounts enable row level security;
alter table public.parent_students enable row level security;
alter table public.parent_credentials enable row level security;
alter table public.parent_sessions enable row level security;

drop policy if exists parent_accounts_superadmin on public.parent_accounts;
create policy parent_accounts_superadmin on public.parent_accounts
  for all to authenticated using (is_superadmin()) with check (is_superadmin());

drop policy if exists parent_students_superadmin on public.parent_students;
create policy parent_students_superadmin on public.parent_students
  for all to authenticated using (is_superadmin()) with check (is_superadmin());

revoke all on public.parent_credentials from anon, authenticated;
revoke all on public.parent_sessions from anon, authenticated;
revoke all on public.parent_accounts from anon;
revoke all on public.parent_students from anon;
grant select, insert, update, delete on public.parent_accounts to authenticated;
grant select, insert, delete on public.parent_students to authenticated;

-- ---------------------------------------------------------------------
-- 3. Passwords. 8 characters from an alphabet without look-alikes
--    (no 0/O, 1/l/I), easy to dictate over the phone.
-- ---------------------------------------------------------------------
create or replace function public.parent_generate_password()
returns text
language plpgsql
volatile
as $function$
declare
  v_alphabet constant text := 'abcdefghjkmnpqrstuvwxyz23456789';
  v_bytes bytea := extensions.gen_random_bytes(8);
  v_out text := '';
begin
  for i in 0..7 loop
    v_out := v_out || substr(v_alphabet, 1 + (get_byte(v_bytes, i) % length(v_alphabet)), 1);
  end loop;
  return v_out;
end;
$function$;

-- Sets a fresh password and signs the account out everywhere. Internal:
-- callers check is_superadmin() first.
create or replace function public.parent_reset_credentials(p_parent_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_password text := public.parent_generate_password();
begin
  insert into public.parent_credentials (parent_id, password_hash)
    values (p_parent_id, extensions.crypt(v_password, extensions.gen_salt('bf', 8)))
  on conflict (parent_id) do update set
    password_hash = excluded.password_hash,
    failed_attempts = 0,
    locked_until = null;
  delete from public.parent_sessions where parent_id = p_parent_id;
  update public.parent_accounts set password_set_at = now() where id = p_parent_id;
  return v_password;
end;
$function$;

revoke execute on function public.parent_reset_credentials(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Superadmin RPCs. Each returns the new plain-text password exactly
--    once; only its bcrypt hash is stored.
-- ---------------------------------------------------------------------

-- "Батьки" section: new account with the children ticked in the form.
create or replace function public.parent_create_account(
  p_phone text,
  p_name text default null,
  p_student_ids uuid[] default '{}'
)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_phone text := public.parent_normalize_phone(p_phone);
  v_id uuid;
begin
  if not is_superadmin() then
    raise exception 'Лише суперадмін може керувати кабінетами батьків';
  end if;
  if v_phone !~ '^\d{10,15}$' then
    raise exception 'Невірний номер телефону';
  end if;
  if exists (select 1 from public.parent_accounts where phone = v_phone) then
    raise exception 'Кабінет для номера % уже існує', v_phone;
  end if;

  insert into public.parent_accounts (phone, name) values (v_phone, p_name)
    returning id into v_id;
  insert into public.parent_students (parent_id, student_id)
    select v_id, s from unnest(coalesce(p_student_ids, '{}')) s
    on conflict do nothing;

  return json_build_object('id', v_id, 'phone', v_phone, 'password', public.parent_reset_credentials(v_id));
end;
$function$;

create or replace function public.parent_reset_password(p_parent_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_acc record;
begin
  if not is_superadmin() then
    raise exception 'Лише суперадмін може керувати кабінетами батьків';
  end if;
  select * into v_acc from public.parent_accounts where id = p_parent_id;
  if not found then
    raise exception 'Кабінет не знайдено';
  end if;
  return json_build_object('id', v_acc.id, 'phone', v_acc.phone, 'name', v_acc.name,
    'password', public.parent_reset_credentials(v_acc.id));
end;
$function$;

-- Student card: "Згенерувати пароль". Uses the account for the phone in
-- the student's card, creating it (named after the parents in the card)
-- if there is none yet, and links this student to it. Other children are
-- added to the same account by hand in the "Батьки" section.
create or replace function public.parent_password_for_student(p_student_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_student record;
  v_phone text;
  v_id uuid;
  v_created boolean := false;
begin
  if not is_superadmin() then
    raise exception 'Лише суперадмін може керувати кабінетами батьків';
  end if;
  select * into v_student from public.students where id = p_student_id;
  if not found then
    raise exception 'Учня не знайдено';
  end if;
  v_phone := public.parent_normalize_phone(v_student.phone);
  if v_phone !~ '^\d{10,15}$' then
    raise exception 'У картці учня не вказано коректний телефон батьків';
  end if;

  select id into v_id from public.parent_accounts where phone = v_phone;
  if v_id is null then
    insert into public.parent_accounts (phone, name)
      values (v_phone, nullif(btrim(concat_ws(' ', v_student.parent_last_name, v_student.parent_first_name)), ''))
      returning id into v_id;
    v_created := true;
  end if;
  insert into public.parent_students (parent_id, student_id) values (v_id, p_student_id)
    on conflict do nothing;

  return json_build_object('id', v_id, 'phone', v_phone, 'created', v_created,
    'password', public.parent_reset_credentials(v_id));
end;
$function$;

revoke execute on function public.parent_create_account(text, text, uuid[]) from public, anon;
revoke execute on function public.parent_reset_password(uuid) from public, anon;
revoke execute on function public.parent_password_for_student(uuid) from public, anon;
grant execute on function public.parent_create_account(text, text, uuid[]) to authenticated;
grant execute on function public.parent_reset_password(uuid) to authenticated;
grant execute on function public.parent_password_for_student(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Parent sign-in. Callable with just the anon key. Returns {token, …}
--    or {error}. Ten wrong passwords in a row lock the account for 15
--    minutes. The error never says whether the phone exists.
-- ---------------------------------------------------------------------
create or replace function public.parent_login(
  p_phone text,
  p_password text,
  p_client text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_acc record;
  v_cred record;
  v_token text;
  v_expires timestamptz := now() + interval '180 days';
begin
  select * into v_acc from public.parent_accounts
    where phone = public.parent_normalize_phone(p_phone);
  if found then
    select * into v_cred from public.parent_credentials where parent_id = v_acc.id for update;
  end if;

  if v_acc.id is null or v_cred.parent_id is null or not v_acc.active then
    perform extensions.crypt(coalesce(p_password, ''), extensions.gen_salt('bf', 8));
    return json_build_object('error', 'Невірний телефон або пароль');
  end if;

  if v_cred.locked_until is not null and v_cred.locked_until > now() then
    return json_build_object('error', format('Забагато невдалих спроб. Спробуйте через %s хв',
      greatest(1, ceil(extract(epoch from v_cred.locked_until - now()) / 60)::int)));
  end if;

  if v_cred.password_hash <> extensions.crypt(coalesce(p_password, ''), v_cred.password_hash) then
    -- Returned, not raised: an exception would roll the counter back.
    update public.parent_credentials
      set failed_attempts = case when v_cred.failed_attempts + 1 >= 10 then 0 else v_cred.failed_attempts + 1 end,
          locked_until = case when v_cred.failed_attempts + 1 >= 10 then now() + interval '15 minutes' else null end
      where parent_id = v_acc.id;
    return json_build_object('error', 'Невірний телефон або пароль');
  end if;

  update public.parent_credentials set failed_attempts = 0, locked_until = null where parent_id = v_acc.id;
  update public.parent_accounts set last_login_at = now() where id = v_acc.id;
  delete from public.parent_sessions where parent_id = v_acc.id and expires_at < now();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.parent_sessions (token_hash, parent_id, client, expires_at)
    values (encode(extensions.digest(v_token, 'sha256'), 'hex'), v_acc.id, left(p_client, 40), v_expires);

  return json_build_object('token', v_token, 'expires_at', v_expires,
    'parent', json_build_object('name', v_acc.name, 'phone', v_acc.phone));
end;
$function$;

-- The account behind a token, or null. Extends the session on use.
create or replace function public.parent_session_account(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_parent uuid;
begin
  if p_token is null or length(p_token) < 32 then
    return null;
  end if;
  update public.parent_sessions s
    set last_seen_at = now(),
        expires_at = greatest(s.expires_at, now() + interval '180 days')
    from public.parent_accounts a
    where s.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and s.expires_at > now()
      and a.id = s.parent_id and a.active
    returning s.parent_id into v_parent;
  return v_parent;
end;
$function$;

revoke execute on function public.parent_session_account(text) from public, anon, authenticated;

create or replace function public.parent_logout(p_token text)
returns void
language sql
security definer
set search_path = public
as $function$
  delete from public.parent_sessions
    where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$function$;

-- ---------------------------------------------------------------------
-- 6. parent_portal(token): everything the portal shows, as one JSON
--    document, for this parent's children only. Same money rules as the
--    studio report (sql/0017): a lesson is unpaid when the child was
--    present and no payment was recorded; what's owed is the lesson price
--    plus that child's print surcharge. Teacher pay is never included.
-- ---------------------------------------------------------------------
create or replace function public.parent_portal(p_token text)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_parent uuid := public.parent_session_account(p_token);
  v_acc record;
  v_result json;
begin
  if v_parent is null then
    raise exception 'session_expired' using errcode = 'P0001', hint = 'Увійдіть знову';
  end if;
  select * into v_acc from public.parent_accounts where id = v_parent;

  select json_build_object(
    'parent', json_build_object('name', v_acc.name, 'phone', v_acc.phone),
    'generated_at', now(),
    'today', (now() at time zone 'Europe/Kyiv')::date,
    'payments_enabled', false,
    'students', coalesce((
      select json_agg(st order by st->>'name')
      from (
        select json_build_object(
          'id', s.id,
          'name', s.name,
          'photo', s.photo,
          'birthday', s.birthday,
          'lessons', coalesce((
            select json_agg(json_build_object(
              'id', l.id,
              'date', l.date,
              'time', l.time,
              'duration_minutes', l.duration_minutes,
              'course', l.course,
              'format', l.format,
              'theme', l.theme,
              'room', l.room,
              'teacher', nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
              'status', la.status,
              'payment_method', la.payment_method,
              'amount', case when la.payment_method is not null then la.amount end,
              'due', case when la.status = 'present' and la.payment_method is null then
                  coalesce(l.price_amount, 0)
                  + case when la.print_enabled then public.lesson_print_surcharge(l.id, la.print_price) else 0 end
                end,
              'print_enabled', coalesce(la.print_enabled, false),
              'trial', coalesce(w.trial, false),
              'subscription_id', la.subscription_id
            ) order by l.date desc, l.time desc nulls last)
            from public.lessons l
            left join public.lesson_attendance la on la.lesson_id = l.id and la.student_id = s.id
            left join public.works w on w.lesson_id = l.id and w.student_id = s.id
            left join public.profiles p on p.id = coalesce(l.substitute_owner_id, l.owner_id)
            where s.id = any(l.student_ids)
          ), '[]'::json),
          'works', coalesce((
            select json_agg(json_build_object(
              'lesson_id', w.lesson_id,
              'date', l.date,
              'course', l.course,
              'format', l.format,
              'theme', l.theme,
              'photo', w.photo,
              'printed', coalesce(w.printed, false),
              'trial', coalesce(w.trial, false),
              'print_enabled', coalesce(la.print_enabled, false)
            ) order by l.date desc)
            from public.works w
            join public.lessons l on l.id = w.lesson_id
            left join public.lesson_attendance la on la.lesson_id = w.lesson_id and la.student_id = s.id
            where w.student_id = s.id
          ), '[]'::json),
          'subscriptions', coalesce((
            select json_agg(json_build_object(
              'id', sub.id,
              'course', sub.course,
              'total_lessons', sub.total_lessons,
              'remaining_lessons', sub.remaining_lessons,
              'total_price', sub.total_price,
              'status', sub.status,
              'purchased_at', sub.purchased_at,
              'payment_method', sub.payment_method
            ) order by sub.purchased_at desc)
            from public.subscriptions sub
            where sub.student_id = s.id
          ), '[]'::json)
        ) as st
        from public.parent_students ps
        join public.students s on s.id = ps.student_id
        where ps.parent_id = v_parent
      ) x
    ), '[]'::json)
  ) into v_result;

  return v_result;
end;
$function$;

revoke execute on function public.parent_login(text, text, text) from public;
revoke execute on function public.parent_logout(text) from public;
revoke execute on function public.parent_portal(text) from public;
grant execute on function public.parent_login(text, text, text) to anon, authenticated;
grant execute on function public.parent_logout(text) to anon, authenticated;
grant execute on function public.parent_portal(text) to anon, authenticated;

commit;

notify pgrst, 'reload schema';
