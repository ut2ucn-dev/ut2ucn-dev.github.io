-- Stage 20: live updates in the apps.
--
-- The apps (mobile/, the Mac admin app) listen to Supabase Realtime and
-- reload when anyone changes studio data, so nobody has to press refresh.
-- Realtime only reports changes to tables in the supabase_realtime
-- publication; this adds the studio's tables to it.
--
-- Realtime applies Row Level Security: a subscriber only hears about rows
-- they may read. The apps subscribe for admins only — a change event
-- carries the whole row, prices included, which teachers must not see.
--
-- Safe to run more than once. Run in Supabase → SQL Editor, after
-- 0001-0019. Until it is run, the apps simply don't update live.

do $$
declare
  t text;
begin
  foreach t in array array[
    'lessons',
    'lesson_attendance',
    'works',
    'students',
    'subscriptions',
    'profiles',
    'student_comments',
    'rate_cards'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end
$$;
