-- Stage 2: 8-category tariffs split into ЗП (teacher payout) / ЦІНА (client
-- price), superadmin-only rate editing, and database-level hiding of every
-- price_* value from teachers. Run once in Supabase → SQL Editor, after
-- 0001_teacher_lifecycle.sql (this depends on its is_admin() function).

-- ---------------------------------------------------------------------
-- 1. Superadmin check, used to gate WRITES to rate_cards.
-- ---------------------------------------------------------------------
create or replace function public.is_superadmin()
returns boolean
language sql
stable security definer
as $function$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'superadmin'
  );
$function$;

-- ---------------------------------------------------------------------
-- 2. rate_cards: 8 categories × (zp_*, price_*). The 7 old rate_* columns
--    are left in place, unused by the app from now on — drop them later
--    yourself if you want, they're harmless until then.
-- ---------------------------------------------------------------------
alter table public.rate_cards
  add column if not exists zp_group_1 numeric not null default 0,
  add column if not exists price_group_1 numeric not null default 0,
  add column if not exists zp_group_2_6 numeric not null default 0,
  add column if not exists price_group_2_6 numeric not null default 0,
  add column if not exists zp_individual numeric not null default 0,
  add column if not exists price_individual numeric not null default 0,
  add column if not exists zp_individual_online_print numeric not null default 0,
  add column if not exists price_individual_online_print numeric not null default 0,
  add column if not exists zp_individual_online_no_print numeric not null default 0,
  add column if not exists price_individual_online_no_print numeric not null default 0,
  add column if not exists zp_group_online_print numeric not null default 0,
  add column if not exists price_group_online_print numeric not null default 0,
  add column if not exists zp_group_online_no_print numeric not null default 0,
  add column if not exists price_group_online_no_print numeric not null default 0,
  add column if not exists zp_extra_service numeric not null default 0,
  add column if not exists price_extra_service numeric not null default 0;

-- Only a superadmin may write rates directly — the admin UI already hides
-- this screen from regular admins; this is the matching DB-level rule.
alter policy rate_cards_admin_write on public.rate_cards
  using (is_superadmin()) with check (is_superadmin());

-- Direct table reads become admin-and-up only — everybody reads through
-- the masked view below instead from now on.
alter policy rate_cards_select_all on public.rate_cards
  using (is_admin());

-- One read path for everyone: teachers get every zp_* column as-is and
-- every price_* column as null; admins/superadmins get everything.
create or replace view public.rate_cards_safe as
select
  course,
  zp_group_1, zp_group_2_6, zp_individual,
  zp_individual_online_print, zp_individual_online_no_print,
  zp_group_online_print, zp_group_online_no_print, zp_extra_service,
  case when is_admin() then price_group_1 end as price_group_1,
  case when is_admin() then price_group_2_6 end as price_group_2_6,
  case when is_admin() then price_individual end as price_individual,
  case when is_admin() then price_individual_online_print end as price_individual_online_print,
  case when is_admin() then price_individual_online_no_print end as price_individual_online_no_print,
  case when is_admin() then price_group_online_print end as price_group_online_print,
  case when is_admin() then price_group_online_no_print end as price_group_online_no_print,
  case when is_admin() then price_extra_service end as price_extra_service
from public.rate_cards;

grant select on public.rate_cards_safe to authenticated;

-- ---------------------------------------------------------------------
-- 3. lessons: rename extra_print -> extra_service (it covers any add-on
--    now, not just printing), add price_amount next to the existing
--    payroll_amount, and mask price_amount from teachers the same way.
--    (lessons is already broadly readable by any authenticated user —
--    this view doesn't loosen that, it only hides the one new column.)
-- ---------------------------------------------------------------------
alter table public.lessons rename column extra_print to extra_service;
alter table public.lessons add column if not exists price_amount numeric not null default 0;

create or replace view public.lessons_safe as
select
  id, owner_id, series_id, date, time, theme, course, format,
  student_ids, extra_service, payroll_amount,
  case when is_admin() then price_amount end as price_amount
from public.lessons;

grant select on public.lessons_safe to authenticated;

-- ---------------------------------------------------------------------
-- 4. Compute payroll_amount / price_amount SERVER-SIDE on every insert
--    or update, from the real (unmasked) rate_cards row. This is what
--    makes the masking above safe end-to-end: a teacher creating their
--    own lesson never has to read a price to get the right price stored
--    on it — this trigger does it for them, with rights they don't have.
--    Whatever the client sends for these two columns is overwritten.
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
begin
  -- Editing a lesson always resends course/format/student_ids/extra_service
  -- (the app's update payload includes them unconditionally), which would
  -- otherwise re-price every lesson on every edit — even just fixing a typo
  -- in the theme. Only recompute when one of them actually changed value;
  -- otherwise keep whatever was already frozen on this row.
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

drop trigger if exists trg_compute_lesson_amounts on public.lessons;
create trigger trg_compute_lesson_amounts
  before insert or update of course, format, student_ids, extra_service
  on public.lessons
  for each row
  execute function public.compute_lesson_amounts();

-- Note: this only affects lessons created or re-priced (course, format,
-- student_ids or extra_service changed) from now on. Existing lessons keep
-- whatever payroll_amount they were frozen with; their price_amount starts
-- at 0 (the column default) since it never existed before — they predate
-- the ЦІНА concept entirely, so there's nothing correct to back-fill it
-- with automatically. If you want, tell Claude and it can help you fill in
-- price_amount for historical lessons individually.
