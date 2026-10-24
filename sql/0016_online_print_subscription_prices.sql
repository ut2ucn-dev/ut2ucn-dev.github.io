-- Stage 16:
--   1. Online formats no longer split into "+друк"/"-друк". There is one
--      "Індив (online)" and one "Група (online)"; printing is a per-lesson
--      checkbox (lessons.print_enabled) that adds a print surcharge to the
--      client price only — never to the teacher's ЗП. The surcharge is the
--      lesson's own print_price if the admin typed one, else the course's
--      rate_cards.price_print_online, else 100 грн. A lesson paid by
--      subscription is unaffected: the subscription covers printing.
--   2. Subscription price per format (group / individual / individual
--      online / group online) instead of one per course.
--   3. Room "3D-майстерня" renamed to "Клас 3D".
--   4. A newly bought subscription is dated by the lesson it was bought on
--      (or a date the admin picks), not by when the button was pressed, and
--      records how it was paid (card / cash).
--
-- Run once in Supabase → SQL Editor, after 0001-0015. The whole script is
-- one transaction: if any statement fails, nothing is changed.

begin;

-- ---------------------------------------------------------------------
-- 1. Room rename.
-- ---------------------------------------------------------------------
alter table public.lessons drop constraint if exists lessons_room_check;
update public.lessons set room = 'Клас 3D' where room = '3D-майстерня';
alter table public.lessons
  add constraint lessons_room_check
  check (room is null or room in ('Клас AI', 'Клас VR', 'Комп''ютерний клас', 'Клас 3D'));

-- ---------------------------------------------------------------------
-- 2. Lessons: print flag + optional per-lesson price override, and the
--    four online formats collapsed into two.
--
--    The pricing trigger is disabled while existing rows are converted:
--    changing `format` would otherwise make it re-price every historical
--    online lesson. Their frozen payroll_amount / price_amount must stay
--    exactly as they are.
-- ---------------------------------------------------------------------
alter table public.lessons
  add column if not exists print_enabled boolean not null default false;
alter table public.lessons
  add column if not exists print_price numeric;
alter table public.lessons drop constraint if exists lessons_print_price_check;
alter table public.lessons
  add constraint lessons_print_price_check check (print_price is null or print_price >= 0);

alter table public.lessons drop constraint if exists lessons_format_check;
alter table public.lessons disable trigger trg_compute_lesson_amounts;

update public.lessons
  set print_enabled = (format in ('individual_online_print', 'group_online_print')),
      format = case
        when format in ('individual_online_print', 'individual_online_no_print') then 'individual_online'
        else 'group_online'
      end
  where format in ('individual_online_print', 'individual_online_no_print',
                   'group_online_print', 'group_online_no_print');

alter table public.lessons enable trigger trg_compute_lesson_amounts;
alter table public.lessons
  add constraint lessons_format_check
  check (format in ('group', 'individual', 'individual_online', 'group_online'));

-- ---------------------------------------------------------------------
-- 3. rate_cards: merged online columns, per-course print price, and the
--    four per-format subscription prices. New online rates start from the
--    old "-друк" rates (print is now a separate surcharge); every new
--    subscription price starts from the course's old single price, so
--    nothing changes until the admin edits them. The old columns are left
--    in place, unused, the same way 0002 left the original rate_* ones.
-- ---------------------------------------------------------------------
alter table public.rate_cards
  add column if not exists zp_individual_online numeric not null default 0,
  add column if not exists price_individual_online numeric not null default 0,
  add column if not exists zp_group_online numeric not null default 0,
  add column if not exists price_group_online numeric not null default 0,
  add column if not exists price_print_online numeric,
  add column if not exists price_sub_group numeric not null default 0,
  add column if not exists price_sub_individual numeric not null default 0,
  add column if not exists price_sub_individual_online numeric not null default 0,
  add column if not exists price_sub_group_online numeric not null default 0;

update public.rate_cards set
  zp_individual_online = case when zp_individual_online = 0 then coalesce(zp_individual_online_no_print, 0) else zp_individual_online end,
  price_individual_online = case when price_individual_online = 0 then coalesce(price_individual_online_no_print, 0) else price_individual_online end,
  zp_group_online = case when zp_group_online = 0 then coalesce(zp_group_online_no_print, 0) else zp_group_online end,
  price_group_online = case when price_group_online = 0 then coalesce(price_group_online_no_print, 0) else price_group_online end,
  price_sub_group = case when price_sub_group = 0 then coalesce(price_subscription, 0) else price_sub_group end,
  price_sub_individual = case when price_sub_individual = 0 then coalesce(price_subscription, 0) else price_sub_individual end,
  price_sub_individual_online = case when price_sub_individual_online = 0 then coalesce(price_subscription, 0) else price_sub_individual_online end,
  price_sub_group_online = case when price_sub_group_online = 0 then coalesce(price_subscription, 0) else price_sub_group_online end;

-- Teachers keep seeing zp_* only; every price is admin-only, as before.
drop view if exists public.rate_cards_safe;
create view public.rate_cards_safe as
select
  course,
  zp_group_1, zp_group_2_6, zp_individual, zp_individual_online, zp_group_online, zp_extra_service,
  case when is_admin() then price_group_1 end as price_group_1,
  case when is_admin() then price_group_2_6 end as price_group_2_6,
  case when is_admin() then price_individual end as price_individual,
  case when is_admin() then price_individual_online end as price_individual_online,
  case when is_admin() then price_group_online end as price_group_online,
  case when is_admin() then price_extra_service end as price_extra_service,
  case when is_admin() then price_print_online end as price_print_online,
  case when is_admin() then price_sub_group end as price_sub_group,
  case when is_admin() then price_sub_individual end as price_sub_individual,
  case when is_admin() then price_sub_individual_online end as price_sub_individual_online,
  case when is_admin() then price_sub_group_online end as price_sub_group_online
from public.rate_cards;
grant select on public.rate_cards_safe to authenticated;

-- print_enabled is visible to everyone (teachers need it for the print
-- queue); print_price is a client price, so admin-only like price_amount.
drop view if exists public.lessons_safe;
create view public.lessons_safe as
select
  id, owner_id, date, time, theme, course, format, student_ids,
  extra_service, series_id, payroll_amount,
  case when is_admin() then price_amount end as price_amount,
  duration_minutes, room, substitute_owner_id, completed,
  print_enabled,
  case when is_admin() then print_price end as print_price
from public.lessons;
grant select on public.lessons_safe to authenticated;

-- ---------------------------------------------------------------------
-- 4. Pricing trigger: new buckets + the print surcharge (client price
--    only). Same calc_start_date rule and same "only re-price when a
--    pricing input changed" rule as 0011.
-- ---------------------------------------------------------------------
create or replace function public.compute_lesson_amounts()
returns trigger
language plpgsql
security definer
as $function$
declare
  rc record;
  bucket text;
  student_count int;
  v_calc_start date;
  v_print numeric := 0;
begin
  select calc_start_date into v_calc_start from public.studio_settings limit 1;
  if v_calc_start is not null and new.date < v_calc_start then
    new.payroll_amount := 0;
    new.price_amount := 0;
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.course is not distinct from old.course
     and new.format is not distinct from old.format
     and new.student_ids is not distinct from old.student_ids
     and new.extra_service is not distinct from old.extra_service
     and new.print_enabled is not distinct from old.print_enabled
     and new.print_price is not distinct from old.print_price then
    new.payroll_amount := old.payroll_amount;
    new.price_amount := old.price_amount;
    return new;
  end if;

  student_count := coalesce(array_length(new.student_ids, 1), 0);

  bucket := case
    when new.format = 'individual' then 'individual'
    when new.format = 'individual_online' then 'individual_online'
    when new.format = 'group_online' then 'group_online'
    when student_count <= 1 then 'group_1'
    else 'group_2_6'
  end;

  select * into rc from public.rate_cards where course = new.course;

  if new.print_enabled and new.format in ('individual_online', 'group_online') then
    v_print := coalesce(new.print_price, rc.price_print_online, 100);
  end if;

  if rc is null then
    new.payroll_amount := 0;
    new.price_amount := v_print;
    return new;
  end if;

  new.payroll_amount := coalesce(
      case bucket
        when 'group_1' then rc.zp_group_1
        when 'group_2_6' then rc.zp_group_2_6
        when 'individual' then rc.zp_individual
        when 'individual_online' then rc.zp_individual_online
        when 'group_online' then rc.zp_group_online
      end, 0)
    + case when new.extra_service then coalesce(rc.zp_extra_service, 0) else 0 end;

  new.price_amount := coalesce(
      case bucket
        when 'group_1' then rc.price_group_1
        when 'group_2_6' then rc.price_group_2_6
        when 'individual' then rc.price_individual
        when 'individual_online' then rc.price_individual_online
        when 'group_online' then rc.price_group_online
      end, 0)
    + case when new.extra_service then coalesce(rc.price_extra_service, 0) else 0 end
    + v_print;

  return new;
end;
$function$;

drop trigger if exists trg_compute_lesson_amounts on public.lessons;
create trigger trg_compute_lesson_amounts
  before insert or update of course, format, student_ids, extra_service, print_enabled, print_price
  on public.lessons
  for each row
  execute function public.compute_lesson_amounts();

-- ---------------------------------------------------------------------
-- 5. set_lesson_print(): the lesson card's "друк" checkbox. Updates the
--    lesson (the trigger above re-prices it), then brings any already
--    recorded card/cash/certificate charge for that lesson in line with
--    the new price, keeping each student's discount. Subscription-paid
--    rows are left alone: the subscription covers printing.
--    Runs as the caller, so RLS decides who can actually change what.
-- ---------------------------------------------------------------------
create or replace function public.set_lesson_print(
  p_lesson_id uuid,
  p_enabled boolean,
  p_price numeric default null
)
returns void
language plpgsql
as $function$
begin
  if p_price is not null and p_price < 0 then
    raise exception 'invalid print price: %', p_price;
  end if;

  update public.lessons
    set print_enabled = coalesce(p_enabled, false),
        print_price = case when coalesce(p_enabled, false) then p_price else null end
    where id = p_lesson_id;

  update public.lesson_attendance la
    set amount = round(l.price_amount * (1 - la.discount_percent / 100.0), 2)
    from public.lessons l
    where l.id = la.lesson_id
      and la.lesson_id = p_lesson_id
      and la.status = 'present'
      and la.payment_method in ('card', 'cash', 'certificate');
end;
$function$;

grant execute on function public.set_lesson_print(uuid, boolean, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Subscriptions: how the package was paid for.
-- ---------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists payment_method text;
alter table public.subscriptions drop constraint if exists subscriptions_payment_method_check;
alter table public.subscriptions
  add constraint subscriptions_payment_method_check
  check (payment_method is null or payment_method in ('card', 'cash'));

-- ---------------------------------------------------------------------
-- 7. mark_attendance(): same rules as 0012, plus — when this lesson starts
--    a NEW subscription — its purchase date (default: this lesson's date)
--    and payment method, and the package price chosen by this lesson's
--    format. The older 4- and 5-argument versions are dropped so there is
--    exactly one function the app can call.
-- ---------------------------------------------------------------------
drop function if exists public.mark_attendance(uuid, uuid, text, text);
drop function if exists public.mark_attendance(uuid, uuid, text, text, numeric);

create or replace function public.mark_attendance(
  p_lesson_id uuid,
  p_student_id uuid,
  p_status text,
  p_payment_method text default null,
  p_discount_percent numeric default 0,
  p_purchase_date date default null,
  p_purchase_method text default null
)
returns public.lesson_attendance
language plpgsql
as $function$
declare
  v_lesson record;
  v_existing record;
  v_sub record;
  v_rc record;
  v_sub_price numeric;
  v_amount numeric := 0;
  v_discount numeric := coalesce(p_discount_percent, 0);
  v_subscription_id uuid := null;
  v_result public.lesson_attendance;
begin
  if p_status not in ('present', 'absent', 'excused') then
    raise exception 'invalid status: %', p_status;
  end if;
  if p_payment_method is not null and p_payment_method not in ('card', 'cash', 'subscription', 'certificate') then
    raise exception 'invalid payment method: %', p_payment_method;
  end if;
  if p_purchase_method is not null and p_purchase_method not in ('card', 'cash') then
    raise exception 'invalid subscription payment method: %', p_purchase_method;
  end if;
  if v_discount < 0 or v_discount > 100 then
    raise exception 'invalid discount percent: %', v_discount;
  end if;

  select * into v_lesson from public.lessons where id = p_lesson_id;
  if not found then
    raise exception 'lesson not found';
  end if;

  select * into v_existing from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id
    for update;

  if v_existing is not null and v_existing.subscription_id is not null
     and v_existing.status <> 'absent' then
    update public.subscriptions
      set remaining_lessons = remaining_lessons + 1,
          status = 'active'
      where id = v_existing.subscription_id;
  end if;

  if p_status = 'present' then
    v_amount := coalesce(v_lesson.price_amount, 0);
    if p_payment_method = 'subscription' then
      select * into v_sub from public.subscriptions
        where student_id = p_student_id and course = v_lesson.course
          and status = 'active' and remaining_lessons > 0
        order by purchased_at asc
        limit 1
        for update;
      if not found then
        select * into v_rc from public.rate_cards where course = v_lesson.course;
        if found then
          v_sub_price := case v_lesson.format
            when 'group' then v_rc.price_sub_group
            when 'individual' then v_rc.price_sub_individual
            when 'individual_online' then v_rc.price_sub_individual_online
            when 'group_online' then v_rc.price_sub_group_online
          end;
          v_sub_price := coalesce(nullif(v_sub_price, 0), v_rc.price_subscription, 0);
        end if;
        insert into public.subscriptions (
          student_id, course, total_lessons, remaining_lessons, total_price,
          purchased_by, purchased_at, payment_method
        ) values (
          p_student_id, v_lesson.course, 4, 4, coalesce(v_sub_price, 0),
          auth.uid(),
          coalesce(p_purchase_date, v_lesson.date)::timestamp at time zone 'UTC',
          p_purchase_method
        )
        returning * into v_sub;
      end if;
      update public.subscriptions
        set remaining_lessons = v_sub.remaining_lessons - 1,
            status = case when v_sub.remaining_lessons - 1 <= 0 then 'completed' else 'active' end
        where id = v_sub.id;
      v_subscription_id := v_sub.id;
      if v_sub.total_price > 0 and v_sub.total_lessons > 0 then
        v_amount := round(v_sub.total_price / v_sub.total_lessons, 2);
      end if;
    end if;
    v_amount := round(v_amount * (1 - v_discount / 100.0), 2);
  else
    v_amount := 0;
    v_discount := 0;
    p_payment_method := null;
  end if;

  insert into public.lesson_attendance (
    lesson_id, student_id, owner_id, status, payment_method, amount, discount_percent, subscription_id, marked_by, marked_at
  ) values (
    p_lesson_id, p_student_id, v_lesson.owner_id, p_status, p_payment_method, v_amount, v_discount, v_subscription_id, auth.uid(), now()
  )
  on conflict (lesson_id, student_id) do update set
    status = excluded.status,
    payment_method = excluded.payment_method,
    amount = excluded.amount,
    discount_percent = excluded.discount_percent,
    subscription_id = excluded.subscription_id,
    marked_by = excluded.marked_by,
    marked_at = excluded.marked_at;

  select * into v_result from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id;

  return v_result;
end;
$function$;

grant execute on function public.mark_attendance(uuid, uuid, text, text, numeric, date, text) to authenticated;

commit;

notify pgrst, 'reload schema';
