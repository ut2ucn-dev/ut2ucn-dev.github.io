-- Stage 15: schedule redesign support — room assignment, lesson duration
-- (needed for the new hour-grid week view), a substitute-teacher note, a
-- "lesson completed" flag, and a proper dated comment log per student
-- (replacing the single free-text notes field from 0013).
--
-- Run once in Supabase → SQL Editor, after 0001-0014.

-- ---------------------------------------------------------------------
-- 1. Lessons: room, duration, substitute teacher, completed flag.
--    All four are plain columns on a table admin already has full write
--    access to (LessonModal's save() is already admin-gated) — no RLS
--    changes needed for these.
-- ---------------------------------------------------------------------
alter table public.lessons
  add column if not exists duration_minutes integer not null default 60;

alter table public.lessons
  add column if not exists room text;

alter table public.lessons
  drop constraint if exists lessons_room_check;
alter table public.lessons
  add constraint lessons_room_check
  check (room is null or room in ('Клас AI', 'Клас VR', 'Комп''ютерний клас', '3D-майстерня'));

alter table public.lessons
  add column if not exists substitute_owner_id uuid references public.profiles(id);

alter table public.lessons
  add column if not exists completed boolean not null default false;

-- ---------------------------------------------------------------------
-- 1b. lessons_safe is what every tab actually reads from (it masks
--     price_amount from non-admin — see 0002), not the bare table, so the
--     four new columns are invisible through it until it's rebuilt too.
--     CREATE OR REPLACE VIEW can only append columns, never drop/retype
--     the existing ones, so this is safe to run even if a column here
--     turns out to be named slightly differently than Supabase expects —
--     it will fail loudly and nothing else is affected.
-- ---------------------------------------------------------------------
create or replace view public.lessons_safe as
select
  id, owner_id, date, time, theme, course, format, student_ids,
  extra_service, series_id, payroll_amount,
  case when is_admin() then price_amount end as price_amount,
  duration_minutes, room, substitute_owner_id, completed
from public.lessons;

-- ---------------------------------------------------------------------
-- 2. Student comments: an append-only dated/authored log, replacing the
--    single students.notes textarea. Visible to any signed-in user (same
--    access as the rest of the shared student roster — this is day-to-day
--    operational notes, not financial data), anyone can add a new entry,
--    nobody edits or deletes an existing one (a log, not a document).
-- ---------------------------------------------------------------------
create table if not exists public.student_comments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  author_id uuid references public.profiles(id),
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.student_comments enable row level security;

drop policy if exists student_comments_read on public.student_comments;
create policy student_comments_read on public.student_comments
  for select using (true);

drop policy if exists student_comments_insert on public.student_comments;
create policy student_comments_insert on public.student_comments
  for insert with check (auth.uid() is not null);

-- One-time backfill: carry over any existing free-text note as that
-- student's first comment, so nothing written under the old single-
-- textarea notes field is lost when the UI switches to the comment log.
-- Guarded so re-running this file is harmless (it only ever inserts once,
-- the first time it finds no comments yet for that student).
insert into public.student_comments (student_id, body, created_at)
select s.id, s.notes, now()
from public.students s
where s.notes is not null and btrim(s.notes) <> ''
  and not exists (
    select 1 from public.student_comments c where c.student_id = s.id
  );
