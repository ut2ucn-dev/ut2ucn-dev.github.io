--
-- PostgreSQL database dump
--

\restrict z3IzcRNRmS9YLgUswUJXXTfyUgMUKhb4o916hdVU3yCkD6OPDH9Rac5ERK7MgjL

-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: apply_lesson_print_default(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_lesson_print_default() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  r record;
begin
  if new.format not in ('individual_online', 'group_online') then
    return new;
  end if;
  for r in
    select student_id from public.lesson_attendance
    where lesson_id = new.id and status = 'present' and print_enabled is distinct from new.print_default
  loop
    perform public.set_attendance_print(new.id, r.student_id, new.print_default, null);
  end loop;
  return new;
end;
$$;


--
-- Name: cleanup_deleted_student_from_lessons(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_deleted_student_from_lessons() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  update public.lessons
    set student_ids = array_remove(student_ids, old.id)
    where date >= current_date
      and old.id = any(student_ids);
  return old;
end;
$$;


--
-- Name: compute_lesson_amounts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_lesson_amounts() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  rc record;
  bucket text;
  student_count int;
  v_calc_start date;
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
     and new.extra_service is not distinct from old.extra_service then
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

  if rc is null then
    new.payroll_amount := 0;
    new.price_amount := 0;
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
    + case when new.extra_service then coalesce(rc.price_extra_service, 0) else 0 end;

  return new;
end;
$$;


--
-- Name: compute_work_cost(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_work_cost() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_printer record;
  v_price_per_kg numeric;
  v_tariff numeric;
  v_waste numeric;
  v_hours numeric;
  v_material numeric;
  v_electricity numeric;
  v_depreciation numeric;
begin
  if tg_op = 'UPDATE'
     and new.weight_g is not distinct from old.weight_g
     and new.print_minutes is not distinct from old.print_minutes
     and new.printer_id is not distinct from old.printer_id
     and new.filament_id is not distinct from old.filament_id then
    return new;
  end if;

  if new.weight_g is null and new.print_minutes is null then
    delete from public.work_costs where work_id = new.id;
    return new;
  end if;

  select power_watts, depreciation_per_hour into v_printer from public.printers where id = new.printer_id;
  select price_per_kg into v_price_per_kg from public.filaments where id = new.filament_id;
  select electricity_tariff, filament_waste_percent into v_tariff, v_waste from public.studio_settings limit 1;

  v_waste := coalesce(v_waste, 0);
  v_hours := coalesce(new.print_minutes, 0) / 60.0;
  v_material := round(coalesce(new.weight_g, 0) * (1 + v_waste / 100.0) * coalesce(v_price_per_kg, 0) / 1000.0, 2);
  v_electricity := round(v_hours * coalesce(v_printer.power_watts, 0) / 1000.0 * coalesce(v_tariff, 0), 2);
  v_depreciation := round(v_hours * coalesce(v_printer.depreciation_per_hour, 0), 2);

  insert into public.work_costs (
    work_id, weight_g, waste_percent, price_per_kg, print_minutes, power_watts, electricity_tariff,
    depreciation_per_hour, material_cost, electricity_cost, depreciation_cost, total_cost, computed_at
  ) values (
    new.id, new.weight_g, v_waste, v_price_per_kg, new.print_minutes, v_printer.power_watts, v_tariff,
    v_printer.depreciation_per_hour, v_material, v_electricity, v_depreciation,
    v_material + v_electricity + v_depreciation, now()
  )
  on conflict (work_id) do update set
    weight_g = excluded.weight_g,
    waste_percent = excluded.waste_percent,
    price_per_kg = excluded.price_per_kg,
    print_minutes = excluded.print_minutes,
    power_watts = excluded.power_watts,
    electricity_tariff = excluded.electricity_tariff,
    depreciation_per_hour = excluded.depreciation_per_hour,
    material_cost = excluded.material_cost,
    electricity_cost = excluded.electricity_cost,
    depreciation_cost = excluded.depreciation_cost,
    total_cost = excluded.total_cost,
    computed_at = excluded.computed_at;

  return new;
end;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'superadmin'))
$$;


--
-- Name: is_superadmin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_superadmin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'superadmin'
  );
$$;


--
-- Name: lesson_print_surcharge(uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
declare
  v_lesson record;
  v_calc_start date;
  v_course_price numeric;
begin
  select date, course, format into v_lesson from public.lessons where id = p_lesson_id;
  if not found or v_lesson.format not in ('individual_online', 'group_online') then
    return 0;
  end if;
  select calc_start_date into v_calc_start from public.studio_settings limit 1;
  if v_calc_start is not null and v_lesson.date < v_calc_start then
    return 0;
  end if;
  select price_print_online into v_course_price from public.rate_cards where course = v_lesson.course;
  return coalesce(p_price, v_course_price, 100);
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: lesson_attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lesson_attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lesson_id uuid NOT NULL,
    student_id uuid NOT NULL,
    owner_id uuid,
    status text NOT NULL,
    payment_method text,
    amount numeric DEFAULT 0 NOT NULL,
    subscription_id uuid,
    marked_by uuid,
    marked_at timestamp with time zone DEFAULT now() NOT NULL,
    discount_percent numeric DEFAULT 0 NOT NULL,
    print_enabled boolean DEFAULT false NOT NULL,
    print_price numeric,
    CONSTRAINT lesson_attendance_discount_percent_check CHECK (((discount_percent >= (0)::numeric) AND (discount_percent <= (100)::numeric))),
    CONSTRAINT lesson_attendance_payment_method_check CHECK ((payment_method = ANY (ARRAY['card'::text, 'cash'::text, 'subscription'::text, 'certificate'::text]))),
    CONSTRAINT lesson_attendance_print_price_check CHECK (((print_price IS NULL) OR (print_price >= (0)::numeric))),
    CONSTRAINT lesson_attendance_status_check CHECK ((status = ANY (ARRAY['present'::text, 'absent'::text, 'excused'::text])))
);


--
-- Name: mark_attendance(uuid, uuid, text, text, numeric, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text DEFAULT NULL::text, p_discount_percent numeric DEFAULT 0, p_purchase_date date DEFAULT NULL::date, p_purchase_method text DEFAULT NULL::text) RETURNS public.lesson_attendance
    LANGUAGE plpgsql
    AS $$
declare
  v_lesson record;
  v_existing record;
  v_sub record;
  v_rc record;
  v_sub_price numeric;
  v_amount numeric := 0;
  v_discount numeric := coalesce(p_discount_percent, 0);
  v_subscription_id uuid := null;
  v_print boolean;
  v_print_price numeric;
  v_new_present boolean;
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

  -- The child's print: their own while they stay "П", otherwise the
  -- lesson's "+ друк" (online formats only).
  v_new_present := p_status = 'present' and (v_existing is null or v_existing.status <> 'present');
  if v_new_present then
    v_print := v_lesson.print_default and v_lesson.format in ('individual_online', 'group_online');
    v_print_price := null;
  else
    v_print := coalesce(v_existing.print_enabled, false);
    v_print_price := v_existing.print_price;
  end if;

  if p_status = 'present' then
    v_amount := coalesce(v_lesson.price_amount, 0);
    if v_print then
      v_amount := v_amount + public.lesson_print_surcharge(p_lesson_id, v_print_price);
    end if;
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
    lesson_id, student_id, owner_id, status, payment_method, amount, discount_percent, subscription_id,
    marked_by, marked_at, print_enabled, print_price
  ) values (
    p_lesson_id, p_student_id, v_lesson.owner_id, p_status, p_payment_method, v_amount, v_discount, v_subscription_id,
    auth.uid(), now(), v_print, v_print_price
  )
  on conflict (lesson_id, student_id) do update set
    status = excluded.status,
    payment_method = excluded.payment_method,
    amount = excluded.amount,
    discount_percent = excluded.discount_percent,
    subscription_id = excluded.subscription_id,
    marked_by = excluded.marked_by,
    marked_at = excluded.marked_at,
    print_enabled = case when v_new_present then excluded.print_enabled else lesson_attendance.print_enabled end,
    print_price = case when v_new_present then excluded.print_price else lesson_attendance.print_price end;

  select * into v_result from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id;

  return v_result;
end;
$$;


--
-- Name: my_taught_student_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_taught_student_ids() RETURNS uuid[]
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  select coalesce(array_agg(distinct sid), '{}'::uuid[])
  from public.lessons l, unnest(l.student_ids) as sid
  where l.owner_id = auth.uid();
$$;


--
-- Name: parent_accounts_normalize(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_accounts_normalize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.phone := public.parent_normalize_phone(new.phone);
  new.name := nullif(btrim(coalesce(new.name, '')), '');
  return new;
end;
$$;


--
-- Name: parent_create_account(text, text, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_create_account(p_phone text, p_name text DEFAULT NULL::text, p_student_ids uuid[] DEFAULT '{}'::uuid[]) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;


--
-- Name: parent_generate_password(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_generate_password() RETURNS text
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: parent_login(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_login(p_phone text, p_password text, p_client text DEFAULT NULL::text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: parent_logout(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_logout(p_token text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  delete from public.parent_sessions
    where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;


--
-- Name: parent_normalize_phone(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_normalize_phone(p_phone text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when d ~ '^0\d{9}$' then '38' || d
    when d ~ '^\d{9}$' then '380' || d
    when d ~ '^80\d{9}$' then '3' || d
    else d
  end
  from (select regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') as d) x;
$_$;


--
-- Name: parent_password_for_student(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_password_for_student(p_student_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;


--
-- Name: parent_portal(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_portal(p_token text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: parent_reset_credentials(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_reset_credentials(p_parent_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: parent_reset_password(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_reset_password(p_parent_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: parent_session_account(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.parent_session_account(p_token text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: set_attendance_print(uuid, uuid, boolean, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric DEFAULT NULL::numeric) RETURNS public.lesson_attendance
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
  v_result public.lesson_attendance;
begin
  if p_price is not null and p_price < 0 then
    raise exception 'invalid print price: %', p_price;
  end if;

  update public.lesson_attendance
    set print_enabled = coalesce(p_enabled, false),
        print_price = case when coalesce(p_enabled, false) then p_price else null end
    where lesson_id = p_lesson_id and student_id = p_student_id and status = 'present'
    returning id into v_id;

  if v_id is null then
    raise exception 'Спочатку позначте учня присутнім (П)';
  end if;

  update public.lesson_attendance la
    set amount = round(
          (l.price_amount
            + case when la.print_enabled then public.lesson_print_surcharge(l.id, la.print_price) else 0 end)
          * (1 - la.discount_percent / 100.0), 2)
    from public.lessons l
    where l.id = la.lesson_id
      and la.id = v_id
      and la.payment_method in ('card', 'cash', 'certificate');

  select * into v_result from public.lesson_attendance where id = v_id;
  return v_result;
end;
$$;


--
-- Name: set_calc_start_date(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_calc_start_date(p_date date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if not is_superadmin() then
    raise exception 'Лише суперадміністратор може змінювати цю дату.';
  end if;

  update public.studio_settings
    set calc_start_date = p_date,
        updated_at = now(),
        updated_by = auth.uid()
    where id = true;

  if p_date is not null then
    update public.lessons
      set payroll_amount = 0, price_amount = 0
      where date < p_date
        and (payroll_amount <> 0 or price_amount <> 0);
  end if;
end;
$$;


--
-- Name: set_print_cost_settings(numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if not is_admin() then
    raise exception 'Лише адміністратор може змінювати ці налаштування.';
  end if;
  update public.studio_settings
    set electricity_tariff = coalesce(p_tariff, 0),
        filament_waste_percent = coalesce(p_waste_percent, 0),
        updated_at = now(),
        updated_by = auth.uid()
    where id = true;
end;
$$;


--
-- Name: studio_report_summary(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.studio_report_summary(p_from date, p_to date) RETURNS TABLE(paid_total numeric, paid_count integer, debt_total numeric, debt_count integer, unused_subscription_lessons integer, unused_subscription_count integer, unused_excused_total numeric, unused_excused_count integer)
    LANGUAGE plpgsql STABLE
    AS $$
begin
  if not is_superadmin() then
    paid_total := 0;
    paid_count := 0;
    debt_total := 0;
    debt_count := 0;
    unused_subscription_lessons := 0;
    unused_subscription_count := 0;
    unused_excused_total := 0;
    unused_excused_count := 0;
    return next;
    return;
  end if;

  select coalesce(sum(p.amount), 0), count(p.id)
    into paid_total, paid_count
    from public.report_paid p
    where p.lesson_date between p_from and p_to;

  select coalesce(sum(d.price_amount), 0), count(d.id)
    into debt_total, debt_count
    from public.report_debt d
    where d.lesson_date between p_from and p_to;

  select coalesce(sum(u.remaining_lessons), 0), count(u.subscription_id)
    into unused_subscription_lessons, unused_subscription_count
    from public.report_unused_subscriptions u;

  select coalesce(sum(e.amount), 0), count(e.id)
    into unused_excused_total, unused_excused_count
    from public.report_unused_excused e;

  return next;
end;
$$;


--
-- Name: unmark_attendance(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  v_existing record;
begin
  select * into v_existing from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id
    for update;

  if not found then
    return;
  end if;

  if v_existing.subscription_id is not null and v_existing.status <> 'absent' then
    update public.subscriptions
      set remaining_lessons = remaining_lessons + 1,
          status = 'active'
      where id = v_existing.subscription_id;
  end if;

  delete from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id;
end;
$$;


--
-- Name: filaments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.filaments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    material text NOT NULL,
    color text,
    price_per_kg numeric DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT filaments_price_per_kg_check CHECK ((price_per_kg >= (0)::numeric))
);


--
-- Name: filaments_safe; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.filaments_safe AS
 SELECT id,
    material,
    color,
    active,
    created_at,
        CASE
            WHEN public.is_admin() THEN price_per_kg
            ELSE NULL::numeric
        END AS price_per_kg
   FROM public.filaments;


--
-- Name: lessons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lessons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid NOT NULL,
    series_id uuid,
    date date NOT NULL,
    "time" time without time zone,
    theme text,
    course text,
    format text DEFAULT 'group'::text NOT NULL,
    student_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    extra_service boolean DEFAULT false NOT NULL,
    payroll_amount numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    price_amount numeric DEFAULT 0 NOT NULL,
    duration_minutes integer DEFAULT 60 NOT NULL,
    room text,
    substitute_owner_id uuid,
    completed boolean DEFAULT false NOT NULL,
    print_default boolean DEFAULT false NOT NULL,
    CONSTRAINT lessons_format_check CHECK ((format = ANY (ARRAY['group'::text, 'individual'::text, 'individual_online'::text, 'group_online'::text]))),
    CONSTRAINT lessons_room_check CHECK (((room IS NULL) OR (room = ANY (ARRAY['Клас AI'::text, 'Клас VR'::text, 'Комп''ютерний клас'::text, 'Клас 3D'::text]))))
);


--
-- Name: lessons_safe; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.lessons_safe AS
 SELECT id,
    owner_id,
    date,
    "time",
    theme,
    course,
    format,
    student_ids,
    extra_service,
    series_id,
    payroll_amount,
        CASE
            WHEN public.is_admin() THEN price_amount
            ELSE NULL::numeric
        END AS price_amount,
    duration_minutes,
    room,
    substitute_owner_id,
    completed,
    print_default
   FROM public.lessons;


--
-- Name: parent_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.parent_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    phone text NOT NULL,
    name text,
    active boolean DEFAULT true NOT NULL,
    password_set_at timestamp with time zone,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT auth.uid(),
    CONSTRAINT parent_accounts_phone_check CHECK ((phone ~ '^\d{10,15}$'::text))
);


--
-- Name: parent_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.parent_credentials (
    parent_id uuid NOT NULL,
    password_hash text NOT NULL,
    failed_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone
);


--
-- Name: parent_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.parent_sessions (
    token_hash text NOT NULL,
    parent_id uuid NOT NULL,
    client text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: parent_students; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.parent_students (
    parent_id uuid NOT NULL,
    student_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: printers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.printers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    power_watts numeric DEFAULT 0 NOT NULL,
    depreciation_per_hour numeric DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT printers_depreciation_per_hour_check CHECK ((depreciation_per_hour >= (0)::numeric)),
    CONSTRAINT printers_power_watts_check CHECK ((power_watts >= (0)::numeric))
);


--
-- Name: printers_safe; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.printers_safe AS
 SELECT id,
    name,
    active,
    created_at,
        CASE
            WHEN public.is_admin() THEN power_watts
            ELSE NULL::numeric
        END AS power_watts,
        CASE
            WHEN public.is_admin() THEN depreciation_per_hour
            ELSE NULL::numeric
        END AS depreciation_per_hour
   FROM public.printers;


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text,
    first_name text,
    last_name text,
    role text DEFAULT 'teacher'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    photo text
);


--
-- Name: rate_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_cards (
    course text NOT NULL,
    rate_group numeric,
    rate_individual numeric,
    rate_mini_group numeric,
    rate_online numeric,
    rate_online_group numeric,
    rate_extra_print numeric,
    rate_trial numeric,
    zp_group_1 numeric DEFAULT 0 NOT NULL,
    price_group_1 numeric DEFAULT 0 NOT NULL,
    zp_group_2_6 numeric DEFAULT 0 NOT NULL,
    price_group_2_6 numeric DEFAULT 0 NOT NULL,
    zp_individual numeric DEFAULT 0 NOT NULL,
    price_individual numeric DEFAULT 0 NOT NULL,
    zp_individual_online_print numeric DEFAULT 0 NOT NULL,
    price_individual_online_print numeric DEFAULT 0 NOT NULL,
    zp_individual_online_no_print numeric DEFAULT 0 NOT NULL,
    price_individual_online_no_print numeric DEFAULT 0 NOT NULL,
    zp_group_online_print numeric DEFAULT 0 NOT NULL,
    price_group_online_print numeric DEFAULT 0 NOT NULL,
    zp_group_online_no_print numeric DEFAULT 0 NOT NULL,
    price_group_online_no_print numeric DEFAULT 0 NOT NULL,
    zp_extra_service numeric DEFAULT 0 NOT NULL,
    price_extra_service numeric DEFAULT 0 NOT NULL,
    price_subscription numeric DEFAULT 0 NOT NULL,
    zp_individual_online numeric DEFAULT 0 NOT NULL,
    price_individual_online numeric DEFAULT 0 NOT NULL,
    zp_group_online numeric DEFAULT 0 NOT NULL,
    price_group_online numeric DEFAULT 0 NOT NULL,
    price_print_online numeric,
    price_sub_group numeric DEFAULT 0 NOT NULL,
    price_sub_individual numeric DEFAULT 0 NOT NULL,
    price_sub_individual_online numeric DEFAULT 0 NOT NULL,
    price_sub_group_online numeric DEFAULT 0 NOT NULL
);


--
-- Name: rate_cards_safe; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.rate_cards_safe AS
 SELECT course,
    zp_group_1,
    zp_group_2_6,
    zp_individual,
    zp_individual_online,
    zp_group_online,
    zp_extra_service,
        CASE
            WHEN public.is_admin() THEN price_group_1
            ELSE NULL::numeric
        END AS price_group_1,
        CASE
            WHEN public.is_admin() THEN price_group_2_6
            ELSE NULL::numeric
        END AS price_group_2_6,
        CASE
            WHEN public.is_admin() THEN price_individual
            ELSE NULL::numeric
        END AS price_individual,
        CASE
            WHEN public.is_admin() THEN price_individual_online
            ELSE NULL::numeric
        END AS price_individual_online,
        CASE
            WHEN public.is_admin() THEN price_group_online
            ELSE NULL::numeric
        END AS price_group_online,
        CASE
            WHEN public.is_admin() THEN price_extra_service
            ELSE NULL::numeric
        END AS price_extra_service,
        CASE
            WHEN public.is_admin() THEN price_print_online
            ELSE NULL::numeric
        END AS price_print_online,
        CASE
            WHEN public.is_admin() THEN price_sub_group
            ELSE NULL::numeric
        END AS price_sub_group,
        CASE
            WHEN public.is_admin() THEN price_sub_individual
            ELSE NULL::numeric
        END AS price_sub_individual,
        CASE
            WHEN public.is_admin() THEN price_sub_individual_online
            ELSE NULL::numeric
        END AS price_sub_individual_online,
        CASE
            WHEN public.is_admin() THEN price_sub_group_online
            ELSE NULL::numeric
        END AS price_sub_group_online
   FROM public.rate_cards;


--
-- Name: students; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.students (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid,
    name text NOT NULL,
    phone text,
    parent_last_name text,
    parent_first_name text,
    photo text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    birthday date,
    notes text
);


--
-- Name: report_debt; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.report_debt AS
 SELECT la.id,
    la.lesson_id,
    la.student_id,
    la.owner_id,
    la.marked_at,
    l.date AS lesson_date,
    l.course,
    l.theme,
    (l.price_amount +
        CASE
            WHEN la.print_enabled THEN public.lesson_print_surcharge(l.id, la.print_price)
            ELSE (0)::numeric
        END) AS price_amount,
    s.name AS student_name
   FROM ((public.lesson_attendance la
     JOIN public.lessons l ON ((l.id = la.lesson_id)))
     JOIN public.students s ON ((s.id = la.student_id)))
  WHERE ((la.status = 'present'::text) AND (la.payment_method IS NULL) AND public.is_superadmin());


--
-- Name: report_paid; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.report_paid AS
 SELECT la.id,
    la.lesson_id,
    la.student_id,
    la.owner_id,
    la.payment_method,
    la.amount,
    la.marked_at,
    l.date AS lesson_date,
    l.course,
    l.theme,
    s.name AS student_name
   FROM ((public.lesson_attendance la
     JOIN public.lessons l ON ((l.id = la.lesson_id)))
     JOIN public.students s ON ((s.id = la.student_id)))
  WHERE ((la.status = 'present'::text) AND (la.payment_method IS NOT NULL) AND public.is_superadmin());


--
-- Name: work_costs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_costs (
    work_id uuid NOT NULL,
    weight_g numeric,
    waste_percent numeric DEFAULT 0 NOT NULL,
    price_per_kg numeric,
    print_minutes numeric,
    power_watts numeric,
    electricity_tariff numeric,
    depreciation_per_hour numeric,
    material_cost numeric DEFAULT 0 NOT NULL,
    electricity_cost numeric DEFAULT 0 NOT NULL,
    depreciation_cost numeric DEFAULT 0 NOT NULL,
    total_cost numeric DEFAULT 0 NOT NULL,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: works; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.works (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid,
    lesson_id uuid NOT NULL,
    student_id uuid NOT NULL,
    photo text,
    printed boolean DEFAULT false NOT NULL,
    printed_by_name text,
    printed_at timestamp with time zone,
    trial boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    weight_g numeric,
    print_minutes numeric,
    printer_id uuid,
    filament_id uuid,
    CONSTRAINT works_print_inputs_check CHECK ((((weight_g IS NULL) OR (weight_g >= (0)::numeric)) AND ((print_minutes IS NULL) OR (print_minutes >= (0)::numeric))))
);


--
-- Name: report_print_costs; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.report_print_costs AS
 SELECT w.id AS work_id,
    w.lesson_id,
    w.student_id,
    w.owner_id,
    COALESCE(((w.printed_at AT TIME ZONE 'Europe/Kyiv'::text))::date, l.date) AS print_date,
    l.date AS lesson_date,
    l.course,
    l.theme,
    s.name AS student_name,
    w.weight_g,
    w.print_minutes,
    w.printer_id,
    w.filament_id,
    p.name AS printer_name,
    f.material AS filament_material,
    f.color AS filament_color,
    wc.material_cost,
    wc.electricity_cost,
    wc.depreciation_cost,
    wc.total_cost
   FROM (((((public.works w
     JOIN public.lessons l ON ((l.id = w.lesson_id)))
     LEFT JOIN public.students s ON ((s.id = w.student_id)))
     LEFT JOIN public.printers p ON ((p.id = w.printer_id)))
     LEFT JOIN public.filaments f ON ((f.id = w.filament_id)))
     LEFT JOIN public.work_costs wc ON ((wc.work_id = w.id)))
  WHERE (w.printed AND public.is_admin());


--
-- Name: report_unused_excused; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.report_unused_excused AS
 SELECT la.id,
    la.lesson_id,
    la.student_id,
    la.owner_id,
    la.payment_method,
    la.amount,
    la.marked_at,
    l.date AS lesson_date,
    l.course,
    l.theme,
    s.name AS student_name
   FROM ((public.lesson_attendance la
     JOIN public.lessons l ON ((l.id = la.lesson_id)))
     JOIN public.students s ON ((s.id = la.student_id)))
  WHERE ((la.status = 'excused'::text) AND (la.payment_method IS NOT NULL) AND public.is_superadmin());


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    student_id uuid NOT NULL,
    course text NOT NULL,
    total_lessons integer DEFAULT 4 NOT NULL,
    remaining_lessons integer DEFAULT 4 NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    purchased_by uuid,
    purchased_at timestamp with time zone DEFAULT now() NOT NULL,
    total_price numeric DEFAULT 0 NOT NULL,
    payment_method text,
    CONSTRAINT subscriptions_payment_method_check CHECK (((payment_method IS NULL) OR (payment_method = ANY (ARRAY['card'::text, 'cash'::text])))),
    CONSTRAINT subscriptions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'cancelled'::text])))
);


--
-- Name: report_unused_subscriptions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.report_unused_subscriptions AS
 SELECT sub.id AS subscription_id,
    sub.student_id,
    sub.course,
    sub.remaining_lessons,
    sub.total_lessons,
    sub.purchased_at,
    s.name AS student_name
   FROM (public.subscriptions sub
     JOIN public.students s ON ((s.id = sub.student_id)))
  WHERE ((sub.status = 'active'::text) AND (sub.remaining_lessons > 0) AND public.is_superadmin());


--
-- Name: student_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    student_id uuid NOT NULL,
    author_id uuid,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: studio_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.studio_settings (
    id boolean DEFAULT true NOT NULL,
    calc_start_date date,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    electricity_tariff numeric DEFAULT 0 NOT NULL,
    filament_waste_percent numeric DEFAULT 0 NOT NULL,
    CONSTRAINT studio_settings_id_check CHECK (id),
    CONSTRAINT studio_settings_print_cost_check CHECK (((electricity_tariff >= (0)::numeric) AND (filament_waste_percent >= (0)::numeric) AND (filament_waste_percent <= (100)::numeric)))
);


--
-- Name: filaments filaments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.filaments
    ADD CONSTRAINT filaments_pkey PRIMARY KEY (id);


--
-- Name: lesson_attendance lesson_attendance_lesson_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_attendance
    ADD CONSTRAINT lesson_attendance_lesson_id_student_id_key UNIQUE (lesson_id, student_id);


--
-- Name: lesson_attendance lesson_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_attendance
    ADD CONSTRAINT lesson_attendance_pkey PRIMARY KEY (id);


--
-- Name: lessons lessons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lessons
    ADD CONSTRAINT lessons_pkey PRIMARY KEY (id);


--
-- Name: parent_accounts parent_accounts_phone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_accounts
    ADD CONSTRAINT parent_accounts_phone_key UNIQUE (phone);


--
-- Name: parent_accounts parent_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_accounts
    ADD CONSTRAINT parent_accounts_pkey PRIMARY KEY (id);


--
-- Name: parent_credentials parent_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_credentials
    ADD CONSTRAINT parent_credentials_pkey PRIMARY KEY (parent_id);


--
-- Name: parent_sessions parent_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_sessions
    ADD CONSTRAINT parent_sessions_pkey PRIMARY KEY (token_hash);


--
-- Name: parent_students parent_students_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_students
    ADD CONSTRAINT parent_students_pkey PRIMARY KEY (parent_id, student_id);


--
-- Name: printers printers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.printers
    ADD CONSTRAINT printers_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: rate_cards rate_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_cards
    ADD CONSTRAINT rate_cards_pkey PRIMARY KEY (course);


--
-- Name: student_comments student_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_comments
    ADD CONSTRAINT student_comments_pkey PRIMARY KEY (id);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (id);


--
-- Name: studio_settings studio_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.studio_settings
    ADD CONSTRAINT studio_settings_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: work_costs work_costs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_costs
    ADD CONSTRAINT work_costs_pkey PRIMARY KEY (work_id);


--
-- Name: works works_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.works
    ADD CONSTRAINT works_pkey PRIMARY KEY (id);


--
-- Name: idx_lesson_attendance_lesson; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lesson_attendance_lesson ON public.lesson_attendance USING btree (lesson_id);


--
-- Name: idx_lesson_attendance_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lesson_attendance_student ON public.lesson_attendance USING btree (student_id);


--
-- Name: idx_subscriptions_student_course; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscriptions_student_course ON public.subscriptions USING btree (student_id, course);


--
-- Name: parent_sessions_parent_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX parent_sessions_parent_idx ON public.parent_sessions USING btree (parent_id);


--
-- Name: parent_students_student_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX parent_students_student_idx ON public.parent_students USING btree (student_id);


--
-- Name: students trg_cleanup_deleted_student_from_lessons; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cleanup_deleted_student_from_lessons AFTER DELETE ON public.students FOR EACH ROW EXECUTE FUNCTION public.cleanup_deleted_student_from_lessons();


--
-- Name: lessons trg_compute_lesson_amounts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_compute_lesson_amounts BEFORE INSERT OR UPDATE OF course, format, student_ids, extra_service ON public.lessons FOR EACH ROW EXECUTE FUNCTION public.compute_lesson_amounts();


--
-- Name: works trg_compute_work_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_compute_work_cost AFTER INSERT OR UPDATE OF weight_g, print_minutes, printer_id, filament_id ON public.works FOR EACH ROW EXECUTE FUNCTION public.compute_work_cost();


--
-- Name: lessons trg_lesson_print_default; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lesson_print_default AFTER UPDATE OF print_default ON public.lessons FOR EACH ROW WHEN ((new.print_default IS DISTINCT FROM old.print_default)) EXECUTE FUNCTION public.apply_lesson_print_default();


--
-- Name: parent_accounts trg_parent_accounts_normalize; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_parent_accounts_normalize BEFORE INSERT OR UPDATE OF phone, name ON public.parent_accounts FOR EACH ROW EXECUTE FUNCTION public.parent_accounts_normalize();


--
-- Name: lesson_attendance lesson_attendance_lesson_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_attendance
    ADD CONSTRAINT lesson_attendance_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES public.lessons(id) ON DELETE CASCADE;


--
-- Name: lesson_attendance lesson_attendance_marked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_attendance
    ADD CONSTRAINT lesson_attendance_marked_by_fkey FOREIGN KEY (marked_by) REFERENCES public.profiles(id);


--
-- Name: lesson_attendance lesson_attendance_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_attendance
    ADD CONSTRAINT lesson_attendance_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id);


--
-- Name: lesson_attendance lesson_attendance_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_attendance
    ADD CONSTRAINT lesson_attendance_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE CASCADE;


--
-- Name: lesson_attendance lesson_attendance_subscription_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_attendance
    ADD CONSTRAINT lesson_attendance_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: lessons lessons_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lessons
    ADD CONSTRAINT lessons_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id);


--
-- Name: lessons lessons_substitute_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lessons
    ADD CONSTRAINT lessons_substitute_owner_id_fkey FOREIGN KEY (substitute_owner_id) REFERENCES public.profiles(id);


--
-- Name: parent_credentials parent_credentials_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_credentials
    ADD CONSTRAINT parent_credentials_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.parent_accounts(id) ON DELETE CASCADE;


--
-- Name: parent_sessions parent_sessions_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_sessions
    ADD CONSTRAINT parent_sessions_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.parent_accounts(id) ON DELETE CASCADE;


--
-- Name: parent_students parent_students_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_students
    ADD CONSTRAINT parent_students_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.parent_accounts(id) ON DELETE CASCADE;


--
-- Name: parent_students parent_students_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parent_students
    ADD CONSTRAINT parent_students_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: student_comments student_comments_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_comments
    ADD CONSTRAINT student_comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id);


--
-- Name: student_comments student_comments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_comments
    ADD CONSTRAINT student_comments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE CASCADE;


--
-- Name: students students_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id);


--
-- Name: studio_settings studio_settings_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.studio_settings
    ADD CONSTRAINT studio_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: subscriptions subscriptions_purchased_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_purchased_by_fkey FOREIGN KEY (purchased_by) REFERENCES public.profiles(id);


--
-- Name: subscriptions subscriptions_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE CASCADE;


--
-- Name: work_costs work_costs_work_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_costs
    ADD CONSTRAINT work_costs_work_id_fkey FOREIGN KEY (work_id) REFERENCES public.works(id) ON DELETE CASCADE;


--
-- Name: works works_filament_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.works
    ADD CONSTRAINT works_filament_id_fkey FOREIGN KEY (filament_id) REFERENCES public.filaments(id) ON DELETE SET NULL;


--
-- Name: works works_lesson_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.works
    ADD CONSTRAINT works_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES public.lessons(id) ON DELETE CASCADE;


--
-- Name: works works_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.works
    ADD CONSTRAINT works_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id);


--
-- Name: works works_printer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.works
    ADD CONSTRAINT works_printer_id_fkey FOREIGN KEY (printer_id) REFERENCES public.printers(id) ON DELETE SET NULL;


--
-- Name: works works_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.works
    ADD CONSTRAINT works_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE CASCADE;


--
-- Name: filaments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.filaments ENABLE ROW LEVEL SECURITY;

--
-- Name: filaments filaments_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY filaments_admin_all ON public.filaments USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: lesson_attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lesson_attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: lesson_attendance lesson_attendance_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_attendance_admin_all ON public.lesson_attendance USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: lesson_attendance lesson_attendance_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_attendance_read_all ON public.lesson_attendance FOR SELECT USING (true);


--
-- Name: lessons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lessons ENABLE ROW LEVEL SECURITY;

--
-- Name: lessons lessons_select_scoped; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lessons_select_scoped ON public.lessons FOR SELECT USING (((owner_id = auth.uid()) OR public.is_admin() OR (student_ids && public.my_taught_student_ids())));


--
-- Name: parent_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.parent_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: parent_accounts parent_accounts_superadmin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY parent_accounts_superadmin ON public.parent_accounts TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


--
-- Name: parent_credentials; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.parent_credentials ENABLE ROW LEVEL SECURITY;

--
-- Name: parent_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.parent_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: parent_students; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.parent_students ENABLE ROW LEVEL SECURITY;

--
-- Name: parent_students parent_students_superadmin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY parent_students_superadmin ON public.parent_students TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


--
-- Name: printers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.printers ENABLE ROW LEVEL SECURITY;

--
-- Name: printers printers_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY printers_admin_all ON public.printers USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_cards rate_cards_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rate_cards_admin_write ON public.rate_cards USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


--
-- Name: rate_cards rate_cards_select_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rate_cards_select_all ON public.rate_cards FOR SELECT USING (public.is_admin());


--
-- Name: student_comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.student_comments ENABLE ROW LEVEL SECURITY;

--
-- Name: student_comments student_comments_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY student_comments_insert ON public.student_comments FOR INSERT WITH CHECK ((auth.uid() IS NOT NULL));


--
-- Name: student_comments student_comments_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY student_comments_read ON public.student_comments FOR SELECT USING (true);


--
-- Name: students; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

--
-- Name: students students_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY students_delete_admin ON public.students FOR DELETE USING (public.is_admin());


--
-- Name: students students_insert_shared; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY students_insert_shared ON public.students FOR INSERT WITH CHECK ((auth.uid() IS NOT NULL));


--
-- Name: students students_select_shared; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY students_select_shared ON public.students FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: students students_update_shared; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY students_update_shared ON public.students FOR UPDATE USING ((auth.uid() IS NOT NULL)) WITH CHECK ((auth.uid() IS NOT NULL));


--
-- Name: studio_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.studio_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: studio_settings studio_settings_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY studio_settings_admin_read ON public.studio_settings FOR SELECT USING (public.is_admin());


--
-- Name: subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: subscriptions subscriptions_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY subscriptions_admin_all ON public.subscriptions USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: work_costs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_costs ENABLE ROW LEVEL SECURITY;

--
-- Name: work_costs work_costs_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_costs_admin_read ON public.work_costs FOR SELECT USING (public.is_admin());


--
-- Name: works; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.works ENABLE ROW LEVEL SECURITY;

--
-- Name: works works_select_scoped; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY works_select_scoped ON public.works FOR SELECT USING (((owner_id = auth.uid()) OR public.is_admin() OR (student_id = ANY (public.my_taught_student_ids()))));


--
-- PostgreSQL database dump complete
--

\unrestrict z3IzcRNRmS9YLgUswUJXXTfyUgMUKhb4o916hdVU3yCkD6OPDH9Rac5ERK7MgjL

