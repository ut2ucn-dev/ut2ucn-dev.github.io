-- Stage 17: the online-lesson "Друк" checkbox moves from the lesson (0016)
-- to each student. Printing is decided child by child: it adds a print
-- surcharge to that one child's charge, never to the lesson's sticker
-- price and never to the teacher's ЗП. A child paying by subscription
-- still pays nothing extra for printing.
--
-- Where things live now:
--   lessons.price_amount              — base price, no print in it
--   lesson_attendance.print_enabled   — this child's work gets printed
--   lesson_attendance.print_price     — optional custom amount for it
-- The surcharge is print_price if set, else the course's
-- rate_cards.price_print_online, else 100 грн (0 for lessons before the
-- studio's calc_start_date, same as every other amount).
--
-- Run once in Supabase → SQL Editor, after 0001-0016. One transaction.

begin;

-- ---------------------------------------------------------------------
-- 1. Per-student columns.
-- ---------------------------------------------------------------------
alter table public.lesson_attendance
  add column if not exists print_enabled boolean not null default false;
alter table public.lesson_attendance
  add column if not exists print_price numeric;
alter table public.lesson_attendance drop constraint if exists lesson_attendance_print_price_check;
alter table public.lesson_attendance
  add constraint lesson_attendance_print_price_check check (print_price is null or print_price >= 0);

-- ---------------------------------------------------------------------
-- 2. The surcharge for one child on one lesson.
-- ---------------------------------------------------------------------
create or replace function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric)
returns numeric
language plpgsql
stable
security definer
as $function$
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

grant execute on function public.lesson_print_surcharge(uuid, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Move every lesson-level tick from 0016 onto the children marked
--    present on that lesson, and take the print part back out of the
--    lesson's sticker price (it is added per child from now on). The
--    print part removed is the same amount each child gets added back,
--    so every charge already recorded stays exactly what it was.
--
--    For lessons converted from the old "+друк" formats, the old price
--    had print built in at whatever the old rate difference was; this
--    takes it as the course's print price (or 100 грн), which is what
--    those lessons would cost under the new rules anyway.
-- ---------------------------------------------------------------------
update public.lesson_attendance la
  set print_enabled = true,
      print_price = l.print_price
  from public.lessons l
  where l.id = la.lesson_id
    and l.print_enabled
    and la.status = 'present';

alter table public.lessons disable trigger trg_compute_lesson_amounts;
update public.lessons l
  set price_amount = greatest(l.price_amount - public.lesson_print_surcharge(l.id, l.print_price), 0)
  where l.print_enabled and l.price_amount > 0;
alter table public.lessons enable trigger trg_compute_lesson_amounts;

-- ---------------------------------------------------------------------
-- 4. Remove the lesson-level print from 0016: the trigger, the view, the
--    function and the two columns.
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

drop trigger if exists trg_compute_lesson_amounts on public.lessons;
create trigger trg_compute_lesson_amounts
  before insert or update of course, format, student_ids, extra_service
  on public.lessons
  for each row
  execute function public.compute_lesson_amounts();

drop view if exists public.lessons_safe;
create view public.lessons_safe as
select
  id, owner_id, date, time, theme, course, format, student_ids,
  extra_service, series_id, payroll_amount,
  case when is_admin() then price_amount end as price_amount,
  duration_minutes, room, substitute_owner_id, completed
from public.lessons;
grant select on public.lessons_safe to authenticated;

drop function if exists public.set_lesson_print(uuid, boolean, numeric);

alter table public.lessons drop constraint if exists lessons_print_price_check;
alter table public.lessons drop column if exists print_enabled;
alter table public.lessons drop column if exists print_price;

-- ---------------------------------------------------------------------
-- 5. set_attendance_print(): one child's "Друк" checkbox. The child must
--    already be marked present. Re-prices that child's card / cash /
--    certificate charge (keeping their discount); a subscription charge
--    is left alone. Runs as the caller: attendance writes are admin-only
--    by RLS, so for anyone else the update simply matches no row.
-- ---------------------------------------------------------------------
create or replace function public.set_attendance_print(
  p_lesson_id uuid,
  p_student_id uuid,
  p_enabled boolean,
  p_price numeric default null
)
returns public.lesson_attendance
language plpgsql
as $function$
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

grant execute on function public.set_attendance_print(uuid, uuid, boolean, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- 6. mark_attendance(): same as 0016, plus the child's own print
--    surcharge on a non-subscription charge. The print columns are never
--    written here, so re-marking keeps whatever was ticked.
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

  if p_status = 'present' then
    v_amount := coalesce(v_lesson.price_amount, 0);
    if v_existing.print_enabled then
      v_amount := v_amount + public.lesson_print_surcharge(p_lesson_id, v_existing.print_price);
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

grant execute on function public.mark_attendance(uuid, uuid, text, text, numeric, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Debt report: an unpaid child who had a print owes it too.
-- ---------------------------------------------------------------------
drop view if exists public.report_debt;
create view public.report_debt as
select
  la.id, la.lesson_id, la.student_id, la.owner_id, la.marked_at,
  l.date as lesson_date, l.course, l.theme,
  l.price_amount
    + case when la.print_enabled then public.lesson_print_surcharge(l.id, la.print_price) else 0 end
    as price_amount,
  s.name as student_name
from public.lesson_attendance la
join public.lessons l on l.id = la.lesson_id
join public.students s on s.id = la.student_id
where la.status = 'present' and la.payment_method is null and is_superadmin();
grant select on public.report_debt to authenticated;

commit;

notify pgrst, 'reload schema';
