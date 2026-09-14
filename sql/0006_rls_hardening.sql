-- Stage 6: close the two RLS gaps that let any logged-in teacher read
-- every OTHER teacher's lessons and works directly via the API (the app
-- itself never queries this way, but nothing in the database stopped it).
-- Run once in Supabase → SQL Editor, after 0001-0005.
--
-- Not touched on purpose: students_shared_all (ALL, any authenticated
-- user) — that one is the intentional "one shared roster for the whole
-- studio" design, not a bug. Tightening it is a product decision, not a
-- pure security fix, so it's left alone unless you ask for it.

-- ---------------------------------------------------------------------
-- Helper: every student_id this teacher has ever had in one of their own
-- lessons. SECURITY DEFINER so it bypasses RLS internally — otherwise a
-- self-referencing subquery on `lessons` inside a `lessons` policy risks
-- recursion.
-- ---------------------------------------------------------------------
create or replace function public.my_taught_student_ids()
returns uuid[]
language sql
stable
security definer
as $function$
  select coalesce(array_agg(distinct sid), '{}'::uuid[])
  from public.lessons l, unnest(l.student_ids) as sid
  where l.owner_id = auth.uid();
$function$;

-- ---------------------------------------------------------------------
-- lessons: a teacher may read their own lessons, everything if
-- admin/superadmin, or another teacher's lesson IF it shares a student
-- they've also taught (keeps the student-card "full history across
-- teachers" feature working) — never an entirely unrelated colleague's
-- schedule.
-- ---------------------------------------------------------------------
drop policy if exists lessons_select_all on public.lessons;
create policy lessons_select_scoped on public.lessons
  for select using (
    owner_id = auth.uid()
    or is_admin()
    or student_ids && my_taught_student_ids()
  );

-- ---------------------------------------------------------------------
-- works: same idea. works_all_own (full CRUD on your own rows) and
-- works_admin_all are untouched — only the blanket readonly policy is
-- replaced.
-- ---------------------------------------------------------------------
drop policy if exists works_select_all_readonly on public.works;
create policy works_select_scoped on public.works
  for select using (
    owner_id = auth.uid()
    or is_admin()
    or student_id = any(my_taught_student_ids())
  );
