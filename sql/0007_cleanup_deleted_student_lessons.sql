-- Stage 7: when a student is deleted, their id can be left dangling inside
-- lessons.student_ids (a plain array, not a foreign key) — that's the exact
-- cause of the "8 в черзі на друк" vs "2 у Черзі друку" mismatch reported:
-- the top counter on Розклад counted these ghost ids, while the Черга друку
-- tab already (silently) skips any id it can't resolve to a real student.
-- The app now applies that same skip when counting (see index.html), so the
-- numbers agree either way — this migration additionally cleans the
-- dangling ids out of the data itself, instead of only hiding them.
--
-- Run once in Supabase → SQL Editor, after 0001-0006.

-- ---------------------------------------------------------------------
-- Why only lessons dated today or later:
-- lessons.payroll_amount / price_amount are frozen on the lesson row by
-- trg_compute_lesson_amounts (0002) whenever student_ids changes, and
-- "Зарплата" / "Зарплата студії" (PayrollTab) sum that column directly for
-- every lesson in the chosen period — including past ones. If this cleanup
-- touched a PAST lesson's student_ids, it would silently re-price it (e.g.
-- drop it from "group of 3" to "group of 2" pricing) and change a payroll
-- total that was already paid out and reported on. Scoping to upcoming
-- lessons only means the recompute this triggers is the same thing that
-- already happens when a teacher edits a future lesson's roster by hand —
-- never a rewrite of already-settled history.
-- ---------------------------------------------------------------------

-- One-time backfill: strip any already-dangling ids out of upcoming lessons
-- created before this migration existed.
update public.lessons l
  set student_ids = (
    select coalesce(array_agg(sid), '{}'::uuid[])
    from unnest(l.student_ids) as sid
    where exists (select 1 from public.students s where s.id = sid)
  )
  where l.date >= current_date
    and exists (
      select 1 from unnest(l.student_ids) as sid
      where not exists (select 1 from public.students s where s.id = sid)
    );

-- Going forward: whenever a student is deleted, drop their id from every
-- upcoming lesson's student_ids right away.
create or replace function public.cleanup_deleted_student_from_lessons()
returns trigger
language plpgsql
security definer
as $function$
begin
  update public.lessons
    set student_ids = array_remove(student_ids, old.id)
    where date >= current_date
      and old.id = any(student_ids);
  return old;
end;
$function$;

drop trigger if exists trg_cleanup_deleted_student_from_lessons on public.students;
create trigger trg_cleanup_deleted_student_from_lessons
  after delete on public.students
  for each row
  execute function public.cleanup_deleted_student_from_lessons();

-- Past lessons are intentionally left untouched, dangling ids and all —
-- their frozen amounts stay exactly as they were. The app already hides
-- these ghost rows from both the schedule's print-queue counter and the
-- Черга друку tab, so nothing about them is visible or wrong to a user;
-- this migration only makes sure it stops happening for new deletions and
-- clears it out of the lessons that haven't happened yet.
