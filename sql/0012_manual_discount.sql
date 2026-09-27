-- Stage 12: replace the automatic same-day 10% multi-lesson discount (0008)
-- with a manual one — the admin marking attendance types whatever discount
-- percent they want (0-100) right next to the payment method, and it's
-- applied to that one lesson's charge on the spot. No more recomputing
-- other lessons of the day behind the scenes.
--
-- Run once in Supabase → SQL Editor, after 0001-0011.

-- ---------------------------------------------------------------------
-- 1. Store the applied percent on the attendance row itself, so the UI
--    can show what was typed (not just back-derive it from the amount).
-- ---------------------------------------------------------------------
alter table public.lesson_attendance
  add column if not exists discount_percent numeric not null default 0;

alter table public.lesson_attendance
  drop constraint if exists lesson_attendance_discount_percent_check;
alter table public.lesson_attendance
  add constraint lesson_attendance_discount_percent_check
  check (discount_percent >= 0 and discount_percent <= 100);

-- ---------------------------------------------------------------------
-- 2. mark_attendance(): same as 0005's version (the same-day CTE from
--    0008 is gone entirely) plus one new optional param, applied as a
--    flat percent off whatever v_amount already resolved to — the
--    lesson's frozen price_amount, or the subscription's amortized
--    package price when paid by subscription. payroll_amount is still
--    never touched, exactly as before.
-- ---------------------------------------------------------------------
create or replace function public.mark_attendance(
  p_lesson_id uuid,
  p_student_id uuid,
  p_status text,
  p_payment_method text default null,
  p_discount_percent numeric default 0
)
returns public.lesson_attendance
language plpgsql
as $function$
declare
  v_lesson record;
  v_existing record;
  v_sub record;
  v_course_price numeric;
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
        select coalesce(price_subscription, 0) into v_course_price
          from public.rate_cards where course = v_lesson.course;
        insert into public.subscriptions (student_id, course, total_lessons, remaining_lessons, total_price, purchased_by)
          values (p_student_id, v_lesson.course, 4, 4, coalesce(v_course_price, 0), auth.uid())
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

-- Nothing else changes: RLS, the report views (0003/0004) and the payroll
-- tab already read lesson_attendance.amount the same way — it's still the
-- one number that reflects whatever was actually charged, discount and all.
