-- Stage 5: subscriptions get their own package price (instead of being
-- priced as 4× whatever the individual lesson happens to cost), and the
-- amount is frozen on the subscription at purchase time — like every
-- other frozen-at-creation amount in this app, a later rate change never
-- retroactively reprices an already-sold subscription.
-- Run once in Supabase → SQL Editor, after 0001-0004.

-- ---------------------------------------------------------------------
-- 1. One flat price per course for a whole 4-lesson subscription. No
--    zp_subscription: the teacher is still paid the normal per-lesson
--    rate for whatever format each of the 4 lessons actually is —
--    only the client-facing package price is a separate concept.
-- ---------------------------------------------------------------------
alter table public.rate_cards
  add column if not exists price_subscription numeric not null default 0;

-- rate_cards_safe (0002) listed columns explicitly, so the new one needs
-- adding here too — same masking as every other price_* column.
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
  case when is_admin() then price_extra_service end as price_extra_service,
  case when is_admin() then price_subscription end as price_subscription
from public.rate_cards;

-- ---------------------------------------------------------------------
-- 2. Freeze the package price on the subscription itself when it's
--    bought, same as lessons freeze their own amounts.
-- ---------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists total_price numeric not null default 0;

-- ---------------------------------------------------------------------
-- 3. mark_attendance(): when creating a fresh subscription, snapshot
--    price_subscription onto it; when crediting a lesson that consumes a
--    subscription slot, use the subscription's own frozen total_price /
--    total_lessons instead of that lesson's individual price_amount
--    (falling back to the individual price if no package price was ever
--    set for the course, so existing behavior doesn't silently break).
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
    marked_at = excluded.marked_at
  returning * into v_result;

  return v_result;
end;
$function$;

-- Nothing else changes: RLS (admin/superadmin-only on subscriptions and
-- lesson_attendance) and the report views from 0003/0004 already work
-- unchanged with the new total_price column.
