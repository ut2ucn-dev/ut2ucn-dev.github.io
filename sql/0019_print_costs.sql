-- Stage 19: cost of every printed model.
--
-- When a work is marked "Надруковано" the teacher enters its weight (g),
-- print time (minutes), printer and filament. The cost is then computed
-- in the database and frozen on that work:
--
--   material     = weight × (1 + waste %) × filament ₴/kg / 1000
--   electricity  = hours × printer W / 1000 × studio tariff ₴/kWh
--   depreciation = hours × printer ₴/hour
--
-- Re-saving a work with the same inputs never re-prices it, so a later
-- change of any price leaves models already costed untouched. Costs are
-- admin-only: teachers enter the inputs but never see a price.
--
-- Run once in Supabase → SQL Editor, after 0001-0018. One transaction.

begin;

-- ---------------------------------------------------------------------
-- 1. Directories. Rows are hidden (active = false), never deleted, so
--    names stay available for models printed on them earlier.
-- ---------------------------------------------------------------------
create table if not exists public.printers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  power_watts numeric not null default 0 check (power_watts >= 0),
  depreciation_per_hour numeric not null default 0 check (depreciation_per_hour >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.filaments (
  id uuid primary key default gen_random_uuid(),
  material text not null,
  color text,
  price_per_kg numeric not null default 0 check (price_per_kg >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.printers enable row level security;
alter table public.filaments enable row level security;

drop policy if exists printers_admin_all on public.printers;
create policy printers_admin_all on public.printers
  for all using (is_admin()) with check (is_admin());
drop policy if exists filaments_admin_all on public.filaments;
create policy filaments_admin_all on public.filaments
  for all using (is_admin()) with check (is_admin());

-- Everyone picks a printer / filament by name; only admins see numbers.
drop view if exists public.printers_safe;
create view public.printers_safe as
select id, name, active, created_at,
  case when is_admin() then power_watts end as power_watts,
  case when is_admin() then depreciation_per_hour end as depreciation_per_hour
from public.printers;
grant select on public.printers_safe to authenticated;

drop view if exists public.filaments_safe;
create view public.filaments_safe as
select id, material, color, active, created_at,
  case when is_admin() then price_per_kg end as price_per_kg
from public.filaments;
grant select on public.filaments_safe to authenticated;

-- ---------------------------------------------------------------------
-- 2. Studio-wide settings: electricity tariff and filament waste %.
--    studio_settings has no write policy (see 0011); writes go through
--    this admin-checked function.
-- ---------------------------------------------------------------------
alter table public.studio_settings
  add column if not exists electricity_tariff numeric not null default 0;
alter table public.studio_settings
  add column if not exists filament_waste_percent numeric not null default 0;
alter table public.studio_settings drop constraint if exists studio_settings_print_cost_check;
alter table public.studio_settings
  add constraint studio_settings_print_cost_check
  check (electricity_tariff >= 0 and filament_waste_percent >= 0 and filament_waste_percent <= 100);

create or replace function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric)
returns void
language plpgsql
security definer
as $function$
begin
  if not is_admin() then
    raise exception 'Лише адміністратор може змінювати ці налаштування.';
  end if;
  update public.studio_settings
    set electricity_tariff = coalesce(p_tariff, 0),
        filament_waste_percent = coalesce(p_waste_percent, 0),
        updated_at = now(),
        updated_by = auth.uid();
end;
$function$;
grant execute on function public.set_print_cost_settings(numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- 3. What the teacher enters on a work.
-- ---------------------------------------------------------------------
alter table public.works add column if not exists weight_g numeric;
alter table public.works add column if not exists print_minutes numeric;
alter table public.works add column if not exists printer_id uuid references public.printers(id) on delete set null;
alter table public.works add column if not exists filament_id uuid references public.filaments(id) on delete set null;
alter table public.works drop constraint if exists works_print_inputs_check;
alter table public.works
  add constraint works_print_inputs_check
  check ((weight_g is null or weight_g >= 0) and (print_minutes is null or print_minutes >= 0));

-- ---------------------------------------------------------------------
-- 4. The frozen cost, one row per work. Admin-only to read; written only
--    by the trigger below.
-- ---------------------------------------------------------------------
create table if not exists public.work_costs (
  work_id uuid primary key references public.works(id) on delete cascade,
  weight_g numeric,
  waste_percent numeric not null default 0,
  price_per_kg numeric,
  print_minutes numeric,
  power_watts numeric,
  electricity_tariff numeric,
  depreciation_per_hour numeric,
  material_cost numeric not null default 0,
  electricity_cost numeric not null default 0,
  depreciation_cost numeric not null default 0,
  total_cost numeric not null default 0,
  computed_at timestamptz not null default now()
);

alter table public.work_costs enable row level security;
drop policy if exists work_costs_admin_read on public.work_costs;
create policy work_costs_admin_read on public.work_costs
  for select using (is_admin());

create or replace function public.compute_work_cost()
returns trigger
language plpgsql
security definer
as $function$
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

drop trigger if exists trg_compute_work_cost on public.works;
create trigger trg_compute_work_cost
  after insert or update of weight_g, print_minutes, printer_id, filament_id
  on public.works
  for each row
  execute function public.compute_work_cost();

-- ---------------------------------------------------------------------
-- 5. One row per printed work for the admin «Друк» page. print_date is
--    when it was marked printed (the lesson date for older rows).
-- ---------------------------------------------------------------------
drop view if exists public.report_print_costs;
create view public.report_print_costs as
select
  w.id as work_id, w.lesson_id, w.student_id, w.owner_id,
  coalesce((w.printed_at at time zone 'Europe/Kyiv')::date, l.date) as print_date,
  l.date as lesson_date, l.course, l.theme,
  s.name as student_name,
  w.weight_g, w.print_minutes, w.printer_id, w.filament_id,
  p.name as printer_name,
  f.material as filament_material, f.color as filament_color,
  wc.material_cost, wc.electricity_cost, wc.depreciation_cost, wc.total_cost
from public.works w
join public.lessons l on l.id = w.lesson_id
left join public.students s on s.id = w.student_id
left join public.printers p on p.id = w.printer_id
left join public.filaments f on f.id = w.filament_id
left join public.work_costs wc on wc.work_id = w.id
where w.printed and is_admin();
grant select on public.report_print_costs to authenticated;

commit;

notify pgrst, 'reload schema';
