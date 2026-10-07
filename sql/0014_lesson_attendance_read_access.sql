-- Stage 14: teachers need to know which of their students were marked
-- "П" today — the schedule and print-queue tabs now only let you attach
-- a work photo / toggle it printed for a student who actually attended,
-- and that gating has to work in a teacher's own (non-admin) view too,
-- not just admin's. Attendance *marking* stays admin/superadmin-only
-- (mark_attendance / unmark_attendance already enforce that via the
-- existing write policies) — this only widens who may read the status.
--
-- Run once in Supabase → SQL Editor, after 0001-0013.

drop policy if exists lesson_attendance_read_all on public.lesson_attendance;
create policy lesson_attendance_read_all on public.lesson_attendance
  for select using (true);
