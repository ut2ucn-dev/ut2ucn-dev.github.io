-- Stage 10: add a birthday field to students, shown on the student card as
-- ДД.ММ.РРРР. Plain date column, no RLS changes needed — students is
-- already readable/writable by every signed-in user (shared roster) and
-- this is just one more column on that same row.
--
-- Run once in Supabase → SQL Editor, after 0001-0009.

alter table public.students
  add column if not exists birthday date;
