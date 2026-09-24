-- Stage 9: fix "new row for relation lessons violates check constraint
-- lessons_format_check" on any of the 4 online formats.
--
-- lessons_format_check predates 0002_tariff_rework.sql and was never
-- widened when that migration split "online" into 4 separate formats
-- (individual/group × print/no-print). The app and the payroll/price
-- trigger have sent and expected these values ever since, but the
-- database itself was still only accepting the original 'individual' and
-- 'group' — so every attempt to save a lesson in any of the 4 online
-- formats has been failing at the database, not just "Група (online)
-- +друк" specifically.
--
-- Run once in Supabase → SQL Editor, after 0001-0008.

alter table public.lessons drop constraint if exists lessons_format_check;

alter table public.lessons add constraint lessons_format_check
  check (format in (
    'individual',
    'group',
    'individual_online_print',
    'individual_online_no_print',
    'group_online_print',
    'group_online_no_print'
  ));

-- Nothing else changes: this only widens what the column accepts to match
-- what FORMAT_OPTIONS in index.html has been sending since stage 2.
