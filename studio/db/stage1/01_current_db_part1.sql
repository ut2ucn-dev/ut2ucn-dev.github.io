-- STEMIK · знеособлена копія робочої бази · частина 1 з 7: структура: таблиці, функції (без даних)
-- Виконуйте СУВОРО по черзі: 01_current_db_part1 → … → 01_current_db_part7. Кожна частина — окрема транзакція.

-- STEMIK: знеособлена копія бази даних (знеособлена)
-- Створено 2026-11-10 з робочої бази лише запитами на читання.
--
-- Що змінено порівняно з робочою базою:
--   • учні: імена «Учень 001», вигадані телефони, імена батьків «Батьки 001»,
--     дата народження — той самий рік, випадковий день; нотатки й фото прибрано;
--   • працівники: «Викладач 01» / «Адмін 01», пошта user01@example.test, без фото;
--   • батьківські акаунти: вигадані телефони й імена; паролі й сесії не скопійовано;
--   • коментарі про учнів замінено на «Коментар 0001»; фото робіт прибрано;
--   • у темах занять слова, що збігаються з іменами учнів чи батьків, замінено на ***;
--   • усі гроші (тарифи, ціни занять, оплати, зарплати, абонементи, ціна філаменту,
--     амортизація, тариф електроенергії) — правдоподібні вигадані: помножені на
--     випадковий таємний коефіцієнт (щонайменше ±15%) із шумом і округлені; справжні суми з них не відновити.
-- Ідентифікатори, дати, відвідування, курси, кількість занять тощо — як у робочій базі.
-- Файли (фото) у копію не входять.
--
-- Як завантажити:
--   • новий порожній проєкт Supabase → SQL Editor → вставити весь файл → Run;
--   • або звичайний PostgreSQL 15+: psql -d <база> -f цей_файл.sql
-- Файл можна запускати повторно: він видаляє попередню знеособлену копію і створює її знову.
-- ЗАХИСТ: у базі, де вже є справжні дані (немає позначки знеособленої копії),
-- файл зупиниться з помилкою і нічого не змінить.

begin;
set local check_function_bodies = false;
set local client_min_messages = warning;
set local search_path = public, extensions;

do $guard$
begin
  if to_regclass('public.students') is not null and to_regclass('public._training_copy') is null then
    raise exception 'СТОП: у цій базі вже є таблиця students, і це не знеособлена копія. Схоже, це робоча база — нічого не змінено.';
  end if;
end $guard$;

-- Щоб файл працював і поза Supabase: ролі, схеми й функції, які Supabase має сам.
do $prelude$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
  if not exists (select 1 from pg_namespace where nspname = 'auth') then
    create schema auth;
    create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text,
      raw_user_meta_data jsonb, raw_app_meta_data jsonb, created_at timestamptz default now(), updated_at timestamptz default now());
    create function auth.uid() returns uuid language sql stable
      as $f$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $f$;
    create function auth.role() returns text language sql stable
      as $f$ select nullif(current_setting('request.jwt.claim.role', true), '') $f$;
    create function auth.jwt() returns jsonb language sql stable
      as $f$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $f$;
    grant usage on schema auth to anon, authenticated, service_role;
  end if;
end $prelude$;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;


-- Попередня знеособлена копія (якщо є)
drop trigger if exists on_auth_user_created on auth.users;
drop view if exists public.lessons_safe cascade;
drop view if exists public.report_paid cascade;
drop view if exists public.report_unused_subscriptions cascade;
drop view if exists public.report_unused_excused cascade;
drop view if exists public.rate_cards_safe cascade;
drop view if exists public.report_debt cascade;
drop view if exists public.filaments_safe cascade;
drop view if exists public.printers_safe cascade;
drop view if exists public.report_print_costs cascade;
drop table if exists public.filaments cascade;
drop table if exists public.lesson_attendance cascade;
drop table if exists public.lessons cascade;
drop table if exists public.parent_accounts cascade;
drop table if exists public.parent_credentials cascade;
drop table if exists public.parent_sessions cascade;
drop table if exists public.parent_students cascade;
drop table if exists public.printers cascade;
drop table if exists public.profiles cascade;
drop table if exists public.rate_cards cascade;
drop table if exists public.student_comments cascade;
drop table if exists public.students cascade;
drop table if exists public.studio_settings cascade;
drop table if exists public.subscriptions cascade;
drop table if exists public.work_costs cascade;
drop table if exists public.works cascade;
drop table if exists public._training_copy cascade;
drop function if exists public.apply_lesson_print_default() cascade;
drop function if exists public.cleanup_deleted_student_from_lessons() cascade;
drop function if exists public.compute_lesson_amounts() cascade;
drop function if exists public.compute_work_cost() cascade;
drop function if exists public.handle_new_user() cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.is_superadmin() cascade;
drop function if exists public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) cascade;
drop function if exists public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) cascade;
drop function if exists public.my_taught_student_ids() cascade;
drop function if exists public.parent_accounts_normalize() cascade;
drop function if exists public.parent_create_account(p_phone text, p_name text, p_student_ids uuid[]) cascade;
drop function if exists public.parent_generate_password() cascade;
drop function if exists public.parent_login(p_phone text, p_password text, p_client text) cascade;
drop function if exists public.parent_logout(p_token text) cascade;
drop function if exists public.parent_normalize_phone(p_phone text) cascade;
drop function if exists public.parent_password_for_student(p_student_id uuid) cascade;
drop function if exists public.parent_portal(p_token text) cascade;
drop function if exists public.parent_reset_credentials(p_parent_id uuid) cascade;
drop function if exists public.parent_reset_password(p_parent_id uuid) cascade;
drop function if exists public.parent_session_account(p_token text) cascade;
drop function if exists public.rls_auto_enable() cascade;
drop function if exists public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) cascade;
drop function if exists public.set_calc_start_date(p_date date) cascade;
drop function if exists public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) cascade;
drop function if exists public.studio_report_summary(p_from date, p_to date) cascade;
drop function if exists public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) cascade;
-- Таблиці
create table public._training_copy (created_at timestamptz not null default now());
insert into public._training_copy default values;
alter table public._training_copy enable row level security;
create table public.filaments (
  "id" uuid default gen_random_uuid() not null,
  "material" text not null,
  "color" text,
  "price_per_kg" numeric default 0 not null,
  "active" boolean default true not null,
  "created_at" timestamp with time zone default now() not null,
  constraint "filaments_pkey" PRIMARY KEY (id),
  constraint "filaments_price_per_kg_check" CHECK ((price_per_kg >= (0)::numeric))
);
create table public.lesson_attendance (
  "id" uuid default gen_random_uuid() not null,
  "lesson_id" uuid not null,
  "student_id" uuid not null,
  "owner_id" uuid,
  "status" text not null,
  "payment_method" text,
  "amount" numeric default 0 not null,
  "subscription_id" uuid,
  "marked_by" uuid,
  "marked_at" timestamp with time zone default now() not null,
  "discount_percent" numeric default 0 not null,
  "print_enabled" boolean default false not null,
  "print_price" numeric,
  constraint "lesson_attendance_discount_percent_check" CHECK (((discount_percent >= (0)::numeric) AND (discount_percent <= (100)::numeric))),
  constraint "lesson_attendance_lesson_id_student_id_key" UNIQUE (lesson_id, student_id),
  constraint "lesson_attendance_payment_method_check" CHECK ((payment_method = ANY (ARRAY['card'::text, 'cash'::text, 'subscription'::text, 'certificate'::text]))),
  constraint "lesson_attendance_pkey" PRIMARY KEY (id),
  constraint "lesson_attendance_print_price_check" CHECK (((print_price IS NULL) OR (print_price >= (0)::numeric))),
  constraint "lesson_attendance_status_check" CHECK ((status = ANY (ARRAY['present'::text, 'absent'::text, 'excused'::text])))
);
create table public.lessons (
  "id" uuid default gen_random_uuid() not null,
  "owner_id" uuid not null,
  "series_id" uuid,
  "date" date not null,
  "time" text,
  "theme" text not null,
  "student_ids" uuid[] default '{}'::uuid[] not null,
  "created_at" timestamp with time zone default now(),
  "course" text,
  "format" text default 'group'::text not null,
  "extra_service" boolean default false not null,
  "payroll_amount" numeric,
  "price_amount" numeric default 0 not null,
  "duration_minutes" integer default 60 not null,
  "room" text,
  "substitute_owner_id" uuid,
  "completed" boolean default false not null,
  "print_default" boolean default false not null,
  constraint "lessons_format_check" CHECK ((format = ANY (ARRAY['group'::text, 'individual'::text, 'individual_online'::text, 'group_online'::text]))),
  constraint "lessons_pkey" PRIMARY KEY (id),
  constraint "lessons_room_check" CHECK (((room IS NULL) OR (room = ANY (ARRAY['Клас AI'::text, 'Клас VR'::text, 'Комп''ютерний клас'::text, 'Клас 3D'::text]))))
);
create table public.parent_accounts (
  "id" uuid default gen_random_uuid() not null,
  "phone" text not null,
  "name" text,
  "active" boolean default true not null,
  "password_set_at" timestamp with time zone,
  "last_login_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "created_by" uuid default auth.uid(),
  constraint "parent_accounts_phone_check" CHECK ((phone ~ '^\d{10,15}$'::text)),
  constraint "parent_accounts_phone_key" UNIQUE (phone),
  constraint "parent_accounts_pkey" PRIMARY KEY (id)
);
create table public.parent_credentials (
  "parent_id" uuid not null,
  "password_hash" text not null,
  "failed_attempts" integer default 0 not null,
  "locked_until" timestamp with time zone,
  constraint "parent_credentials_pkey" PRIMARY KEY (parent_id)
);
create table public.parent_sessions (
  "token_hash" text not null,
  "parent_id" uuid not null,
  "client" text,
  "created_at" timestamp with time zone default now() not null,
  "last_seen_at" timestamp with time zone default now() not null,
  "expires_at" timestamp with time zone not null,
  constraint "parent_sessions_pkey" PRIMARY KEY (token_hash)
);
create table public.parent_students (
  "parent_id" uuid not null,
  "student_id" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  constraint "parent_students_pkey" PRIMARY KEY (parent_id, student_id)
);
create table public.printers (
  "id" uuid default gen_random_uuid() not null,
  "name" text not null,
  "power_watts" numeric default 0 not null,
  "depreciation_per_hour" numeric default 0 not null,
  "active" boolean default true not null,
  "created_at" timestamp with time zone default now() not null,
  constraint "printers_depreciation_per_hour_check" CHECK ((depreciation_per_hour >= (0)::numeric)),
  constraint "printers_pkey" PRIMARY KEY (id),
  constraint "printers_power_watts_check" CHECK ((power_watts >= (0)::numeric))
);
create table public.profiles (
  "id" uuid not null,
  "email" text,
  "role" text default 'teacher'::text not null,
  "created_at" timestamp with time zone default now(),
  "last_name" text default ''::text not null,
  "first_name" text default ''::text not null,
  "active" boolean default true not null,
  "photo" text,
  constraint "profiles_pkey" PRIMARY KEY (id),
  constraint "profiles_role_check" CHECK ((role = ANY (ARRAY['teacher'::text, 'admin'::text, 'superadmin'::text])))
);
create table public.rate_cards (
  "course" text not null,
  "rate_group_1" numeric default 0 not null,
  "rate_group_2_4" numeric default 0 not null,
  "rate_group_5_6" numeric default 0 not null,
  "rate_individual" numeric default 0 not null,
  "rate_online_print" numeric default 0 not null,
  "rate_online_no_print" numeric default 0 not null,
  "rate_extra_print" numeric default 0 not null,
  "updated_at" timestamp with time zone default now(),
  "zp_group_1" numeric default 0 not null,
  "price_group_1" numeric default 0 not null,
  "zp_group_2_6" numeric default 0 not null,
  "price_group_2_6" numeric default 0 not null,
  "zp_individual" numeric default 0 not null,
  "price_individual" numeric default 0 not null,
  "zp_individual_online_print" numeric default 0 not null,
  "price_individual_online_print" numeric default 0 not null,
  "zp_individual_online_no_print" numeric default 0 not null,
  "price_individual_online_no_print" numeric default 0 not null,
  "zp_group_online_print" numeric default 0 not null,
  "price_group_online_print" numeric default 0 not null,
  "zp_group_online_no_print" numeric default 0 not null,
  "price_group_online_no_print" numeric default 0 not null,
  "zp_extra_service" numeric default 0 not null,
  "price_extra_service" numeric default 0 not null,
  "price_subscription" numeric default 0 not null,
  "zp_individual_online" numeric default 0 not null,
  "price_individual_online" numeric default 0 not null,
  "zp_group_online" numeric default 0 not null,
  "price_group_online" numeric default 0 not null,
  "price_print_online" numeric,
  "price_sub_group" numeric default 0 not null,
  "price_sub_individual" numeric default 0 not null,
  "price_sub_individual_online" numeric default 0 not null,
  "price_sub_group_online" numeric default 0 not null,
  constraint "rate_cards_pkey" PRIMARY KEY (course)
);
create table public.student_comments (
  "id" uuid default gen_random_uuid() not null,
  "student_id" uuid not null,
  "author_id" uuid,
  "body" text not null,
  "created_at" timestamp with time zone default now() not null,
  constraint "student_comments_pkey" PRIMARY KEY (id)
);
create table public.students (
  "id" uuid default gen_random_uuid() not null,
  "owner_id" uuid not null,
  "name" text not null,
  "created_at" timestamp with time zone default now(),
  "phone" text default ''::text not null,
  "parent_last_name" text default ''::text not null,
  "parent_first_name" text default ''::text not null,
  "photo" text,
  "birthday" date,
  "notes" text,
  constraint "students_pkey" PRIMARY KEY (id)
);
create table public.studio_settings (
  "id" boolean default true not null,
  "calc_start_date" date,
  "updated_at" timestamp with time zone default now() not null,
  "updated_by" uuid,
  "electricity_tariff" numeric default 0 not null,
  "filament_waste_percent" numeric default 0 not null,
  constraint "studio_settings_id_check" CHECK (id),
  constraint "studio_settings_pkey" PRIMARY KEY (id),
  constraint "studio_settings_print_cost_check" CHECK (((electricity_tariff >= (0)::numeric) AND (filament_waste_percent >= (0)::numeric) AND (filament_waste_percent <= (100)::numeric)))
);
create table public.subscriptions (
  "id" uuid default gen_random_uuid() not null,
  "student_id" uuid not null,
  "course" text not null,
  "total_lessons" integer default 4 not null,
  "remaining_lessons" integer default 4 not null,
  "status" text default 'active'::text not null,
  "purchased_by" uuid,
  "purchased_at" timestamp with time zone default now() not null,
  "total_price" numeric default 0 not null,
  "payment_method" text,
  constraint "subscriptions_payment_method_check" CHECK (((payment_method IS NULL) OR (payment_method = ANY (ARRAY['card'::text, 'cash'::text])))),
  constraint "subscriptions_pkey" PRIMARY KEY (id),
  constraint "subscriptions_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'cancelled'::text])))
);
create table public.work_costs (
  "work_id" uuid not null,
  "weight_g" numeric,
  "waste_percent" numeric default 0 not null,
  "price_per_kg" numeric,
  "print_minutes" numeric,
  "power_watts" numeric,
  "electricity_tariff" numeric,
  "depreciation_per_hour" numeric,
  "material_cost" numeric default 0 not null,
  "electricity_cost" numeric default 0 not null,
  "depreciation_cost" numeric default 0 not null,
  "total_cost" numeric default 0 not null,
  "computed_at" timestamp with time zone default now() not null,
  constraint "work_costs_pkey" PRIMARY KEY (work_id)
);
create table public.works (
  "id" uuid default gen_random_uuid() not null,
  "owner_id" uuid not null,
  "lesson_id" uuid not null,
  "student_id" uuid not null,
  "photo" text,
  "printed" boolean default false not null,
  "created_at" timestamp with time zone default now(),
  "printed_by_name" text,
  "printed_at" timestamp with time zone,
  "trial" boolean default false not null,
  "weight_g" numeric,
  "print_minutes" numeric,
  "printer_id" uuid,
  "filament_id" uuid,
  constraint "works_pkey" PRIMARY KEY (id),
  constraint "works_print_inputs_check" CHECK ((((weight_g IS NULL) OR (weight_g >= (0)::numeric)) AND ((print_minutes IS NULL) OR (print_minutes >= (0)::numeric))))
);

-- Функції
CREATE OR REPLACE FUNCTION public.apply_lesson_print_default()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_deleted_student_from_lessons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  update public.lessons
    set student_ids = array_remove(student_ids, old.id)
    where date >= current_date
      and old.id = any(student_ids);
  return old;
end;
$function$;

CREATE OR REPLACE FUNCTION public.compute_lesson_amounts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.compute_work_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  insert into public.profiles (id, email, last_name, first_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    coalesce(new.raw_user_meta_data->>'first_name', '')
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role in ('admin', 'superadmin')
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_superadmin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'superadmin'
  );
$function$;

CREATE OR REPLACE FUNCTION public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text DEFAULT NULL::text, p_discount_percent numeric DEFAULT 0, p_purchase_date date DEFAULT NULL::date, p_purchase_method text DEFAULT NULL::text)
 RETURNS lesson_attendance
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.my_taught_student_ids()
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select coalesce(array_agg(distinct sid), '{}'::uuid[])
  from public.lessons l, unnest(l.student_ids) as sid
  where l.owner_id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.parent_accounts_normalize()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.phone := public.parent_normalize_phone(new.phone);
  new.name := nullif(btrim(coalesce(new.name, '')), '');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.parent_create_account(p_phone text, p_name text DEFAULT NULL::text, p_student_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.parent_generate_password()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
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

CREATE OR REPLACE FUNCTION public.parent_login(p_phone text, p_password text, p_client text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.parent_logout(p_token text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  delete from public.parent_sessions
    where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$function$;

CREATE OR REPLACE FUNCTION public.parent_normalize_phone(p_phone text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when d ~ '^0\d{9}$' then '38' || d
    when d ~ '^\d{9}$' then '380' || d
    when d ~ '^80\d{9}$' then '3' || d
    else d
  end
  from (select regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') as d) x;
$function$;

CREATE OR REPLACE FUNCTION public.parent_password_for_student(p_student_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.parent_portal(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.parent_reset_credentials(p_parent_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.parent_reset_password(p_parent_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.parent_session_account(p_token text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric DEFAULT NULL::numeric)
 RETURNS lesson_attendance
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.set_calc_start_date(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.studio_report_summary(p_from date, p_to date)
 RETURNS TABLE(paid_total numeric, paid_count integer, debt_total numeric, debt_count integer, unused_subscription_lessons integer, unused_subscription_count integer, unused_excused_total numeric, unused_excused_count integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.unmark_attendance(p_lesson_id uuid, p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
$function$;


-- Дані (знеособлені)

commit;
