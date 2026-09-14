-- Stage 4: superadmin-only studio report — paid lessons, debt, and unused
-- (paid-for-but-not-consumed) lessons. Run once in Supabase → SQL Editor,
-- after 0001-0003 (needs is_admin()/is_superadmin() and the attendance
-- tables from those).
--
-- Same principle as the earlier stages: the definitions of "paid",
-- "debt" and "unused" — and the sums — live in the database, not in the
-- app. The app calls studio_report_summary() for the headline numbers
-- and reads the four detail views below for line items. Every one of
-- them returns nothing at all unless the caller is a superadmin.

-- ---------------------------------------------------------------------
-- Detail views (for the line-item lists under each report section).
-- ---------------------------------------------------------------------

create or replace view public.report_paid as
select
  la.id, la.lesson_id, la.student_id, la.owner_id, la.payment_method, la.amount, la.marked_at,
  l.date as lesson_date, l.course, l.theme,
  s.name as student_name
from public.lesson_attendance la
join public.lessons l on l.id = la.lesson_id
join public.students s on s.id = la.student_id
where la.status = 'present' and la.payment_method is not null and is_superadmin();

create or replace view public.report_debt as
select
  la.id, la.lesson_id, la.student_id, la.owner_id, la.marked_at,
  l.date as lesson_date, l.course, l.theme, l.price_amount,
  s.name as student_name
from public.lesson_attendance la
join public.lessons l on l.id = la.lesson_id
join public.students s on s.id = la.student_id
where la.status = 'present' and la.payment_method is null and is_superadmin();

create or replace view public.report_unused_subscriptions as
select
  sub.id as subscription_id, sub.student_id, sub.course, sub.remaining_lessons,
  sub.total_lessons, sub.purchased_at,
  s.name as student_name
from public.subscriptions sub
join public.students s on s.id = sub.student_id
where sub.status = 'active' and sub.remaining_lessons > 0 and is_superadmin();

create or replace view public.report_unused_excused as
select
  la.id, la.lesson_id, la.student_id, la.owner_id, la.payment_method, la.amount, la.marked_at,
  l.date as lesson_date, l.course, l.theme,
  s.name as student_name
from public.lesson_attendance la
join public.lessons l on l.id = la.lesson_id
join public.students s on s.id = la.student_id
where la.status = 'excused' and la.payment_method is not null and is_superadmin();

grant select on public.report_paid to authenticated;
grant select on public.report_debt to authenticated;
grant select on public.report_unused_subscriptions to authenticated;
grant select on public.report_unused_excused to authenticated;

-- ---------------------------------------------------------------------
-- Headline numbers for a date range (subscriptions are a standing
-- balance, so they're reported as of now regardless of the range).
-- ---------------------------------------------------------------------
create or replace function public.studio_report_summary(p_from date, p_to date)
returns table (
  paid_total numeric,
  paid_count int,
  debt_total numeric,
  debt_count int,
  unused_subscription_lessons int,
  unused_subscription_count int,
  unused_excused_total numeric,
  unused_excused_count int
)
language plpgsql
stable
as $function$
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

grant execute on function public.studio_report_summary(date, date) to authenticated;
