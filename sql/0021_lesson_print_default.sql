-- Stage 21: "+ друк" on an online lesson.
--
-- The lesson form gets a "+ друк" tick for the online formats. It is a
-- default for the whole lesson: every child marked "П" on it gets their
-- own "Друк" (lesson_attendance.print_enabled, sql/0017) switched on, with
-- the usual surcharge. A child's own switch in the lesson card still wins
-- afterwards — the tick only sets the starting point.
--
--   lessons.print_default   — the lesson's "+ друк"
--
-- Ticking or unticking it on a lesson that already has children marked
-- "П" applies the change to them too (and re-prices their charge, exactly
-- as their own switch would).
--
-- Run once in Supabase → SQL Editor, after 0001-0020. One transaction.

begin;

-- ---------------------------------------------------------------------
-- 1. The column, and lessons_safe exposing it (same columns as 0017 plus
--    print_default, which is not a price).
-- ---------------------------------------------------------------------
alter table public.lessons
  add column if not exists print_default boolean not null default false;

drop view if exists public.lessons_safe;
create view public.lessons_safe as
select
  id, owner_id, date, time, theme, course, format, student_ids,
  extra_service, series_id, payroll_amount,
  case when is_admin() then price_amount end as price_amount,
  duration_minutes, room, substitute_owner_id, completed,
  print_default
from public.lessons;
grant select on public.lessons_safe to authenticated;

-- ---------------------------------------------------------------------
-- 2. mark_attendance(): as in 0017, plus — when a child becomes "П" on a
--    lesson with "+ друк" (newly marked, or changed from Н/ВПП) — their
--    print switched on and its surcharge added. Re-marking a child who is
--    already "П" (a new payment, a discount) keeps whatever print they have.
-- ---------------------------------------------------------------------
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

grant execute on function public.mark_attendance(uuid, uuid, text, text, numeric, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Ticking / unticking "+ друк" on a lesson applies it to the children
--    already marked "П", through set_attendance_print() so their charge
--    is re-priced the same way their own switch does it.
-- ---------------------------------------------------------------------
create or replace function public.apply_lesson_print_default()
returns trigger
language plpgsql
as $function$
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

drop trigger if exists trg_lesson_print_default on public.lessons;
create trigger trg_lesson_print_default
  after update of print_default on public.lessons
  for each row
  when (new.print_default is distinct from old.print_default)
  execute function public.apply_lesson_print_default();

commit;

notify pgrst, 'reload schema';
