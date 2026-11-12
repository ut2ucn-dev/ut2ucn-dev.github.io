-- STEMIK: навчальна копія бази даних (знеособлена)
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
-- Файл можна запускати повторно: він видаляє попередню навчальну копію і створює її знову.
-- ЗАХИСТ: у базі, де вже є справжні дані (немає позначки навчальної копії),
-- файл зупиниться з помилкою і нічого не змінить.

begin;
set local check_function_bodies = false;
set local client_min_messages = warning;
set local search_path = public, extensions;

do $guard$
begin
  if to_regclass('public.students') is not null and to_regclass('public._training_copy') is null then
    raise exception 'СТОП: у цій базі вже є таблиця students, і це не навчальна копія. Схоже, це робоча база — нічого не змінено.';
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


-- Попередня навчальна копія (якщо є)
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
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email, '{}', '{"provider":"email","providers":["email"]}', now(), now()
from (values
  ('0ab913d6-ea2f-4f30-b75d-b77a803fed15'::uuid, 'user04@example.test'),
  ('114b4ba6-4313-4a1e-a1c5-121e4aa333b3'::uuid, 'user07@example.test'),
  ('51137c32-5d66-48e6-963e-cd96ff1603f9'::uuid, 'user06@example.test'),
  ('75f98c1e-3264-440f-b4bb-f70d6778b767'::uuid, 'user03@example.test'),
  ('85701c53-77ce-4783-a157-e21476b16d4c'::uuid, 'user08@example.test'),
  ('a6de212d-bc6b-4a11-8f8c-351881292c4c'::uuid, 'user05@example.test'),
  ('c8db7e24-402e-495a-8a3d-74bed8b0c55c'::uuid, 'user02@example.test'),
  ('ec757c5a-f5e1-47dc-bde5-5ff69d22318e'::uuid, 'user01@example.test')
) as v(id, email)
on conflict (id) do nothing;
insert into public.filaments ("id", "material", "color", "price_per_kg", "active", "created_at") values
('052766f2-f11c-45e6-af34-876fe38263a2', 'PLA Basic', 'Cyan (10603)', '450', 'true', '2026-10-26 15:18:59.236417+00'),
('18d3ea69-ef67-4cc2-99a0-f9ad039f535a', 'PLA Basic', 'Silver (10102)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('1c396eff-b092-4ffd-b00f-3a3fb0dd25ae', 'PLA Basic', 'Dark Gray (10105)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('1fcaf95e-31da-4a8b-a309-c7df2f3cd036', 'PLA Basic', 'Bambu Green (10501)', '450', 'true', '2026-10-26 15:19:50.898175+00'),
('212bc730-3694-49ca-b8fe-24238b6b6bde', 'PLA Basic', 'Maroon Red (10205)', '450', 'true', '2026-10-26 15:19:56.169109+00'),
('26134483-e0a1-48bf-9f2c-3badbe43bd59', 'PLA Basic', 'Mistletoe Green (10502)', '450', 'true', '2026-10-26 15:19:50.898175+00'),
('324b06aa-b4c9-404d-bd34-88105af3906e', 'PLA Basic', 'Light Gray (10104)', '450', 'true', '2026-10-26 15:19:10.93602+00'),
('42527182-2482-4eae-98a6-79a1029c8525', 'PLA Basic', 'Pumpkin Orange (10301)', '450', 'true', '2026-10-26 15:19:50.898175+00'),
('4619332d-284c-4e91-b94f-fd005bef0ad8', 'PLA Basic', 'Blue Grey (10602)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('4c45c00c-e9ac-4478-af72-29b8b1be2f54', 'PLA Basic', 'Black (10101)', '450', 'true', '2026-10-26 15:18:59.236417+00'),
('526f0d5e-3501-4a7b-80f9-6ecc6a7f453e', 'PLA Basic', 'Orange (10300)', '450', 'true', '2026-10-26 15:18:59.236417+00'),
('541c8e34-68ed-4284-b976-cf3692030446', 'PLA Basic', 'Purple (10700)', '450', 'true', '2026-10-26 15:19:56.169109+00'),
('5a032e0a-bcff-46b2-98f1-dc1c7089d566', 'PLA Basic', 'Yellow (10400)', '450', 'true', '2026-10-26 15:19:10.93602+00'),
('61cdca61-fc53-4571-81ac-ed530235f2ea', 'PLA Basic', 'Bronze (10801)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('6e2d32ea-b276-46b9-9f35-429880107fdf', 'PLA Basic', 'Brown (10800)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('6f356641-a899-4139-a982-925dcd151750', 'PLA Basic', 'Gold (10401)', '450', 'true', '2026-10-26 15:19:10.93602+00'),
('76df8ba8-8513-4c45-927f-c84a2f7b4ecd', 'PLA Basic', 'Sunflower Yellow (10402)', '450', 'true', '2026-10-26 15:19:10.93602+00'),
('76e047b8-00bf-43fb-b5a3-3be834879f19', 'PLA Basic', 'Beige (10201)', '450', 'true', '2026-10-26 15:19:10.93602+00'),
('7a6893df-f7c3-44cb-9264-2d0144a0bef7', 'PLA Basic', 'Cocoa Brown (10802)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('7feb0a4f-4eae-4295-b703-6816c6f44bfe', 'PLA Basic', 'Magenta (10202)', '450', 'true', '2026-10-26 15:19:56.169109+00'),
('845e0578-2f03-4299-baa1-fe02cf49de4a', 'PLA Basic', 'Bright Green (10503)', '450', 'true', '2026-10-26 15:19:50.898175+00'),
('87b662f4-8222-4ed4-8dd0-ba36e76fb851', 'PLA Basic', 'Red (10200)', '450', 'true', '2026-10-26 15:19:56.169109+00'),
('a6dbf23a-b19a-4b77-b2c5-2dbab136edad', 'PLA Basic', 'Hot Pink (10204)', '450', 'true', '2026-10-26 15:19:56.169109+00'),
('ab763386-0525-452f-a7b4-b65e4b3eb4cd', 'PLA Basic', 'Cobalt Blue (10604)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('b1693bc6-9549-4043-b45e-8a221e97dca7', 'PLA Basic', 'Turquoise (10605)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('b97f2da8-463c-4a27-9a5f-b0304781aadb', 'PLA Basic', 'Jade White (10100)', '450', 'true', '2026-10-26 15:18:59.236417+00'),
('c5fa57a9-0325-43b5-b267-b4f5e6050531', 'PLA Basic', 'Blue (10601)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('da436b04-acdb-4268-bec7-6814c390367a', 'PLA Basic', 'Indigo Purple (10701)', '450', 'true', '2026-10-29 17:01:56.07406+00'),
('e37fb655-b214-470d-be05-fc5db5eb4109', 'PLA Basic', 'Pink (10203)', '450', 'true', '2026-10-26 15:19:50.898175+00'),
('f40fcb3c-2e86-4c82-8a76-d3bb0c43d128', 'PLA Basic', 'Gray (10103)', '450', 'true', '2026-10-26 15:18:59.236417+00');
insert into public.lesson_attendance ("id", "lesson_id", "student_id", "owner_id", "status", "payment_method", "amount", "subscription_id", "marked_by", "marked_at", "discount_percent", "print_enabled", "print_price") values
('015506b5-26fc-4f7f-8041-55a0b0677abc', 'a9fda877-9ae0-4d02-8f24-300f09ee5c4b', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-10 13:10:25.347774+00', '0', 'false', NULL),
('015a7880-a267-4396-aa94-f7dfc5afcb0a', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 09:37:11.886576+00', '10', 'false', NULL),
('018ce3f4-964c-4fde-aa13-e88e4a9cc36f', 'edf693ff-5ff8-4bc3-a76a-8c59e663034c', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'cash', '420', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:56:16.02399+00', '0', 'false', NULL),
('0197e647-bb96-4542-8ac7-b726ec12914e', 'ff84ab59-df43-4b83-a32c-61711dd233bf', '7e538107-a218-47e5-9daa-8d2763445b5e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '300', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 11:46:27.299465+00', '15', 'false', NULL),
('030f0084-043e-4c56-877b-e131beec17d8', '000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', '28511a97-5dca-4516-b5e0-afc636c23dd2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 13:28:09.38947+00', '0', 'false', NULL),
('03f70dca-ad7b-43bc-818e-8b909a8eb4fb', 'd221272e-d869-4172-b838-42684fa7a94d', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-04 12:18:47.071237+00', '0.0', 'true', NULL),
('064b1438-fd84-4cdb-b27d-eb67944ebca2', '2bd234a7-bd14-406c-9e61-d59f009d14d2', '320747d4-9733-45ea-a0b6-86f0654aef24', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 12:23:17.285962+00', '0', 'false', NULL),
('06a21a7c-2a9d-41d0-82c5-bdeb08c2ffcc', '53312f9a-aa0a-4a28-b83f-e2246c0f366b', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 11:15:09.006454+00', '0', 'false', NULL),
('078b2045-2fa2-4053-8b34-c3c5a0ce1599', '702b1756-4601-4448-9781-60c76f7669e8', '09b20d74-f3da-4342-b268-017f66ac101e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 12:36:58.721195+00', '0', 'false', NULL),
('082b774b-9c4b-4b98-8ba0-1e94012f8cde', '22a88243-93c1-4144-a537-2f4e2840d42f', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-02 13:25:33.126898+00', '0', 'false', NULL),
('099315a3-ecbf-4e50-b30f-c62270ac81cd', 'a0a85659-5d7b-415f-8a29-8b1b4d4e55cf', '78261ab1-3948-46c8-b5c6-7621398af6fc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '30bd2af5-ca1d-4532-b5ef-ee90e9467fe3', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:05:47.814484+00', '0', 'false', NULL),
('09960215-0086-410a-bf1f-bd669829182e', '2b68e2be-73c4-41cc-bed7-12fc80bcbb07', '08572b9e-65bb-46a9-8267-409a49dffe6e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 09:36:45.414904+00', '0', 'false', NULL),
('0cc16469-ab92-4862-9748-fb9fde65e5f2', '1c144d5f-7bcd-410c-920a-84f4159320de', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'e542dfea-de9f-4f8f-9dc2-ea3af9b6ab28', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 13:16:01.088056+00', '0', 'false', NULL),
('0ec7453b-c693-4b56-8f5e-49f760a263bd', 'bae8c2d4-ff0f-491c-b55a-62a21098663a', 'd9dfe264-fdf8-41f5-92ca-87de083f4f29', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-30 10:57:09.489091+00', '0', 'true', NULL),
('11a4f088-79b0-457b-9d57-faf38c1b1573', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '4ea6c617-fa16-4da5-8123-8e48391f6b52', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:53:31.967664+00', '0', 'false', NULL),
('12362871-82b2-4980-b842-50046dff71be', '91b39afb-4b1f-4f29-9e58-57baa8422449', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '370', '1ed1bd3d-57f2-41ee-94a4-c5365573ab60', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 15:00:05.705532+00', '10', 'false', NULL),
('13bac632-754d-49ad-9c8f-df69c8a80e6c', '000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '8787b0fc-035f-4f8b-b183-290cce87c603', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 14:35:07.594622+00', '0', 'false', NULL),
('1422d372-3408-43ed-a1aa-d674d5cbfcdf', '4a6d992a-2911-4b7c-9462-abbf77e781f9', '7e538107-a218-47e5-9daa-8d2763445b5e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '340', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-15 12:27:07.967054+00', '16', 'true', NULL),
('15490be1-b994-4a08-9e42-24d2f9e22eff', '1d952609-d721-49cf-bbad-011370e867a5', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'bf566dab-57f3-4eeb-acc4-92a61e0a3708', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 14:10:04.893875+00', '0', 'false', NULL),
('168c2fbb-a33b-40fa-80dd-84f580579139', '5557b435-0c50-4108-87f4-78d2c38f4c2d', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'c1efe9d7-e7e7-4e6e-a676-a417d71ee1e0', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:42:12.619081+00', '0', 'false', NULL),
('16c73ec6-fde4-4375-9cd9-fde149fc8e04', '232b3983-b09d-4ba7-b8dc-291b1ed0f1b8', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 09:34:17.195808+00', '10', 'false', NULL),
('1784c79f-e060-49a9-9b10-a23a0e95f14c', '539bbd29-bdc2-4a35-8993-1603ee952adc', '6c880fed-268a-4a2a-a8d6-b4c30c151211', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 13:40:48.83529+00', '0', 'false', NULL),
('18a7b176-bde7-4d1b-8e10-5efa70ea50dd', '31ac52d8-b464-451d-86fc-6dd979037447', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '848b2704-5ce9-4d36-ad7f-c39fc00b137e', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 13:35:26.078211+00', '0', 'false', NULL),
('18d22c9c-984c-4035-bba0-886c6798d8a8', '91b39afb-4b1f-4f29-9e58-57baa8422449', '08572b9e-65bb-46a9-8267-409a49dffe6e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 03:29:45.768305+00', '0', 'false', NULL),
('1a12c797-4c9a-42e6-acd0-e69365944949', 'abf264d3-6c22-4e86-a7dd-7f8f34826d0f', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 12:46:49.726466+00', '10', 'false', NULL),
('1a6607ff-11ee-4bad-9cf6-2cbca152df53', '753f58cd-5efa-4ee7-8822-f6ab41826489', '6c880fed-268a-4a2a-a8d6-b4c30c151211', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-11 07:31:34.250957+00', '0', 'false', NULL),
('1aacc7b3-f8cb-4747-a740-bd24a0e0b9a2', '232b3983-b09d-4ba7-b8dc-291b1ed0f1b8', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 09:34:21.952495+00', '10', 'false', NULL),
('1b1063c9-bc26-431e-a121-c786d9822b96', '639fc253-3fc9-4dca-ace5-2dbe078f47da', '78261ab1-3948-46c8-b5c6-7621398af6fc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '30bd2af5-ca1d-4532-b5ef-ee90e9467fe3', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-22 13:58:36.919281+00', '0', 'false', NULL),
('1b4429a5-3a2b-44ee-b4b5-5555463138a7', '0ad3b624-7c8b-4155-83e6-59614b8cd1ea', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 11:18:58.115223+00', '0', 'false', NULL),
('1c8c45f4-c41c-4059-b20f-a21fca04c211', '702b1756-4601-4448-9781-60c76f7669e8', '6c880fed-268a-4a2a-a8d6-b4c30c151211', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 13:47:00.676911+00', '0', 'false', NULL),
('1cd3fbd9-f240-454b-9c8c-890f9ae5505f', '95e3414d-9b71-46aa-8f46-d3087a65dddf', 'c073a4ab-4437-4565-849f-c4a610c3525b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'absent', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 11:20:08.777697+00', '0', 'false', NULL),
('1f83d4bd-bd12-4775-80c7-258e7ccf0153', 'bb62cb2f-1d6f-4a2d-816f-d36637fe40a8', 'f6af0dd7-8905-4467-a298-27ec99ff9be3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '380', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-01 18:33:24.525312+00', '15', 'false', NULL),
('1f8a873b-866e-488a-84b4-1ae084f515f9', '1c144d5f-7bcd-410c-920a-84f4159320de', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 12:29:57.686076+00', '10', 'false', NULL),
('1fdbff78-fc83-4942-953d-bc7d06948bd4', '37f74e5d-1368-4877-908e-582e7eaeb192', '80416764-8767-4960-ab9e-d9047ef32f43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:51:25.626345+00', '0', 'false', NULL),
('20a66dca-b744-4430-9c13-49770491d6d5', '3ca29392-6b4f-45a6-a60e-a822148b729e', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '420', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 09:33:00.013143+00', '5', 'false', NULL),
('222888bf-c1e8-4468-ab2c-3b825f5303d9', 'e1a8bce7-2b4c-488a-83d0-279f4e0cad11', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 13:42:11.429286+00', '10', 'false', NULL),
('27c4d94d-459d-4ac5-a234-999819541cb6', 'e1a8bce7-2b4c-488a-83d0-279f4e0cad11', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-16 13:40:17.70098+00', '0', 'false', NULL),
('2a07bc37-5979-4f45-bef8-2fa7c2d3381f', '97236184-eb55-40c1-9ced-4d6bcc933e8e', 'bd02b3c6-bef2-4775-95e4-54f4dcec7544', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 11:46:09.056189+00', '0', 'false', NULL),
('2b0d6164-8cd2-4a0b-8f4c-802bfc4ae2e1', 'ffb14310-780c-49e7-a4b9-60e3d787c7ee', 'd2451baa-b8e3-4403-9192-f179984de641', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '370', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-05 13:45:11.644532+00', '0', 'false', NULL),
('2b52fa41-ef18-4a4f-b242-f705dcf64f1f', 'dea6cbf4-35c6-48ad-a8c4-227235ddec16', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 12:07:40.72889+00', '0', 'false', NULL),
('2dea7bbd-4ef4-453f-b0df-e87e80740f8a', '45739435-11ed-4d8c-b7d8-d86337e28c0d', 'd5fba59f-d806-40fe-8de1-6e498156a182', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', 'a620fe27-c956-4d7e-b475-95708bd663a1', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-23 14:15:12.712168+00', '0', 'false', NULL),
('2eb314f2-813e-4264-8ee8-d4f04239b31f', '325ff33b-66f4-4511-b759-f5559aba18b8', 'ca69e2e7-a023-4814-8df8-82d39d191886', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '439d4a60-3a16-4feb-b45d-472c8b128ceb', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 11:09:54.175838+00', '0', 'false', NULL),
('2f9f0803-1ae0-4971-a3ad-d2f3635f828e', '91b39afb-4b1f-4f29-9e58-57baa8422449', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 10:38:57.608035+00', '0', 'false', NULL),
('30f9d182-cb9c-46a8-add9-5436c0be9211', '232b3983-b09d-4ba7-b8dc-291b1ed0f1b8', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'bf566dab-57f3-4eeb-acc4-92a61e0a3708', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 14:09:43.900508+00', '0', 'false', NULL),
('312f76ae-e7f5-4bf8-9ee5-5194be381c65', '199b4019-226b-497e-8497-0686d46cb38b', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 10:30:56.181302+00', '0', 'false', NULL),
('32cc7e77-a439-4b02-babd-c241b8956314', 'a3c849f9-8ad0-4f30-b132-644ab68db310', '3fd870d2-916a-4e60-a7db-daa5f2a8ec03', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-25 15:29:56.783864+00', '0', 'false', NULL),
('33d9b540-4c26-445e-b19d-c6f123a152a6', '9a9b7555-c25e-4c2c-a5e0-73ce2f652ef6', 'd9dfe264-fdf8-41f5-92ca-87de083f4f29', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-23 13:51:18.763436+00', '0', 'true', NULL),
('34f43488-7f30-45cc-9bfb-533eca0be749', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', '0b9b1eca-81c8-4c87-bdf0-0b80a25a9ae9', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 16:17:30.324623+00', '0.0', 'false', NULL),
('352594aa-a132-4fd7-a493-796f77aed6db', 'bb62cb2f-1d6f-4a2d-816f-d36637fe40a8', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-01 18:33:35.586177+00', '0', 'false', NULL),
('35a32a92-27cf-4461-86b2-82a09ca00d2c', '753f58cd-5efa-4ee7-8822-f6ab41826489', '09b20d74-f3da-4342-b268-017f66ac101e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 12:36:25.648288+00', '0', 'false', NULL),
('36bc803a-c621-4369-acc9-2d60e7ed48eb', '2b68e2be-73c4-41cc-bed7-12fc80bcbb07', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'c3955d8f-fc2a-4f0d-befc-aceded24689e', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 14:59:41.32262+00', '0', 'false', NULL),
('36fcb901-7fd9-44f3-bb46-661e4648851e', 'a3c849f9-8ad0-4f30-b132-644ab68db310', 'd5fba59f-d806-40fe-8de1-6e498156a182', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', 'a620fe27-c956-4d7e-b475-95708bd663a1', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:12:25.002691+00', '0', 'false', NULL),
('388c8536-9f23-4bfa-9220-0fa2e1a7833d', '325ff33b-66f4-4511-b759-f5559aba18b8', '320747d4-9733-45ea-a0b6-86f0654aef24', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 11:10:50.500207+00', '0', 'false', NULL),
('38d53434-6719-4beb-9e94-e8f8cce7001f', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'fdb5f116-3717-4fd3-b27a-14c1cf5c9f5b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 12:13:35.852023+00', '0', 'false', NULL),
('3b7071d7-ea7e-42f5-bf4f-0ceaf53e1cae', 'c8de471e-bba4-46cd-a558-2d3ba774ac17', '78261ab1-3948-46c8-b5c6-7621398af6fc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '30bd2af5-ca1d-4532-b5ef-ee90e9467fe3', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:05:37.050102+00', '0', 'false', NULL),
('3db55cce-4898-4efe-b9d6-c473c4840ae8', '31ac52d8-b464-451d-86fc-6dd979037447', '1e3b0597-a906-4eb0-9d0c-623a70b9ac67', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 14:06:46.242533+00', '0', 'false', NULL),
('3ec917bf-d4f4-44bf-b278-6d09dcf9cccb', 'd221272e-d869-4172-b838-42684fa7a94d', '7e538107-a218-47e5-9daa-8d2763445b5e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-04 12:18:44.382616+00', '0', 'false', NULL),
('403a6c25-5e14-482f-87d1-e5808d1b57f3', '000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', '09b20d74-f3da-4342-b268-017f66ac101e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 14:31:19.287991+00', '0', 'false', NULL),
('40748da5-1893-4e7d-bb88-6611b2507b73', 'dea6cbf4-35c6-48ad-a8c4-227235ddec16', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 12:07:40.115912+00', '0', 'false', NULL),
('415c56b5-f3dd-4c00-bdf6-1a7362ba109a', '9a9b7555-c25e-4c2c-a5e0-73ce2f652ef6', '66f1e3e2-c7b0-411c-8d28-411e0f4c20da', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-23 13:51:17.623631+00', '0', 'true', NULL),
('4164ab2a-aa69-44b9-9756-d32a81ce03ec', '1ea29b9a-6477-42c2-9703-1188f3e66dde', '80416764-8767-4960-ab9e-d9047ef32f43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '440', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-09-22 11:53:11.917703+00', '0', 'false', NULL),
('41c38165-d0fd-4462-8eeb-94c0a78492ff', 'c16de641-3998-4565-a3a1-ef681557d39b', '08572b9e-65bb-46a9-8267-409a49dffe6e', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'cash', '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 15:38:54.966993+00', '0', 'false', NULL),
('4217951c-95df-4a32-9146-8ad2653b73b2', '95e3414d-9b71-46aa-8f46-d3087a65dddf', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '5f89f353-2738-4057-9de5-aa2b12dafa8a', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:24:17.036672+00', '0', 'false', NULL),
('44ecb2ff-2675-4323-85e8-abb6b23c01a0', '000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', '6c880fed-268a-4a2a-a8d6-b4c30c151211', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'absent', NULL, '0', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-25 20:10:52.44804+00', '0', 'false', NULL),
('471cfbef-7690-4b2e-80e8-6ea0ca924612', 'ddddef08-da4f-4165-bc18-28584ea46f7e', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'bf566dab-57f3-4eeb-acc4-92a61e0a3708', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 10:46:49.199755+00', '0', 'false', NULL),
('47f496ed-b6b3-4fb8-8d0b-7c36489fdc58', '470294c2-4592-4082-aec4-494eaea7b0fc', 'ca69e2e7-a023-4814-8df8-82d39d191886', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '439d4a60-3a16-4feb-b45d-472c8b128ceb', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:18:41.188358+00', '0', 'false', NULL),
('49436733-a9d4-448d-8708-2cc8243258a1', '5144b63c-7cfd-4e50-9e9d-0b46881007f6', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '69ae0c5b-a795-40c6-9bb3-4690dab67488', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 12:15:09.795464+00', '0', 'false', NULL),
('49d45179-d6d3-4e57-ad5d-f4be09e3e8f0', '94797ebd-b40f-4377-96e2-8de24bc91ca3', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '1ed1bd3d-57f2-41ee-94a4-c5365573ab60', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 15:00:15.219716+00', '0', 'false', NULL),
('4a58d62e-6db1-44dc-b736-e05c6853d8ea', '2b68e2be-73c4-41cc-bed7-12fc80bcbb07', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 09:36:41.566574+00', '0', 'false', NULL),
('4a861e7b-7640-48c8-89c8-317d781d9e5b', '31ac52d8-b464-451d-86fc-6dd979037447', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 14:06:53.54873+00', '10', 'false', NULL),
('4c3917b2-8d7b-49f3-a3c2-4ac1eb090d7d', '0222a3ed-518d-44f5-b696-6f95153289aa', 'd9dfe264-fdf8-41f5-92ca-87de083f4f29', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-05 15:02:49.071863+00', '0', 'true', NULL),
('4dbed15c-d323-46f8-a872-bc329ea7ee06', '2eac99f7-63dd-4f88-967b-a5ba0eb59fbe', 'd5fba59f-d806-40fe-8de1-6e498156a182', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', 'a620fe27-c956-4d7e-b475-95708bd663a1', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:12:47.01344+00', '0', 'false', NULL),
('4e81b7a3-a2a6-41b1-ac08-2a9bf1a18af0', '55074bff-20ed-4074-a530-c8baa0d23bbc', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '490', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 14:07:02.087896+00', '0', 'false', NULL),
('4ed7dc5d-8eef-4351-b21c-c98384ba2ce6', '1c144d5f-7bcd-410c-920a-84f4159320de', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'fab83083-7b6c-4ce7-a031-e8c5c22731bc', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 13:45:47.927254+00', '0', 'false', NULL),
('4f6a058a-e03c-4f53-b783-00105940f022', '470294c2-4592-4082-aec4-494eaea7b0fc', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '280', '5f89f353-2738-4057-9de5-aa2b12dafa8a', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:24:05.419293+00', '20', 'false', NULL),
('4f9e48b4-753e-4d5c-9cbf-afcbb193989b', '3870ece3-ace8-40e3-889e-ac5455bdf8a7', '00b11be9-337b-4e89-b9af-c0aec4d7930a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '660', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-15 14:33:03.663248+00', '0', 'false', NULL),
('507d0bf7-9603-4886-9314-8bf9c2b52dbf', '089823af-b6ca-41e2-a06b-797da3a3241b', '0c9af1bb-b47b-42a7-a770-095553ab98df', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 15:32:41.171424+00', '0', 'false', NULL),
('519d34ef-8336-46c8-8be5-60f0a5b2766c', '8aa769e8-0c50-4a46-88f6-2b5f16c05c6c', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 09:22:00.733993+00', '0', 'false', NULL),
('51ee2713-d17b-467e-8765-1a61db0af32f', '346bef1b-a769-4a0c-93f6-8b1c4e4ea022', '6ccebb1c-7124-4a5c-9585-3c99c2029681', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '660', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-28 17:06:40.902495+00', '0', 'false', NULL),
('5312b186-877c-4061-8aba-80af2867dfe0', '9235f3c8-b0f3-495c-8d97-4989e35e46e8', '6c880fed-268a-4a2a-a8d6-b4c30c151211', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 14:47:10.553408+00', '0', 'false', NULL),
('54226b29-dae6-4b0c-85c3-8134ea8a5c2e', '31ac52d8-b464-451d-86fc-6dd979037447', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'fc6f3a2f-5650-4637-876f-446ef6376eba', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-11-07 13:38:53.312163+00', '0.0', 'false', NULL),
('559f51ce-4dfb-401b-8bb8-6d8c9d577110', '3e872f13-e9d7-4978-bfc4-f6a2b84d14d0', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 09:33:37.993799+00', '10', 'false', NULL),
('57443ebd-da43-4b83-b298-d8488cf90b61', 'dea6cbf4-35c6-48ad-a8c4-227235ddec16', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '69ae0c5b-a795-40c6-9bb3-4690dab67488', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 12:16:43.14718+00', '0', 'false', NULL),
('57c1e4f3-dc59-4947-8897-0b756fb79df8', 'a0a85659-5d7b-415f-8a29-8b1b4d4e55cf', '6ccebb1c-7124-4a5c-9585-3c99c2029681', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-15 10:07:57.691612+00', '0', 'false', NULL),
('5a527b9d-c78f-4fc0-904c-5929d150afa8', 'c84d3555-c005-4bc6-ad06-25ed349006d8', '08572b9e-65bb-46a9-8267-409a49dffe6e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 09:12:07.209686+00', '0', 'false', NULL),
('5b293a98-1aff-4fb1-8072-e646716ba5cf', '9b323a39-4e4d-49e0-afe8-f746250f2148', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 13:01:00.711236+00', '0', 'false', NULL),
('5b59ed23-5a97-4913-a817-8327572eb102', '325ff33b-66f4-4511-b759-f5559aba18b8', '80416764-8767-4960-ab9e-d9047ef32f43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 11:03:15.155574+00', '0', 'false', NULL),
('5f979867-2ee9-4e19-a53a-cba6cedb7aa6', 'c76ef1ad-d412-4b43-b633-9833652ca9a8', 'c904d118-af0a-4582-a15e-c36e690a5766', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '10ec7a2b-2561-4ffc-b2ec-d086254e6212', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:08:30.097524+00', '0', 'false', NULL),
('60db0749-6247-4c24-a2c5-a5b644fce712', '5144b63c-7cfd-4e50-9e9d-0b46881007f6', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 10:45:50.901022+00', '0', 'false', NULL),
('62cedac8-9694-4919-b9a0-23d1347b1342', '3a30af7a-d675-4887-9288-1b4dcd583e18', 'e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-24 08:30:43.708485+00', '0', 'false', NULL),
('643bf02a-11b9-4267-b080-67ebdd993cd1', 'c84d3555-c005-4bc6-ad06-25ed349006d8', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'c3955d8f-fc2a-4f0d-befc-aceded24689e', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 14:59:19.300161+00', '0', 'false', NULL),
('6549d0dc-536b-4a5d-9cc8-974b8f4ada39', 'ed0035b9-f256-41ff-a1d1-e4958a272c51', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:56:00.007309+00', '0', 'false', NULL),
('662d1c46-453a-48fc-9f92-913c7cf72bf0', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 09:37:18.31317+00', '10', 'false', NULL),
('6695e1a3-1145-4daa-98c6-7988bfb07f89', '55074bff-20ed-4074-a530-c8baa0d23bbc', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '450', 'dffa701a-2af1-48b4-a151-928c2bd5b649', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 14:07:06.605043+00', '0', 'false', NULL),
('66a5aef5-9688-4de2-b628-24c3c916bf16', '53312f9a-aa0a-4a28-b83f-e2246c0f366b', 'd2451baa-b8e3-4403-9192-f179984de641', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 11:15:11.994647+00', '0', 'false', NULL),
('66adbcec-da0b-4b83-9f61-0d8caf439908', '702b1756-4601-4448-9781-60c76f7669e8', '28511a97-5dca-4516-b5e0-afc636c23dd2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 12:31:56.579957+00', '0', 'false', NULL),
('66e8a413-57b3-47a9-9c07-3648e50fc677', '539bbd29-bdc2-4a35-8993-1603ee952adc', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'da020fe0-eaf4-4b0e-91a4-fbd841898193', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 13:39:02.871099+00', '0', 'false', NULL),
('68f7838b-01e3-41a8-afd2-f926ca2233cc', 'ffb14310-780c-49e7-a4b9-60e3d787c7ee', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '280', '6758d4fc-8400-410e-b57a-7c7f5d5804bc', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-05 13:46:53.685228+00', '20', 'false', NULL),
('6958c345-aa22-4aa9-8286-573143be3b94', '199b4019-226b-497e-8497-0686d46cb38b', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-30 12:42:05.186811+00', '0', 'false', NULL),
('69697026-8ca0-484a-8cfa-3f95b88e8896', '9235f3c8-b0f3-495c-8d97-4989e35e46e8', '09b20d74-f3da-4342-b268-017f66ac101e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 13:42:18.651235+00', '0', 'false', NULL),
('6adafe83-cbf4-4ac1-998c-de0f620253c3', '2eac99f7-63dd-4f88-967b-a5ba0eb59fbe', '00b11be9-337b-4e89-b9af-c0aec4d7930a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-16 12:41:09.587685+00', '0', 'false', NULL),
('6b4b53e2-e0cf-426a-ae9e-a94eb3161481', '753f58cd-5efa-4ee7-8822-f6ab41826489', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '8787b0fc-035f-4f8b-b183-290cce87c603', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 14:34:51.1197+00', '0', 'false', NULL),
('6b8e41c9-6bc0-45b2-ab4a-bb587fcffc97', '37f74e5d-1368-4877-908e-582e7eaeb192', 'ca69e2e7-a023-4814-8df8-82d39d191886', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '5b8a5c99-af7a-43ca-be4c-0fcb72a4f3e2', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:51:14.898681+00', '0', 'false', NULL),
('6c5e5b17-209c-40f0-97be-a7b9076055e9', 'b1d67bb8-df37-4bc2-bc68-8ceba59f8c45', '80416764-8767-4960-ab9e-d9047ef32f43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 11:02:32.964666+00', '10', 'false', NULL),
('6d5d22c5-608c-48b9-b7fc-14a9c91b23f6', 'eda51042-f49c-4290-81f4-d2e11f0723d5', 'c904d118-af0a-4582-a15e-c36e690a5766', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '10ec7a2b-2561-4ffc-b2ec-d086254e6212', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:08:20.260657+00', '0', 'false', NULL),
('6dc2e2be-a615-430d-b3c5-2ec49ffd123f', '639fc253-3fc9-4dca-ace5-2dbe078f47da', 'c904d118-af0a-4582-a15e-c36e690a5766', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '10ec7a2b-2561-4ffc-b2ec-d086254e6212', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-22 13:57:35.574223+00', '0', 'false', NULL),
('6e36ed3f-ffb5-4b56-a00f-8f7b7f645945', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', '88b1789a-7485-4d0d-a5a9-b101706c0961', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'absent', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 12:21:03.703953+00', '0', 'false', NULL),
('6e988d27-4d0e-400b-8167-62194119b47c', '7851f70d-3f50-4728-ac55-ab15e32fec0e', '6ccebb1c-7124-4a5c-9585-3c99c2029681', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'excused', NULL, '0', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-25 15:26:14.658369+00', '0', 'false', NULL),
('6f8cc849-857d-46f6-95ed-a2396f3dae69', '94797ebd-b40f-4377-96e2-8de24bc91ca3', 'da959919-410e-40a1-88d0-da5bf9712012', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 09:14:28.609488+00', '0', 'false', NULL),
('701d150f-78f0-474d-ac35-a29e1b7560e1', '37f74e5d-1368-4877-908e-582e7eaeb192', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:51:23.023077+00', '0', 'false', NULL),
('70721840-54e0-4c87-9ba2-222ec947285c', 'abf264d3-6c22-4e86-a7dd-7f8f34826d0f', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 12:33:44.533135+00', '10', 'false', NULL),
('7171a9b4-dcbc-4d9a-b8ae-2943f2d1236f', '5b2420f6-07e8-4c4c-966d-5137bc31c21d', '08572b9e-65bb-46a9-8267-409a49dffe6e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 10:36:37.888522+00', '0', 'false', NULL),
('73c3cd73-709d-4e51-a591-f095a622972c', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', 'd5fba59f-d806-40fe-8de1-6e498156a182', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-03 11:47:29.326714+00', '0', 'false', NULL),
('73e08224-60b5-4c1c-a7a2-ef7df2a11171', '92279374-9dcf-463c-b8f0-f742c90d5dc8', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'c1efe9d7-e7e7-4e6e-a676-a417d71ee1e0', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 11:37:52.636474+00', '0', 'false', NULL),
('74805a21-9959-4ff4-b6ca-7524eae6d9c9', '7aba4c46-9191-41e8-b6c9-be3d5d49e70d', 'd2451baa-b8e3-4403-9192-f179984de641', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '370', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-22 09:11:41.003802+00', '0', 'false', NULL),
('75382041-44fd-48d0-9af9-f87d6ade942d', '3fb0e385-49c5-4709-9c13-6fca611d229f', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-28 08:07:24.959977+00', '0.0', 'true', NULL),
('7683130d-1fea-4f7e-817d-5182eb2acc95', 'a0a85659-5d7b-415f-8a29-8b1b4d4e55cf', 'c904d118-af0a-4582-a15e-c36e690a5766', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '10ec7a2b-2561-4ffc-b2ec-d086254e6212', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:08:38.669444+00', '0', 'false', NULL),
('7763fc5a-827b-431b-a51b-4a8d9a4aae62', '0e623a52-80a2-4df8-b62b-a85cfc614f45', '7e538107-a218-47e5-9daa-8d2763445b5e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '340', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-02 13:28:27.240421+00', '16', 'false', NULL),
('78d94aaa-d216-423c-b56f-7898b9eab732', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 13:18:09.998327+00', '0', 'false', NULL),
('79a428c2-c7ce-418e-926e-a584a8d37972', '06315bbc-565d-413f-b5d1-306fd726151d', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 11:01:31.778644+00', '10', 'false', NULL),
('7adf667d-4154-41ec-b32c-84cb611bbf97', '470294c2-4592-4082-aec4-494eaea7b0fc', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 08:45:41.38677+00', '0', 'false', NULL),
('7c091ad2-f85d-46f4-bc06-857eacd4c83b', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', '00b11be9-337b-4e89-b9af-c0aec4d7930a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 16:40:50.9948+00', '0', 'false', NULL),
('7c333c41-4bf6-4279-9a80-703164190b7c', '0abf27db-e6eb-4f32-b51e-7227663a4415', 'd2451baa-b8e3-4403-9192-f179984de641', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-14 16:39:23.831361+00', '0', 'false', NULL),
('7d3b4042-ae1a-4299-9cdc-e53defbfb95e', 'dcc1ba13-1b40-49fd-bbec-746bb2d0352f', '09b20d74-f3da-4342-b268-017f66ac101e', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-19 10:36:57.551903+00', '0', 'false', NULL),
('7e39ae00-9465-477c-a61c-b9e45ca3842c', 'abf264d3-6c22-4e86-a7dd-7f8f34826d0f', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'fab83083-7b6c-4ce7-a031-e8c5c22731bc', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:37:54.679603+00', '0', 'false', NULL),
('7ef0e2fb-3e0c-4d8c-b270-b57c3cd4de98', '92279374-9dcf-463c-b8f0-f742c90d5dc8', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '0', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-24 22:42:44.414713+00', '100', 'false', NULL),
('7ffa5c8d-1750-4086-9931-51033735f7d8', 'f2fc1a93-6fd6-4d15-a932-818a5d51963d', '88b1789a-7485-4d0d-a5a9-b101706c0961', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'absent', NULL, '0', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-26 19:59:36.263121+00', '0', 'false', NULL),
('8064d104-9a20-45a3-aae7-66cd64c00548', '2bd234a7-bd14-406c-9e61-d59f009d14d2', '80416764-8767-4960-ab9e-d9047ef32f43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 10:56:13.081109+00', '10', 'false', NULL),
('8185f24d-70dd-4b8f-95d0-081a75607e49', '1a813807-3bb4-49f3-8ce2-f7f3b86b4644', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-27 14:34:54.716716+00', '0', 'true', NULL),
('81c06c9f-e9b5-4551-8f3e-e67abd0d5c04', '95e3414d-9b71-46aa-8f46-d3087a65dddf', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 15:17:47.699853+00', '0', 'false', NULL),
('852bdc60-d785-4f51-a431-312587e82a41', '6833df5f-f1c9-46ae-aed2-8f82cb6d9076', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'cash', '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 13:27:31.280333+00', '0', 'false', NULL),
('861bff58-6fb5-4943-b18e-441845251dda', '2eac99f7-63dd-4f88-967b-a5ba0eb59fbe', 'e6ba5875-3763-49ec-a21d-972d1806edca', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-16 14:51:04.247156+00', '0', 'false', NULL),
('86804723-13e1-4e83-9cf5-7f7a81a1f568', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', '80416764-8767-4960-ab9e-d9047ef32f43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 12:52:28.820454+00', '0', 'false', NULL),
('86857a60-75a8-4719-a873-72c5c42dad8c', '1e2edbdf-57c1-4e4d-807d-5cf968d0fd29', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'cash', '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 12:30:01.442764+00', '0', 'false', NULL),
('86a53685-b067-4508-bd0f-61f1c7407c96', '31ac52d8-b464-451d-86fc-6dd979037447', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 13:35:21.100992+00', '0', 'false', NULL),
('876ad3e5-d15d-4f8a-bf1c-e2fa29708b9c', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 12:31:09.431058+00', '0', 'false', NULL),
('883aba82-0afe-4af1-a0f2-1fc3d325b993', '0abf27db-e6eb-4f32-b51e-7227663a4415', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '4cac3325-d21c-45e8-8dbf-9a67947dd168', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 09:28:35.495598+00', '0', 'false', NULL),
('89d24177-6a20-4093-9b4d-c0ec5c649311', '68875410-b3ac-4841-872a-f45c2f7353d8', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '490', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 13:42:04.278794+00', '0', 'false', NULL),
('8a52301d-5925-4a7c-9905-52b2343b4039', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:53:20.339823+00', '0', 'false', NULL),
('8c0602b6-c321-4398-b286-ddc6d103e9da', '1c144d5f-7bcd-410c-920a-84f4159320de', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-23 13:57:37.0558+00', '0', 'false', NULL),
('8cfe196a-8d21-4ce1-951e-6e5b26065fcf', 'f2fc1a93-6fd6-4d15-a932-818a5d51963d', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-25 14:10:56.157236+00', '0', 'false', NULL),
('8efba6c6-24d5-41f1-bae1-169ba153a32d', 'ff84ab59-df43-4b83-a32c-61711dd233bf', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 11:46:18.629519+00', '0', 'true', NULL),
('8f7d091f-93b0-4dc6-9f85-eeb248551ab4', '3e872f13-e9d7-4978-bfc4-f6a2b84d14d0', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'c1efe9d7-e7e7-4e6e-a676-a417d71ee1e0', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 10:50:24.790723+00', '0', 'false', NULL),
('91d6c2ae-607b-4eec-9285-17383de32caf', '1d952609-d721-49cf-bbad-011370e867a5', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 09:34:11.088677+00', '0', 'false', NULL),
('9226b90e-96ec-4389-962d-f68839b3026b', '3fb0e385-49c5-4709-9c13-6fca611d229f', '7e538107-a218-47e5-9daa-8d2763445b5e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-28 08:07:21.992043+00', '0', 'false', NULL),
('93079b55-8284-444d-bbc8-6f92eb6c2e55', '22a88243-93c1-4144-a537-2f4e2840d42f', 'ca69e2e7-a023-4814-8df8-82d39d191886', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '439d4a60-3a16-4feb-b45d-472c8b128ceb', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:18:25.849585+00', '0', 'false', NULL),
('942c8354-e180-4697-ab9f-7e1b20599c8e', 'ec6b5402-91ba-445c-a00b-3aa409204b81', '80416764-8767-4960-ab9e-d9047ef32f43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '400', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-24 13:25:10.177372+00', '10', 'false', NULL),
('95edcb63-107a-4b84-8584-5821afbbba78', '2f4e8a00-37a0-479a-8624-cec48a45adad', '44db9928-9c11-4689-acaa-aea1f78ac7b7', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 10:30:34.364126+00', '0', 'false', NULL),
('97b29d96-bc76-4377-ac1f-0d0b29f7325b', '7aba4c46-9191-41e8-b6c9-be3d5d49e70d', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '310', '4cac3325-d21c-45e8-8dbf-9a67947dd168', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-22 13:29:56.787275+00', '17', 'false', NULL),
('97b52f44-c1c8-4c30-8e8f-32cb20223aff', '8749f3e8-4439-4f94-8878-91404ccb5d21', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '490', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 08:48:03.20239+00', '0', 'false', NULL),
('98abb89a-8f13-4f1b-a930-086cddfa435d', '22a88243-93c1-4144-a537-2f4e2840d42f', '80416764-8767-4960-ab9e-d9047ef32f43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:16:45.926862+00', '0', 'false', NULL),
('98c9b8e2-2ad3-47ce-a25f-027f23001477', 'abf264d3-6c22-4e86-a7dd-7f8f34826d0f', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-01 15:04:31.523073+00', '0', 'false', NULL),
('994bfd3e-09af-47fc-b669-cf8950e109dd', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 12:06:11.633186+00', '0', 'false', NULL),
('9a7ea810-bd37-4eec-96b6-f96e27aacc7b', 'eda51042-f49c-4290-81f4-d2e11f0723d5', '6ccebb1c-7124-4a5c-9585-3c99c2029681', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-01 14:11:22.691777+00', '0', 'false', NULL),
('9b291510-2456-4ff9-a94f-28876ae716e3', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', 'e6ba5875-3763-49ec-a21d-972d1806edca', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 16:40:56.752043+00', '0', 'false', NULL),
('9bd91c9b-21ca-482e-80c6-bfabbae619eb', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '8787b0fc-035f-4f8b-b183-290cce87c603', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 14:34:59.087549+00', '0', 'false', NULL),
('9c0632ef-c882-4354-b296-dbfd74444f7c', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', '6c880fed-268a-4a2a-a8d6-b4c30c151211', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 13:57:00.532562+00', '0', 'false', NULL),
('9c80dc38-2f9b-4717-99b4-a2fedf0e3c1b', '1fd5f793-d702-4c9d-b6c4-69e48b92b6fc', '80416764-8767-4960-ab9e-d9047ef32f43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-26 10:54:52.699549+00', '0', 'false', NULL),
('9cbedb6a-0af3-4753-ab15-71268a555d49', 'c16de641-3998-4565-a3a1-ef681557d39b', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'cash', '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 15:28:46.263191+00', '0', 'false', NULL),
('9d8bc6e0-dfcd-4580-9253-a9c1cfdd96d9', 'cd84373a-c655-4755-9ffd-391cc884bc9c', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '450', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-27 17:18:49.870314+00', '0', 'false', NULL),
('9e79cb1b-6dc5-4f52-b49f-8948ff309d34', 'dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'absent', NULL, '0', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-09-21 18:05:00.3506+00', '0', 'false', NULL),
('a076fa82-7b7c-41ec-97e7-f6ae1d22f05a', '7465ed42-bc2d-41e1-85c8-e8a22b7b7d19', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'cash', '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 12:33:49.317254+00', '0', 'false', NULL),
('a2f28889-e6a0-477d-ac85-528a157bd137', '68875410-b3ac-4841-872a-f45c2f7353d8', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '450', 'dffa701a-2af1-48b4-a151-928c2bd5b649', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 13:42:00.556076+00', '0', 'false', NULL),
('a415fe11-67f6-40f5-ae6d-b83a6159f461', '199b4019-226b-497e-8497-0686d46cb38b', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'e542dfea-de9f-4f8f-9dc2-ea3af9b6ab28', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 13:39:42.463513+00', '0', 'false', NULL),
('a4179942-2122-4250-85a4-fd9c16c9e889', '089823af-b6ca-41e2-a06b-797da3a3241b', 'e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 15:32:43.962284+00', '0', 'false', NULL),
('a4747b81-e4a8-494c-bb9e-e9e0c1f89ec4', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', '09b20d74-f3da-4342-b268-017f66ac101e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 12:20:11.375016+00', '0', 'false', NULL),
('a49f1690-5574-4302-8c51-0b6d64a7629b', 'd6282d22-364a-4d7f-aa34-da6fcafebfc7', '80416764-8767-4960-ab9e-d9047ef32f43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 10:56:04.052458+00', '0', 'false', NULL),
('a520d1f0-890a-438d-9668-4da942a92ff1', '91b39afb-4b1f-4f29-9e58-57baa8422449', 'ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '33ce036e-e5f1-4913-9e5f-a67c198a1d15', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 10:27:21.726034+00', '0', 'false', NULL),
('a719da4d-4b94-46b9-b295-2095d26592e5', '753f58cd-5efa-4ee7-8822-f6ab41826489', '28511a97-5dca-4516-b5e0-afc636c23dd2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-11 07:31:32.963216+00', '0', 'false', NULL),
('a95600e5-25e2-428d-8f73-4d0b43d83473', '5b2420f6-07e8-4c4c-966d-5137bc31c21d', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'c3955d8f-fc2a-4f0d-befc-aceded24689e', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 14:59:52.94265+00', '0', 'false', NULL),
('abb99b6d-96f3-469b-afb1-8d78451ad328', '470294c2-4592-4082-aec4-494eaea7b0fc', '80416764-8767-4960-ab9e-d9047ef32f43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 15:12:51.879406+00', '0', 'false', NULL),
('abfa969b-9ac4-48bf-925a-612fcedd69ff', 'e6ffcc87-38c1-4ce6-89be-bef5aac26672', '00b11be9-337b-4e89-b9af-c0aec4d7930a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '660', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-05 15:02:44.593823+00', '0', 'false', NULL),
('ad9ead2e-73d4-46d7-9d2e-7fbf56fba271', 'ef6b5a3f-2ebe-42db-be3b-68e612bce07b', 'd5fba59f-d806-40fe-8de1-6e498156a182', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 15:31:02.852512+00', '0', 'false', NULL),
('ae7a2504-e8d2-4af0-8c83-35252d4f3677', 'c76ef1ad-d412-4b43-b633-9833652ca9a8', 'd5fba59f-d806-40fe-8de1-6e498156a182', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', 'a620fe27-c956-4d7e-b475-95708bd663a1', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:12:39.015669+00', '0', 'false', NULL),
('aed4afe0-23e5-4abc-a521-1ad6729524fd', '94797ebd-b40f-4377-96e2-8de24bc91ca3', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 10:23:45.112104+00', '0', 'false', NULL),
('af20a967-02f0-49ce-bd9b-8858620a5ef2', 'bf130da3-f342-488c-8acf-ec9cf15b3219', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '4cac3325-d21c-45e8-8dbf-9a67947dd168', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-28 17:06:47.890596+00', '0', 'false', NULL),
('b0f63fcf-7099-427f-8ee0-2e476a728949', '8aa769e8-0c50-4a46-88f6-2b5f16c05c6c', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'c3955d8f-fc2a-4f0d-befc-aceded24689e', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 14:59:33.2698+00', '0', 'false', NULL),
('b1186ca9-80aa-4887-860d-b5246c33fb3b', '8da183e7-5415-4c1d-a8bf-cd0c61f08cfd', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 10:36:02.172682+00', '0', 'false', NULL),
('b18a9357-2d9f-47c8-8368-4587e7ba94e3', '575e4f94-7889-4375-8b52-4b747bc89ea7', 'a57be370-0f09-4e81-ac2c-579095cebe97', '85701c53-77ce-4783-a157-e21476b16d4c', 'present', 'card', '380', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-18 14:41:55.362716+00', '15', 'false', NULL),
('b3220fa3-c034-45de-9ee4-10e94f7729b5', '3a30af7a-d675-4887-9288-1b4dcd583e18', '320747d4-9733-45ea-a0b6-86f0654aef24', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-24 08:30:39.169649+00', '0', 'false', NULL),
('b442e07d-907e-482f-905d-20ceaea6b80a', 'c8de471e-bba4-46cd-a558-2d3ba774ac17', '6ccebb1c-7124-4a5c-9585-3c99c2029681', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 14:57:49.8447+00', '0', 'false', NULL),
('b6d98ac0-84f9-4e14-8539-6378ed151c8e', 'bf130da3-f342-488c-8acf-ec9cf15b3219', 'd2451baa-b8e3-4403-9192-f179984de641', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '370', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 10:56:58.01461+00', '0', 'false', NULL),
('b7510471-c278-491e-b541-2afb175ef468', '1e2edbdf-57c1-4e4d-807d-5cf968d0fd29', '08572b9e-65bb-46a9-8267-409a49dffe6e', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', NULL, '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 13:45:41.78245+00', '0', 'false', NULL),
('b7957a49-0f89-47e7-aad6-81efa956f336', '5144b63c-7cfd-4e50-9e9d-0b46881007f6', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 10:45:57.717279+00', '10', 'false', NULL),
('b894d9cb-f9af-48ee-ab20-d2454bd35998', '97236184-eb55-40c1-9ced-4d6bcc933e8e', 'bd160e22-40d7-4826-8c2a-659cdac3ec4b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 11:46:03.561822+00', '0', 'false', NULL),
('bb0163f1-9495-498a-9882-84e534fda091', '325ff33b-66f4-4511-b759-f5559aba18b8', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '5f89f353-2738-4057-9de5-aa2b12dafa8a', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 11:03:01.766122+00', '0', 'false', NULL),
('bb22b048-0c34-4eb5-acbd-8f26c1d95e52', 'ed0035b9-f256-41ff-a1d1-e4958a272c51', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:55:57.343236+00', '0', 'false', NULL),
('bb3580fa-f26d-47d2-ba45-12bed149ada7', 'ddddef08-da4f-4165-bc18-28584ea46f7e', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 10:46:46.644539+00', '0', 'false', NULL),
('bba6be9d-2fc4-4b94-a318-4385b23df3f9', '089823af-b6ca-41e2-a06b-797da3a3241b', '320747d4-9733-45ea-a0b6-86f0654aef24', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 15:32:42.630031+00', '0', 'false', NULL),
('bc5d70af-e76a-4b3f-b179-6b815c8daf28', '4a6d992a-2911-4b7c-9462-abbf77e781f9', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-12 15:41:53.193346+00', '0', 'true', NULL),
('be506b49-789e-4a89-9990-92c077b8fdd4', '3ca29392-6b4f-45a6-a60e-a822148b729e', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'bf566dab-57f3-4eeb-acc4-92a61e0a3708', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 14:09:53.614866+00', '0', 'false', NULL),
('bfcb6032-8860-4d9a-9d70-a0fe46ddaef1', 'e1a8bce7-2b4c-488a-83d0-279f4e0cad11', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'fab83083-7b6c-4ce7-a031-e8c5c22731bc', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:38:20.444817+00', '0', 'false', NULL),
('c096e8e0-b55d-48b5-bd8a-ff6f6a950714', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', 'ca69e2e7-a023-4814-8df8-82d39d191886', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '1bad7eb8-6a5c-4ebd-9ea2-879efdf4fc8b', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 13:08:41.220484+00', '0', 'false', NULL),
('c3af120b-0cf1-46f0-9ea4-36ac06a06e5e', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', '78261ab1-3948-46c8-b5c6-7621398af6fc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'subscription', '390', '30bd2af5-ca1d-4532-b5ef-ee90e9467fe3', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-06 15:38:20.087346+00', '0', 'false', NULL),
('c43cd908-55a0-40fb-8f43-43112c8bb68b', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:53:35.726314+00', '0', 'false', NULL),
('c6260a8f-9875-4b44-9d5f-4615210ec7d9', 'e1a8bce7-2b4c-488a-83d0-279f4e0cad11', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'e542dfea-de9f-4f8f-9dc2-ea3af9b6ab28', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 13:41:02.726996+00', '0', 'false', NULL),
('c6b60521-9ccb-494a-a914-022b17ea6efb', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'ca69e2e7-a023-4814-8df8-82d39d191886', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '1bad7eb8-6a5c-4ebd-9ea2-879efdf4fc8b', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 12:11:25.116089+00', '0', 'false', NULL),
('c6cefa85-4c85-486b-9c05-4cbe0ab920b6', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '5f89f353-2738-4057-9de5-aa2b12dafa8a', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 12:52:39.830958+00', '0', 'false', NULL),
('c83a9dd9-1984-4f7a-95d6-df52ede3a119', '92279374-9dcf-463c-b8f0-f742c90d5dc8', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 09:34:27.727946+00', '0', 'false', NULL),
('c85fbf27-0c0c-47b1-b535-8718b770a012', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', '320747d4-9733-45ea-a0b6-86f0654aef24', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 12:52:43.411211+00', '0', 'false', NULL);
insert into public.lesson_attendance ("id", "lesson_id", "student_id", "owner_id", "status", "payment_method", "amount", "subscription_id", "marked_by", "marked_at", "discount_percent", "print_enabled", "print_price") values
('c939aec6-9335-438b-b576-f710ef65ff5c', '3e872f13-e9d7-4978-bfc4-f6a2b84d14d0', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 09:33:31.98496+00', '100', 'false', NULL),
('c9509d2d-a5f4-4bc8-8b5b-300bc2dfb273', 'a9fda877-9ae0-4d02-8f24-300f09ee5c4b', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'fab83083-7b6c-4ce7-a031-e8c5c22731bc', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:38:09.947865+00', '0', 'false', NULL),
('c9becbb3-1c3a-43aa-ae5f-ef623fa9ccca', 'bb62cb2f-1d6f-4a2d-816f-d36637fe40a8', 'a57be370-0f09-4e81-ac2c-579095cebe97', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '330', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-01 18:34:17.604332+00', '23', 'false', NULL),
('ca30220d-cf80-4196-b5fc-7226af97b265', '95e3414d-9b71-46aa-8f46-d3087a65dddf', 'ca69e2e7-a023-4814-8df8-82d39d191886', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '439d4a60-3a16-4feb-b45d-472c8b128ceb', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:18:51.821038+00', '0', 'false', NULL),
('cb15ee9d-439e-4d07-bce5-26de9b9926db', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', '28511a97-5dca-4516-b5e0-afc636c23dd2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 12:32:45.502243+00', '0', 'false', NULL),
('cbe2f9ce-4e25-4f09-8856-7e4ade718e49', '95e3414d-9b71-46aa-8f46-d3087a65dddf', '80416764-8767-4960-ab9e-d9047ef32f43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 10:32:25.086948+00', '10', 'false', NULL),
('ccfa02ef-4b5e-4379-944b-58b7741b9273', '22a88243-93c1-4144-a537-2f4e2840d42f', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 12:34:13.843811+00', '0', 'false', NULL),
('cd3204a3-32ad-4442-ab5b-07c91ea318ec', '8aa769e8-0c50-4a46-88f6-2b5f16c05c6c', 'ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 08:40:23.287432+00', '0', 'false', NULL),
('cdedbd9d-53da-4616-bae8-c3794c1527a0', '8da183e7-5415-4c1d-a8bf-cd0c61f08cfd', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 14:48:08.362755+00', '0', 'false', NULL),
('d4faecf2-9a9f-4cec-a22c-352bfd7f1c02', '8749f3e8-4439-4f94-8878-91404ccb5d21', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '450', 'dffa701a-2af1-48b4-a151-928c2bd5b649', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 12:24:29.877883+00', '0', 'false', NULL),
('d5168325-7684-4591-ac00-3de888fad71b', '3a30af7a-d675-4887-9288-1b4dcd583e18', '0c9af1bb-b47b-42a7-a770-095553ab98df', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-24 08:30:48.537647+00', '0', 'false', NULL),
('d53351d5-ff9d-4f25-a6ab-2f6761270723', '539bbd29-bdc2-4a35-8993-1603ee952adc', '09b20d74-f3da-4342-b268-017f66ac101e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-11-08 16:41:43.427081+00', '0', 'false', NULL),
('d558ebb6-ced5-4001-b3b6-ba91811ed411', '85a42bdd-a939-4606-b0cd-453f0edf586e', '80416764-8767-4960-ab9e-d9047ef32f43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 10:32:14.070253+00', '0', 'false', NULL),
('d6105f04-8537-47eb-a5d3-4a38199573cd', '2f4e8a00-37a0-479a-8624-cec48a45adad', '80416764-8767-4960-ab9e-d9047ef32f43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 10:30:34.375028+00', '10', 'false', NULL),
('d66ce528-2ded-4b9c-8dd8-cf69af3d15b0', '2bd234a7-bd14-406c-9e61-d59f009d14d2', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '280', 'eeba61b7-94e8-439b-9e5b-b65367c8466a', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 12:00:04.905489+00', '20', 'false', NULL),
('d6efe1c2-2de4-4ce9-843f-ad7362c2da36', '3ca29392-6b4f-45a6-a60e-a822148b729e', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '420', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 09:32:57.09847+00', '5', 'false', NULL),
('d86de8c7-f750-4dc5-9305-7793893adb5d', 'c76ef1ad-d412-4b43-b633-9833652ca9a8', '00b11be9-337b-4e89-b9af-c0aec4d7930a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-09 16:28:04.901238+00', '0', 'false', NULL),
('d9701eeb-347f-4111-9a80-36b5ad7574e8', 'cc1a1f76-62fc-46c4-a6ad-ebfcb83ec504', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:59:13.365424+00', '0', 'false', NULL),
('da6f988f-7f60-4eba-bc62-ef1d6e21559f', '5b2420f6-07e8-4c4c-966d-5137bc31c21d', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 14:47:11.285563+00', '0', 'false', NULL),
('dc959d20-a672-49b2-9501-bf653cb63df8', '325ff33b-66f4-4511-b759-f5559aba18b8', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 12:04:42.934265+00', '0', 'false', NULL),
('dc9c58be-78ff-4c54-8089-011ccce76ad9', 'a9fda877-9ae0-4d02-8f24-300f09ee5c4b', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 08:47:35.19371+00', '10', 'false', NULL),
('deae18e2-de07-45c7-b2e5-94648e016793', '9b323a39-4e4d-49e0-afe8-f746250f2148', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 13:01:05.070313+00', '0', 'false', NULL),
('df0151e0-d15c-442f-9c6a-e2750b5e80e1', '702b1756-4601-4448-9781-60c76f7669e8', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '8787b0fc-035f-4f8b-b183-290cce87c603', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-25 14:34:39.517857+00', '0', 'false', NULL),
('df97a26d-2961-43b5-a150-246e68ce9a54', '470294c2-4592-4082-aec4-494eaea7b0fc', '320747d4-9733-45ea-a0b6-86f0654aef24', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 08:47:06.538708+00', '0', 'false', NULL),
('dfbda62f-8c70-4fbb-a54a-0213e5d352e3', '0ad3b624-7c8b-4155-83e6-59614b8cd1ea', '7e538107-a218-47e5-9daa-8d2763445b5e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 11:18:57.108703+00', '0', 'false', NULL),
('dfd262bf-e025-4aa8-aba5-2c487f6a2017', '3a30af7a-d675-4887-9288-1b4dcd583e18', '9d017639-4958-4772-a563-884569c04bf6', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-24 08:30:45.596855+00', '0', 'false', NULL),
('e1b03922-ebfe-4fe4-8d9d-d78b396c1880', '199b4019-226b-497e-8497-0686d46cb38b', '92f2560c-5a4c-4067-8459-e46f8226c9a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '400', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 13:27:25.630298+00', '10', 'false', NULL),
('e3357f67-d3f1-490a-895d-b40c3e80f3d4', '06315bbc-565d-413f-b5d1-306fd726151d', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', '7010ac26-c5f2-427a-a1d4-fbc7a4cffd7d', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 10:24:06.969575+00', '0', 'false', NULL),
('e47e4f62-c19e-46cc-b35f-10d300345f6e', 'c84d3555-c005-4bc6-ad06-25ed349006d8', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 09:11:51.299578+00', '0', 'false', NULL),
('e5e5fa61-05e1-44ce-b1c6-3b10be2a17db', '575e4f94-7889-4375-8b52-4b747bc89ea7', 'f6af0dd7-8905-4467-a298-27ec99ff9be3', '85701c53-77ce-4783-a157-e21476b16d4c', 'present', 'card', '300', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-18 14:42:13.10143+00', '24', 'false', NULL),
('e63d2b58-44c6-4483-9c42-3549c91e0695', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:53:11.536232+00', '0', 'false', NULL),
('e80f19e9-618b-4448-ba49-1b6ca2237e11', '45739435-11ed-4d8c-b7d8-d86337e28c0d', 'e6ba5875-3763-49ec-a21d-972d1806edca', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-23 14:15:19.10602+00', '0', 'false', NULL),
('eb17b3d1-4892-4dd8-aaf9-27e2c5101404', '0e623a52-80a2-4df8-b62b-a85cfc614f45', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-30 16:16:54.797781+00', '0', 'false', NULL),
('edc8e557-d6b4-4fc8-bc85-0495b98d7b06', '94797ebd-b40f-4377-96e2-8de24bc91ca3', 'ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-11-08 18:19:39.021252+00', '0', 'false', NULL),
('ef9285e1-dd85-475a-9450-0faa872a266f', 'c8de471e-bba4-46cd-a558-2d3ba774ac17', 'c904d118-af0a-4582-a15e-c36e690a5766', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 11:15:29.781365+00', '0', 'false', NULL),
('ef9c7e7f-9afc-4f92-aca6-8cecca47dfdd', 'f2fc1a93-6fd6-4d15-a932-818a5d51963d', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-25 14:23:01.203745+00', '0', 'false', NULL),
('f006f473-93da-432c-81dc-b9403df12398', 'eda51042-f49c-4290-81f4-d2e11f0723d5', '78261ab1-3948-46c8-b5c6-7621398af6fc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '2026-10-02 11:48:28.851128+00', '0', 'false', NULL),
('f048a9eb-f05b-4f47-b7b7-b79c07d66c4e', '7851f70d-3f50-4728-ac55-ab15e32fec0e', 'c904d118-af0a-4582-a15e-c36e690a5766', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', NULL, '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-25 15:26:17.915709+00', '0', 'false', NULL),
('f1f80cd3-8646-468e-bebd-722f5b985625', '95e3414d-9b71-46aa-8f46-d3087a65dddf', '320747d4-9733-45ea-a0b6-86f0654aef24', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-17 12:03:42.813262+00', '0', 'false', NULL),
('f20cbfae-468b-447a-b02f-f7fcb885a562', 'f2fc1a93-6fd6-4d15-a932-818a5d51963d', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-25 14:10:55.303725+00', '0', 'false', NULL),
('f2b6b799-72fe-498b-9152-ffa00653fae4', '546eb2bd-cee5-4ff2-b9eb-6c81d167e688', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '450', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-27 19:14:02.052989+00', '0', 'false', NULL),
('f61705cd-2cc7-4e88-9963-33b07bbc01c6', '539bbd29-bdc2-4a35-8993-1603ee952adc', '28511a97-5dca-4516-b5e0-afc636c23dd2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 14:06:37.634326+00', '0', 'false', NULL),
('f6e9b29f-4247-41c6-bd86-a73ea0c27782', '94797ebd-b40f-4377-96e2-8de24bc91ca3', '08572b9e-65bb-46a9-8267-409a49dffe6e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'cash', '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 10:01:55.158907+00', '0', 'false', NULL),
('f7630882-cbbf-4ff4-97ec-8f1fe3f5bcb0', 'a9fda877-9ae0-4d02-8f24-300f09ee5c4b', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'e542dfea-de9f-4f8f-9dc2-ea3af9b6ab28', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 08:47:43.926481+00', '0', 'false', NULL),
('f95091e3-2e90-4847-af5e-d3f4fe315d18', '7465ed42-bc2d-41e1-85c8-e8a22b7b7d19', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'present', 'card', '450', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 12:46:39.391059+00', '0', 'false', NULL),
('fb40a9bc-707e-4938-be83-9973e29dc24f', '9235f3c8-b0f3-495c-8d97-4989e35e46e8', '28511a97-5dca-4516-b5e0-afc636c23dd2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'card', '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-11-01 13:25:24.78516+00', '0', 'false', NULL),
('fc1b1ef9-a3f3-4e40-a8e7-7512ed5e95a9', 'da7186c9-cc9b-4bb7-b62f-bcfbfef34f86', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'excused', NULL, '0', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-08 10:28:47.701037+00', '0', 'false', NULL),
('fd4fb255-6af0-4807-8f60-676f5feb44cb', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'd1819c58-e0a6-4bf4-ae9e-82cc84bc6d05', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', NULL, '440', NULL, '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 11:56:13.922887+00', '0', 'false', NULL),
('ff3955c9-28b6-4f6c-91ad-da81d3e4bc7e', '9235f3c8-b0f3-495c-8d97-4989e35e46e8', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'present', 'subscription', '390', 'da020fe0-eaf4-4b0e-91a4-fbd841898193', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-11-01 13:34:52.877005+00', '0', 'false', NULL),
('ffffde38-c7ff-4d18-8187-b01b8028bc60', 'dcc1ba13-1b40-49fd-bbec-746bb2d0352f', '80416764-8767-4960-ab9e-d9047ef32f43', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'present', 'cash', '440', NULL, 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-19 10:37:02.590503+00', '0', 'false', NULL);
insert into public.lessons ("id", "owner_id", "series_id", "date", "time", "theme", "student_ids", "created_at", "course", "format", "extra_service", "payroll_amount", "price_amount", "duration_minutes", "room", "substitute_owner_id", "completed", "print_default") values
('000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-10-25', '15:30', 'Тема 8', '{716fd538-274d-43a0-9a4a-f9c47858d92c,09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', 'Клас AI', NULL, 'false', 'false'),
('00990d54-e67c-4611-a7ca-9381c939149f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-02-15', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('0108a0b2-7003-4fc3-8982-2a77e621691e', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-03-04', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('019cdef4-73ce-46e3-882f-3df832143e11', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-01-24', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('01a51062-299d-4c37-99c0-9e67b48fef27', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-04-17', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('0222a3ed-518d-44f5-b696-6f95153289aa', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-11-05', '18:20', '1.3 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'true', 'true'),
('02a68e15-425c-4bac-809e-289e708122b4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-20', '15:30', 'Кольоровий друк. 2 урок', '{28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211,716fd538-274d-43a0-9a4a-f9c47858d92c,c90f9850-c36e-4a24-9a58-388cf32c97ed}', '2026-09-19 10:51:53.015767+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('02b65e0e-3496-4511-8fe3-6ad09d05ad34', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-03-06', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('03502653-ccca-4ab1-bf25-345be5cbdc77', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-11-12', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('03651755-960c-4f15-9ff4-f87f6adf61c3', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-12-31', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('04a4d875-c837-4fba-84f9-687fe7bdaa90', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-03-24', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('0500091d-04ee-4481-9262-0cbdfa256c91', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-02-11', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('05dcb9cf-8eb4-4887-9670-de218f83dcf8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-01-18', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('06315bbc-565d-413f-b5d1-306fd726151d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-11-08', '12:30', 'Smart life. 10 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('06f21346-9a00-44e3-bcf6-99fdae10dc7e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-11-28', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('07c37d81-2415-456c-852a-de7cb50a6f26', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-12-23', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('07ec6135-dc08-4c0f-a1d9-651acfef9877', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-11-29', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('07f659a2-8270-4bf4-94d7-27aab28db200', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-01-27', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('089823af-b6ca-41e2-a06b-797da3a3241b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-11-04', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('094ae370-3d90-407e-93b2-9d96e5019dd2', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-12-24', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('097d862b-ca3a-44ec-a2a3-ba5a213296d6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-12-28', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('0abf27db-e6eb-4f32-b51e-7227663a4415', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-10-14', '18:00', '2 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-10-04 13:30:33.763655+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('0ad3b624-7c8b-4155-83e6-59614b8cd1ea', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-10-05', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-01 14:34:00.089669+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('0b456612-85be-44bd-8ecb-db2b9fa7e41b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-04-19', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('0bb88d1a-abb2-469e-b271-a8bdc6686a79', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-01-31', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('0c562733-70c6-449d-b86e-a20a718d54b6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '7176230b-5165-4a75-8f18-cab4d100e3c3', '2026-08-29', '14:00', '.', '{}', '2026-09-09 20:25:32.637899+00', '3D MakersEmpire', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('0c8208e8-f215-47a7-9eb5-ff40c5948df8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-01-02', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('0d1d35dd-1b9e-444e-9615-d6742c068282', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-02-10', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('0e13af45-8ba4-467d-b62a-f532e53012e8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2027-01-10', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('0e48fb0e-1f2e-425d-baa7-4d9471b31b9e', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-12-16', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('0e623a52-80a2-4df8-b62b-a85cfc614f45', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-30', '18:00', '1 урок', '{a89a18b5-3741-4158-98cb-3b99b677d5c3,7e538107-a218-47e5-9daa-8d2763445b5e}', '2026-09-30 16:13:11.075275+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('0e784061-c070-4a46-9f2f-4e123c6abea0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-02-07', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('0e97ae08-e09d-4055-9840-baa785aa4a4a', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-11-14', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('0e9fd379-590e-4b5b-a291-302035cd5034', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-12-05', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('0f9565e4-1adc-44c8-8c81-32955d8ce476', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-03-29', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('10236fa0-956a-42e4-bd36-0344457114e4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-04-17', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('1053d096-9d96-4ced-8167-76b0856c55e1', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-03-22', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('11e36d30-95a6-4463-b6ea-4246eb131294', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-20', '16:45', 'Очі кота', '{3e299914-0e61-4a28-9979-b95afb618630}', '2026-09-19 10:52:20.531747+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('1284a5cb-f63a-4d53-9079-999df82b107d', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-12-24', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('12cfd91e-fe9e-4d53-9ed8-f2accbc9171d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-02-27', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('133de994-6671-4b9b-b716-430370360548', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-12-26', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('13cf0263-5324-4c38-9d56-4cf34d406d98', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-03-18', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('13e21c4e-2029-48d9-914a-c89039d9eac2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-05-01', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('1483bd29-bdf6-4e28-a1de-08a16ae1905d', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-01-21', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('155171ad-a388-433d-b125-96b70d57c008', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-12-12', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('15f6e15e-67e4-4ef1-88f6-5d335e3d889d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-12-12', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('16c19b99-2f0f-4514-9b79-852d8ae3e706', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-12-30', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('176bcce7-e2d5-4ba1-a5e1-72bf28307f66', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-01-20', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('18424164-2c3f-4d87-a59a-40bd43aba8b5', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-03-10', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('195b969a-1f38-47c7-9a88-8270b9f473e5', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-02-19', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('199b4019-226b-497e-8497-0686d46cb38b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-10-31', '15:30', '4.9', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('1a813807-3bb4-49f3-8ce2-f7f3b86b4644', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-21', '18:00', 'Шарнір горизонтальний', '{b7bdaa70-d2fd-4490-aa99-11af4a7c58d0,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-09-24 19:34:47.293184+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('1abc7fd8-dfc6-461d-a8d1-759b9d080f7c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-02-28', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('1b21665a-e668-4c5a-b74c-752e3031e6bb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-03-13', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('1b2a95d7-bd9a-43e1-be16-23c974776097', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-04-03', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('1bbbb05c-7d2c-4c1d-ab2c-182a7da17438', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-11-19', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('1c144d5f-7bcd-410c-920a-84f4159320de', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-10-24', '15:30', 'Урок 8', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', 'Клас AI', NULL, 'false', 'false'),
('1c9518d9-9b69-4b5f-824c-59745f6371df', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-12-03', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('1d952609-d721-49cf-bbad-011370e867a5', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-10-18', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('1de0d4f8-799e-43a7-8adb-6ebcf0f9bc2f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-01-13', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('1e2edbdf-57c1-4e4d-807d-5cf968d0fd29', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-10-24', '16:45', 'Batman', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', 'Клас VR', NULL, 'false', 'false'),
('1e4b46ad-b34d-42e7-a144-0b002d4e3a9b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-03-10', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('1ea29b9a-6477-42c2-9703-1188f3e66dde', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', NULL, '2026-09-19', '12:15', '9 урок (Творча)', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-09-18 08:47:32.291158+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('1ec50272-9734-4709-a139-d1c684e41381', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2027-01-24', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('1f23456b-fb21-4298-bf9c-b740bf88693e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-12-27', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('1f6ffdf3-871d-42d1-915c-078e31066787', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-01-07', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('1fd5f793-d702-4c9d-b6c4-69e48b92b6fc', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', NULL, '2026-09-26', '12:15', 'Жирафа', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-09-26 09:08:25.813969+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('206cdc9c-6dc0-44ba-9fa0-5244e26bad83', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-12-19', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('207a6d14-872e-473d-9a5d-50a576fba93d', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-02-24', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2099619b-f4b6-4703-b86f-769eb26619a0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-12-06', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('209a43c5-5296-4cce-8350-aac122fac08e', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-12-05', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('20a64708-4bb3-44b0-a270-8080db8f5e6d', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-01-30', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('22a88243-93c1-4144-a537-2f4e2840d42f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-10-03', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb}', '2026-09-27 12:49:47.560904+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('232b3983-b09d-4ba7-b8dc-291b1ed0f1b8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-10-04', '12:30', 'Smart life. 5 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:24:48.437882+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('23b80a93-7485-4533-8f08-ccc218234123', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-12-31', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('246ae80c-91e6-421b-b4a6-96a7a178f72e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-06-07', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('25685133-1a31-4b03-b826-2a9449c132bb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-01-30', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('262d9e92-90bb-4f6b-b470-cba6904a36aa', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-01-11', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('26fb622d-7ba5-43bb-9945-4ce26de08513', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-12-25', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('288d0710-e41a-4642-bcc0-422580314d73', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-12-05', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('2980121f-8a44-41f5-b278-d4626684d76f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-04-07', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2a1e478c-9160-4d54-9986-1e7f64bedadd', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-11-14', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('2a66bd7f-04bd-472f-a0ba-0c0e8c4d0a3a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-03-11', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('2a93b12b-bd7e-44f7-a32c-3d51b22e6c40', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-12-21', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('2b68e2be-73c4-41cc-bed7-12fc80bcbb07', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-10-18', '11:15', 'тема 7', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,82690e1c-139d-45e1-b8b4-95c071215298,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2bd234a7-bd14-406c-9e61-d59f009d14d2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-11-07', '14:00', 'Тюлень', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24,fdb5f116-3717-4fd3-b27a-14c1cf5c9f5b,d1819c58-e0a6-4bf4-ae9e-82cc84bc6d05}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('2cdf4e2b-5a1c-41c2-8355-95e2060337a9', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-04-16', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2d0a1925-967b-41bf-acbd-88a2a0655af3', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-04-30', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2d3e703e-347b-4b9b-aac3-53ba2c39c8b8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-11-15', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2de303c7-07b7-4249-b3eb-509297d072e0', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-12-03', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2eac99f7-63dd-4f88-967b-a5ba0eb59fbe', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-10-16', '17:15', '6 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,00b11be9-337b-4e89-b9af-c0aec4d7930a,e6ba5875-3763-49ec-a21d-972d1806edca}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('2f4e8a00-37a0-479a-8624-cec48a45adad', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-10-31', '12:15', 'тема 14', '{80416764-8767-4960-ab9e-d9047ef32f43,44db9928-9c11-4689-acaa-aea1f78ac7b7}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('311493f6-c210-45c1-975e-61af3e0d9b5a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-02-08', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('31ac52d8-b464-451d-86fc-6dd979037447', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-11-07', '15:30', 'Урок 5.1', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2,1e3b0597-a906-4eb0-9d0c-623a70b9ac67}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('31d009a9-eae5-4dc4-add9-a3cb1a82d6b2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-11-23', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('3213c1be-3773-4a4b-aef3-f7b2a3c02926', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-04-12', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('325ff33b-66f4-4511-b759-f5559aba18b8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-10-24', '14:00', 'Морські риби', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', 'Клас AI', NULL, 'false', 'false'),
('332ff428-caf9-448d-84da-8e40c52ea5c5', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-03-08', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('346bef1b-a769-4a0c-93f6-8b1c4e4ea022', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-10-28', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-10-22 13:28:50.39375+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'true', 'false'),
('3631218c-11e0-4c77-9b27-d51df6ec199d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-11-15', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('36a076d3-f8de-4ded-a4c7-162c4eb3d503', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-01-23', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3710fa33-63e6-4c83-a37d-3b5035ed8de6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-01-25', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('372e0393-d97e-4f9b-a7f5-e41d4502b135', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-02-20', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('37dc20a8-ea5d-4164-b54d-0bf2a76970b5', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-01-15', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('37f74e5d-1368-4877-908e-582e7eaeb192', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-09-26', '14:00', 'Творче. Казковий світ', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40}', '2026-09-27 12:49:47.560904+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3870ece3-ace8-40e3-889e-ac5455bdf8a7', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-10-15', '16:00', '1+2 урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-14 16:46:34.313697+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('389a210f-edb5-40cc-8149-9c9a31d8eed2', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-05-12', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('38ecc74c-85e9-40ff-a54e-79167358723d', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-02-17', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('392f0d0c-1f65-4271-824c-78fae6412342', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-03-20', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('392faa1b-dfa9-4939-8972-f7d42d5903f4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-12-19', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('39408f0c-dfec-40fa-b05d-1e0a87a74025', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-03-24', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3a30af7a-d675-4887-9288-1b4dcd583e18', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-10-23', '15:00', 'Замок', '{320747d4-9733-45ea-a0b6-86f0654aef24,837fd648-c58f-4150-b98b-3b39fa377217,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581,9d017639-4958-4772-a563-884569c04bf6,359776e3-246a-40d5-b8aa-03f9d821bc24,0c9af1bb-b47b-42a7-a770-095553ab98df}', '2026-10-23 14:35:29.296461+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3a4b0a29-0c3e-474c-b86c-4c04e077bf3f', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-12-23', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('3a68e6aa-f08b-4cba-9e45-b21ff79b7353', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-11-09', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('3a9dca56-5d67-40f0-912a-ed78e07fd29e', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-12-18', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3b18be5b-5ffd-480f-aa87-500f714a827a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-02-20', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('3c2f9b96-30a4-475a-8cb7-950e66ecd20a', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-09-03', NULL, 'Урок 1', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-09-13 17:26:44.805592+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('3c4d97d4-0ec0-4868-8dbc-e7596319bf4e', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-02-27', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('3ca29392-6b4f-45a6-a60e-a822148b729e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-10-11', '12:30', 'Smart life. 6 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('3d88064c-ff25-4902-b1ad-bb9da5f29dc8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-04-05', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('3da3400c-c69a-4499-9c82-ac56e46c32ce', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-05-01', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3e872f13-e9d7-4978-bfc4-f6a2b84d14d0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-10-11', '14:15', 'Пінгвін', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44,91cd18e5-294e-4d9c-998e-6da8cc9019a4}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('3ed6ade0-60ff-4815-8652-b7fa9fea14e2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-10-18', '14:15', 'Сортування сміття', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3f1ff9e3-fd2e-42ac-b1ee-ac1c85e4ecef', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-04-01', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('3fb0e385-49c5-4709-9c13-6fca611d229f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-10-26', '18:00', '4 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'true', 'false'),
('3fbb8815-0f30-49ac-b217-85146694ab44', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-12-06', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('3fd26216-c7ad-4480-aa4e-88dd9f1355e7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-12-13', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('405c7321-39eb-4398-959b-4a9198542de7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-01-11', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('409bc932-87e8-436a-8cbc-01b186355f3f', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-01-06', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('40a58615-60e6-444d-b752-8d8b9754e244', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-03-20', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('40c5e801-e596-4aff-8d4c-4c6b156cacee', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-01-28', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('41b2a9ff-d54d-4812-9128-caf93a94aa25', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-01-16', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('41bd198a-279c-42df-a4ad-f918cce8533e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-11-21', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('42e9e2c3-78e8-4d95-aa3a-4350ced29f0f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-11-14', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('4380e524-06eb-451a-96fb-a6c58599e52a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-05-10', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('44e620e4-e02e-4e16-a2c9-b94c7fb4a640', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-02-20', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('44f51ba6-9920-47c7-b15c-6819f9200495', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-03-26', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('45739435-11ed-4d8c-b7d8-d86337e28c0d', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-10-23', '17:15', '7 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('459ede08-aea4-4418-921f-601ab0348da8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2027-01-17', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('460aac71-8ed7-408f-b0c9-b362a14abf3f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-05-06', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('470294c2-4592-4082-aec4-494eaea7b0fc', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-10-10', '14:00', 'Пінгвін', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,81c76f3d-c311-441f-a169-437c39c71d51,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('478600d2-e691-479c-9fde-e102b530b5bc', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-03-04', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('48ac66d0-31d8-4c94-8fb8-46ec3b9992c3', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-12-10', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('4973d1c2-d640-4f13-80cc-09c203ba91f3', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-04-15', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('4a4c9829-33d6-4818-8f2f-e93664c88d07', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-03-17', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('4a6d992a-2911-4b7c-9462-abbf77e781f9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-10-12', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('4bc1f41a-d140-47fc-a93e-f99a1f313e1f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-03-22', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('4d274647-4bac-42b8-8ce6-c19dd5d60340', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-03-14', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('4d7d5e22-37f6-47bc-86cf-7ac8097f61cf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-04-11', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('4e8c8e60-4c69-41f2-8bee-080421214473', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-12-12', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('4e8f15f7-8bda-4c7b-9bdf-5e0186a44127', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-04-01', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('4f2cd789-a704-49ff-a2b6-02f44981405f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-12-27', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('504170ed-a1c5-4059-b415-c3cc031ad706', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-01-25', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('50baf828-cfa1-4d04-92bf-a5e681e721b6', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-02-03', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5102a6ec-eb94-4c51-92d1-0a47ac718b89', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-03-31', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('5144b63c-7cfd-4e50-9e9d-0b46881007f6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-11-08', '14:15', 'Вулкан', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('51c35550-41be-4e6e-bc94-6117669c1c99', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-04-08', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5232ab56-08c1-4a03-809e-9dd61a235520', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-01-09', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('53088962-b583-4ebf-af23-99aeb68c482b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-01-16', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('53312f9a-aa0a-4a28-b83f-e2246c0f366b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-10-07', '18:00', '1 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-10-04 13:30:33.763655+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'true', 'false'),
('533809db-36f2-4f92-8487-fad2d1de7c48', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-12-31', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('539bbd29-bdc2-4a35-8993-1603ee952adc', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-11-08', '15:30', 'Тема 5.1', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('546eb2bd-cee5-4ff2-b9eb-6c81d167e688', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-10-27', '19:30', 'Проект "Школа"', '{001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-27 10:12:52.432921+00', '3D Tinkercad PRO (9-12)', 'individual_online', 'false', '240', '450', '60', NULL, NULL, 'false', 'false'),
('5476994a-ceb9-4077-bd78-b2ce5b08435b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-02-06', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('54d4210e-a5fd-45f9-ba10-c94c6527718b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-12-30', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('55074bff-20ed-4074-a530-c8baa0d23bbc', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-11-07', '16:45', '4', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'true', 'false'),
('551b0522-47ec-414f-a214-6f1d5c6db79d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-05-01', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5557b435-0c50-4108-87f4-78d2c38f4c2d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-20', '14:15', 'Еко-парк', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,27ae626f-fb4e-467b-9c7c-20b0cf892f44,d1fbf933-a1ef-45ee-9a75-4c976c50108b}', '2026-09-19 10:48:14.397447+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('558afed1-158a-4b9f-aeeb-8323eab95fbb', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-11-26', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('55980cd6-6ed7-4321-916e-49d52f4e1125', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', NULL, '2026-09-12', '16:45', 'QuestCraft Будівництво будинку', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,cb6ddd95-dd05-4ef7-a7ab-e83f1fadfed5}', '2026-09-13 21:59:23.050412+00', 'VR ІГРОВИЙ', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('56185442-495b-468e-b1f1-a1c4d9ec1cd2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-12-07', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('56a46b29-3c4d-4141-95d2-8e7d742fbcda', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-02-21', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('56d9de69-e235-4684-a174-ef124938edba', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-02-17', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5716fe1c-c241-414b-a565-3579404325d3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-04-10', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('575e4f94-7889-4375-8b52-4b747bc89ea7', '85701c53-77ce-4783-a157-e21476b16d4c', NULL, '2026-10-04', '16:45', '?', '{a57be370-0f09-4e81-ac2c-579095cebe97,f6af0dd7-8905-4467-a298-27ec99ff9be3}', '2026-10-04 09:13:41.864127+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('584373d7-18f4-4aea-a142-aa54cb9605a0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-04-03', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('595f12f9-1e70-4492-b82e-7874273d7370', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-05-09', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('598c8157-b8c8-4b02-a3bb-c2be1270b499', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2027-01-03', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('59e1a9fe-d04f-4f9e-a041-2bca8bb1acc5', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-02-03', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('5a238fd4-4275-457a-a878-ca14f90d6d66', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-01-01', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5b2420f6-07e8-4c4c-966d-5137bc31c21d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-10-25', '11:15', 'тема 8', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,82690e1c-139d-45e1-b8b4-95c071215298,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', 'Клас AI', NULL, 'false', 'false'),
('5ba7b318-4e6e-4c18-b071-0bf0cd18c757', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-12-19', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5beaab42-69cc-49c7-8427-235c745fc3b1', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-12-27', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5c2c9fe3-23bd-4184-8628-5e8597df5c00', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-05-16', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5cdccd41-6de8-4075-8c06-5733bb64da3d', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-01-06', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5ce6453a-a7fe-4804-96d8-96ae4fbb42cd', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-03-31', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5d44e7ce-5691-40a5-963d-b9335a252904', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-03-07', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('5ff15fe7-a35b-43d9-b3a0-b67aeb247602', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-03-05', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('6121eff0-f973-4485-97f3-493aec2af0a1', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-12-26', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('61d24d4e-c549-496e-ba4b-6d7af1acb984', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-12-12', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('61df4c61-aaa0-4b51-ba62-60385598dfaa', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-02-06', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('6284987e-25bf-4bc5-a950-eeeb4cc36f48', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-01-28', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('62ed30b1-7ec1-4b6b-b3bf-315477810b7f', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-01-13', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('639fc253-3fc9-4dca-ace5-2dbe078f47da', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-10-22', '17:00', 'Тема 7', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('65149aa8-7f28-4179-8a75-f9bdd716447c', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-03-03', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('651b700a-5b3d-4420-9817-ab2c35300ea6', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-04-29', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('651f0fcd-ce9a-43a0-9a2d-b3a5662c1ba6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-04-26', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('65b42e36-a6cc-41c6-9c10-4577cf73e53b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-03-25', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('65d1b9e6-4c42-49ce-b82c-8e58405392f6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-06-14', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('66e99d9c-6cb3-42d2-8af8-a4d7aba3793c', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-01-20', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false');
insert into public.lessons ("id", "owner_id", "series_id", "date", "time", "theme", "student_ids", "created_at", "course", "format", "extra_service", "payroll_amount", "price_amount", "duration_minutes", "room", "substitute_owner_id", "completed", "print_default") values
('6717f6da-9ce8-425e-9d67-e2b8b14c19ea', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-12-16', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('6764db1b-0781-44b1-a644-b308451c04d8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-11-28', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('6833df5f-f1c9-46ae-aed2-8f82cb6d9076', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-10-31', '16:45', 'Batman', '{92f2560c-5a4c-4067-8459-e46f8226c9a8}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '240', '450', '60', NULL, NULL, 'true', 'false'),
('6863610a-aaa5-40da-bdb2-e1b4c6d4fb5e', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-10-14', '19:30', '1 урок', '{c4849368-3e1a-4454-a794-03247b7dc88f,e2fd5bd5-5481-4a20-8f3e-33a8b29a0447}', '2026-10-12 15:44:31.429627+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('68875410-b3ac-4841-872a-f45c2f7353d8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-10-17', '16:45', 'тема 3.2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 13:39:52.418662+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('6956887f-d2d3-434f-8566-6831b763e3ee', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-05-08', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('6976adce-22f2-4d88-b744-92c35d5eb3bc', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-03-08', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('6bf8b5fe-ba07-470c-8733-8aed9cc93d23', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-02-01', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('6c8cdcd9-a202-42ea-8c21-109183c241cd', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-01-14', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('6d65bf87-2828-45b0-b522-4affe83e3e8b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-04-07', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('6d9a0d52-d82e-4071-957d-7c2755b80339', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-20', '12:30', 'smart life - 3 урок', '{6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,d1fbf933-a1ef-45ee-9a75-4c976c50108b,60e52e47-9158-4d49-94c5-99e8b1e9f7fb,e098aea3-1f11-4e21-ab48-5be7c82a54fb}', '2026-09-19 10:43:59.607482+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('6da1578b-ff8b-42e7-bea1-603e4c86c6da', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-03-03', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('6ee96863-3bd6-41f8-a0f0-1102e02367f8', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-11-12', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('6f198034-6101-4f3f-a95d-a3410d6f2483', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-20', '11:15', '2 урок', '{6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,dbeddff1-36f2-4b4a-9425-5be7d302b236,08572b9e-65bb-46a9-8267-409a49dffe6e,82690e1c-139d-45e1-b8b4-95c071215298,58d838f4-69b1-4c48-856a-704b908e4a7c,fd338a9c-a230-4eed-ac01-356bcbb0ac13}', '2026-09-19 10:41:35.569386+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('70239776-f500-4151-901e-58c331637bf4', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-12-10', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('702b1756-4601-4448-9781-60c76f7669e8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-10-04', '15:30', 'Тема 5', '{716fd538-274d-43a0-9a4a-f9c47858d92c,09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-01 14:27:17.13092+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('706d0472-04c4-4ee1-ba2a-7c034470a820', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-04-03', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('708a8543-3a41-4d4d-bd36-2bde7dd16101', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-12-14', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('71881c9e-fc5d-4853-81b8-e3246df679e7', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-02-18', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('72099f23-add8-4ba7-b808-d051dd6d87e5', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-11-21', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('73b52600-4360-47a6-ac96-1b0913027871', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-09-11', NULL, 'Урок 1', '{}', '2026-09-13 17:31:17.298864+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('7429bd95-ba57-4636-b846-a2eb857101b8', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-02-13', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('7465ed42-bc2d-41e1-85c8-e8a22b7b7d19', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-10-03', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('74999aa4-4cf3-42e4-84cb-6dfaa30630cb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-03-27', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('753f58cd-5efa-4ee7-8822-f6ab41826489', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-10-11', '15:30', 'Тема 6', '{716fd538-274d-43a0-9a4a-f9c47858d92c,09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('766117c4-fb74-4426-8fa9-3b78a0b931f7', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-05-05', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('76c6bc48-0652-4446-a292-3375fdf0006a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-04-17', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('77366715-59f8-4523-8d9a-9e65372e682c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-11-28', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('7741a06f-e0e9-4997-9153-9300c924c524', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-01-23', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('7851f70d-3f50-4728-ac55-ab15e32fec0e', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-09-24', '17:00', 'Тема 4', '{6ccebb1c-7124-4a5c-9585-3c99c2029681,c904d118-af0a-4582-a15e-c36e690a5766,59971532-66d5-462a-b070-89881602d45b,e71bdf4e-71ab-4093-93a0-875379392e6a}', '2026-09-23 15:15:12.347776+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('78c30ed3-f9fc-41f3-9b1e-8eb62a2d9ca0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-12-05', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('79047c06-8db0-454f-a831-75621ec7ab43', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-12-12', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('797867df-2336-4920-b2a7-e33bfdb9cd2a', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-11-12', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('79b93e67-d8d9-41e3-aa15-61e02152e9d8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-05-17', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('7aba4c46-9191-41e8-b6c9-be3d5d49e70d', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-10-21', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-10-16 14:55:50.351038+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('7ae698f5-b482-4fa6-b83e-e8cdb57d2217', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-01-06', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('7bb9f45e-6774-48a0-8534-6a75107d308b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-12-16', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('7c5dafa0-5ab8-44f6-89d2-c080d781c346', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-12-19', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('7d0f5930-2517-40ac-90c6-01b76493feae', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-01-21', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('7f4b9a84-9e70-4fac-80c5-7bf107323d00', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-12-02', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('8002f706-7fc1-474a-be13-c750fdc728d8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-02-20', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8086b277-379c-45b4-a22e-dad5fbd4dcf3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-02-22', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('81b1f5f7-76b2-4982-b735-dc5bfdb8c856', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-02-10', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8301d52b-d20d-41f9-9752-4b687f478843', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-19', '16:45', '2 урок', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8}', '2026-09-19 10:17:21.882414+00', 'Robo AI (UGot 9-12)', 'group', 'false', '240', '490', '60', NULL, NULL, 'false', 'false'),
('831b2e97-ba67-4843-b0c2-4ae49d58ea53', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-12-20', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('831f611f-f9d5-42e7-b3e3-e0f9ad1f3468', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-02-14', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('850c7bed-f4ad-4b7d-87da-5f4103af7036', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-11-30', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('85a42bdd-a939-4606-b0cd-453f0edf586e', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-10-17', '12:15', 'тема 13', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('86f2ea4e-eb94-4749-b747-23648d2ac605', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-01-04', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('86f403ac-7bbd-4721-bf0a-8931d85ae935', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-04-03', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8749f3e8-4439-4f94-8878-91404ccb5d21', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-10-10', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-09-27 12:55:42.439171+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'true', 'false'),
('88c7c67f-c772-4e41-b9a0-abfafb972a0d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-12-06', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8911912c-541f-4978-a10d-34fa94fa4ef1', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-11-19', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('891487ac-65a1-48f5-8a1c-1e3df3559e0a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-04-26', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('89624d37-f943-4670-b411-c8e76fce1f7e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-04-12', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('8a7f3060-6cb9-44a6-b316-bb8dc6f8d3cc', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-04-21', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('8aa769e8-0c50-4a46-88f6-2b5f16c05c6c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-10-11', '11:15', 'тема 5', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,82690e1c-139d-45e1-b8b4-95c071215298,bd033223-6587-44f3-8d23-1761d4d9bd30,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('8ad1525d-a712-49b5-93af-d255f618c07e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2027-01-03', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8aefbd87-87da-4a29-a8a5-dd391e54b44a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-01-27', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8b16512d-206d-49c3-ab7b-f46c9cf3d452', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-02-24', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('8b3234bf-c3a0-40f7-bd78-791bafad6af0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-11-29', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8bf09590-d03f-4728-9909-5372a3215b8f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-01-20', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8c7dfacd-26ba-4232-a4ee-355c85d2e87d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-04-24', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8cd64af8-d1dc-4f69-a4d1-bc227d4647ef', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-01-04', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('8d71f95a-a763-4b36-9a9a-fea9b3b3f151', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-11-26', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('8da183e7-5415-4c1d-a8bf-cd0c61f08cfd', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-11-01', '12:30', 'Smart life. 9 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('8df35316-da30-4fea-9b03-1c5248170844', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-03-19', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('8e5c90ae-b80d-41f8-9a8a-9b7a079846eb', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-05-20', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('8f1ffde9-e982-4ec5-b098-1b9b87e75726', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-01-09', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('8f9b005c-3325-4258-a258-d31ecd5a64ff', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-01-10', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('90586a37-1958-4b09-a8bc-9bae620dfb10', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-12-14', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('91101d2c-1b98-4b43-8c7a-6816058fe343', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-05-15', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('911e503e-d4b9-4523-84fc-d65111d2ce95', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-04-10', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('911fd34e-a140-4cb5-a95c-638eef026901', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-04-22', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('9156b9c1-640c-4e24-9ff3-a1565426692f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-01-29', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('91b39afb-4b1f-4f29-9e58-57baa8422449', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-11-01', '11:15', '1.9', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,82690e1c-139d-45e1-b8b4-95c071215298,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('9203b5d9-5208-4b6a-aef8-b29658d2aa77', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-12-21', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('92279374-9dcf-463c-b8f0-f742c90d5dc8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-10-04', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9235f3c8-b0f3-495c-8d97-4989e35e46e8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-11-01', '15:30', '4.9', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('9274b6e1-717a-445e-bdfb-0c96ed785419', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-11-22', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('92e02e22-d6ef-46ca-bcaf-44f813d2d0df', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-01-27', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('92eddbb0-47a2-407e-b48d-709523dc6530', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-01-02', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('930a97eb-31d8-43ef-bb40-d14aae94c182', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-12-03', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('94529775-65ed-4ba4-a4ad-70e214b7aa1a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-05-22', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('94797ebd-b40f-4377-96e2-8de24bc91ca3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-11-08', '11:15', '2.1', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,da959919-410e-40a1-88d0-da5bf9712012,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('94f380f5-4441-48de-ba5e-b867ff64eda7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-03-27', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('951afa93-2e68-4682-91e5-7180a92e9654', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2027-01-16', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('958fc04a-cb4b-4ead-ac96-4657780c84f2', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-12-02', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('95e3414d-9b71-46aa-8f46-d3087a65dddf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-10-17', '14:00', 'Субмарина', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,c073a4ab-4437-4565-849f-c4a610c3525b,320747d4-9733-45ea-a0b6-86f0654aef24,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('95e93265-f364-47b9-9830-cc3592ddf124', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-03-01', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('96870cdb-c5d3-4088-8f0d-951e14cd609c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-05-24', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('96bdee8a-13e4-4a44-9788-bdb8b2c38fa8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-05-08', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('97236184-eb55-40c1-9ced-4d6bcc933e8e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-10-19', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-16 14:52:56.858733+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('97441e54-29df-41c8-91d5-495c69d6ac58', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-03-12', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('97aa3fc5-7cfe-4694-b4ec-8d3882dd5d28', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-11-15', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('97d18a9a-f690-450c-8427-d06357e4f0a0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-02-27', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('9803a23e-98fa-4d2f-bd12-c633576da558', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-01-17', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9813174c-8376-45aa-b8d5-73f578a1a444', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-11-28', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('988d14f0-b78f-4013-8053-6dd184d05483', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-12-24', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('98a58777-8295-4c67-a5bc-180c6ca54376', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-11-14', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9a9b7555-c25e-4c2c-a5e0-73ce2f652ef6', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-10-22', '18:20', '1 урок', '{66f1e3e2-c7b0-411c-8d28-411e0f4c20da,d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-10-16 14:57:55.782102+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('9b323a39-4e4d-49e0-afe8-f746250f2148', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-27', '12:30', 'Smart life 4урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-09-27 13:00:49.349339+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9b38ae34-beb5-4e32-8922-8967042dd9da', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-01-30', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9b3b0385-cc1c-43e4-9ddf-2a614b0cded1', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2027-01-17', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9c5b21c6-66b7-4e7d-907e-071fe952ad18', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-04-18', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9ca13762-d38c-48af-b245-c0baf82c0647', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-12-26', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('9d1a96ca-7df4-4ec2-8e1e-ab201f6fe4d3', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-04-22', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9ec67e0d-b594-4bc4-8caa-a883eeb49c61', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2027-01-03', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9ed8b484-c1d4-43f3-ae1b-602ee1f849ea', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-01-02', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('9f276656-3cc9-485a-b163-15ac9afdb09f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2027-01-10', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9f78794f-51e7-45f3-b75b-475f36580a8a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-01-16', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('9fc88ce1-e8b3-4cdb-b472-690b89f2272b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-12-17', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('a0a85659-5d7b-415f-8a29-8b1b4d4e55cf', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-10-15', '17:00', 'Тема 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681,c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a0ee3b72-7ceb-40be-b2cb-d9bc2272a90b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-02-03', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('a1563ced-8902-4e32-bfb8-1d2219a208ba', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-02-10', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('a17424ac-1ba5-44ab-8a5f-2753681a93c7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-12-20', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a1ccbe65-30b2-4a36-9988-ea25ea3b8ce1', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-11-25', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('a1d78da9-6ab7-4c7f-b8bd-673b5d7ff0d3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-03-06', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a2aa645c-1a13-4a04-96a0-28edf91ceb16', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-04-23', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a3426fd4-b797-4b8e-958b-5491afe35b97', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-02-25', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('a3c849f9-8ad0-4f30-b132-644ab68db310', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-09-25', '17:15', '2 тема', '{d5fba59f-d806-40fe-8de1-6e498156a182,3fd870d2-916a-4e60-a7db-daa5f2a8ec03}', '2026-09-25 15:29:50.862388+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a4b0e033-aae6-440b-a774-642fe6b137b2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-01-09', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a4f7c3f3-9f42-4948-b45f-e9c18fafea61', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-02-01', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('a5d5e0cb-4d3f-4e62-a331-e83440e5819f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-12-20', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a627350b-474e-4f1a-8fde-577819decb28', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-02-12', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a77f87a3-24cb-49c2-931c-4a156a266375', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2026-11-16', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('a9569062-2f61-4986-817b-91b815700cb4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-03-20', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('a9fda877-9ae0-4d02-8f24-300f09ee5c4b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-10-10', '15:30', 'Урок 6', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,2a6f4077-4397-415b-b41b-68ab616b7e44,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('aa2c13c0-bc2c-45be-947e-9a9e222c22ce', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-12-19', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('aa611ac3-6fdd-4180-9b3e-d02ec6e60ab9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-11-29', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('aadbab46-4eda-40f8-b77c-e189837e2d9b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-05-13', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('abf264d3-6c22-4e86-a7dd-7f8f34826d0f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-10-03', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,2a6f4077-4397-415b-b41b-68ab616b7e44,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-09-06 16:01:37.508606+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ac6222e1-ab33-4f14-bbbd-0f921a48956b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-11-18', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ac72c1f1-23c5-43b8-99c5-d32d280617bf', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-12-09', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('ac9424ed-c672-43ac-9fab-c1746f213dce', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-01-03', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('acbc2a74-3d35-4c37-9fb4-18976edb8f0f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-11-25', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ad0fa640-8213-4511-9a77-796d9ce9d8e2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-05-31', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('aea4d7ab-8eb7-4112-a534-16cbed580daa', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '7176230b-5165-4a75-8f18-cab4d100e3c3', '2026-09-05', '14:00', 'Чарівна паличка', '{3ce83cfa-8679-488a-b3dc-87772490a72a,04fec549-77ed-409b-9ae3-839e86f89a24,4652cc9c-8204-4a38-953c-cf107a092674}', '2026-09-09 20:25:32.637899+00', '3D MakersEmpire', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('aee099c0-0d66-4f12-b4d9-46309185366e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-11-16', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('afd08f86-01d6-4ce3-a896-810242d15fe6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-04-24', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('b00ebd5c-bab2-48f7-814a-a57fcb2889a9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2027-01-17', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('b14dfdb9-65eb-4aa3-8a02-aa142d13be71', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-02-24', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('b1d67bb8-df37-4bc2-bc68-8ceba59f8c45', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-10-03', '12:15', 'тема 11.12', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 13:52:34.302142+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('b25b1f4b-c0e3-4df1-9da3-a25d56cc25b2', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-02-25', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('b27f5e63-5741-412b-a9e1-cae53b3368c9', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-03-13', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('b2d8ed1e-1796-4585-a311-b3aadf817a09', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-03-21', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('b3407fc7-7360-4865-a79e-838e29adcbc0', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-01-14', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('b5085d41-5249-435c-9df9-4db588288b0e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-01-16', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('b5c8fda1-1bee-4dae-a834-478213b0aefb', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-02-05', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('b6adc486-95ff-47fc-8877-9019371cce34', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-09-10', NULL, 'Урок 2', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-09-13 17:29:39.951371+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('b7799038-004b-4785-ad43-177a49d14508', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2027-03-17', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('b8ee1326-0237-41c7-bab2-b3e8d571e98a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-10-18', '15:30', 'Тема 7', '{716fd538-274d-43a0-9a4a-f9c47858d92c,09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ba2f4009-a91f-4d29-a70a-066a689beb81', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-05-19', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('ba64eacb-f0b3-4f50-a319-560987ea6c0e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-01-30', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bae8c2d4-ff0f-491c-b55a-62a21098663a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-10-29', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-10-30 10:57:03.85005+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'true', 'true'),
('bb0397ae-b2ca-42e7-a70a-7beb28c2b488', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-11-21', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('bb214027-5390-4f5d-a69b-53e9651238ae', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-01-18', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('bb3d45ef-dcff-406c-8367-5a795ed8543b', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2027-01-09', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('bb62cb2f-1d6f-4a2d-816f-d36637fe40a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-27', '15:30', '4 урок', '{f6af0dd7-8905-4467-a298-27ec99ff9be3,716fd538-274d-43a0-9a4a-f9c47858d92c,c90f9850-c36e-4a24-9a58-388cf32c97ed,a57be370-0f09-4e81-ac2c-579095cebe97}', '2026-10-01 18:31:11.61977+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bb76cfa2-a9c2-4023-9a78-ced56904c31a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-11-22', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bb836f77-dec6-488d-b64a-dccef31deff6', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-11-11', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('bbdb287b-8fc9-4a41-b16d-c051581839e0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-03-01', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('bc080f90-202d-425d-9c57-ad31d3e7e4bf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-12-26', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bcad840f-13e3-434a-95ea-a85c468ab066', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-12-10', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bcb91335-102a-48ff-b6eb-d08bfdc82b1e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-11-15', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bd31fee5-e3f8-4195-9a16-35dea6e215a5', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-04-14', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('be21c8be-6805-4a9e-a0b3-cb9b51bcc387', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2027-01-10', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bf130da3-f342-488c-8acf-ec9cf15b3219', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-10-28', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-10-16 14:55:50.351038+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'true', 'false'),
('bf16422d-1995-4659-b46a-6b40cfa16415', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-11-21', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('bf852975-5e25-4c7f-a6c8-b7d40aabc881', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-03-15', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('bfdc310d-763a-4fb7-b9e1-5020eeac3ada', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-12-13', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('c0d94427-8e00-4ea2-9383-c1239dca7ef8', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-02-18', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('c16de641-3998-4565-a3a1-ef681557d39b', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-11-07', '16:45', 'no more rainbow', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'true', 'false'),
('c210defe-14c7-4799-8183-aae1ebff17f5', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-05-13', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('c292116e-1a0b-4e66-add5-3b3d9b5462c8', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-01-22', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('c2ece7cd-4d66-4a24-8138-b6da18028d3f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-12-23', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('c327c4e6-e64d-441b-b6fb-fd702902fa37', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-03-13', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('c33d1938-72aa-4466-b88a-e6b236ab2f02', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-11-11', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('c3c67348-5f7d-4696-93a6-2798ca2faa1e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-12-06', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('c3fc7f07-3140-4005-948e-c6d510421042', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-02-08', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('c48bf15c-b35d-4b0a-ad72-a265a74f2420', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2027-01-02', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('c5e23f9c-22de-4735-b917-cf91144a0b13', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-04-28', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('c6a7ba1a-0084-44c6-8d78-95a7383fe002', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', NULL, '2026-09-19', '16:45', 'Minecraft (місто майбутнього)', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,cb6ddd95-dd05-4ef7-a7ab-e83f1fadfed5}', '2026-09-19 10:16:22.876967+00', 'VR ІГРОВИЙ', 'group', 'false', '310', '450', '60', NULL, NULL, 'false', 'false'),
('c76ef1ad-d412-4b43-b633-9833652ca9a8', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-10-09', '17:15', '5 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,c904d118-af0a-4582-a15e-c36e690a5766,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('c84d3555-c005-4bc6-ad06-25ed349006d8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-10-04', '11:15', 'тема 5', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,82690e1c-139d-45e1-b8b4-95c071215298,08572b9e-65bb-46a9-8267-409a49dffe6e}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('c8604f54-7726-463d-9d23-5371562e28df', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-04-25', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('c8de471e-bba4-46cd-a558-2d3ba774ac17', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-10-08', '17:00', 'Тема 5', '{6ccebb1c-7124-4a5c-9585-3c99c2029681,c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('c9fb013b-432f-4ccd-bb13-ac4540bca938', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-12-09', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('ca065421-110b-434b-96ed-2905d87115b9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-04-19', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('cbda675b-a31e-4658-8396-7a5e355bd7c5', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-02-26', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('cc0c24f6-5b38-4140-a635-633dfe9bccd1', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-11-19', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('cc1a1f76-62fc-46c4-a6ad-ebfcb83ec504', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-09-27', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,82690e1c-139d-45e1-b8b4-95c071215298}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('cc549fd0-f453-485d-8793-51c1e15d06e1', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2026-12-17', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('cd58aa3e-2a4f-4719-a742-69e888343680', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-03-06', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('cd84373a-c655-4755-9ffd-391cc884bc9c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-10-26', '19:30', 'Проект "Школа"', '{001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-27 10:11:21.53717+00', '3D Tinkercad PRO (9-12)', 'individual_online', 'false', '240', '450', '60', NULL, NULL, 'false', 'false'),
('cfd24ef3-b19d-4ebc-bbcd-b683270b8822', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-12-28', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('d05117a0-b47e-4f43-bffb-063058e75677', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-02-13', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('d06166e5-6e30-4beb-b695-b6bb62bea1f2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-04-10', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d10ff7a6-322c-4959-a0ce-afe9ef2f431c', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-05-20', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d143d6ae-fba1-4e5b-b4be-5a7a4803f271', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-03-27', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false');
insert into public.lessons ("id", "owner_id", "series_id", "date", "time", "theme", "student_ids", "created_at", "course", "format", "extra_service", "payroll_amount", "price_amount", "duration_minutes", "room", "substitute_owner_id", "completed", "print_default") values
('d1840b97-fdf2-443f-9fa9-5c3a2dc4d714', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-01-08', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d187bd83-eafd-4ddc-933a-c8b582569891', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-11-25', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('d19805e9-f970-4e1f-86e8-4788c14dfd82', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-01-23', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d1f99bea-495f-4882-9bc7-c8332b96b00a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-11-30', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('d20d651f-d0b6-4746-83b9-473b3a4a373f', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-12-30', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('d221272e-d869-4172-b838-42684fa7a94d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-11-02', '18:00', '4.5 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('d3535021-2a75-46c0-8b46-f66f40ee7b27', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-03-15', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('d3f28058-b390-43b7-81f1-8ff7341f1339', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2027-01-07', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('d4152b27-63ae-4d38-b4cd-1270f8d6cac3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-02-13', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d5100858-a856-4b63-8dc9-bcff33cfb157', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-05-03', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('d6282d22-364a-4d7f-aa34-da6fcafebfc7', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-11-07', '12:15', 'тема 15. Динозавр', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'true', 'false'),
('d68d58da-6fa5-4321-b956-dfc77bbf14c8', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-11-21', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('d6d0c517-3324-4f91-a52d-3b78c82344dd', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-01-02', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d7d5f67a-d060-45b2-9a11-4adbce63510c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-12-13', '14:15', 'Кліматичні зміни. Атмосфера Землі', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d7f8ed43-23df-44e6-bf55-876b8e00360e', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-02-06', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('d85c2996-8aad-4a01-916b-fc07c8036b8a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-12-02', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('d901ac2c-4bdc-415d-ad1a-448ee6ccb327', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-11-06', '17:15', '1.8 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a,78261ab1-3948-46c8-b5c6-7621398af6fc,0b9b1eca-81c8-4c87-bdf0-0b80a25a9ae9}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('d98ed3ab-e0b0-45e8-9d99-53cb2b21b14c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-02-13', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('da7186c9-cc9b-4bb7-b62f-bcfbfef34f86', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-11-09', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('dbc82244-cdd6-4958-b695-058920615eab', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ce7549dc-24ee-4bbc-aa3f-1fecff784ff7', '2026-08-28', '12:15', '.', '{}', '2026-09-09 20:28:58.811198+00', 'Робототехніка Ukit', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('dcc1ba13-1b40-49fd-bbec-746bb2d0352f', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-09-17', '17:00', '3 урок', '{80416764-8767-4960-ab9e-d9047ef32f43,09b20d74-f3da-4342-b268-017f66ac101e,b4e78491-b20c-44f0-a05a-e0b59e784747}', '2026-09-19 10:35:57.522959+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('dd16790c-a3f0-4711-be6e-607c37b5c002', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-04-08', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('dd3f1fad-1255-487c-ad52-03522db03435', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-02-06', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ddddef08-da4f-4165-bc18-28584ea46f7e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-10-25', '12:30', 'Smart life 5  урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', 'Клас AI', NULL, 'false', 'false'),
('dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-19', '15:30', '3 урок', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,3f3fdeed-71b1-4fbb-8920-f244f69fefc2,61886bd2-6b1e-402d-a725-1ed9073e0bf8,cb6ddd95-dd05-4ef7-a7ab-e83f1fadfed5,2a6f4077-4397-415b-b41b-68ab616b7e44}', '2026-09-19 10:09:37.12759+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('de02dcc7-0630-4d71-b74b-36161cb5da8a', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-02-17', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('de55e886-9372-4403-8fd2-6b5bf1705d58', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-03-11', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('dea6cbf4-35c6-48ad-a8c4-227235ddec16', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-11-01', '14:15', 'Творче. Кліматичний винахід', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('df99225e-3bfa-4363-9a2f-3af812a27491', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-04-02', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e0800b58-e9db-43be-8f31-276d810fac76', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-11-11', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e0e0cdcc-7282-4583-8fc0-31c5688236ca', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-04-29', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e11c24e3-f30e-4c25-82ab-4a6b81f2024e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-01-09', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e1a8bce7-2b4c-488a-83d0-279f4e0cad11', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-10-17', '15:30', 'Урок 7', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e1d5d45a-d81d-4d3b-90c3-f3f6f03bb2be', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-04-04', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e1fe6958-c3f6-4d07-8ba5-0157bbc8d2e8', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2026-12-17', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('e281a889-adea-458e-9d6d-bca31a425cb0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-11-29', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e37199a0-722c-447a-9602-49df6946da8a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-11-22', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e3c36e9e-b66b-4bb9-9b40-b3c57bebcb6c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '08b83523-4932-45f1-a790-df89474c3e6a', '2026-08-29', '15:30', '.', '{}', '2026-09-09 20:24:06.162578+00', '3D TinkerCad', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('e3fbd11e-2f5a-4179-b23f-86d4ed42691e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-05-02', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e4ccb801-722e-4f0c-bd7c-d9e2cb4d1b9c', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-11-27', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e56854fd-1b26-4d1e-90bd-f51e7559bfe0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-02-15', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('e5e08f95-5a62-4264-ab91-9d3478e8807c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-12-07', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('e61072e1-4397-458e-b0fc-3a520c7734e3', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-02-04', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e63019cc-bece-4d7a-b20d-0d58595b323d', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dc78309d-44c7-4db2-a8f2-ed4fed7837f3', '2026-12-09', '15:00', 'Магніт', '{0c9af1bb-b47b-42a7-a770-095553ab98df,320747d4-9733-45ea-a0b6-86f0654aef24,e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581}', '2026-11-04 15:52:22.626533+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e678e13c-8aaa-4441-82f2-7a1e99620760', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-02-27', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e6ffcc87-38c1-4ce6-89be-bef5aac26672', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-11-05', '15:45', 'урок 1.3-4', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'true', 'false'),
('e7f673cd-bb9a-4dfe-8a22-3f9a8561957b', '51137c32-5d66-48e6-963e-cd96ff1603f9', NULL, '2026-10-16', '18:30', '1 урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a,d5fba59f-d806-40fe-8de1-6e498156a182}', '2026-10-15 14:35:52.793962+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('e81ac6b8-c15d-41eb-9bec-8b4ea5fa00b2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2026-11-22', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e8cb3338-71b1-4f95-baf5-c9d6c25dee83', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2027-03-13', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e8e34f60-57c3-47b5-b60a-b74f403dad27', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1cbcece5-c031-4d7f-894a-04f34e410c3f', '2026-12-05', '15:30', 'Урок 5', '{92f2560c-5a4c-4067-8459-e46f8226c9a8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac,61886bd2-6b1e-402d-a725-1ed9073e0bf8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2}', '2026-10-01 14:32:49.606141+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e9360e0a-7611-4e6b-b897-31a23bbf23a6', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-03-25', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e99a0f4d-1b37-4bca-9403-c858a01e654b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2026-12-13', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('e9cd1476-e256-46e5-91f6-7aa2ac74e37c', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-11-14', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('ea37bb68-3e82-4ac4-9147-6a4fbc7d6140', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-11-28', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('ea99449c-7b70-4e13-b6df-08e89389179a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-12-11', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('eae7c529-4fcf-4e3e-a346-0eb46efb85bf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '18746e78-8e92-41b9-94b2-6054fdec7059', '2027-01-24', '12:30', 'Smart life. 4 урок', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a}', '2026-10-01 14:25:02.003692+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('eb9c04b7-9d81-442c-a4a3-fe4ec70d2d70', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-01-23', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('ec5455ef-8b50-47a5-b24b-2dcbaaad78e4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2027-04-24', '14:00', 'забруднення океанів. Черепаха', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ec6acfc2-9875-45d2-b548-f9bb36e2fe67', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-11-23', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('ec6b5402-91ba-445c-a00b-3aa409204b81', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2026-10-24', '12:15', 'не було заняття', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', 'Клас AI', NULL, 'false', 'false'),
('ed0035b9-f256-41ff-a1d1-e4958a272c51', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-09-26', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-09-27 12:55:42.439171+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('eda51042-f49c-4290-81f4-d2e11f0723d5', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'c311184c-9e9d-4fb6-9350-2a3b4f00117b', '2026-10-01', '17:00', '4 урок', '{6ccebb1c-7124-4a5c-9585-3c99c2029681,c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-01 13:45:20.230148+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ede86ad8-a45a-4e63-894b-8249d1313eec', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-12-27', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('edf693ff-5ff8-4bc3-a76a-8c59e663034c', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f1a9e74-7f6b-478c-b7d8-2556dd455e05', '2026-09-26', '16:45', 'Max Mustard', '{92f2560c-5a4c-4067-8459-e46f8226c9a8}', '2026-09-27 12:54:51.044623+00', 'VR ІГРОВИЙ', 'group', 'false', '240', '450', '60', NULL, NULL, 'false', 'false'),
('ef23fd02-f889-4f70-81dd-c16cdaebcd41', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2027-03-03', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('ef6b5a3f-2ebe-42db-be3b-68e612bce07b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-11-13', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f04d85f3-403c-4bd8-abf5-8380105ed579', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-03-29', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('f13c65ed-6cce-44e3-bbbe-b2b5f05f41e9', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-11-18', '18:00', '3 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('f17383c2-f780-4e55-abee-62dcd3dfda06', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6c363d54-fe84-4198-afb2-c203d560ecdd', '2026-12-20', '11:15', 'тема 4', '{dbeddff1-36f2-4b4a-9425-5be7d302b236,6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a,08572b9e-65bb-46a9-8267-409a49dffe6e,ff1ec5c9-713c-42e2-9f4e-54e74a3538fe}', '2026-09-27 12:59:07.770366+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f18b9494-f869-460f-bfe9-dbed80565d7b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-12-04', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f1aab548-c4d9-4745-9f38-bf657ed13bbf', '51137c32-5d66-48e6-963e-cd96ff1603f9', '5232092d-9bc7-405e-9cd3-b07bd5a440ac', '2026-11-26', '15:45', 'урок', '{00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-11-04 14:15:17.948318+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('f2fc1a93-6fd6-4d15-a932-818a5d51963d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '647f2fcc-432f-4db5-93f5-e9bb45515af1', '2026-10-25', '14:15', 'Творче. Кліматичний винахід', '{60e52e47-9158-4d49-94c5-99e8b1e9f7fb,d1fbf933-a1ef-45ee-9a75-4c976c50108b,27ae626f-fb4e-467b-9c7c-20b0cf892f44,88b1789a-7485-4d0d-a5a9-b101706c0961}', '2026-10-01 14:25:55.055603+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', 'Клас AI', NULL, 'false', 'false'),
('f3ce68b4-f130-46b7-8c49-a014bb72b148', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-03-27', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('f4f8caf9-1ab9-4fa3-8284-354443fdc518', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-02-11', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f5510426-daca-4729-936f-0be0c3997569', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'd925e208-a143-4097-8bb5-5ab211e19a78', '2027-03-06', '12:15', 'тема 11', '{80416764-8767-4960-ab9e-d9047ef32f43}', '2026-10-01 14:32:18.594331+00', 'Robo AI (Ukit 6-8)', 'group', 'false', '240', '440', '60', NULL, NULL, 'false', 'false'),
('f64b026f-979b-4e45-be84-f3e89245e0f1', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-02-04', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('f6b18913-4307-4162-acdc-59666383d926', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ccbb7c04-3d2e-4c2d-9d1f-e4569daf3b45', '2027-02-22', '19:30', '1 урок', '{bd160e22-40d7-4826-8c2a-659cdac3ec4b,bd02b3c6-bef2-4775-95e4-54f4dcec7544}', '2026-10-25 12:08:57.551176+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('f6fe9436-ec6f-4afe-a200-4cc60f72a339', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2027-04-05', '18:00', '2 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('f7756024-3213-451c-a5cd-8d58d45c8236', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'a5754c09-4068-42a1-ae33-d019bc77661a', '2026-09-05', '16:45', 'VR Minecraft', '{}', '2026-09-09 20:31:03.6266+00', 'VR ігровий', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('f784728b-cefa-434b-b9fa-3a003399301b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '087a01fb-51e8-4b29-972b-4d1c42279907', '2027-03-28', '15:30', 'Тема 5', '{09b20d74-f3da-4342-b268-017f66ac101e,c90f9850-c36e-4a24-9a58-388cf32c97ed,28511a97-5dca-4516-b5e0-afc636c23dd2,6c880fed-268a-4a2a-a8d6-b4c30c151211}', '2026-10-08 15:14:31.554583+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f7c17761-b268-45da-a1f1-68dd85cdd7a3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', NULL, '2026-09-19', '14:00', 'Казковий персонаж', '{ca69e2e7-a023-4814-8df8-82d39d191886,80416764-8767-4960-ab9e-d9047ef32f43}', '2026-09-19 10:08:58.711048+00', '3D Makers PRO (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f813347b-5bb6-4365-95fb-2929cdaf15f1', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'f7f6e799-6c37-4668-8eda-ba7ee512bdfa', '2027-05-06', '18:20', '2 урок', '{d9dfe264-fdf8-41f5-92ca-87de083f4f29}', '2026-11-01 10:25:11.732746+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'true'),
('f81a24b3-e4a8-4436-8a66-32cee65e7c7b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2e9cb0d7-4c88-4b00-b5ca-be7fa849baae', '2026-10-31', '14:00', 'Білий ведмідь', '{80416764-8767-4960-ab9e-d9047ef32f43,ca69e2e7-a023-4814-8df8-82d39d191886,bfbe42c5-7959-42dc-baba-9e2857fb4c40,0f70e64d-753f-4ac2-a755-4ef0eb0c25eb,320747d4-9733-45ea-a0b6-86f0654aef24}', '2026-10-01 14:32:38.652891+00', '3D Makers FIRST (6-8)', 'group', 'false', '310', '440', '60', NULL, NULL, 'true', 'false'),
('f87492d1-9ca4-4f67-8cb3-01be1b647b5b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2027-01-13', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('f8be28f4-a603-4119-9de2-4839a40de706', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2026-11-20', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f8d0889c-d33d-4c75-a796-784952c1dbb4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2026-12-26', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('f9154993-3a3c-4e25-a133-959297e525a4', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-04-15', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('f952b843-ccd3-435d-ace2-17fdb79b9658', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'c4ca76c5-498c-4d1b-b5ce-37c9593aec9e', '2026-09-26', '15:30', 'Кольоровий друк. 4 тема', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,2a6f4077-4397-415b-b41b-68ab616b7e44,92f2560c-5a4c-4067-8459-e46f8226c9a8,3f3fdeed-71b1-4fbb-8920-f244f69fefc2,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-09-27 12:53:00.552979+00', '3D Tinkercad PRO (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('faf4cacb-e005-4b95-92be-26fae152ac34', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-01-07', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('fc7c30a6-9de7-4e3b-b715-36623cbcf706', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b7a03165-6967-4446-becb-9bb7d81edbc9', '2027-03-18', '17:00', 'Тема 5', '{c904d118-af0a-4582-a15e-c36e690a5766,78261ab1-3948-46c8-b5c6-7621398af6fc}', '2026-10-04 14:31:18.767897+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('fcd59792-8459-4dfd-b088-afe59d4c682f', '51137c32-5d66-48e6-963e-cd96ff1603f9', '46574bed-071c-402d-be7b-73b90116c89c', '2026-11-18', '17:00', 'урок 6', '{6ccebb1c-7124-4a5c-9585-3c99c2029681}', '2026-11-01 10:22:51.637986+00', '3D Tinkercad FIRST (9-12)', 'individual', 'false', '310', '660', '60', NULL, NULL, 'false', 'false'),
('feb88580-edc2-4aa2-b532-5be0d1fa3790', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '653c3b92-8f4c-460e-8abb-fb5538b102fc', '2027-03-20', '16:45', 'тема 2', '{61886bd2-6b1e-402d-a725-1ed9073e0bf8,001ba17e-f9e2-4eab-bccd-9ffafdb739ac}', '2026-10-16 15:01:18.54762+00', 'Robo AI (UGot 9-12)', 'group', 'false', '310', '490', '60', NULL, NULL, 'false', 'false'),
('fec81103-b9b7-4482-9ad6-0fcf4410cbea', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '08b83523-4932-45f1-a790-df89474c3e6a', '2026-09-05', '15:30', 'Урок 1. Кольоровий друк', '{f9bfcf8c-8474-4eaf-a700-765b39893507,8a6a5b77-ca2a-4ffe-81d4-519ef0b826c3,1d2e9f2c-97a6-4096-b935-2d7eba790f6a,bc377d88-0143-48ed-856a-18ceb9d55e45}', '2026-09-09 20:24:06.162578+00', '3D TinkerCad', 'group', 'false', NULL, '0', '60', NULL, NULL, 'false', 'false'),
('fed7d637-0deb-4243-93cc-53f8c781310f', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a4aa81e8-dd12-46bc-bbb9-50ac5c784db0', '2027-04-09', '17:15', '3 урок', '{d5fba59f-d806-40fe-8de1-6e498156a182,e6ba5875-3763-49ec-a21d-972d1806edca,00b11be9-337b-4e89-b9af-c0aec4d7930a}', '2026-10-03 11:55:02.269371+00', '3D Tinkercad FIRST (9-12)', 'group', 'false', '310', '440', '60', NULL, NULL, 'false', 'false'),
('ff84ab59-df43-4b83-a32c-61711dd233bf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1face04b-ae29-4305-aceb-a6f764501ab8', '2026-10-19', '18:00', '3 урок (онлайн)', '{7e538107-a218-47e5-9daa-8d2763445b5e,a89a18b5-3741-4158-98cb-3b99b677d5c3}', '2026-10-08 11:19:32.267549+00', '3D Tinkercad PRO (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'false', 'false'),
('ffb14310-780c-49e7-a4b9-60e3d787c7ee', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2e7731f4-5334-41d0-af9b-0604db636a6e', '2026-11-04', '18:00', '1.5 урок', '{29e27d18-c7bb-48f2-bda4-56b16ec6e3cc,d2451baa-b8e3-4403-9192-f179984de641}', '2026-11-01 10:22:34.666079+00', '3D Tinkercad FIRST (9-12)', 'group_online', 'false', '310', '370', '60', NULL, NULL, 'true', 'false');
insert into public.parent_accounts ("id", "phone", "name", "active", "password_set_at", "last_login_at", "created_at", "created_by") values
('12c9c9cb-7308-4d7a-920b-f8e6b5eaf851', '380000000003', 'Батьки 003', 'true', '2026-10-26 18:36:19.275552+00', '2026-10-26 20:05:30.480142+00', '2026-10-26 18:36:19.275552+00', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c'),
('2b38e185-5f63-46c5-a627-2758c37dc592', '380000000001', 'Батьки 001', 'true', '2026-10-24 21:04:11.663274+00', '2026-10-24 21:04:40.17664+00', '2026-10-24 21:04:11.663274+00', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c'),
('4e7c859c-111b-49e0-994a-2b1ab981ca94', '380000000002', 'Батьки 002', 'true', '2026-10-24 21:34:20.322902+00', '2026-11-01 08:53:30.595484+00', '2026-10-24 21:34:20.322902+00', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c');
insert into public.parent_students ("parent_id", "student_id", "created_at") values
('12c9c9cb-7308-4d7a-920b-f8e6b5eaf851', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', '2026-10-26 18:36:19.275552+00'),
('2b38e185-5f63-46c5-a627-2758c37dc592', 'd8ab7a22-8311-451d-9748-979f6197e4ab', '2026-10-24 21:04:11.663274+00'),
('4e7c859c-111b-49e0-994a-2b1ab981ca94', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', '2026-10-24 21:34:20.322902+00'),
('4e7c859c-111b-49e0-994a-2b1ab981ca94', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', '2026-10-24 21:38:02.260293+00');
insert into public.printers ("id", "name", "power_watts", "depreciation_per_hour", "active", "created_at") values
('1b1260e1-51a6-4e0e-bb32-e376de3d0635', 'Snapmaker u1', '127', '9.48', 'true', '2026-10-26 15:18:58.998505+00'),
('7924ec2d-32c4-47b9-9f72-d87186122bd8', 'BambuLab P2S', '200', '9.48', 'true', '2026-10-26 15:18:58.998505+00');
insert into public.profiles ("id", "email", "role", "created_at", "last_name", "first_name", "active", "photo") values
('0ab913d6-ea2f-4f30-b75d-b77a803fed15', 'user04@example.test', 'superadmin', '2026-09-12 09:21:58.667649+00', '04', 'Суперадмін', 'true', NULL),
('114b4ba6-4313-4a1e-a1c5-121e4aa333b3', 'user07@example.test', 'superadmin', '2026-09-26 09:23:44.134025+00', '07', 'Суперадмін', 'false', NULL),
('51137c32-5d66-48e6-963e-cd96ff1603f9', 'user06@example.test', 'teacher', '2026-09-13 17:22:20.759764+00', '06', 'Викладач', 'true', NULL),
('75f98c1e-3264-440f-b4bb-f70d6778b767', 'user03@example.test', 'admin', '2026-09-09 13:39:24.244051+00', '03', 'Адмін', 'true', NULL),
('85701c53-77ce-4783-a157-e21476b16d4c', 'user08@example.test', 'superadmin', '2026-09-26 15:56:11.690117+00', '08', 'Суперадмін', 'true', NULL),
('a6de212d-bc6b-4a11-8f8c-351881292c4c', 'user05@example.test', 'teacher', '2026-09-12 17:41:28.490647+00', '05', 'Викладач', 'true', NULL),
('c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'user02@example.test', 'superadmin', '2026-09-06 16:06:19.612018+00', '02', 'Суперадмін', 'true', NULL),
('ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'user01@example.test', 'admin', '2026-09-06 15:56:00.977844+00', '01', 'Адмін', 'true', NULL);
insert into public.rate_cards ("course", "rate_group_1", "rate_group_2_4", "rate_group_5_6", "rate_individual", "rate_online_print", "rate_online_no_print", "rate_extra_print", "updated_at", "zp_group_1", "price_group_1", "zp_group_2_6", "price_group_2_6", "zp_individual", "price_individual", "zp_individual_online_print", "price_individual_online_print", "zp_individual_online_no_print", "price_individual_online_no_print", "zp_group_online_print", "price_group_online_print", "zp_group_online_no_print", "price_group_online_no_print", "zp_extra_service", "price_extra_service", "price_subscription", "zp_individual_online", "price_individual_online", "zp_group_online", "price_group_online", "price_print_online", "price_sub_group", "price_sub_individual", "price_sub_individual_online", "price_sub_group_online") values
('3D Makers FIRST (6-8)', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '440', '310', '440', '310', '660', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1640', '0', '0', '0', '0', NULL, '1640', '1640', '1640', '1640'),
('3D Makers PRO (6-8)', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '440', '310', '440', '310', '660', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1640', '0', '0', '0', '0', NULL, '1640', '1640', '1640', '1640'),
('3D Tinkercad FIRST (9-12)', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '440', '310', '440', '310', '660', '310', '540', '240', '450', '310', '440', '310', '370', '0', '0', '1640', '240', '450', '310', '370', NULL, '1640', '1640', '1640', '1640'),
('3D Tinkercad PRO (9-12)', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '440', '310', '440', '310', '660', '310', '540', '240', '450', '310', '440', '310', '370', '0', '0', '1640', '240', '450', '310', '370', NULL, '1640', '1640', '1640', '1640'),
('3D слайсинг', '310', '370', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '0', '310', '0', '310', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', NULL, '0', '0', '0', '0'),
('Robo AI (UGot 9-12)', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '490', '310', '490', '310', '660', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1670', '0', '0', '0', '0', NULL, '1670', '1670', '1670', '1670'),
('Robo AI (Ukit 6-8)', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '440', '310', '440', '310', '660', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1640', '0', '0', '0', '0', NULL, '1640', '1640', '1640', '1640'),
('VR ІГРОВИЙ', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '450', '310', '450', '310', '660', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1700', '0', '0', '0', '0', NULL, '1700', '1700', '1700', '1700'),
('VR РОЗРОБКА (Delightex)', '0', '0', '0', '0', '0', '0', '0', '2026-09-14 16:26:25.128114+00', '240', '450', '310', '450', '310', '660', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1700', '0', '0', '0', '0', NULL, '1700', '1700', '1700', '1700');
insert into public.student_comments ("id", "student_id", "author_id", "body", "created_at") values
('6c8721fa-0a7a-425d-a817-bb04ebad2533', 'e6ba5875-3763-49ec-a21d-972d1806edca', '85701c53-77ce-4783-a157-e21476b16d4c', 'Коментар 0005', '2026-10-23 15:22:45.637572+00'),
('9259f7be-9b85-443e-9e1a-09f97b01573e', '28511a97-5dca-4516-b5e0-afc636c23dd2', '85701c53-77ce-4783-a157-e21476b16d4c', 'Коментар 0008', '2026-11-07 12:18:38.667319+00'),
('aa7dc7ce-793a-4ddb-ab75-a56841501aa1', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', NULL, 'Коментар 0001', '2026-10-08 10:02:21.988266+00'),
('c8749f43-cbd1-4be3-88b4-80289fab1b17', '78261ab1-3948-46c8-b5c6-7621398af6fc', '85701c53-77ce-4783-a157-e21476b16d4c', 'Коментар 0002', '2026-10-08 15:04:50.628551+00'),
('cff36714-6214-4f82-bfe9-f9bd1a6877a6', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '85701c53-77ce-4783-a157-e21476b16d4c', 'Коментар 0003', '2026-10-14 16:39:40.250865+00'),
('d30cd714-9f3f-4a94-8c73-ec4164828d52', '44db9928-9c11-4689-acaa-aea1f78ac7b7', '85701c53-77ce-4783-a157-e21476b16d4c', 'Коментар 0007', '2026-11-06 15:38:54.778779+00'),
('e9bbac24-c3e6-44df-9860-479323e74775', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Коментар 0006', '2026-11-01 12:41:25.178038+00'),
('f9cfeaf6-6332-4ea4-b9d1-8b8ed3aedd86', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', '85701c53-77ce-4783-a157-e21476b16d4c', 'Коментар 0004', '2026-10-18 09:22:50.233378+00');
insert into public.students ("id", "owner_id", "name", "created_at", "phone", "parent_last_name", "parent_first_name", "photo", "birthday", "notes") values
('001ba17e-f9e2-4eab-bccd-9ffafdb739ac', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 007', '2026-09-11 15:12:05.416328+00', '+380 00 000 00 07', 'Батьки', '007', NULL, NULL, NULL),
('00b11be9-337b-4e89-b9af-c0aec4d7930a', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'Учень 032', '2026-10-09 13:54:27.17318+00', '+380 00 000 00 32', 'Батьки', '032', NULL, NULL, NULL),
('08572b9e-65bb-46a9-8267-409a49dffe6e', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 011', '2026-09-13 08:16:09.095849+00', '+380 00 000 00 11', 'Батьки', '011', NULL, NULL, NULL),
('09b20d74-f3da-4342-b268-017f66ac101e', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 015', '2026-09-19 10:36:20.679076+00', '+380 00 000 00 15', 'Батьки', '015', NULL, NULL, NULL),
('0b9b1eca-81c8-4c87-bdf0-0b80a25a9ae9', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'Учень 049', '2026-11-01 10:21:13.402964+00', '+380 00 000 00 49', 'Батьки', '049', NULL, NULL, NULL),
('0c9af1bb-b47b-42a7-a770-095553ab98df', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 044', '2026-10-23 14:36:51.11478+00', '+380 00 000 00 44', 'Батьки', '044', NULL, NULL, NULL),
('0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 026', '2026-10-01 13:59:47.773392+00', '+380 00 000 00 26', 'Батьки', '026', NULL, NULL, NULL),
('1e3b0597-a906-4eb0-9d0c-623a70b9ac67', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'Учень 051', '2026-11-06 13:48:04.650937+00', '+380 00 000 00 51', 'Батьки', '051', NULL, NULL, NULL),
('27ae626f-fb4e-467b-9c7c-20b0cf892f44', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 016', '2026-09-19 10:46:04.710889+00', '+380 00 000 00 16', 'Батьки', '016', NULL, NULL, NULL),
('28511a97-5dca-4516-b5e0-afc636c23dd2', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 017', '2026-09-19 10:50:01.00996+00', '+380 00 000 00 17', 'Батьки', '017', NULL, NULL, NULL),
('29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 029', '2026-10-04 13:31:31.704844+00', '+380 00 000 00 29', 'Батьки', '029', NULL, NULL, NULL),
('320747d4-9733-45ea-a0b6-86f0654aef24', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'Учень 033', '2026-10-09 16:55:48.328181+00', '+380 00 000 00 33', 'Батьки', '033', NULL, NULL, NULL),
('3f3fdeed-71b1-4fbb-8920-f244f69fefc2', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 006', '2026-09-11 15:11:17.97094+00', '+380 00 000 00 06', 'Батьки', '006', NULL, NULL, NULL),
('3fd870d2-916a-4e60-a7db-daa5f2a8ec03', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 022', '2026-09-25 15:28:58.909297+00', '+380 00 000 00 22', 'Батьки', '022', NULL, NULL, NULL),
('44db9928-9c11-4689-acaa-aea1f78ac7b7', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 048', '2026-10-30 12:15:02.684981+00', '+380 00 000 00 48', 'Батьки', '048', NULL, NULL, NULL),
('60e52e47-9158-4d49-94c5-99e8b1e9f7fb', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 013', '2026-09-13 08:28:54.806259+00', '+380 00 000 00 13', 'Батьки', '013', NULL, NULL, NULL),
('61886bd2-6b1e-402d-a725-1ed9073e0bf8', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 008', '2026-09-11 15:13:01.813421+00', '+380 00 000 00 08', 'Батьки', '008', NULL, NULL, NULL),
('66f1e3e2-c7b0-411c-8d28-411e0f4c20da', '75f98c1e-3264-440f-b4bb-f70d6778b767', 'Учень 041', '2026-10-16 14:58:57.064602+00', '+380 00 000 00 41', 'Батьки', '041', NULL, NULL, NULL),
('6c880fed-268a-4a2a-a8d6-b4c30c151211', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 018', '2026-09-19 10:50:11.186807+00', '+380 00 000 00 18', 'Батьки', '018', NULL, NULL, NULL),
('6ccebb1c-7124-4a5c-9585-3c99c2029681', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 001', '2026-09-10 12:51:25.579057+00', '+380 00 000 00 01', 'Батьки', '001', NULL, NULL, NULL),
('6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 010', '2026-09-13 08:15:28.777374+00', '+380 00 000 00 10', 'Батьки', '010', NULL, NULL, NULL),
('7474be52-99f0-496e-909a-f567c0cddae7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'Учень 042', '2026-10-22 13:54:27.092935+00', '+380 00 000 00 42', 'Батьки', '042', NULL, NULL, NULL),
('78261ab1-3948-46c8-b5c6-7621398af6fc', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 025', '2026-10-01 13:48:42.279195+00', '+380 00 000 00 25', 'Батьки', '025', NULL, NULL, NULL),
('7e538107-a218-47e5-9daa-8d2763445b5e', '0ab913d6-ea2f-4f30-b75d-b77a803fed15', 'Учень 024', '2026-09-30 16:14:16.055081+00', '+380 00 000 00 24', 'Батьки', '024', NULL, NULL, NULL),
('80416764-8767-4960-ab9e-d9047ef32f43', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 002', '2026-09-10 13:02:51.396293+00', '+380 00 000 00 02', 'Батьки', '002', NULL, NULL, NULL),
('82fe617b-7f7c-4e0b-b1e3-918ea80d7935', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 035', '2026-10-15 12:34:30.476436+00', '+380 00 000 00 35', 'Батьки', '035', NULL, NULL, NULL),
('88b1789a-7485-4d0d-a5a9-b101706c0961', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'Учень 034', '2026-10-15 12:33:13.315374+00', '+380 00 000 00 34', 'Батьки', '034', NULL, NULL, NULL),
('92f2560c-5a4c-4067-8459-e46f8226c9a8', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 005', '2026-09-11 15:10:51.888309+00', '+380 00 000 00 05', 'Батьки', '005', NULL, NULL, NULL),
('9d017639-4958-4772-a563-884569c04bf6', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 045', '2026-10-23 14:37:00.963642+00', '+380 00 000 00 45', 'Батьки', '045', NULL, NULL, NULL),
('a57be370-0f09-4e81-ac2c-579095cebe97', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 027', '2026-10-01 18:29:07.297895+00', '+380 00 000 00 27', 'Батьки', '027', NULL, NULL, NULL),
('a89a18b5-3741-4158-98cb-3b99b677d5c3', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 014', '2026-09-19 10:33:46.389808+00', '+380 00 000 00 14', 'Батьки', '014', NULL, NULL, NULL),
('bd02b3c6-bef2-4775-95e4-54f4dcec7544', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 039', '2026-10-16 14:53:53.121552+00', '+380 00 000 00 39', 'Батьки', '039', NULL, NULL, NULL),
('bd160e22-40d7-4826-8c2a-659cdac3ec4b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'Учень 038', '2026-10-16 14:52:56.652+00', '+380 00 000 00 38', 'Батьки', '038', NULL, NULL, NULL),
('bfbe42c5-7959-42dc-baba-9e2857fb4c40', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 023', '2026-09-26 09:10:20.539996+00', '+380 00 000 00 23', 'Батьки', '023', NULL, NULL, NULL),
('c073a4ab-4437-4565-849f-c4a610c3525b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'Учень 036', '2026-10-15 12:40:14.412964+00', '+380 00 000 00 36', 'Батьки', '036', NULL, NULL, NULL),
('c904d118-af0a-4582-a15e-c36e690a5766', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 020', '2026-09-23 15:23:46.765008+00', '+380 00 000 00 20', 'Батьки', '020', NULL, NULL, NULL),
('c90f9850-c36e-4a24-9a58-388cf32c97ed', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 019', '2026-09-19 10:50:37.043443+00', '+380 00 000 00 19', 'Батьки', '019', NULL, NULL, NULL),
('ca69e2e7-a023-4814-8df8-82d39d191886', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 003', '2026-09-11 14:55:33.136906+00', '+380 00 000 00 03', 'Батьки', '003', NULL, NULL, NULL),
('d1819c58-e0a6-4bf4-ae9e-82cc84bc6d05', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 052', '2026-11-07 10:57:18.596251+00', '+380 00 000 00 52', 'Батьки', '052', NULL, NULL, NULL),
('d1fbf933-a1ef-45ee-9a75-4c976c50108b', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 012', '2026-09-13 08:28:17.218674+00', '+380 00 000 00 12', 'Батьки', '012', NULL, NULL, NULL),
('d2451baa-b8e3-4403-9192-f179984de641', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 030', '2026-10-04 13:32:08.28234+00', '+380 00 000 00 30', 'Батьки', '030', NULL, NULL, NULL),
('d5fba59f-d806-40fe-8de1-6e498156a182', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 021', '2026-09-25 15:28:08.743072+00', '+380 00 000 00 21', 'Батьки', '021', NULL, NULL, NULL),
('d8ab7a22-8311-451d-9748-979f6197e4ab', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 046', '2026-10-24 13:25:42.449576+00', '+380 00 000 00 46', 'Батьки', '046', NULL, NULL, NULL),
('d9dfe264-fdf8-41f5-92ca-87de083f4f29', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 040', '2026-10-16 14:57:55.7821+00', '+380 00 000 00 40', 'Батьки', '040', NULL, NULL, NULL),
('da959919-410e-40a1-88d0-da5bf9712012', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 047', '2026-10-25 10:40:09.395492+00', '+380 00 000 00 47', 'Батьки', '047', NULL, NULL, NULL),
('dbeddff1-36f2-4b4a-9425-5be7d302b236', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 009', '2026-09-13 08:14:23.032326+00', '+380 00 000 00 09', 'Батьки', '009', NULL, NULL, NULL),
('e098aea3-1f11-4e21-ab48-5be7c82a54fb', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', 'Учень 004', '2026-09-11 15:09:33.961792+00', '+380 00 000 00 04', 'Батьки', '004', NULL, NULL, NULL),
('e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 043', '2026-10-23 14:36:34.931362+00', '+380 00 000 00 43', 'Батьки', '043', NULL, NULL, NULL),
('e6ba5875-3763-49ec-a21d-972d1806edca', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'Учень 037', '2026-10-16 12:42:12.456953+00', '+380 00 000 00 37', 'Батьки', '037', NULL, NULL, NULL),
('f6af0dd7-8905-4467-a298-27ec99ff9be3', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 028', '2026-10-01 18:29:38.376246+00', '+380 00 000 00 28', 'Батьки', '028', NULL, NULL, NULL),
('fdb5f116-3717-4fd3-b27a-14c1cf5c9f5b', '85701c53-77ce-4783-a157-e21476b16d4c', 'Учень 050', '2026-11-05 13:39:44.694106+00', '+380 00 000 00 50', 'Батьки', '050', NULL, NULL, NULL),
('ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'Учень 031', '2026-10-08 14:43:28.014992+00', '+380 00 000 00 31', 'Батьки', '031', NULL, NULL, NULL);
insert into public.studio_settings ("id", "calc_start_date", "updated_at", "updated_by", "electricity_tariff", "filament_waste_percent") values
('true', NULL, '2026-10-29 17:01:56.254246+00', '0ab913d6-ea2f-4f30-b75d-b77a803fed15', '7.47', '10');
insert into public.subscriptions ("id", "student_id", "course", "total_lessons", "remaining_lessons", "status", "purchased_by", "purchased_at", "total_price", "payment_method") values
('10ec7a2b-2561-4ffc-b2ec-d086254e6212', 'c904d118-af0a-4582-a15e-c36e690a5766', '3D Tinkercad FIRST (9-12)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-01 13:53:22.407469+00', '1640', NULL),
('1bad7eb8-6a5c-4ebd-9ea2-879efdf4fc8b', 'ca69e2e7-a023-4814-8df8-82d39d191886', '3D Makers FIRST (6-8)', '4', '2', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-31 00:00:00+00', '1640', 'card'),
('1ed1bd3d-57f2-41ee-94a4-c5365573ab60', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', '3D Tinkercad FIRST (9-12)', '4', '2', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 00:00:00+00', '1640', 'cash'),
('246800bb-71e1-44aa-9a4e-ba42ed32d1b3', 'd8ab7a22-8311-451d-9748-979f6197e4ab', '3D Tinkercad PRO (9-12)', '4', '0', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-24 00:00:00+00', '1640', 'card'),
('24699a30-723a-4d12-ad4b-ba10b377090f', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', '3D Makers FIRST (6-8)', '4', '4', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-11 08:46:28.829204+00', '1640', NULL),
('26b84ccd-5383-4ddf-9c54-19f83e8fdae4', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', '3D Tinkercad FIRST (9-12)', '4', '0', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 14:09:19.084502+00', '1640', NULL),
('2e965853-e5aa-40fe-a2c2-0c938718ae0b', 'd8ab7a22-8311-451d-9748-979f6197e4ab', '3D Tinkercad PRO (9-12)', '4', '4', 'active', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-10-19 00:00:00+00', '1640', 'card'),
('30bd2af5-ca1d-4532-b5ef-ee90e9467fe3', '78261ab1-3948-46c8-b5c6-7621398af6fc', '3D Tinkercad FIRST (9-12)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-08 15:04:30.398438+00', '1640', NULL),
('33ce036e-e5f1-4913-9e5f-a67c198a1d15', 'ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', '3D Tinkercad FIRST (9-12)', '4', '3', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 00:00:00+00', '1640', 'card'),
('439d4a60-3a16-4feb-b45d-472c8b128ceb', 'ca69e2e7-a023-4814-8df8-82d39d191886', '3D Makers FIRST (6-8)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:18:25.849585+00', '1640', NULL),
('482fa600-a8d3-44c2-ba53-58cb0f81572a', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'Robo AI (Ukit 6-8)', '4', '7', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 13:01:09.902239+00', '1640', NULL),
('4cac3325-d21c-45e8-8dbf-9a67947dd168', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '3D Tinkercad FIRST (9-12)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-14 16:39:20.651429+00', '1640', NULL),
('4ea6c617-fa16-4da5-8123-8e48391f6b52', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', '3D Tinkercad PRO (9-12)', '4', '6', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:53:24.441126+00', '1640', NULL),
('5b8a5c99-af7a-43ca-be4c-0fcb72a4f3e2', 'ca69e2e7-a023-4814-8df8-82d39d191886', '3D Makers FIRST (6-8)', '4', '4', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:51:02.631591+00', '1640', NULL),
('5f89f353-2738-4057-9de5-aa2b12dafa8a', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', '3D Makers FIRST (6-8)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:23:59.893648+00', '1640', NULL),
('6758d4fc-8400-410e-b57a-7c7f5d5804bc', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '3D Tinkercad FIRST (9-12)', '4', '3', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-04 00:00:00+00', '1640', NULL),
('69ae0c5b-a795-40c6-9bb3-4690dab67488', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', '3D Makers PRO (6-8)', '4', '2', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 00:00:00+00', '1640', 'cash'),
('6e46706f-a4c6-4d06-a1b7-8b107d6db3db', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', '3D Tinkercad FIRST (9-12)', '4', '1', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 00:00:00+00', '1640', 'cash'),
('7010ac26-c5f2-427a-a1d4-fbc7a4cffd7d', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'Robo AI (Ukit 6-8)', '4', '2', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-01 00:00:00+00', '1640', 'cash'),
('848b2704-5ce9-4d36-ad7f-c39fc00b137e', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', '3D Tinkercad PRO (9-12)', '4', '3', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 00:00:00+00', '1640', 'card'),
('8787b0fc-035f-4f8b-b183-290cce87c603', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', '3D Tinkercad PRO (9-12)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 12:27:13.31173+00', '1640', NULL),
('a43f229b-bec0-455c-85c8-25ce6c1209ad', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', '3D Tinkercad FIRST (9-12)', '4', '7', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-09-27 12:59:16.897495+00', '1640', NULL),
('a5f3d303-3770-4e08-b26a-a06ba37dba0a', '80416764-8767-4960-ab9e-d9047ef32f43', 'Robo AI (Ukit 6-8)', '4', '4', 'cancelled', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-26 09:08:58.735178+00', '1640', NULL),
('a620fe27-c956-4d7e-b475-95708bd663a1', 'd5fba59f-d806-40fe-8de1-6e498156a182', '3D Tinkercad FIRST (9-12)', '4', '0', 'completed', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-09-25 15:30:03.648293+00', '1640', NULL),
('bf566dab-57f3-4eeb-acc4-92a61e0a3708', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', 'Robo AI (Ukit 6-8)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-18 14:09:43.900508+00', '1640', NULL),
('c1efe9d7-e7e7-4e6e-a676-a417d71ee1e0', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', '3D Makers PRO (6-8)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 11:09:54.378165+00', '1640', NULL),
('c3955d8f-fc2a-4f0d-befc-aceded24689e', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', '3D Tinkercad FIRST (9-12)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-04 00:00:00+00', '1640', 'cash'),
('c561de53-e08c-43dc-aedd-b80ed85878d6', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', '3D Tinkercad FIRST (9-12)', '4', '2', 'cancelled', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-04 00:00:00+00', '1640', NULL),
('da020fe0-eaf4-4b0e-91a4-fbd841898193', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', '3D Tinkercad PRO (9-12)', '4', '2', 'active', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-11-01 00:00:00+00', '1640', 'card'),
('dffa701a-2af1-48b4-a151-928c2bd5b649', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', 'Robo AI (UGot 9-12)', '4', '1', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-03 12:24:29.877883+00', '1670', NULL),
('e542dfea-de9f-4f8f-9dc2-ea3af9b6ab28', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', '3D Tinkercad PRO (9-12)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-01 15:04:15.263411+00', '1640', NULL),
('eeba61b7-94e8-439b-9e5b-b65367c8466a', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', '3D Makers FIRST (6-8)', '4', '3', 'active', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-11-07 00:00:00+00', '1640', 'card'),
('fab83083-7b6c-4ce7-a031-e8c5c22731bc', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', '3D Tinkercad PRO (9-12)', '4', '0', 'completed', '85701c53-77ce-4783-a157-e21476b16d4c', '2026-10-20 12:37:54.679603+00', '1640', NULL),
('fc6f3a2f-5650-4637-876f-446ef6376eba', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', '3D Tinkercad PRO (9-12)', '4', '3', 'active', 'c8db7e24-402e-495a-8a3d-74bed8b0c55c', '2026-11-07 00:00:00+00', '1640', 'card');
insert into public.works ("id", "owner_id", "lesson_id", "student_id", "photo", "printed", "created_at", "printed_by_name", "printed_at", "trial", "weight_g", "print_minutes", "printer_id", "filament_id") values
('00084427-4510-4a7d-89ad-8909dcc4b25a', '51137c32-5d66-48e6-963e-cd96ff1603f9', '0abf27db-e6eb-4f32-b51e-7227663a4415', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', NULL, 'true', '2026-10-16 15:11:27.914949+00', 'Викладач', '2026-10-16 15:11:27.817+00', 'false', NULL, NULL, NULL, NULL),
('00186beb-c1ac-45df-8392-f8ec8707c9e9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', NULL, 'true', '2026-10-01 10:17:44.171006+00', 'Викладач', '2026-10-02 11:31:26.995+00', 'false', NULL, NULL, NULL, NULL),
('00ac2055-7c7b-4686-a7ce-caad4166b546', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '702b1756-4601-4448-9781-60c76f7669e8', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-10-07 19:34:28.346893+00', 'Викладач', '2026-10-09 08:49:50.84+00', 'false', NULL, NULL, NULL, NULL),
('025439ce-a6df-4148-ae42-0f5d553cd386', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '94797ebd-b40f-4377-96e2-8de24bc91ca3', 'ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', NULL, 'false', '2026-11-08 18:19:45.803187+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('033c79e7-f69f-44dc-9df6-76eb3dcdfdf3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '470294c2-4592-4082-aec4-494eaea7b0fc', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', NULL, 'true', '2026-10-11 16:49:04.662271+00', 'Викладач', '2026-10-14 15:45:54.152+00', 'false', NULL, NULL, NULL, NULL),
('03eec33a-1457-4572-9de1-17cd740b7cf9', '51137c32-5d66-48e6-963e-cd96ff1603f9', '3a30af7a-d675-4887-9288-1b4dcd583e18', '320747d4-9733-45ea-a0b6-86f0654aef24', NULL, 'true', '2026-10-24 08:25:49.849069+00', 'Викладач', '2026-11-06 17:16:40.551+00', 'false', NULL, NULL, NULL, NULL),
('04e14da5-070b-48dc-bef6-838608993880', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '539bbd29-bdc2-4a35-8993-1603ee952adc', '09b20d74-f3da-4342-b268-017f66ac101e', NULL, 'true', '2026-11-08 16:41:48.940121+00', 'Викладач', '2026-11-08 16:41:49.242+00', 'false', NULL, NULL, NULL, NULL),
('062b74bf-060a-4eef-8f7e-e1d3eb65c132', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'bb62cb2f-1d6f-4a2d-816f-d36637fe40a8', 'a57be370-0f09-4e81-ac2c-579095cebe97', NULL, 'true', '2026-10-02 11:36:24.510444+00', 'Викладач', '2026-10-04 13:32:36.232+00', 'false', NULL, NULL, NULL, NULL),
('06b5517c-7aab-4798-bcaf-d4390401675b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a3c849f9-8ad0-4f30-b132-644ab68db310', '3fd870d2-916a-4e60-a7db-daa5f2a8ec03', NULL, 'true', '2026-10-03 18:10:09.047663+00', 'Викладач', '2026-10-03 18:10:08.858+00', 'false', NULL, NULL, NULL, NULL),
('095c6dc1-4fc3-4637-a9ce-badbf92e2795', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '95e3414d-9b71-46aa-8f46-d3087a65dddf', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', NULL, 'true', '2026-10-18 13:26:31.150876+00', 'Викладач', '2026-10-19 17:18:07.55+00', 'false', NULL, NULL, NULL, NULL),
('09f1c7b0-615f-4dd2-b399-a6b83c4df836', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '22a88243-93c1-4144-a537-2f4e2840d42f', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', NULL, 'true', '2026-10-01 14:00:10.214299+00', 'Викладач', '2026-10-11 16:43:54.463+00', 'true', NULL, NULL, NULL, NULL),
('0acb8d46-d542-48ac-9dc0-c21b18acdc51', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', '09b20d74-f3da-4342-b268-017f66ac101e', NULL, 'true', '2026-10-25 15:18:36.382469+00', 'Викладач', '2026-10-30 12:40:58.44+00', 'false', NULL, NULL, NULL, NULL),
('0bbd2e92-5d6d-457a-bdda-7d7936851a3a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'abf264d3-6c22-4e86-a7dd-7f8f34826d0f', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'true', '2026-10-07 19:27:21.071559+00', 'Викладач', '2026-10-09 08:49:43.598+00', 'false', NULL, NULL, NULL, NULL),
('0cccb187-280d-448a-87f7-1c4603626403', '51137c32-5d66-48e6-963e-cd96ff1603f9', '3a30af7a-d675-4887-9288-1b4dcd583e18', 'e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581', NULL, 'true', '2026-10-24 08:27:31.286807+00', 'Викладач', '2026-11-05 08:16:04.435+00', 'false', NULL, NULL, NULL, NULL),
('0d7c80f5-2888-41c3-8f1b-64ffc71f0e23', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '702b1756-4601-4448-9781-60c76f7669e8', '28511a97-5dca-4516-b5e0-afc636c23dd2', NULL, 'true', '2026-10-07 19:35:06.950373+00', 'Викладач', '2026-10-09 08:49:49.608+00', 'false', NULL, NULL, NULL, NULL),
('0e526f24-6ff7-4794-b1d2-e204ab990d23', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '95e3414d-9b71-46aa-8f46-d3087a65dddf', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-10-18 13:17:46.672949+00', 'Викладач', '2026-10-19 20:17:23.13+00', 'false', NULL, NULL, NULL, NULL),
('0f161e2f-3a49-4014-b5a6-979a31d5af02', '51137c32-5d66-48e6-963e-cd96ff1603f9', '53312f9a-aa0a-4a28-b83f-e2246c0f366b', '29e27d18-c7bb-48f2-bda4-56b16ec6e3cc', NULL, 'true', '2026-10-04 13:33:20.048802+00', 'Викладач', '2026-10-16 15:11:25.8+00', 'true', NULL, NULL, NULL, NULL),
('0f39b2d4-6ec6-4a62-8ea4-1d20b87c1bd7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'a9fda877-9ae0-4d02-8f24-300f09ee5c4b', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', NULL, 'true', '2026-10-11 16:50:08.881702+00', 'Викладач', '2026-10-12 19:29:17.356+00', 'false', NULL, NULL, NULL, NULL),
('12e8dc3c-adfa-43fb-bb77-579e338ba718', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '5557b435-0c50-4108-87f4-78d2c38f4c2d', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', NULL, 'true', '2026-10-03 18:10:04.109602+00', 'Викладач', '2026-10-03 18:10:03.924+00', 'false', NULL, NULL, NULL, NULL),
('131fb2a3-6130-4153-a1e5-d592bb55a633', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a0a85659-5d7b-415f-8a29-8b1b4d4e55cf', 'c904d118-af0a-4582-a15e-c36e690a5766', NULL, 'true', '2026-10-17 19:55:39.773088+00', 'Викладач', '2026-10-20 09:26:45.18+00', 'false', NULL, NULL, NULL, NULL),
('1359a50f-d927-44ab-a920-9a679530a9f6', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'c76ef1ad-d412-4b43-b633-9833652ca9a8', 'd5fba59f-d806-40fe-8de1-6e498156a182', NULL, 'true', '2026-10-10 12:09:56.688814+00', 'Викладач', '2026-10-14 20:36:28.567+00', 'false', NULL, NULL, NULL, NULL),
('13dc5a6b-8ef4-4955-bb55-decb0e0ab9ba', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '92279374-9dcf-463c-b8f0-f742c90d5dc8', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', NULL, 'true', '2026-10-07 19:38:23.647882+00', 'Викладач', '2026-10-12 19:29:03.646+00', 'false', NULL, NULL, NULL, NULL),
('14792932-a4ba-4fd2-9486-1a3f1edaf9af', '85701c53-77ce-4783-a157-e21476b16d4c', '575e4f94-7889-4375-8b52-4b747bc89ea7', 'a57be370-0f09-4e81-ac2c-579095cebe97', NULL, 'false', '2026-10-07 19:36:25.412648+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('1488371a-ed1f-4476-b75f-320fed196111', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2eac99f7-63dd-4f88-967b-a5ba0eb59fbe', 'e6ba5875-3763-49ec-a21d-972d1806edca', NULL, 'true', '2026-10-16 12:42:28.631318+00', 'Викладач', '2026-10-20 17:44:01.379+00', 'true', NULL, NULL, NULL, NULL),
('17259f28-aa7a-404f-b131-9330e94f0f08', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '702b1756-4601-4448-9781-60c76f7669e8', '09b20d74-f3da-4342-b268-017f66ac101e', NULL, 'true', '2026-10-07 19:35:40.338205+00', 'Викладач', '2026-10-09 08:49:52.237+00', 'false', NULL, NULL, NULL, NULL),
('1781b169-3bb7-4b8d-b3f0-98a6caf75794', '51137c32-5d66-48e6-963e-cd96ff1603f9', '346bef1b-a769-4a0c-93f6-8b1c4e4ea022', '6ccebb1c-7124-4a5c-9585-3c99c2029681', NULL, 'true', '2026-10-31 16:34:10.336273+00', 'Викладач', '2026-11-02 21:06:45.515+00', 'false', NULL, NULL, NULL, NULL),
('19899d07-26e0-49b5-8db0-85e57d703c26', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'bb62cb2f-1d6f-4a2d-816f-d36637fe40a8', 'f6af0dd7-8905-4467-a298-27ec99ff9be3', NULL, 'true', '2026-10-02 11:35:42.244802+00', 'Викладач', '2026-10-02 14:04:50.086+00', 'false', NULL, NULL, NULL, NULL),
('19eada70-b6fd-4128-9c56-84931976b66d', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'c76ef1ad-d412-4b43-b633-9833652ca9a8', '00b11be9-337b-4e89-b9af-c0aec4d7930a', NULL, 'true', '2026-10-09 13:54:40.312582+00', 'Викладач', '2026-10-11 16:45:17.611+00', 'true', NULL, NULL, NULL, NULL),
('1b40e236-c80d-4d94-940b-36f150418293', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1a813807-3bb4-49f3-8ce2-f7f3b86b4644', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', NULL, 'true', '2026-10-03 18:10:07.08242+00', 'Викладач', '2026-10-03 18:10:06.893+00', 'false', NULL, NULL, NULL, NULL),
('1b62f4c2-d19a-4b7b-ab70-9222bdcbd608', '51137c32-5d66-48e6-963e-cd96ff1603f9', '3c2f9b96-30a4-475a-8cb7-950e66ecd20a', '6ccebb1c-7124-4a5c-9585-3c99c2029681', NULL, 'true', '2026-09-13 17:27:23.159239+00', 'Викладач', '2026-09-13 17:28:54.325+00', 'false', NULL, NULL, NULL, NULL),
('1ee8c8ab-edf5-4ec1-a7ef-18f9b7c6535d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6f198034-6101-4f3f-a95d-a3410d6f2483', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', NULL, 'true', '2026-10-03 18:10:01.735853+00', 'Викладач', '2026-10-03 18:10:01.536+00', 'false', NULL, NULL, NULL, NULL),
('21136c20-9cd9-4bd9-93d0-2961984afc59', '51137c32-5d66-48e6-963e-cd96ff1603f9', '089823af-b6ca-41e2-a06b-797da3a3241b', '320747d4-9733-45ea-a0b6-86f0654aef24', NULL, 'false', '2026-11-10 09:27:54.374895+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('26696bb8-ab7a-40cb-80ec-66485f585afa', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', '88b1789a-7485-4d0d-a5a9-b101706c0961', NULL, 'false', '2026-10-15 12:33:29.19894+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('2866d670-f0ff-4f34-9fc2-f093ce6237e5', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '94797ebd-b40f-4377-96e2-8de24bc91ca3', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', NULL, 'false', '2026-11-08 18:15:47.002234+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('2a7f2344-f4ee-43e2-a270-1d5691cd4028', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'b6adc486-95ff-47fc-8877-9019371cce34', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-09-13 20:00:12.499603+00', 'Викладач', '2026-10-03 18:09:45.35+00', 'true', NULL, NULL, NULL, NULL),
('2bf1e034-6ffb-4d53-83d6-cf4f49fe5632', '51137c32-5d66-48e6-963e-cd96ff1603f9', '639fc253-3fc9-4dca-ace5-2dbe078f47da', 'c904d118-af0a-4582-a15e-c36e690a5766', NULL, 'true', '2026-10-26 18:59:32.136854+00', 'Викладач', '2026-10-29 10:00:21.143+00', 'false', NULL, NULL, NULL, NULL),
('2c25f6a7-6f5c-4f5f-b1bd-1cd7922b3ae4', '51137c32-5d66-48e6-963e-cd96ff1603f9', '0222a3ed-518d-44f5-b696-6f95153289aa', 'd9dfe264-fdf8-41f5-92ca-87de083f4f29', NULL, 'false', '2026-11-09 12:02:30.850285+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('2e1d8c6f-7f5e-4fe0-8160-7d1d0c2f7fcd', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', 'b1d67bb8-df37-4bc2-bc68-8ceba59f8c45', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'false', '2026-10-04 09:28:51.18738+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('3022de0e-b578-4156-bbe4-7c62da910735', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1c144d5f-7bcd-410c-920a-84f4159320de', '92f2560c-5a4c-4067-8459-e46f8226c9a8', NULL, 'true', '2026-10-24 16:15:26.743916+00', 'Викладач', '2026-10-27 18:17:30.805591+00', 'false', NULL, NULL, NULL, NULL),
('308610e8-870e-4965-825b-87b92c2340ea', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', 'e6ba5875-3763-49ec-a21d-972d1806edca', NULL, 'false', '2026-11-09 12:25:20.694973+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('309bdd77-238f-4718-8954-d6610ebca5a0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '31ac52d8-b464-451d-86fc-6dd979037447', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', NULL, 'true', '2026-11-07 14:50:37.087761+00', 'Викладач', '2026-11-07 14:50:36.874+00', 'false', NULL, NULL, NULL, NULL),
('31e16d32-13c0-4017-a67e-48473efb924d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', '09b20d74-f3da-4342-b268-017f66ac101e', NULL, 'true', '2026-10-18 17:54:44.440969+00', 'Викладач', '2026-10-21 19:18:49.624+00', 'false', NULL, NULL, NULL, NULL),
('326a580e-9f38-428e-bf7d-f69902f92759', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '5144b63c-7cfd-4e50-9e9d-0b46881007f6', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', NULL, 'false', '2026-11-08 16:41:16.300044+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('376b2e65-400d-4f03-b8c6-71b9a35a8c9e', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a0a85659-5d7b-415f-8a29-8b1b4d4e55cf', '78261ab1-3948-46c8-b5c6-7621398af6fc', NULL, 'true', '2026-10-17 19:52:27.369512+00', 'Викладач', '2026-10-20 10:43:35.062+00', 'false', NULL, NULL, NULL, NULL),
('3b63465b-6c05-4af3-8ce7-adbeb753e179', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'e6ffcc87-38c1-4ce6-89be-bef5aac26672', '00b11be9-337b-4e89-b9af-c0aec4d7930a', NULL, 'false', '2026-11-09 12:08:10.662296+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('3bdf42d8-5804-4cc5-a2c7-45e555925302', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'true', '2026-09-21 18:03:24.085521+00', 'Викладач', '2026-10-03 18:09:55.464+00', 'true', NULL, NULL, NULL, NULL),
('3cf6d691-546c-4375-b089-a2de872df3d7', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'bae8c2d4-ff0f-491c-b55a-62a21098663a', 'd9dfe264-fdf8-41f5-92ca-87de083f4f29', NULL, 'true', '2026-11-01 13:03:31.981577+00', 'Викладач', '2026-11-02 20:20:57.365+00', 'false', NULL, NULL, NULL, NULL),
('3f072e99-83bd-4036-bdbe-6bae0a9e27f4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '95e3414d-9b71-46aa-8f46-d3087a65dddf', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', NULL, 'true', '2026-10-18 13:18:58.545001+00', 'Викладач', '2026-10-19 14:32:54.431+00', 'false', NULL, NULL, NULL, NULL),
('415d9d2e-1824-437c-bb34-227ce506e4bd', '51137c32-5d66-48e6-963e-cd96ff1603f9', '089823af-b6ca-41e2-a06b-797da3a3241b', '0c9af1bb-b47b-42a7-a770-095553ab98df', NULL, 'false', '2026-11-10 09:21:04.580012+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('4235b7d0-2a9e-4ff0-b1b7-f2ad44be9f3b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '4a6d992a-2911-4b7c-9462-abbf77e781f9', '7e538107-a218-47e5-9daa-8d2763445b5e', NULL, 'true', '2026-10-16 15:03:20.126201+00', 'Викладач', '2026-10-16 15:03:19.917+00', 'false', NULL, NULL, NULL, NULL),
('43f544c3-6d98-4192-b8f7-84568d15d5f4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-10-18 17:56:38.963705+00', 'Викладач', '2026-10-20 19:41:32.288+00', 'false', NULL, NULL, NULL, NULL),
('46a674b8-ea55-4e07-9048-9bde5deff137', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-10-31 16:39:43.658658+00', 'Викладач', '2026-11-06 22:53:17.703+00', 'false', NULL, NULL, NULL, NULL),
('46cf7e70-bbab-438e-a684-cd1744d49a8b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'c84d3555-c005-4bc6-ad06-25ed349006d8', '08572b9e-65bb-46a9-8267-409a49dffe6e', NULL, 'true', '2026-10-07 19:25:10.742982+00', 'Викладач', '2026-10-11 16:44:29.719+00', 'false', NULL, NULL, NULL, NULL),
('47256839-7cf1-4fde-a61b-9010067cc323', '51137c32-5d66-48e6-963e-cd96ff1603f9', '9a9b7555-c25e-4c2c-a5e0-73ce2f652ef6', '66f1e3e2-c7b0-411c-8d28-411e0f4c20da', NULL, 'true', '2026-10-22 13:32:45.583813+00', 'Викладач', '2026-10-29 12:19:26.153+00', 'true', NULL, NULL, NULL, NULL),
('473078d3-c5d9-44b7-aa67-7b00e300bc60', '51137c32-5d66-48e6-963e-cd96ff1603f9', '3a30af7a-d675-4887-9288-1b4dcd583e18', '0c9af1bb-b47b-42a7-a770-095553ab98df', NULL, 'true', '2026-10-24 08:30:20.989852+00', 'Викладач', '2026-11-02 20:20:51.914+00', 'false', NULL, NULL, NULL, NULL),
('4854663b-a06e-4e1e-99b3-1bdb54f0af68', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'c76ef1ad-d412-4b43-b633-9833652ca9a8', 'c904d118-af0a-4582-a15e-c36e690a5766', NULL, 'true', '2026-10-10 12:05:00.781726+00', 'Викладач', '2026-10-14 20:36:27.092+00', 'false', NULL, NULL, NULL, NULL),
('499f9206-42a1-4032-aee9-ab5ef6c9e95b', '51137c32-5d66-48e6-963e-cd96ff1603f9', '3870ece3-ace8-40e3-889e-ac5455bdf8a7', '00b11be9-337b-4e89-b9af-c0aec4d7930a', NULL, 'true', '2026-10-17 19:42:42.456482+00', 'Викладач', '2026-10-21 19:18:58.253+00', 'false', NULL, NULL, NULL, NULL),
('4a8426ee-c697-43b0-8306-ce8c73d1cdad', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '1e2edbdf-57c1-4e4d-807d-5cf968d0fd29', '08572b9e-65bb-46a9-8267-409a49dffe6e', NULL, 'false', '2026-10-18 09:20:33.148278+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('4cd25492-7a8e-4dcc-9c2f-94a16e9cdffe', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3fb0e385-49c5-4709-9c13-6fca611d229f', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', NULL, 'true', '2026-10-26 17:01:09.506556+00', 'Викладач', '2026-11-03 16:27:01.574+00', 'false', NULL, NULL, NULL, NULL),
('4cf02a4d-94cf-4078-b37e-aa6ab8a3ba59', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '92279374-9dcf-463c-b8f0-f742c90d5dc8', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', NULL, 'true', '2026-10-07 19:41:01.149296+00', 'Викладач', '2026-10-12 19:29:00.783+00', 'false', NULL, NULL, NULL, NULL),
('4dabbd14-90da-4590-a257-d8d8d81ddc25', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', '82fe617b-7f7c-4e0b-b1e3-918ea80d7935', NULL, 'false', '2026-10-15 12:34:59.169892+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('4e5f106c-828e-47da-bc33-93a306171129', '51137c32-5d66-48e6-963e-cd96ff1603f9', '7851f70d-3f50-4728-ac55-ab15e32fec0e', '6ccebb1c-7124-4a5c-9585-3c99c2029681', NULL, 'true', '2026-10-03 18:10:08.32007+00', 'Викладач', '2026-10-03 18:10:08.137+00', 'false', NULL, NULL, NULL, NULL),
('50115eae-6cc1-4d51-a314-7d33d5a67135', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'c8de471e-bba4-46cd-a558-2d3ba774ac17', '78261ab1-3948-46c8-b5c6-7621398af6fc', NULL, 'true', '2026-10-10 11:59:57.088581+00', 'Викладач', '2026-10-16 15:02:25.499+00', 'false', NULL, NULL, NULL, NULL),
('517f1fb8-f065-46b4-98c6-58675cd4064f', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'false', '2026-09-21 18:03:23.983493+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('5191739a-fb02-4610-aa5a-b8c2caa70c34', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '22a88243-93c1-4144-a537-2f4e2840d42f', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'true', '2026-10-07 17:42:03.436073+00', 'Викладач', '2026-10-11 16:44:21.531+00', 'false', NULL, NULL, NULL, NULL),
('52231bc1-d677-49b9-a302-0cb05d9f1509', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'e1a8bce7-2b4c-488a-83d0-279f4e0cad11', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', NULL, 'true', '2026-10-18 13:23:59.145279+00', 'Викладач', '2026-10-19 09:08:07.853+00', 'false', NULL, NULL, NULL, NULL),
('54b2eeb0-949d-4a70-b670-e840c2c8ac03', '51137c32-5d66-48e6-963e-cd96ff1603f9', '53312f9a-aa0a-4a28-b83f-e2246c0f366b', 'd2451baa-b8e3-4403-9192-f179984de641', NULL, 'true', '2026-10-04 13:33:20.930954+00', 'Викладач', '2026-10-16 15:11:17.233+00', 'true', NULL, NULL, NULL, NULL),
('55b4eb5a-9383-40be-a7c8-5cd035a67894', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'a3c849f9-8ad0-4f30-b132-644ab68db310', 'd5fba59f-d806-40fe-8de1-6e498156a182', NULL, 'true', '2026-10-03 18:10:12.733099+00', 'Викладач', '2026-10-03 18:10:12.537+00', 'false', NULL, NULL, NULL, NULL),
('5881a44a-aacf-42e9-8e9e-ed7ca4f99849', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '5b2420f6-07e8-4c4c-966d-5137bc31c21d', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'true', '2026-10-25 12:04:15.205541+00', 'Викладач', '2026-10-27 18:17:53.534536+00', 'false', NULL, NULL, NULL, NULL),
('58d41da2-f28e-4dea-aa02-b7dc73b05835', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', NULL, 'true', '2026-10-03 18:09:56.405418+00', 'Викладач', '2026-10-03 18:09:56.153+00', 'false', NULL, NULL, NULL, NULL),
('5932219f-1cb9-4efc-9a90-7df45379846e', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'c8de471e-bba4-46cd-a558-2d3ba774ac17', '6ccebb1c-7124-4a5c-9585-3c99c2029681', NULL, 'true', '2026-10-10 12:11:30.485145+00', 'Викладач', '2026-10-16 15:02:26.932+00', 'false', NULL, NULL, NULL, NULL),
('5b5b3c6e-6f86-43a2-b9cf-54e84ee99c11', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', NULL, 'true', '2026-10-18 17:53:16.295876+00', 'Викладач', '2026-10-19 16:43:52.919+00', 'false', NULL, NULL, NULL, NULL),
('5cfc30a3-6104-4f09-b114-71dde8e16c05', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'bb62cb2f-1d6f-4a2d-816f-d36637fe40a8', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-10-02 11:34:13.249171+00', 'Викладач', '2026-10-02 11:36:48.308+00', 'false', NULL, NULL, NULL, NULL),
('5dfb967c-59ae-4bc8-837f-b36b2c0175ff', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2b68e2be-73c4-41cc-bed7-12fc80bcbb07', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', NULL, 'true', '2026-10-19 09:09:50.982357+00', 'Викладач', '2026-10-19 09:10:39.699+00', 'false', NULL, NULL, NULL, NULL),
('5e380777-972e-4cfa-9ea3-5e9776a01705', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '325ff33b-66f4-4511-b759-f5559aba18b8', '320747d4-9733-45ea-a0b6-86f0654aef24', NULL, 'true', '2026-10-24 14:31:06.651083+00', 'Викладач', '2026-10-27 18:17:13.210297+00', 'false', NULL, NULL, NULL, NULL),
('5f62aed5-4af9-4b16-83c4-d0470969fd46', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '02a68e15-425c-4bac-809e-289e708122b4', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-10-03 18:10:04.690538+00', 'Викладач', '2026-10-03 18:10:04.494+00', 'false', NULL, NULL, NULL, NULL),
('6051eed1-ac1c-488f-8223-678c07095fb9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '470294c2-4592-4082-aec4-494eaea7b0fc', '320747d4-9733-45ea-a0b6-86f0654aef24', NULL, 'true', '2026-10-09 16:56:02.997198+00', 'Викладач', '2026-10-14 15:46:08.896+00', 'true', NULL, NULL, NULL, NULL),
('60da2e5b-12d0-47e7-80d6-ddb8b0798573', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'eda51042-f49c-4290-81f4-d2e11f0723d5', '6ccebb1c-7124-4a5c-9585-3c99c2029681', NULL, 'true', '2026-10-04 14:31:42.481461+00', 'Викладач', '2026-10-07 17:37:17.311+00', 'false', NULL, NULL, NULL, NULL),
('61edc8ea-06b9-42f8-b082-e112c991c5b0', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2bd234a7-bd14-406c-9e61-d59f009d14d2', '320747d4-9733-45ea-a0b6-86f0654aef24', NULL, 'false', '2026-11-08 16:35:47.9389+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('62329cb2-d567-4397-b101-a9497bb92e5e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f2fc1a93-6fd6-4d15-a932-818a5d51963d', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', NULL, 'true', '2026-10-25 14:11:30.673536+00', 'Викладач', '2026-10-29 21:39:48.175+00', 'false', NULL, NULL, NULL, NULL),
('62504e82-5772-4e83-9329-6ba41ac5e7bf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '470294c2-4592-4082-aec4-494eaea7b0fc', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', NULL, 'true', '2026-10-11 16:48:31.938169+00', 'Викладач', '2026-10-14 15:45:52.007+00', 'false', NULL, NULL, NULL, NULL),
('6430d9ca-509e-48c3-9f23-7b47c205559c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '5557b435-0c50-4108-87f4-78d2c38f4c2d', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', NULL, 'true', '2026-10-03 18:10:02.863168+00', 'Викладач', '2026-10-03 18:10:02.664+00', 'false', NULL, NULL, NULL, NULL),
('6702e9b9-f3b6-4440-9fe4-43972f02eeb7', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', '0b9b1eca-81c8-4c87-bdf0-0b80a25a9ae9', NULL, 'false', '2026-11-06 16:25:02.516195+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('67084960-b96f-46d2-90de-5957e8f612db', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '753f58cd-5efa-4ee7-8822-f6ab41826489', '09b20d74-f3da-4342-b268-017f66ac101e', NULL, 'true', '2026-10-11 16:58:09.399963+00', 'Викладач', '2026-10-14 15:43:45.496+00', 'false', NULL, NULL, NULL, NULL),
('682ea241-6a12-4db7-8c87-0f29a38fcf17', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '9235f3c8-b0f3-495c-8d97-4989e35e46e8', '6c880fed-268a-4a2a-a8d6-b4c30c151211', NULL, 'true', '2026-11-04 15:19:35.931996+00', 'Викладач', '2026-11-06 16:31:15.703+00', 'false', NULL, NULL, NULL, NULL),
('68f313bd-cb31-4037-8a12-220edd121aef', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dcc1ba13-1b40-49fd-bbec-746bb2d0352f', '09b20d74-f3da-4342-b268-017f66ac101e', NULL, 'true', '2026-09-19 10:36:52.033186+00', 'Викладач', '2026-10-03 18:09:47.839+00', 'true', NULL, NULL, NULL, NULL),
('6941e22d-affb-4e48-94ab-be58be34b5f2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', NULL, 'false', '2026-11-08 16:35:25.132073+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('6a93dda3-1c7b-49d3-81d0-a29e6ba05d04', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'e1a8bce7-2b4c-488a-83d0-279f4e0cad11', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', NULL, 'true', '2026-10-18 13:22:11.237992+00', 'Викладач', '2026-10-19 09:08:13.584+00', 'false', NULL, NULL, NULL, NULL),
('6c63b5d9-3ddb-4b14-ac9d-df6240483d6b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '95e3414d-9b71-46aa-8f46-d3087a65dddf', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'true', '2026-10-18 13:24:46.348699+00', 'Викладач', '2026-10-20 13:22:00.345+00', 'false', NULL, NULL, NULL, NULL),
('6ca2769e-3d1a-4f82-9a91-5888f9ee48f6', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'e7f673cd-bb9a-4dfe-8a22-3f9a8561957b', 'd5fba59f-d806-40fe-8de1-6e498156a182', NULL, 'false', '2026-10-15 14:35:56.925964+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('6d69d0ca-990b-48e2-90e3-8e67f20044a9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '9235f3c8-b0f3-495c-8d97-4989e35e46e8', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-11-04 15:15:21.0619+00', 'Викладач', '2026-11-08 07:29:58.072+00', 'false', NULL, NULL, NULL, NULL),
('711919e9-d444-40aa-8e1a-931c64b92de8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '22a88243-93c1-4144-a537-2f4e2840d42f', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', NULL, 'true', '2026-10-07 19:31:20.926164+00', 'Викладач', '2026-10-11 16:44:14.057+00', 'false', NULL, NULL, NULL, NULL),
('71929b6c-4a73-4ef1-a081-ba3c6a8de6f7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '539bbd29-bdc2-4a35-8993-1603ee952adc', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-11-08 16:41:14.503297+00', 'Викладач', '2026-11-08 16:41:14.802+00', 'false', NULL, NULL, NULL, NULL),
('71b26e87-7857-41df-90e1-6a472c1c7aa3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', '28511a97-5dca-4516-b5e0-afc636c23dd2', NULL, 'true', '2026-10-18 17:55:59.366794+00', 'Викладач', '2026-10-21 07:57:53.863+00', 'false', NULL, NULL, NULL, NULL),
('71cd4f69-9641-4b81-b0bd-7690d230f1db', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f2fc1a93-6fd6-4d15-a932-818a5d51963d', '88b1789a-7485-4d0d-a5a9-b101706c0961', NULL, 'false', '2026-10-25 12:14:53.767668+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('72e69dee-16b9-4a84-af42-f24451b568ae', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '0e623a52-80a2-4df8-b62b-a85cfc614f45', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', NULL, 'false', '2026-10-28 19:07:20.280205+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('7330b7e6-4a52-4b43-8f50-0f7d99914ac8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'false', '2026-09-21 18:03:23.778735+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('77c6cced-3d08-48c6-a993-107cbc4095fc', '51137c32-5d66-48e6-963e-cd96ff1603f9', '0abf27db-e6eb-4f32-b51e-7227663a4415', 'd2451baa-b8e3-4403-9192-f179984de641', NULL, 'true', '2026-10-16 15:11:20.983233+00', 'Викладач', '2026-10-16 15:11:20.833+00', 'false', NULL, NULL, NULL, NULL),
('7903561f-d6e6-44c2-90ba-9dd092640e99', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '9235f3c8-b0f3-495c-8d97-4989e35e46e8', '09b20d74-f3da-4342-b268-017f66ac101e', NULL, 'true', '2026-11-04 15:15:47.466072+00', 'Викладач', '2026-11-08 07:29:51.651+00', 'false', NULL, NULL, NULL, NULL),
('7927dbda-851c-4773-b6f2-7cac3778113d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', NULL, 'true', '2026-10-01 10:20:19.02224+00', 'Викладач', '2026-10-02 11:31:46.401+00', 'false', NULL, NULL, NULL, NULL),
('79a59734-9e90-416c-b767-01d947215b1e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'a9fda877-9ae0-4d02-8f24-300f09ee5c4b', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'true', '2026-10-11 16:51:07.140615+00', 'Викладач', '2026-10-12 19:29:14.476+00', 'false', NULL, NULL, NULL, NULL),
('7aa7949c-f813-4ddf-8cfd-1868f651012e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '325ff33b-66f4-4511-b759-f5559aba18b8', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'true', '2026-10-24 14:11:15.350199+00', 'Викладач', '2026-10-27 18:17:04.407913+00', 'false', NULL, NULL, NULL, NULL),
('7b664234-fa6d-4655-b047-d80e089104af', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f2fc1a93-6fd6-4d15-a932-818a5d51963d', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', NULL, 'true', '2026-10-25 14:13:14.065462+00', 'Викладач', '2026-10-29 08:54:37.78+00', 'false', NULL, NULL, NULL, NULL),
('7c49c874-c6a0-488c-9115-7c13babd9620', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '31ac52d8-b464-451d-86fc-6dd979037447', '92f2560c-5a4c-4067-8459-e46f8226c9a8', NULL, 'true', '2026-11-07 14:50:33.707382+00', 'Викладач', '2026-11-07 14:50:33.133+00', 'false', NULL, NULL, NULL, NULL),
('7df0fc9e-0811-4272-b683-4137836b90f4', '51137c32-5d66-48e6-963e-cd96ff1603f9', '639fc253-3fc9-4dca-ace5-2dbe078f47da', '78261ab1-3948-46c8-b5c6-7621398af6fc', NULL, 'true', '2026-10-26 19:05:25.409443+00', 'Викладач', '2026-10-29 12:19:06.25+00', 'false', NULL, NULL, NULL, NULL),
('7e7bdf3b-472f-475a-92f2-a9fd80508a47', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'ff84ab59-df43-4b83-a32c-61711dd233bf', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', NULL, 'true', '2026-10-28 19:09:33.941311+00', 'Викладач', '2026-10-31 10:48:32.626+00', 'false', NULL, NULL, NULL, NULL),
('827df95f-6e66-4d57-9468-79c52dcb6c35', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '91b39afb-4b1f-4f29-9e58-57baa8422449', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'true', '2026-11-01 10:35:58.415775+00', 'Викладач', '2026-11-07 18:03:18.96+00', 'false', NULL, NULL, NULL, NULL),
('8478cbcc-a09e-4510-b205-f0788845f798', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '37f74e5d-1368-4877-908e-582e7eaeb192', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', NULL, 'true', '2026-10-03 18:10:16.027071+00', 'Викладач', '2026-10-03 18:10:15.835+00', 'false', NULL, NULL, NULL, NULL),
('84eca321-507b-4009-bdda-fc65815ae008', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '22a88243-93c1-4144-a537-2f4e2840d42f', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-10-07 19:29:07.344945+00', 'Викладач', '2026-10-11 16:44:25.353+00', 'false', NULL, NULL, NULL, NULL),
('85dbc374-efdf-4bb8-bcdc-a57faceea205', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '8aa769e8-0c50-4a46-88f6-2b5f16c05c6c', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', NULL, 'true', '2026-10-11 16:59:31.858688+00', 'Викладач', '2026-10-13 09:42:35.48+00', 'false', NULL, NULL, NULL, NULL),
('865bb191-2027-45d0-9957-9d19ff7ccfa6', '51137c32-5d66-48e6-963e-cd96ff1603f9', '089823af-b6ca-41e2-a06b-797da3a3241b', 'e2c446ab-0dfe-4ab1-a2fa-2bfc840fb581', NULL, 'false', '2026-11-10 09:09:46.488091+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('8779dda7-1956-4278-b87f-c3d363e24d48', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'd1819c58-e0a6-4bf4-ae9e-82cc84bc6d05', NULL, 'false', '2026-11-07 10:57:34.515434+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('89b994eb-e7aa-4378-846b-59c2f4538185', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'dcc1ba13-1b40-49fd-bbec-746bb2d0352f', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-10-03 18:09:49.952888+00', 'Викладач', '2026-10-03 18:09:49.729+00', 'false', NULL, NULL, NULL, NULL),
('8b512027-407b-4d43-8c82-ea83913bf808', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2bd234a7-bd14-406c-9e61-d59f009d14d2', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'false', '2026-11-08 16:31:11.428725+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('8cb77510-ae5f-4cc6-a296-64930432b2be', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', '78261ab1-3948-46c8-b5c6-7621398af6fc', NULL, 'false', '2026-11-09 11:30:48.839522+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('8decb19f-ac37-4bfa-b4f2-ebec91493850', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '0e623a52-80a2-4df8-b62b-a85cfc614f45', '7e538107-a218-47e5-9daa-8d2763445b5e', NULL, 'true', '2026-09-30 16:17:02.360401+00', 'Викладач', '2026-10-16 15:03:15.166+00', 'false', NULL, NULL, NULL, NULL),
('8f1ed6b3-d35c-4081-8859-d9d0f1cc1b4a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'a9fda877-9ae0-4d02-8f24-300f09ee5c4b', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', NULL, 'true', '2026-10-11 16:50:36.512637+00', 'Викладач', '2026-10-12 19:29:15.975+00', 'false', NULL, NULL, NULL, NULL),
('8f31043e-5195-4e64-98b4-add145c2d05a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', NULL, 'true', '2026-10-03 18:09:55.049274+00', 'Викладач', '2026-10-03 18:09:54.862+00', 'false', NULL, NULL, NULL, NULL),
('90eccbaa-e317-41d3-b6d9-32f4502deb1c', '51137c32-5d66-48e6-963e-cd96ff1603f9', '9a9b7555-c25e-4c2c-a5e0-73ce2f652ef6', 'd9dfe264-fdf8-41f5-92ca-87de083f4f29', NULL, 'true', '2026-10-22 13:32:46.426908+00', 'Викладач', '2026-10-27 18:19:12.370786+00', 'true', NULL, NULL, NULL, NULL),
('911c48b0-ab30-4f40-b63e-83cc31e22013', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '31ac52d8-b464-451d-86fc-6dd979037447', '1e3b0597-a906-4eb0-9d0c-623a70b9ac67', NULL, 'false', '2026-11-07 13:41:33.490868+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('91aad67c-b3d4-4543-846a-75b8bf117e60', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '8aa769e8-0c50-4a46-88f6-2b5f16c05c6c', 'ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', NULL, 'true', '2026-10-08 14:43:46.926272+00', 'Викладач', '2026-10-19 11:47:29.272+00', 'true', NULL, NULL, NULL, NULL),
('941972bf-9a68-4722-aef6-d5aac7be08c8', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2eac99f7-63dd-4f88-967b-a5ba0eb59fbe', '00b11be9-337b-4e89-b9af-c0aec4d7930a', NULL, 'true', '2026-10-17 19:58:25.477149+00', 'Викладач', '2026-10-19 19:51:36.223+00', 'false', NULL, NULL, NULL, NULL),
('9666b37c-0119-494f-819a-dfa7bc861e43', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '199b4019-226b-497e-8497-0686d46cb38b', '92f2560c-5a4c-4067-8459-e46f8226c9a8', NULL, 'false', '2026-10-31 19:01:44.549854+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('96a27e92-f276-4b46-90cd-f8d16d8b011b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'c84d3555-c005-4bc6-ad06-25ed349006d8', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'true', '2026-10-07 19:32:55.221077+00', 'Викладач', '2026-10-11 16:44:35.675+00', 'false', NULL, NULL, NULL, NULL),
('96a52fe6-e7be-4cc6-8a76-3c60dd9bc108', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', NULL, 'true', '2026-10-19 13:33:35.26514+00', 'Викладач', '2026-10-25 15:26:43.870822+00', 'false', NULL, NULL, NULL, NULL),
('999ac9a7-df26-42a3-942b-862470f647dc', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '5557b435-0c50-4108-87f4-78d2c38f4c2d', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', NULL, 'true', '2026-10-03 18:10:03.433716+00', 'Викладач', '2026-10-03 18:10:03.234+00', 'false', NULL, NULL, NULL, NULL),
('9a9066d9-03ce-43f5-8ad7-4e6e27ca38ba', '51137c32-5d66-48e6-963e-cd96ff1603f9', '45739435-11ed-4d8c-b7d8-d86337e28c0d', 'e6ba5875-3763-49ec-a21d-972d1806edca', NULL, 'true', '2026-10-27 20:04:42.970586+00', 'Викладач', '2026-11-02 17:18:35.557+00', 'false', NULL, NULL, NULL, NULL),
('9c0da562-2503-4822-b2a0-8b3819a77adc', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2bd234a7-bd14-406c-9e61-d59f009d14d2', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', NULL, 'false', '2026-11-08 16:30:20.603285+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('a0fcb2e3-a15c-461d-bb1e-cfad599f0b4b', '85701c53-77ce-4783-a157-e21476b16d4c', '575e4f94-7889-4375-8b52-4b747bc89ea7', 'f6af0dd7-8905-4467-a298-27ec99ff9be3', NULL, 'false', '2026-10-07 19:37:19.93575+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('a48201e3-fa9e-4179-bb94-6cdbb04ec4ed', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'e7f673cd-bb9a-4dfe-8a22-3f9a8561957b', '00b11be9-337b-4e89-b9af-c0aec4d7930a', NULL, 'false', '2026-10-15 14:35:56.083323+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('a5ef38f7-92ad-4615-af99-91f32ee47e94', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2b68e2be-73c4-41cc-bed7-12fc80bcbb07', '08572b9e-65bb-46a9-8267-409a49dffe6e', NULL, 'true', '2026-10-19 09:10:18.606577+00', 'Викладач', '2026-10-19 11:47:07.258+00', 'false', NULL, NULL, NULL, NULL),
('a6f21679-4408-45e2-9204-8ab431540907', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '37f74e5d-1368-4877-908e-582e7eaeb192', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-10-03 18:10:18.435791+00', 'Викладач', '2026-10-03 18:10:18.217+00', 'false', NULL, NULL, NULL, NULL),
('a9400d24-de99-4892-82d3-0a11cd2a1537', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6f198034-6101-4f3f-a95d-a3410d6f2483', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'true', '2026-10-03 18:10:02.294048+00', 'Викладач', '2026-10-03 18:10:02.105+00', 'false', NULL, NULL, NULL, NULL),
('aa2d0f64-92ad-425c-887a-813c3a408010', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '02a68e15-425c-4bac-809e-289e708122b4', '6c880fed-268a-4a2a-a8d6-b4c30c151211', NULL, 'true', '2026-10-03 18:10:05.842985+00', 'Викладач', '2026-10-03 18:10:05.574+00', 'false', NULL, NULL, NULL, NULL),
('aac2e835-01f4-40fd-b0bc-bc53ef59e03c', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1c144d5f-7bcd-410c-920a-84f4159320de', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'true', '2026-10-24 14:33:07.870204+00', 'Викладач', '2026-10-27 18:17:35.023693+00', 'false', NULL, NULL, NULL, NULL),
('ac0ac300-6554-44f9-b8c5-a3352acbbe91', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', '28511a97-5dca-4516-b5e0-afc636c23dd2', NULL, 'true', '2026-10-25 15:18:29.479644+00', 'Викладач', '2026-10-29 16:50:44.806+00', 'false', NULL, NULL, NULL, NULL),
('ac8c8748-7892-4155-b6f5-a7df4d0d259a', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3e872f13-e9d7-4978-bfc4-f6a2b84d14d0', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', NULL, 'true', '2026-10-11 17:06:59.532387+00', 'Викладач', '2026-10-14 15:44:40.379+00', 'false', NULL, NULL, NULL, NULL),
('afa4f613-32a8-4cd8-b9d5-3d0247d096fb', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'b8ee1326-0237-41c7-bab2-b3e8d571e98a', '6c880fed-268a-4a2a-a8d6-b4c30c151211', NULL, 'true', '2026-10-18 17:55:22.958101+00', 'Викладач', '2026-10-21 19:18:53.4+00', 'false', NULL, NULL, NULL, NULL),
('b25921d9-f719-43d3-8bb0-f893843764e3', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '37f74e5d-1368-4877-908e-582e7eaeb192', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'true', '2026-10-03 18:10:16.68918+00', 'Викладач', '2026-10-03 18:10:16.495+00', 'false', NULL, NULL, NULL, NULL),
('b3c7b448-3b68-4460-9a08-cd5ef9cdf555', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '94797ebd-b40f-4377-96e2-8de24bc91ca3', '08572b9e-65bb-46a9-8267-409a49dffe6e', NULL, 'false', '2026-11-08 18:15:28.203797+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('b44e01a4-a3ec-486e-bc05-f21b5465ecac', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'cc1a1f76-62fc-46c4-a6ad-ebfcb83ec504', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'true', '2026-10-01 10:22:35.608316+00', 'Викладач', '2026-10-07 20:59:01.014+00', 'false', NULL, NULL, NULL, NULL),
('b4a8cadf-c346-4d1e-84a8-e3f18386ddce', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', NULL, 'true', '2026-10-31 16:41:10.645796+00', 'Викладач', '2026-11-06 22:53:34.862+00', 'false', NULL, NULL, NULL, NULL),
('b7f877de-28ab-4255-a359-2cceec3a9d59', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'dea6cbf4-35c6-48ad-a8c4-227235ddec16', '27ae626f-fb4e-467b-9c7c-20b0cf892f44', NULL, 'true', '2026-11-01 13:06:31.956937+00', 'Викладач', '2026-11-07 22:20:05.65+00', 'false', NULL, NULL, NULL, NULL),
('b866219e-dc85-4d7e-b401-ea790d85e5d8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', NULL, 'true', '2026-10-31 16:40:41.412591+00', 'Викладач', '2026-11-06 22:53:28.222+00', 'false', NULL, NULL, NULL, NULL),
('b8dab13a-7f32-40b0-bac0-56f1f922bc91', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3e872f13-e9d7-4978-bfc4-f6a2b84d14d0', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', NULL, 'true', '2026-10-11 16:55:41.585746+00', 'Викладач', '2026-10-14 18:38:23.475+00', 'false', NULL, NULL, NULL, NULL),
('b9de19a8-5bb3-4f07-8b3b-fa81e5146ffc', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '000d07bc-0f81-4d2d-9172-9f1efbf9bbe7', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-10-25 15:18:33.474662+00', 'Викладач', '2026-10-30 12:40:59.622+00', 'false', NULL, NULL, NULL, NULL),
('bc1ecfb6-11c5-4314-aeca-f04417bad2a2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '1c144d5f-7bcd-410c-920a-84f4159320de', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', NULL, 'true', '2026-10-24 14:35:49.857765+00', 'Викладач', '2026-10-28 11:09:00.554+00', 'false', NULL, NULL, NULL, NULL),
('bd08c5f8-9145-4659-8f95-3e374bbeb0d8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '539bbd29-bdc2-4a35-8993-1603ee952adc', '28511a97-5dca-4516-b5e0-afc636c23dd2', NULL, 'true', '2026-11-08 16:41:15.357337+00', 'Викладач', '2026-11-08 16:41:15.658+00', 'false', NULL, NULL, NULL, NULL),
('bd9b6f00-7ddb-4554-8d71-40100e28ea2e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '92279374-9dcf-463c-b8f0-f742c90d5dc8', 'd1fbf933-a1ef-45ee-9a75-4c976c50108b', NULL, 'true', '2026-10-07 19:38:56.252074+00', 'Викладач', '2026-10-12 19:29:02.464+00', 'false', NULL, NULL, NULL, NULL),
('bde3a8a3-c140-4a12-88cc-e4266136d8d6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '97236184-eb55-40c1-9ced-4d6bcc933e8e', 'bd02b3c6-bef2-4775-95e4-54f4dcec7544', NULL, 'false', '2026-10-20 11:46:11.158101+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('c0e2cedb-0d30-4296-91fb-753e85977907', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '199b4019-226b-497e-8497-0686d46cb38b', '61886bd2-6b1e-402d-a725-1ed9073e0bf8', NULL, 'true', '2026-10-31 19:02:03.016941+00', 'Викладач', '2026-11-08 10:12:28.995+00', 'false', NULL, NULL, NULL, NULL),
('c2091d25-8c47-4ca5-8e47-4bfa0db1d1ec', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '4a6d992a-2911-4b7c-9462-abbf77e781f9', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', NULL, 'true', '2026-10-28 19:08:54.378247+00', 'Викладач', '2026-11-01 11:04:52.978+00', 'false', NULL, NULL, NULL, NULL),
('c3aaeb11-48a4-451b-8603-aa8726f975e2', 'a6de212d-bc6b-4a11-8f8c-351881292c4c', '2f4e8a00-37a0-479a-8624-cec48a45adad', '44db9928-9c11-4689-acaa-aea1f78ac7b7', NULL, 'false', '2026-10-30 12:15:17.444209+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('c3c78f37-d027-47ee-b21c-4e226a5834c4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '8aa769e8-0c50-4a46-88f6-2b5f16c05c6c', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'true', '2026-10-11 16:59:59.363657+00', 'Викладач', '2026-10-12 19:29:24.004+00', 'false', NULL, NULL, NULL, NULL),
('c63e176d-2208-42df-b2ca-e70fedcb9285', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '94797ebd-b40f-4377-96e2-8de24bc91ca3', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'false', '2026-11-08 18:15:42.28039+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('c7c2a147-9bf4-42da-aae4-8aed6c1b0d0b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'abf264d3-6c22-4e86-a7dd-7f8f34826d0f', '92f2560c-5a4c-4067-8459-e46f8226c9a8', NULL, 'true', '2026-10-07 19:29:56.946491+00', 'Викладач', '2026-10-09 08:49:46.593+00', 'false', NULL, NULL, NULL, NULL),
('c90383f6-6a5f-4f4a-8112-a3949f52b518', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '95e3414d-9b71-46aa-8f46-d3087a65dddf', '320747d4-9733-45ea-a0b6-86f0654aef24', NULL, 'true', '2026-10-18 13:25:59.413966+00', 'Викладач', '2026-10-23 19:45:03.097+00', 'false', NULL, NULL, NULL, NULL),
('ca0cc27e-de76-47d2-8a22-55d755eec72d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '753f58cd-5efa-4ee7-8822-f6ab41826489', 'c90f9850-c36e-4a24-9a58-388cf32c97ed', NULL, 'true', '2026-10-11 16:57:13.842943+00', 'Викладач', '2026-10-14 18:38:25.632+00', 'false', NULL, NULL, NULL, NULL),
('cafbf16e-1512-47a8-9137-3493a2aabc0e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '91b39afb-4b1f-4f29-9e58-57baa8422449', 'ff1ec5c9-713c-42e2-9f4e-54e74a3538fe', NULL, 'true', '2026-11-01 10:36:25.593518+00', 'Викладач', '2026-11-07 18:03:21+00', 'false', NULL, NULL, NULL, NULL),
('cbbfd648-3749-4024-aaa1-8786f04b125d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '325ff33b-66f4-4511-b759-f5559aba18b8', '0f70e64d-753f-4ac2-a755-4ef0eb0c25eb', NULL, 'true', '2026-10-24 14:30:44.298886+00', 'Викладач', '2026-10-27 18:17:11.199293+00', 'false', NULL, NULL, NULL, NULL),
('ced9a89e-4aef-43e1-9711-6699ceae4405', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '6f198034-6101-4f3f-a95d-a3410d6f2483', '08572b9e-65bb-46a9-8267-409a49dffe6e', NULL, 'true', '2026-10-03 18:10:01.163216+00', 'Викладач', '2026-10-03 18:10:00.971+00', 'false', NULL, NULL, NULL, NULL),
('d10fbbd6-21d7-412a-b011-a78728be62f5', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '94797ebd-b40f-4377-96e2-8de24bc91ca3', 'da959919-410e-40a1-88d0-da5bf9712012', NULL, 'false', '2026-10-25 10:40:32.77307+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('d3a65aec-6e92-4f61-b650-870e7c2be3b6', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'fdb5f116-3717-4fd3-b27a-14c1cf5c9f5b', NULL, 'false', '2026-11-05 13:39:59.245066+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('d93e6b08-a438-4b7c-a88e-e7c633967e36', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2b68e2be-73c4-41cc-bed7-12fc80bcbb07', '6dfa8bbe-b5df-4f2f-8aba-0a4455e4694a', NULL, 'true', '2026-10-19 09:09:23.306862+00', 'Викладач', '2026-10-19 11:47:05.318+00', 'false', NULL, NULL, NULL, NULL),
('dbb2b342-c01d-4b5e-982a-77f1bfaaff75', '51137c32-5d66-48e6-963e-cd96ff1603f9', '2eac99f7-63dd-4f88-967b-a5ba0eb59fbe', 'd5fba59f-d806-40fe-8de1-6e498156a182', NULL, 'true', '2026-10-17 20:16:20.748878+00', 'Викладач', '2026-10-20 10:43:33.179+00', 'false', NULL, NULL, NULL, NULL),
('dc0340ba-2210-41fc-93ca-c84ebdb7b0e2', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f7c17761-b268-45da-a1f1-68dd85cdd7a3', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-10-03 18:09:51.17322+00', 'Викладач', '2026-10-03 18:09:50.974+00', 'false', NULL, NULL, NULL, NULL),
('dc401139-c893-4127-975e-6d73b3c8a7aa', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '539bbd29-bdc2-4a35-8993-1603ee952adc', '6c880fed-268a-4a2a-a8d6-b4c30c151211', NULL, 'true', '2026-11-08 16:41:15.861239+00', 'Викладач', '2026-11-08 16:41:16.17+00', 'false', NULL, NULL, NULL, NULL),
('dc646caf-5180-4308-9644-aa1fd17a2a97', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '5b2420f6-07e8-4c4c-966d-5137bc31c21d', '08572b9e-65bb-46a9-8267-409a49dffe6e', NULL, 'true', '2026-10-25 12:00:53.225386+00', 'Викладач', '2026-10-28 09:46:06.409+00', 'false', NULL, NULL, NULL, NULL),
('dc8bf702-593d-4d03-928d-405c1c5b296b', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'eda51042-f49c-4290-81f4-d2e11f0723d5', 'c904d118-af0a-4582-a15e-c36e690a5766', NULL, 'true', '2026-10-04 14:31:11.888939+00', 'Викладач', '2026-10-07 17:37:19+00', 'false', NULL, NULL, NULL, NULL),
('dd96232b-99e5-40cb-9a1b-d5f6eaddd5f8', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '470294c2-4592-4082-aec4-494eaea7b0fc', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'true', '2026-10-11 16:46:50.829456+00', 'Викладач', '2026-10-14 15:46:43.785+00', 'false', NULL, NULL, NULL, NULL),
('df6142b4-b537-4776-b4c6-54ce72ad1b7d', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '325ff33b-66f4-4511-b759-f5559aba18b8', 'bfbe42c5-7959-42dc-baba-9e2857fb4c40', NULL, 'true', '2026-10-24 14:30:25.356993+00', 'Викладач', '2026-10-27 18:17:09.328878+00', 'false', NULL, NULL, NULL, NULL),
('e1ce5787-692f-482d-ae1c-444996d66b6e', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'e1a8bce7-2b4c-488a-83d0-279f4e0cad11', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'true', '2026-10-18 13:23:21.057873+00', 'Викладач', '2026-10-24 09:02:36.858+00', 'false', NULL, NULL, NULL, NULL),
('e301c9b2-7a3d-4168-877c-7298ad4b2406', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f7c17761-b268-45da-a1f1-68dd85cdd7a3', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'true', '2026-10-03 18:09:52.124892+00', 'Викладач', '2026-10-03 18:09:51.934+00', 'false', NULL, NULL, NULL, NULL),
('e4718b07-c890-48db-a3a6-eeeaa7eb52d5', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '94797ebd-b40f-4377-96e2-8de24bc91ca3', '7474be52-99f0-496e-909a-f567c0cddae7', NULL, 'false', '2026-10-22 13:55:45.496921+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('e604e321-9c9a-4b70-9cfa-3e799addba42', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'd221272e-d869-4172-b838-42684fa7a94d', 'a89a18b5-3741-4158-98cb-3b99b677d5c3', NULL, 'true', '2026-11-04 16:31:06.043146+00', 'Викладач', '2026-11-05 13:31:48.738+00', 'false', NULL, NULL, NULL, NULL),
('e673d22a-7343-4fd7-be49-4d60055ba390', '51137c32-5d66-48e6-963e-cd96ff1603f9', '7851f70d-3f50-4728-ac55-ab15e32fec0e', 'c904d118-af0a-4582-a15e-c36e690a5766', NULL, 'true', '2026-09-25 15:26:25.663776+00', 'Викладач', '2026-10-03 18:10:07.496+00', 'true', NULL, NULL, NULL, NULL),
('e683a5dc-b132-4e23-a7f1-ffd808389af4', '51137c32-5d66-48e6-963e-cd96ff1603f9', '3a30af7a-d675-4887-9288-1b4dcd583e18', '9d017639-4958-4772-a563-884569c04bf6', NULL, 'true', '2026-10-24 08:28:58.69859+00', 'Викладач', '2026-11-05 08:16:11.981+00', 'false', NULL, NULL, NULL, NULL),
('e693dd3e-5d9a-459a-8897-4fc193e5a7e4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '97236184-eb55-40c1-9ced-4d6bcc933e8e', 'bd160e22-40d7-4826-8c2a-659cdac3ec4b', NULL, 'false', '2026-10-20 11:46:05.961464+00', NULL, NULL, 'true', NULL, NULL, NULL, NULL),
('ed17a21e-8e27-49af-ad1f-c8e5d1860bcf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'true', '2026-10-01 10:18:53.871503+00', 'Викладач', '2026-10-02 14:04:21.212+00', 'false', NULL, NULL, NULL, NULL),
('ef7c6fe9-2779-4254-a0cb-bcc6443deaf7', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '325ff33b-66f4-4511-b759-f5559aba18b8', '80416764-8767-4960-ab9e-d9047ef32f43', NULL, 'true', '2026-10-24 12:17:41.959891+00', 'Викладач', '2026-10-24 12:17:43.091+00', 'false', NULL, NULL, NULL, NULL),
('ef7e35b1-12f8-4517-9286-4e524101e329', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '2bd234a7-bd14-406c-9e61-d59f009d14d2', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'false', '2026-11-08 16:26:48.284095+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('f19133ce-7f03-4b2c-8fa1-c6de565e6abf', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'dddfe009-4e6b-4377-b7e8-d4e8f1cd76a8', '92f2560c-5a4c-4067-8459-e46f8226c9a8', NULL, 'true', '2026-10-03 18:09:56.917679+00', 'Викладач', '2026-10-03 18:09:56.662+00', 'false', NULL, NULL, NULL, NULL),
('f25d98cf-0e1c-450d-a77d-48530ee9a0d4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'cc1a1f76-62fc-46c4-a6ad-ebfcb83ec504', 'dbeddff1-36f2-4b4a-9425-5be7d302b236', NULL, 'true', '2026-10-01 10:22:07.441895+00', 'Викладач', '2026-10-07 20:58:59.993+00', 'false', NULL, NULL, NULL, NULL),
('f2cc0406-3dc8-480c-bf4d-408c2350f13b', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '31ac52d8-b464-451d-86fc-6dd979037447', '3f3fdeed-71b1-4fbb-8920-f244f69fefc2', NULL, 'true', '2026-11-07 14:50:37.774816+00', 'Викладач', '2026-11-07 14:50:37.56+00', 'false', NULL, NULL, NULL, NULL),
('f36ad2e9-851e-48cc-8b13-9684afd12fd4', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '31ac52d8-b464-451d-86fc-6dd979037447', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', NULL, 'true', '2026-11-07 14:50:35.780328+00', 'Викладач', '2026-11-07 14:50:35.54+00', 'false', NULL, NULL, NULL, NULL),
('f3a4320c-084c-4efb-8e91-ceb3110cebe1', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', '320747d4-9733-45ea-a0b6-86f0654aef24', NULL, 'true', '2026-10-31 16:38:38.264464+00', 'Викладач', '2026-11-07 11:27:42.097+00', 'false', NULL, NULL, NULL, NULL),
('f3bfeb07-90b1-4707-abc1-5c887d468492', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'd901ac2c-4bdc-415d-ad1a-448ee6ccb327', '00b11be9-337b-4e89-b9af-c0aec4d7930a', NULL, 'false', '2026-11-09 12:16:04.161912+00', NULL, NULL, 'false', NULL, NULL, NULL, NULL),
('f626faf9-d92e-4b13-be8b-c6ed41ef1971', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '02a68e15-425c-4bac-809e-289e708122b4', '28511a97-5dca-4516-b5e0-afc636c23dd2', NULL, 'true', '2026-10-03 18:10:06.738101+00', 'Викладач', '2026-10-03 18:10:06.535+00', 'false', NULL, NULL, NULL, NULL),
('f6d99096-93a3-4534-898d-e384f35c14e2', '51137c32-5d66-48e6-963e-cd96ff1603f9', '45739435-11ed-4d8c-b7d8-d86337e28c0d', 'd5fba59f-d806-40fe-8de1-6e498156a182', NULL, 'true', '2026-10-27 20:25:27.793029+00', 'Викладач', '2026-11-01 11:05:22.993+00', 'false', NULL, NULL, NULL, NULL),
('fa8c61dd-58d4-4be5-b979-b0bfdc5be2c9', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3e872f13-e9d7-4978-bfc4-f6a2b84d14d0', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', NULL, 'true', '2026-10-11 17:06:27.288189+00', 'Викладач', '2026-10-14 15:44:11.444+00', 'false', NULL, NULL, NULL, NULL),
('faa6221e-a44a-4ef1-8f97-cd5f17e34a78', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'abf264d3-6c22-4e86-a7dd-7f8f34826d0f', '001ba17e-f9e2-4eab-bccd-9ffafdb739ac', NULL, 'true', '2026-10-07 19:26:34.839395+00', 'Викладач', '2026-10-09 08:49:45.621+00', 'false', NULL, NULL, NULL, NULL),
('fc723145-7bbc-483b-9403-869e96bf41db', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f81a24b3-e4a8-4436-8a66-32cee65e7c7b', 'ca69e2e7-a023-4814-8df8-82d39d191886', NULL, 'true', '2026-10-31 16:40:17.684943+00', 'Викладач', '2026-11-07 11:27:38.427+00', 'false', NULL, NULL, NULL, NULL),
('fda4454f-150d-4f18-8476-e1e8c70032e0', '51137c32-5d66-48e6-963e-cd96ff1603f9', 'eda51042-f49c-4290-81f4-d2e11f0723d5', '78261ab1-3948-46c8-b5c6-7621398af6fc', NULL, 'true', '2026-10-01 13:56:44.043501+00', 'Викладач', '2026-10-07 17:37:20.501+00', 'true', NULL, NULL, NULL, NULL),
('ff698f01-2446-4a47-a576-0c0721a2db79', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', 'f952b843-ccd3-435d-ace2-17fdb79b9658', '92f2560c-5a4c-4067-8459-e46f8226c9a8', NULL, 'true', '2026-10-01 10:19:40.171434+00', 'Викладач', '2026-10-02 11:31:34.884+00', 'false', NULL, NULL, NULL, NULL),
('ffa6afcc-3e65-472a-b771-5c6a9e438aec', 'ec757c5a-f5e1-47dc-bde5-5ff69d22318e', '3ed6ade0-60ff-4815-8652-b7fa9fea14e2', '60e52e47-9158-4d49-94c5-99e8b1e9f7fb', NULL, 'true', '2026-10-19 13:33:02.048256+00', 'Викладач', '2026-10-25 15:26:45.53188+00', 'false', NULL, NULL, NULL, NULL);

-- Зв'язки між таблицями
alter table public.lesson_attendance add constraint "lesson_attendance_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES lessons(id) ON DELETE CASCADE;
alter table public.lesson_attendance add constraint "lesson_attendance_marked_by_fkey" FOREIGN KEY (marked_by) REFERENCES profiles(id);
alter table public.lesson_attendance add constraint "lesson_attendance_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id);
alter table public.lesson_attendance add constraint "lesson_attendance_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.lesson_attendance add constraint "lesson_attendance_subscription_id_fkey" FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);
alter table public.lessons add constraint "lessons_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.lessons add constraint "lessons_substitute_owner_id_fkey" FOREIGN KEY (substitute_owner_id) REFERENCES profiles(id);
alter table public.parent_credentials add constraint "parent_credentials_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES parent_accounts(id) ON DELETE CASCADE;
alter table public.parent_sessions add constraint "parent_sessions_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES parent_accounts(id) ON DELETE CASCADE;
alter table public.parent_students add constraint "parent_students_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES parent_accounts(id) ON DELETE CASCADE;
alter table public.parent_students add constraint "parent_students_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.profiles add constraint "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.student_comments add constraint "student_comments_author_id_fkey" FOREIGN KEY (author_id) REFERENCES profiles(id);
alter table public.student_comments add constraint "student_comments_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.students add constraint "students_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.studio_settings add constraint "studio_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id);
alter table public.subscriptions add constraint "subscriptions_purchased_by_fkey" FOREIGN KEY (purchased_by) REFERENCES profiles(id);
alter table public.subscriptions add constraint "subscriptions_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.work_costs add constraint "work_costs_work_id_fkey" FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE;
alter table public.works add constraint "works_filament_id_fkey" FOREIGN KEY (filament_id) REFERENCES filaments(id) ON DELETE SET NULL;
alter table public.works add constraint "works_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES lessons(id) ON DELETE CASCADE;
alter table public.works add constraint "works_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.works add constraint "works_printer_id_fkey" FOREIGN KEY (printer_id) REFERENCES printers(id) ON DELETE SET NULL;
alter table public.works add constraint "works_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

-- Індекси
CREATE INDEX idx_lesson_attendance_lesson ON public.lesson_attendance USING btree (lesson_id);
CREATE INDEX idx_lesson_attendance_student ON public.lesson_attendance USING btree (student_id);
CREATE INDEX idx_subscriptions_student_course ON public.subscriptions USING btree (student_id, course);
CREATE INDEX parent_sessions_parent_idx ON public.parent_sessions USING btree (parent_id);
CREATE INDEX parent_students_student_idx ON public.parent_students USING btree (student_id);

-- Подання (views)
create view public.filaments_safe as
 SELECT id,
    material,
    color,
    active,
    created_at,
        CASE
            WHEN is_admin() THEN price_per_kg
            ELSE NULL::numeric
        END AS price_per_kg
   FROM filaments;
create view public.lessons_safe as
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
            WHEN is_admin() THEN price_amount
            ELSE NULL::numeric
        END AS price_amount,
    duration_minutes,
    room,
    substitute_owner_id,
    completed,
    print_default
   FROM lessons;
create view public.printers_safe as
 SELECT id,
    name,
    active,
    created_at,
        CASE
            WHEN is_admin() THEN power_watts
            ELSE NULL::numeric
        END AS power_watts,
        CASE
            WHEN is_admin() THEN depreciation_per_hour
            ELSE NULL::numeric
        END AS depreciation_per_hour
   FROM printers;
create view public.rate_cards_safe as
 SELECT course,
    zp_group_1,
    zp_group_2_6,
    zp_individual,
    zp_individual_online,
    zp_group_online,
    zp_extra_service,
        CASE
            WHEN is_admin() THEN price_group_1
            ELSE NULL::numeric
        END AS price_group_1,
        CASE
            WHEN is_admin() THEN price_group_2_6
            ELSE NULL::numeric
        END AS price_group_2_6,
        CASE
            WHEN is_admin() THEN price_individual
            ELSE NULL::numeric
        END AS price_individual,
        CASE
            WHEN is_admin() THEN price_individual_online
            ELSE NULL::numeric
        END AS price_individual_online,
        CASE
            WHEN is_admin() THEN price_group_online
            ELSE NULL::numeric
        END AS price_group_online,
        CASE
            WHEN is_admin() THEN price_extra_service
            ELSE NULL::numeric
        END AS price_extra_service,
        CASE
            WHEN is_admin() THEN price_print_online
            ELSE NULL::numeric
        END AS price_print_online,
        CASE
            WHEN is_admin() THEN price_sub_group
            ELSE NULL::numeric
        END AS price_sub_group,
        CASE
            WHEN is_admin() THEN price_sub_individual
            ELSE NULL::numeric
        END AS price_sub_individual,
        CASE
            WHEN is_admin() THEN price_sub_individual_online
            ELSE NULL::numeric
        END AS price_sub_individual_online,
        CASE
            WHEN is_admin() THEN price_sub_group_online
            ELSE NULL::numeric
        END AS price_sub_group_online
   FROM rate_cards;
create view public.report_debt as
 SELECT la.id,
    la.lesson_id,
    la.student_id,
    la.owner_id,
    la.marked_at,
    l.date AS lesson_date,
    l.course,
    l.theme,
    l.price_amount +
        CASE
            WHEN la.print_enabled THEN lesson_print_surcharge(l.id, la.print_price)
            ELSE 0::numeric
        END AS price_amount,
    s.name AS student_name
   FROM lesson_attendance la
     JOIN lessons l ON l.id = la.lesson_id
     JOIN students s ON s.id = la.student_id
  WHERE la.status = 'present'::text AND la.payment_method IS NULL AND is_superadmin();
create view public.report_paid as
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
   FROM lesson_attendance la
     JOIN lessons l ON l.id = la.lesson_id
     JOIN students s ON s.id = la.student_id
  WHERE la.status = 'present'::text AND la.payment_method IS NOT NULL AND is_superadmin();
create view public.report_print_costs as
 SELECT w.id AS work_id,
    w.lesson_id,
    w.student_id,
    w.owner_id,
    COALESCE((w.printed_at AT TIME ZONE 'Europe/Kyiv'::text)::date, l.date) AS print_date,
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
   FROM works w
     JOIN lessons l ON l.id = w.lesson_id
     LEFT JOIN students s ON s.id = w.student_id
     LEFT JOIN printers p ON p.id = w.printer_id
     LEFT JOIN filaments f ON f.id = w.filament_id
     LEFT JOIN work_costs wc ON wc.work_id = w.id
  WHERE w.printed AND is_admin();
create view public.report_unused_excused as
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
   FROM lesson_attendance la
     JOIN lessons l ON l.id = la.lesson_id
     JOIN students s ON s.id = la.student_id
  WHERE la.status = 'excused'::text AND la.payment_method IS NOT NULL AND is_superadmin();
create view public.report_unused_subscriptions as
 SELECT sub.id AS subscription_id,
    sub.student_id,
    sub.course,
    sub.remaining_lessons,
    sub.total_lessons,
    sub.purchased_at,
    s.name AS student_name
   FROM subscriptions sub
     JOIN students s ON s.id = sub.student_id
  WHERE sub.status = 'active'::text AND sub.remaining_lessons > 0 AND is_superadmin();

-- Правила доступу (RLS)
alter table public.filaments enable row level security;
alter table public.lesson_attendance enable row level security;
alter table public.lessons enable row level security;
alter table public.parent_accounts enable row level security;
alter table public.parent_credentials enable row level security;
alter table public.parent_sessions enable row level security;
alter table public.parent_students enable row level security;
alter table public.printers enable row level security;
alter table public.profiles enable row level security;
alter table public.rate_cards enable row level security;
alter table public.student_comments enable row level security;
alter table public.students enable row level security;
alter table public.studio_settings enable row level security;
alter table public.subscriptions enable row level security;
alter table public.work_costs enable row level security;
alter table public.works enable row level security;
create policy "filaments_admin_all" on public.filaments as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "lesson_attendance_admin_all" on public.lesson_attendance as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "lesson_attendance_read_all" on public.lesson_attendance as permissive for select to public
  using (true);
create policy "lessons_admin_all" on public.lessons as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "lessons_select_scoped" on public.lessons as permissive for select to public
  using (((owner_id = auth.uid()) OR is_admin() OR (student_ids && my_taught_student_ids())));
create policy "parent_accounts_superadmin" on public.parent_accounts as permissive for all to authenticated
  using (is_superadmin())
  with check (is_superadmin());
create policy "parent_students_superadmin" on public.parent_students as permissive for all to authenticated
  using (is_superadmin())
  with check (is_superadmin());
create policy "printers_admin_all" on public.printers as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "profiles_select_own_or_admin" on public.profiles as permissive for select to public
  using (((id = auth.uid()) OR is_admin()));
create policy "profiles_update_own_or_admin" on public.profiles as permissive for update to public
  using (((id = auth.uid()) OR is_admin()));
create policy "rate_cards_admin_write" on public.rate_cards as permissive for all to public
  using (is_superadmin())
  with check (is_superadmin());
create policy "rate_cards_select_all" on public.rate_cards as permissive for select to public
  using (is_admin());
create policy "student_comments_insert" on public.student_comments as permissive for insert to public
  with check ((auth.uid() IS NOT NULL));
create policy "student_comments_read" on public.student_comments as permissive for select to public
  using (true);
create policy "students_delete_admin" on public.students as permissive for delete to public
  using (is_admin());
create policy "students_insert_shared" on public.students as permissive for insert to public
  with check ((auth.uid() IS NOT NULL));
create policy "students_select_shared" on public.students as permissive for select to public
  using ((auth.uid() IS NOT NULL));
create policy "students_update_shared" on public.students as permissive for update to public
  using ((auth.uid() IS NOT NULL))
  with check ((auth.uid() IS NOT NULL));
create policy "studio_settings_admin_read" on public.studio_settings as permissive for select to public
  using (is_admin());
create policy "subscriptions_admin_all" on public.subscriptions as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "work_costs_admin_read" on public.work_costs as permissive for select to public
  using (is_admin());
create policy "works_admin_all" on public.works as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "works_all_own" on public.works as permissive for all to public
  using ((owner_id = auth.uid()))
  with check ((owner_id = auth.uid()));
create policy "works_select_scoped" on public.works as permissive for select to public
  using (((owner_id = auth.uid()) OR is_admin() OR (student_id = ANY (my_taught_student_ids()))));

-- Тригери
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();
CREATE TRIGGER trg_cleanup_deleted_student_from_lessons AFTER DELETE ON public.students FOR EACH ROW EXECUTE FUNCTION cleanup_deleted_student_from_lessons();
CREATE TRIGGER trg_compute_lesson_amounts BEFORE INSERT OR UPDATE OF course, format, student_ids, extra_service ON public.lessons FOR EACH ROW EXECUTE FUNCTION compute_lesson_amounts();
CREATE TRIGGER trg_compute_work_cost AFTER INSERT OR UPDATE OF weight_g, print_minutes, printer_id, filament_id ON public.works FOR EACH ROW EXECUTE FUNCTION compute_work_cost();
CREATE TRIGGER trg_lesson_print_default AFTER UPDATE OF print_default ON public.lessons FOR EACH ROW WHEN ((new.print_default IS DISTINCT FROM old.print_default)) EXECUTE FUNCTION apply_lesson_print_default();
CREATE TRIGGER trg_parent_accounts_normalize BEFORE INSERT OR UPDATE OF phone, name ON public.parent_accounts FOR EACH ROW EXECUTE FUNCTION parent_accounts_normalize();

-- Права ролей
revoke all on public.filaments from public, anon, authenticated, service_role;
grant all on public.filaments to anon;
grant all on public.filaments to authenticated;
grant all on public.filaments to service_role;
revoke all on public.filaments_safe from public, anon, authenticated, service_role;
grant all on public.filaments_safe to anon;
grant all on public.filaments_safe to authenticated;
grant all on public.filaments_safe to service_role;
revoke all on public.lesson_attendance from public, anon, authenticated, service_role;
grant all on public.lesson_attendance to anon;
grant all on public.lesson_attendance to authenticated;
grant all on public.lesson_attendance to service_role;
revoke all on public.lessons from public, anon, authenticated, service_role;
grant all on public.lessons to anon;
grant all on public.lessons to authenticated;
grant all on public.lessons to service_role;
revoke all on public.lessons_safe from public, anon, authenticated, service_role;
grant all on public.lessons_safe to anon;
grant all on public.lessons_safe to authenticated;
grant all on public.lessons_safe to service_role;
revoke all on public.parent_accounts from public, anon, authenticated, service_role;
grant all on public.parent_accounts to authenticated;
grant all on public.parent_accounts to service_role;
revoke all on public.parent_credentials from public, anon, authenticated, service_role;
grant all on public.parent_credentials to service_role;
revoke all on public.parent_sessions from public, anon, authenticated, service_role;
grant all on public.parent_sessions to service_role;
revoke all on public.parent_students from public, anon, authenticated, service_role;
grant all on public.parent_students to authenticated;
grant all on public.parent_students to service_role;
revoke all on public.printers from public, anon, authenticated, service_role;
grant all on public.printers to anon;
grant all on public.printers to authenticated;
grant all on public.printers to service_role;
revoke all on public.printers_safe from public, anon, authenticated, service_role;
grant all on public.printers_safe to anon;
grant all on public.printers_safe to authenticated;
grant all on public.printers_safe to service_role;
revoke all on public.profiles from public, anon, authenticated, service_role;
grant all on public.profiles to anon;
grant all on public.profiles to authenticated;
grant all on public.profiles to service_role;
revoke all on public.rate_cards from public, anon, authenticated, service_role;
grant all on public.rate_cards to anon;
grant all on public.rate_cards to authenticated;
grant all on public.rate_cards to service_role;
revoke all on public.rate_cards_safe from public, anon, authenticated, service_role;
grant all on public.rate_cards_safe to anon;
grant all on public.rate_cards_safe to authenticated;
grant all on public.rate_cards_safe to service_role;
revoke all on public.report_debt from public, anon, authenticated, service_role;
grant all on public.report_debt to anon;
grant all on public.report_debt to authenticated;
grant all on public.report_debt to service_role;
revoke all on public.report_paid from public, anon, authenticated, service_role;
grant all on public.report_paid to anon;
grant all on public.report_paid to authenticated;
grant all on public.report_paid to service_role;
revoke all on public.report_print_costs from public, anon, authenticated, service_role;
grant all on public.report_print_costs to anon;
grant all on public.report_print_costs to authenticated;
grant all on public.report_print_costs to service_role;
revoke all on public.report_unused_excused from public, anon, authenticated, service_role;
grant all on public.report_unused_excused to anon;
grant all on public.report_unused_excused to authenticated;
grant all on public.report_unused_excused to service_role;
revoke all on public.report_unused_subscriptions from public, anon, authenticated, service_role;
grant all on public.report_unused_subscriptions to anon;
grant all on public.report_unused_subscriptions to authenticated;
grant all on public.report_unused_subscriptions to service_role;
revoke all on public.student_comments from public, anon, authenticated, service_role;
grant all on public.student_comments to anon;
grant all on public.student_comments to authenticated;
grant all on public.student_comments to service_role;
revoke all on public.students from public, anon, authenticated, service_role;
grant all on public.students to anon;
grant all on public.students to authenticated;
grant all on public.students to service_role;
revoke all on public.studio_settings from public, anon, authenticated, service_role;
grant all on public.studio_settings to anon;
grant all on public.studio_settings to authenticated;
grant all on public.studio_settings to service_role;
revoke all on public.subscriptions from public, anon, authenticated, service_role;
grant all on public.subscriptions to anon;
grant all on public.subscriptions to authenticated;
grant all on public.subscriptions to service_role;
revoke all on public.work_costs from public, anon, authenticated, service_role;
grant all on public.work_costs to anon;
grant all on public.work_costs to authenticated;
grant all on public.work_costs to service_role;
revoke all on public.works from public, anon, authenticated, service_role;
grant all on public.works to anon;
grant all on public.works to authenticated;
grant all on public.works to service_role;
revoke all on function public.apply_lesson_print_default() from public, anon, authenticated, service_role;
grant execute on function public.apply_lesson_print_default() to public;
grant execute on function public.apply_lesson_print_default() to anon;
grant execute on function public.apply_lesson_print_default() to authenticated;
grant execute on function public.apply_lesson_print_default() to service_role;
revoke all on function public.cleanup_deleted_student_from_lessons() from public, anon, authenticated, service_role;
grant execute on function public.cleanup_deleted_student_from_lessons() to public;
grant execute on function public.cleanup_deleted_student_from_lessons() to anon;
grant execute on function public.cleanup_deleted_student_from_lessons() to authenticated;
grant execute on function public.cleanup_deleted_student_from_lessons() to service_role;
revoke all on function public.compute_lesson_amounts() from public, anon, authenticated, service_role;
grant execute on function public.compute_lesson_amounts() to public;
grant execute on function public.compute_lesson_amounts() to anon;
grant execute on function public.compute_lesson_amounts() to authenticated;
grant execute on function public.compute_lesson_amounts() to service_role;
revoke all on function public.compute_work_cost() from public, anon, authenticated, service_role;
grant execute on function public.compute_work_cost() to public;
grant execute on function public.compute_work_cost() to anon;
grant execute on function public.compute_work_cost() to authenticated;
grant execute on function public.compute_work_cost() to service_role;
revoke all on function public.handle_new_user() from public, anon, authenticated, service_role;
grant execute on function public.handle_new_user() to public;
grant execute on function public.handle_new_user() to anon;
grant execute on function public.handle_new_user() to authenticated;
grant execute on function public.handle_new_user() to service_role;
revoke all on function public.is_admin() from public, anon, authenticated, service_role;
grant execute on function public.is_admin() to public;
grant execute on function public.is_admin() to anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin() to service_role;
revoke all on function public.is_superadmin() from public, anon, authenticated, service_role;
grant execute on function public.is_superadmin() to public;
grant execute on function public.is_superadmin() to anon;
grant execute on function public.is_superadmin() to authenticated;
grant execute on function public.is_superadmin() to service_role;
revoke all on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) from public, anon, authenticated, service_role;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to public;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to anon;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to authenticated;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to service_role;
revoke all on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) from public, anon, authenticated, service_role;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to public;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to anon;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to authenticated;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to service_role;
revoke all on function public.my_taught_student_ids() from public, anon, authenticated, service_role;
grant execute on function public.my_taught_student_ids() to public;
grant execute on function public.my_taught_student_ids() to anon;
grant execute on function public.my_taught_student_ids() to authenticated;
grant execute on function public.my_taught_student_ids() to service_role;
revoke all on function public.parent_accounts_normalize() from public, anon, authenticated, service_role;
grant execute on function public.parent_accounts_normalize() to public;
grant execute on function public.parent_accounts_normalize() to anon;
grant execute on function public.parent_accounts_normalize() to authenticated;
grant execute on function public.parent_accounts_normalize() to service_role;
revoke all on function public.parent_create_account(p_phone text, p_name text, p_student_ids uuid[]) from public, anon, authenticated, service_role;
grant execute on function public.parent_create_account(p_phone text, p_name text, p_student_ids uuid[]) to authenticated;
grant execute on function public.parent_create_account(p_phone text, p_name text, p_student_ids uuid[]) to service_role;
revoke all on function public.parent_generate_password() from public, anon, authenticated, service_role;
grant execute on function public.parent_generate_password() to public;
grant execute on function public.parent_generate_password() to anon;
grant execute on function public.parent_generate_password() to authenticated;
grant execute on function public.parent_generate_password() to service_role;
revoke all on function public.parent_login(p_phone text, p_password text, p_client text) from public, anon, authenticated, service_role;
grant execute on function public.parent_login(p_phone text, p_password text, p_client text) to anon;
grant execute on function public.parent_login(p_phone text, p_password text, p_client text) to authenticated;
grant execute on function public.parent_login(p_phone text, p_password text, p_client text) to service_role;
revoke all on function public.parent_logout(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.parent_logout(p_token text) to anon;
grant execute on function public.parent_logout(p_token text) to authenticated;
grant execute on function public.parent_logout(p_token text) to service_role;
revoke all on function public.parent_normalize_phone(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.parent_normalize_phone(p_phone text) to public;
grant execute on function public.parent_normalize_phone(p_phone text) to anon;
grant execute on function public.parent_normalize_phone(p_phone text) to authenticated;
grant execute on function public.parent_normalize_phone(p_phone text) to service_role;
revoke all on function public.parent_password_for_student(p_student_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.parent_password_for_student(p_student_id uuid) to authenticated;
grant execute on function public.parent_password_for_student(p_student_id uuid) to service_role;
revoke all on function public.parent_portal(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.parent_portal(p_token text) to anon;
grant execute on function public.parent_portal(p_token text) to authenticated;
grant execute on function public.parent_portal(p_token text) to service_role;
revoke all on function public.parent_reset_credentials(p_parent_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.parent_reset_credentials(p_parent_id uuid) to service_role;
revoke all on function public.parent_reset_password(p_parent_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.parent_reset_password(p_parent_id uuid) to authenticated;
grant execute on function public.parent_reset_password(p_parent_id uuid) to service_role;
revoke all on function public.parent_session_account(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.parent_session_account(p_token text) to service_role;
revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;
grant execute on function public.rls_auto_enable() to public;
grant execute on function public.rls_auto_enable() to anon;
grant execute on function public.rls_auto_enable() to authenticated;
grant execute on function public.rls_auto_enable() to service_role;
revoke all on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) from public, anon, authenticated, service_role;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to public;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to anon;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to authenticated;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to service_role;
revoke all on function public.set_calc_start_date(p_date date) from public, anon, authenticated, service_role;
grant execute on function public.set_calc_start_date(p_date date) to public;
grant execute on function public.set_calc_start_date(p_date date) to anon;
grant execute on function public.set_calc_start_date(p_date date) to authenticated;
grant execute on function public.set_calc_start_date(p_date date) to service_role;
revoke all on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) from public, anon, authenticated, service_role;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to public;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to anon;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to authenticated;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to service_role;
revoke all on function public.studio_report_summary(p_from date, p_to date) from public, anon, authenticated, service_role;
grant execute on function public.studio_report_summary(p_from date, p_to date) to public;
grant execute on function public.studio_report_summary(p_from date, p_to date) to anon;
grant execute on function public.studio_report_summary(p_from date, p_to date) to authenticated;
grant execute on function public.studio_report_summary(p_from date, p_to date) to service_role;
revoke all on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to public;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to anon;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to authenticated;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to service_role;

-- Лише для Supabase: realtime, сховище фото (без самих файлів), автоувімкнення RLS
do $rt$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'lesson_attendance') then alter publication supabase_realtime add table public.lesson_attendance; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'lessons') then alter publication supabase_realtime add table public.lessons; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles') then alter publication supabase_realtime add table public.profiles; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rate_cards') then alter publication supabase_realtime add table public.rate_cards; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'student_comments') then alter publication supabase_realtime add table public.student_comments; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'students') then alter publication supabase_realtime add table public.students; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'subscriptions') then alter publication supabase_realtime add table public.subscriptions; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'works') then alter publication supabase_realtime add table public.works; end if;
  end if;
end $rt$;
do $st$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('student-photos', 'student-photos', true, null, null) on conflict (id) do nothing$q$;
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('teacher-photos', 'teacher-photos', true, null, null) on conflict (id) do nothing$q$;
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('works-photos', 'works-photos', true, null, null) on conflict (id) do nothing$q$;
    execute $q$drop policy if exists "student_photos_admin_write_delete" on storage.objects$q$;
    execute $q$create policy "student_photos_admin_write_delete" on storage.objects as permissive for delete to authenticated
  using (((bucket_id = 'student-photos'::text) AND is_admin()))$q$;
    execute $q$drop policy if exists "student_photos_admin_write_insert" on storage.objects$q$;
    execute $q$create policy "student_photos_admin_write_insert" on storage.objects as permissive for insert to authenticated
  with check (((bucket_id = 'student-photos'::text) AND is_admin()))$q$;
    execute $q$drop policy if exists "student_photos_admin_write_update" on storage.objects$q$;
    execute $q$create policy "student_photos_admin_write_update" on storage.objects as permissive for update to authenticated
  using (((bucket_id = 'student-photos'::text) AND is_admin()))$q$;
    execute $q$drop policy if exists "student_photos_public_read" on storage.objects$q$;
    execute $q$create policy "student_photos_public_read" on storage.objects as permissive for select to public
  using ((bucket_id = 'student-photos'::text))$q$;
    execute $q$drop policy if exists "teacher-photos admin manage" on storage.objects$q$;
    execute $q$create policy "teacher-photos admin manage" on storage.objects as permissive for all to public
  using (((bucket_id = 'teacher-photos'::text) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['admin'::text, 'superadmin'::text])))))))$q$;
    execute $q$drop policy if exists "teacher-photos read" on storage.objects$q$;
    execute $q$create policy "teacher-photos read" on storage.objects as permissive for select to public
  using ((bucket_id = 'teacher-photos'::text))$q$;
    execute $q$drop policy if exists "teacher-photos self update" on storage.objects$q$;
    execute $q$create policy "teacher-photos self update" on storage.objects as permissive for update to public
  using (((bucket_id = 'teacher-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)))$q$;
    execute $q$drop policy if exists "teacher-photos self upload" on storage.objects$q$;
    execute $q$create policy "teacher-photos self upload" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'teacher-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)))$q$;
    execute $q$drop policy if exists "works_photos_delete_own" on storage.objects$q$;
    execute $q$create policy "works_photos_delete_own" on storage.objects as permissive for delete to authenticated
  using (((bucket_id = 'works-photos'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR is_admin())))$q$;
    execute $q$drop policy if exists "works_photos_insert_own" on storage.objects$q$;
    execute $q$create policy "works_photos_insert_own" on storage.objects as permissive for insert to authenticated
  with check (((bucket_id = 'works-photos'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR is_admin())))$q$;
    execute $q$drop policy if exists "works_photos_public_read" on storage.objects$q$;
    execute $q$create policy "works_photos_public_read" on storage.objects as permissive for select to public
  using ((bucket_id = 'works-photos'::text))$q$;
    execute $q$drop policy if exists "works_photos_update_own" on storage.objects$q$;
    execute $q$create policy "works_photos_update_own" on storage.objects as permissive for update to authenticated
  using (((bucket_id = 'works-photos'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR is_admin())))$q$;
  end if;
end $st$;
do $ev$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'ensure_rls') then
    create event trigger ensure_rls on ddl_command_end execute function public.rls_auto_enable();
  end if;
exception when insufficient_privilege then
  raise notice 'ensure_rls: немає прав на event trigger, пропущено';
end $ev$;

commit;

notify pgrst, 'reload schema';

-- Рядків у копії: filaments 30, lesson_attendance 250, lessons 496, parent_accounts 3, parent_credentials 0, parent_sessions 0, parent_students 4, printers 2, profiles 8, rate_cards 9, student_comments 8, students 52, studio_settings 1, subscriptions 34, work_costs 0, works 195