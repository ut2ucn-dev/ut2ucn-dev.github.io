-- Stage 8: same-day multi-lesson discount. If a student has 2+ lessons on
-- the same calendar date that are each paid by card or cash, the single
-- most expensive of them gets 10% off; the rest are charged their normal
-- price. Subscription and certificate payments never take part (they're
-- their own pricing already) and the teacher's payroll_amount is never
-- touched — only lesson_attendance.amount (the client-facing charge)
-- changes, exactly as requested.
--
-- Run once in Supabase → SQL Editor, after 0001-0007.

-- ---------------------------------------------------------------------
-- Why recompute the whole day's set on every call, not just "the current
-- lesson": the two lessons of a day can be marked/paid in either order,
-- edited, or un-marked later, and whichever is *currently* the pricier of
-- the day's paid pair should hold the discount — not whichever happened
-- to be marked second. Recomputing from lessons.price_amount (the frozen
-- sticker price, never touched by this) rather than from the
-- previously-stored lesson_attendance.amount means re-running this can
-- never compound a discount on top of a discount.
-- ---------------------------------------------------------------------
create or replace function public.mark_attendance(
  p_lesson_id uuid,
  p_student_id uuid,
  p_status text,
  p_payment_method text default null
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
  v_subscription_id uuid := null;
  v_result public.lesson_attendance;
begin
  if p_status not in ('present', 'absent', 'excused') then
    raise exception 'invalid status: %', p_status;
  end if;
  if p_payment_method is not null and p_payment_method not in ('card', 'cash', 'subscription', 'certificate') then
    raise exception 'invalid payment method: %', p_payment_method;
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
  else
    v_amount := 0;
    p_payment_method := null;
  end if;

  insert into public.lesson_attendance (
    lesson_id, student_id, owner_id, status, payment_method, amount, subscription_id, marked_by, marked_at
  ) values (
    p_lesson_id, p_student_id, v_lesson.owner_id, p_status, p_payment_method, v_amount, v_subscription_id, auth.uid(), now()
  )
  on conflict (lesson_id, student_id) do update set
    status = excluded.status,
    payment_method = excluded.payment_method,
    amount = excluded.amount,
    subscription_id = excluded.subscription_id,
    marked_by = excluded.marked_by,
    marked_at = excluded.marked_at;

  -- Same-day discount recompute for this student, across every lesson on
  -- v_lesson.date (not just this one) — runs unconditionally, because a
  -- change here (marking, unmarking, or switching payment method away
  -- from card/cash) can just as easily shrink another lesson's day-set
  -- from 2 back down to 1 and need its discount removed, as it can create
  -- a new pair that needs one applied.
  with same_day as (
    select la.lesson_id, la.student_id, l.price_amount,
           row_number() over (
             order by l.price_amount desc, l.time desc nulls last, l.id desc
           ) as rn,
           count(*) over () as day_count
    from public.lesson_attendance la
    join public.lessons l on l.id = la.lesson_id
    where la.student_id = p_student_id
      and la.status = 'present'
      and la.payment_method in ('card', 'cash')
      and l.date = v_lesson.date
  )
  update public.lesson_attendance la
    set amount = case when sd.rn = 1 and sd.day_count >= 2
                       then round(sd.price_amount * 0.9, 2)
                       else sd.price_amount
                  end
    from same_day sd
    where la.lesson_id = sd.lesson_id and la.student_id = sd.student_id;

  select * into v_result from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id;

  return v_result;
end;
$function$;

-- Nothing else changes: RLS, the report views (0003/0004) and the payroll
-- tab already read lesson_attendance.amount / lessons.payroll_amount the
-- same way — payroll_amount is untouched by this function, so a teacher's
-- pay for either lesson stays exactly what the rate card and format fixed
-- it at when the lesson was created (see 0002).
--
-- One known, deliberate gap: "Зарплата студії" / "Моя зарплата" show
-- lessons.price_amount (the undiscounted sticker price) as their "Ціна"
-- column, not lesson_attendance.amount — same as how a subscription-paid
-- lesson already showed its individual sticker price there rather than
-- the amortized package price. "Звіт студії" → «Оплачено» is the one that
-- reads lesson_attendance.amount and will correctly show the discounted
-- total actually charged.
