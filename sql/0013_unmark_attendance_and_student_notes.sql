-- Stage 13: two independent fixes.
--
-- Run once in Supabase → SQL Editor.

-- ---------------------------------------------------------------------
-- 1. unmark_attendance(): clear a status (П/Н/ВПП) back to "no record" —
--    clicking the already-active status button in the UI now calls this
--    instead of mark_attendance. Mirrors mark_attendance's own subscription
--    refund logic (a present lesson that had consumed a package slot gives
--    it back), then deletes the attendance row outright — no status, no
--    payment, nothing left to show. Same security model as mark_attendance:
--    not security definer, relies on lesson_attendance/subscriptions RLS
--    (admin/superadmin only) to restrict who can call this usefully.
-- ---------------------------------------------------------------------
create or replace function public.unmark_attendance(
  p_lesson_id uuid,
  p_student_id uuid
)
returns void
language plpgsql
as $function$
declare
  v_existing record;
begin
  select * into v_existing from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id
    for update;

  if not found then
    return;
  end if;

  if v_existing.subscription_id is not null and v_existing.status <> 'absent' then
    update public.subscriptions
      set remaining_lessons = remaining_lessons + 1,
          status = 'active'
      where id = v_existing.subscription_id;
  end if;

  delete from public.lesson_attendance
    where lesson_id = p_lesson_id and student_id = p_student_id;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Free-text notes per student, shown only on that student's own card
--    (StudentCardModal) — never aggregated or shown anywhere else. Same
--    access as the rest of a student's basic info (phone, birthday): any
--    signed-in teacher or admin can read and edit it, since it's shared
--    roster data, not something privacy-gated like the child's photo.
-- ---------------------------------------------------------------------
alter table public.students
  add column if not exists notes text;
