-- Stage 11: let the superadmin turn financial calculation on for the studio
-- starting from a chosen date. Lessons dated before that date get ЗП and
-- Ціна forced to 0 — both for every lesson that already exists (backfilled
-- immediately, once) and for any lesson created or re-priced afterward.
-- Lessons on/after the date calculate exactly as before, unaffected.
--
-- This is a deliberate, superadmin-only exception to the "freeze at
-- creation, never rewrite history" rule the rest of the app follows
-- (0002/0007/0008) — the whole point here is a one-time, explicit studio
-- decision to zero out pre-launch lessons, not something that should ever
-- happen silently as a side effect of something else.
--
-- Run once in Supabase → SQL Editor, after 0001-0010.

-- ---------------------------------------------------------------------
-- 1. One-row studio settings table. calc_start_date = null means "no
--    threshold" — everything calculates as it always has (the default,
--    unchanged behavior for any studio that never touches this).
-- ---------------------------------------------------------------------
create table if not exists public.studio_settings (
  id boolean primary key default true check (id),
  calc_start_date date,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);
insert into public.studio_settings (id) values (true) on conflict (id) do nothing;

alter table public.studio_settings enable row level security;

drop policy if exists studio_settings_admin_read on public.studio_settings;
create policy studio_settings_admin_read on public.studio_settings
  for select using (is_admin());

-- Writes only ever happen through set_calc_start_date() below (security
-- definer, checks is_superadmin() itself) — no direct-write policy needed.

-- ---------------------------------------------------------------------
-- 2. compute_lesson_amounts(): force 0/0 for any lesson dated before the
--    threshold, ahead of the existing "did anything relevant change"
--    check and the normal rate-card lookup.
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
    when new.format = 'individual_online_print' then 'individual_online_print'
    when new.format = 'individual_online_no_print' then 'individual_online_no_print'
    when new.format = 'group_online_print' then 'group_online_print'
    when new.format = 'group_online_no_print' then 'group_online_no_print'
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
        when 'individual_online_print' then rc.zp_individual_online_print
        when 'individual_online_no_print' then rc.zp_individual_online_no_print
        when 'group_online_print' then rc.zp_group_online_print
        when 'group_online_no_print' then rc.zp_group_online_no_print
      end, 0)
    + case when new.extra_service then coalesce(rc.zp_extra_service, 0) else 0 end;

  new.price_amount := coalesce(
      case bucket
        when 'group_1' then rc.price_group_1
        when 'group_2_6' then rc.price_group_2_6
        when 'individual' then rc.price_individual
        when 'individual_online_print' then rc.price_individual_online_print
        when 'individual_online_no_print' then rc.price_individual_online_no_print
        when 'group_online_print' then rc.price_group_online_print
        when 'group_online_no_print' then rc.price_group_online_no_print
      end, 0)
    + case when new.extra_service then coalesce(rc.price_extra_service, 0) else 0 end;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 3. set_calc_start_date(): the one entry point the app calls. Superadmin
--    only (checked here, not just hidden in the UI, since this touches
--    every lesson in the studio). Updates the setting, then immediately
--    zeroes ЗП/Ціна on every EXISTING lesson dated before the new date —
--    a one-time backfill, not something the trigger alone would do,
--    since the trigger only fires on insert/update of a lesson.
--
--    Passing null clears the threshold (new/edited lessons go back to
--    calculating normally regardless of date) but does NOT restore
--    amounts already zeroed by a previous call — there is nothing correct
--    to restore them to, so this direction is one-way by design.
-- ---------------------------------------------------------------------
create or replace function public.set_calc_start_date(p_date date)
returns void
language plpgsql
security definer
as $function$
begin
  if not is_superadmin() then
    raise exception 'Лише суперадміністратор може змінювати цю дату.';
  end if;

  update public.studio_settings
    set calc_start_date = p_date,
        updated_at = now(),
        updated_by = auth.uid();

  if p_date is not null then
    update public.lessons
      set payroll_amount = 0, price_amount = 0
      where date < p_date
        and (payroll_amount <> 0 or price_amount <> 0);
  end if;
end;
$function$;

grant execute on function public.set_calc_start_date(date) to authenticated;
