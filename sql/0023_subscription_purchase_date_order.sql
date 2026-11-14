-- Stage 23: subscriptions bought in advance.
--
-- The bug: a child still has 2 lessons left on the current subscription,
-- the parents pay for the next one ahead of time, and the next lessons are
-- taken from the NEW subscription while the old one stays unused, although
-- the new one has a later purchase date.
--
-- mark_attendance() picked a subscription without looking at the lesson's
-- date at all, and a new one could only be recorded when no subscription
-- was running, so advance purchases ended up as manual fixes.
--
-- Second bug, found while fixing this: changing an already marked lesson
-- (discount, print, payment method) took one more lesson from the
-- subscription without returning the first one, so some subscriptions
-- show fewer lessons left than they really have. See
-- sql/tools/check_subscription_counts.sql to find and fix those.
--
-- Now:
--   * Re-marking returns the lesson's slot before taking one again.
--   * The lesson is paid from the oldest active subscription bought on or
--     before the lesson's date; a later one starts only from its purchase
--     date and only after the earlier ones are used up. (If none was bought
--     by that date, e.g. paid after the first lesson, the oldest running
--     one is used, as before.)
--   * New parameter p_new_subscription: records a new purchase even while
--     another subscription is still running (the «Купити наступний» button).
--     The released apps don't send it and keep working unchanged.
--
-- Already recorded lessons are not moved between subscriptions.
--
-- Run once in Supabase → SQL Editor, after 0001-0022. One transaction.

begin;

-- The extra parameter changes the signature: drop the old one so the API
-- has exactly one mark_attendance to call.
drop function if exists public.mark_attendance(uuid, uuid, text, text, numeric, date, text);

create function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text DEFAULT NULL::text, p_discount_percent numeric DEFAULT 0, p_purchase_date date DEFAULT NULL::date, p_purchase_method text DEFAULT NULL::text, p_new_subscription boolean DEFAULT false)
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

  -- Re-marking a lesson already paid from a subscription gives that slot
  -- back first. (This used to test "v_existing is not null", which for a
  -- row is false as soon as ANY column is null — print_price usually is —
  -- so the slot was never returned and every re-mark took one more.)
  if v_existing.subscription_id is not null
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
      -- A new purchase is recorded when asked for (bought in advance while
      -- another one is still running) or when there is nothing to use.
      if not coalesce(p_new_subscription, false) then
        perform 1 from public.subscriptions
          where student_id = p_student_id and course = v_lesson.course
            and status = 'active' and remaining_lessons > 0;
      end if;
      if coalesce(p_new_subscription, false) or not found then
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
      -- Which subscription pays for THIS lesson: the oldest one already
      -- bought by the lesson's date, so a subscription bought in advance
      -- only starts once its date comes and the earlier ones are used up.
      -- If none was bought by then (paid after the first lessons), the
      -- oldest one still running.
      select * into v_sub from public.subscriptions
        where student_id = p_student_id and course = v_lesson.course
          and status = 'active' and remaining_lessons > 0
        order by ((purchased_at at time zone 'UTC')::date <= v_lesson.date) desc, purchased_at asc, id
        limit 1
        for update;
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

grant execute on function public.mark_attendance(uuid, uuid, text, text, numeric, date, text, boolean) to anon, authenticated, service_role;

commit;

notify pgrst, 'reload schema';
