-- Stage 3: attendance (П/Н/ВПП) + payment (картка/готівка/абонемент/
-- сертифікат) + 4-lesson subscriptions, admin/superadmin-only throughout.
-- Run once in Supabase → SQL Editor, after 0001 and 0002 (needs is_admin()
-- from 0001 and lessons.price_amount from 0002).
--
-- Everything that decides WHAT HAPPENS (does a subscription slot get
-- consumed, refunded, or forfeited) lives in mark_attendance() below —
-- the app only ever calls this one function; it never writes these two
-- tables directly. That's deliberate: it's the single source of truth
-- for the business rules, instead of re-implementing them in JS.

-- ---------------------------------------------------------------------
-- 1. subscriptions — an абонемент is 4 lessons for one (student, course).
-- ---------------------------------------------------------------------
create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  course text not null,
  total_lessons int not null default 4,
  remaining_lessons int not null default 4,
  status text not null default 'active' check (status in ('active', 'completed', 'cancelled')),
  purchased_by uuid references public.profiles(id),
  purchased_at timestamptz not null default now()
);

create index if not exists idx_subscriptions_student_course on public.subscriptions(student_id, course);

alter table public.subscriptions enable row level security;

drop policy if exists subscriptions_admin_all on public.subscriptions;
create policy subscriptions_admin_all on public.subscriptions
  for all using (is_admin()) with check (is_admin());

-- ---------------------------------------------------------------------
-- 2. lesson_attendance — one row per (lesson, student): П/Н/ВПП plus
--    whatever payment was recorded for that occurrence.
-- ---------------------------------------------------------------------
create table if not exists public.lesson_attendance (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  owner_id uuid references public.profiles(id),
  status text not null check (status in ('present', 'absent', 'excused')),
  payment_method text check (payment_method in ('card', 'cash', 'subscription', 'certificate')),
  amount numeric not null default 0,
  subscription_id uuid references public.subscriptions(id),
  marked_by uuid references public.profiles(id),
  marked_at timestamptz not null default now(),
  unique (lesson_id, student_id)
);

create index if not exists idx_lesson_attendance_lesson on public.lesson_attendance(lesson_id);
create index if not exists idx_lesson_attendance_student on public.lesson_attendance(student_id);

alter table public.lesson_attendance enable row level security;

drop policy if exists lesson_attendance_admin_all on public.lesson_attendance;
create policy lesson_attendance_admin_all on public.lesson_attendance
  for all using (is_admin()) with check (is_admin());

-- ---------------------------------------------------------------------
-- 3. mark_attendance() — the one entry point the app calls. Runs as the
--    caller (no security definer needed: admins already have full rights
--    to both tables above via RLS, so a plain call from a non-admin
--    correctly fails instead of silently doing nothing).
--
--    Rules (from the spec):
--    - П (present) + оплата: records the payment. "абонемент" consumes
--      one slot from an active subscription for this (student, course),
--      creating a fresh 4-lesson one if none has slots left.
--    - Н (absent): payment "disappears" — cleared, and if it had
--      consumed a subscription slot, that slot is NOT refunded
--      (forfeited — a no-show costs the slot).
--    - ВПП (excused): payment "carries forward" — cleared from this
--      lesson, and if it had consumed a subscription slot, that slot
--      IS refunded (available again for a future lesson).
--    - Re-saving the same (status, payment_method) is a no-op in effect:
--      any previously consumed slot is refunded, then immediately
--      re-consumed, netting to zero.
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
  if p_status = 'present' and p_payment_method is null then
    -- Present with no payment yet is allowed on purpose — that's exactly
    -- the "заборгованість" (debt) case the superadmin report surfaces.
    null;
  end if;

  select * into v_lesson from public.lessons where id = p_lesson_id;
  if not found then
    raise exception 'lesson not found';
  end if;

  select * into v_existing from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id
    for update;

  -- Undo whatever the previous state had consumed — except a forfeited
  -- absence, which never gives the slot back.
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
        insert into public.subscriptions (student_id, course, total_lessons, remaining_lessons, purchased_by)
          values (p_student_id, v_lesson.course, 4, 4, auth.uid())
          returning * into v_sub;
      end if;
      update public.subscriptions
        set remaining_lessons = v_sub.remaining_lessons - 1,
            status = case when v_sub.remaining_lessons - 1 <= 0 then 'completed' else 'active' end
        where id = v_sub.id;
      v_subscription_id := v_sub.id;
    end if;
  else
    -- absent or excused: no payment attached to this lesson.
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

grant execute on function public.mark_attendance(uuid, uuid, text, text) to authenticated;
