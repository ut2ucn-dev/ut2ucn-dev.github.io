-- Stage 1: teacher deactivation, teacher photos, superadmin role.
-- Run this once in Supabase → SQL Editor (as the project owner) before using
-- the matching app update. Safe to re-run (every statement is idempotent).

-- ---------------------------------------------------------------------
-- 1. "Fire" a teacher without deleting anything — a soft-delete flag.
--    Existing rows all get active = true automatically.
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists active boolean not null default true;

-- ---------------------------------------------------------------------
-- 2. Teacher / admin profile photo (mirrors students.photo).
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists photo text;

-- ---------------------------------------------------------------------
-- 3. Superadmin role.
--    profiles.role is plain text with no CHECK constraint in the schema
--    this app was built against, so "superadmin" just works as a new
--    value. If you DID add your own CHECK constraint restricting role to
--    ('admin','teacher'), uncomment and adjust the two lines below first
--    (find the real constraint name via the query underneath them).
-- ---------------------------------------------------------------------
-- select conname from pg_constraint where conrelid = 'public.profiles'::regclass and contype = 'c';
-- alter table public.profiles drop constraint if exists <constraint_name_from_above>;
-- alter table public.profiles add constraint profiles_role_check check (role in ('teacher','admin','superadmin'));

-- Promote your own account (run once, replace the email):
-- update public.profiles set role = 'superadmin' where email = 'you@example.com';

-- ---------------------------------------------------------------------
-- 4. Storage bucket for teacher/admin photos (mirrors student-photos /
--    works-photos, which this project already uses the same way).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('teacher-photos', 'teacher-photos', true)
on conflict (id) do nothing;

-- Anyone signed in may view teacher photos (the app shows them in shared lists).
drop policy if exists "teacher-photos read" on storage.objects;
create policy "teacher-photos read" on storage.objects
  for select using (bucket_id = 'teacher-photos');

-- A user may upload/replace only their own photo. The app stores each
-- photo at "<profile_id>/avatar.jpg", so the folder name is the owner check.
drop policy if exists "teacher-photos self upload" on storage.objects;
create policy "teacher-photos self upload" on storage.objects
  for insert with check (
    bucket_id = 'teacher-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "teacher-photos self update" on storage.objects;
create policy "teacher-photos self update" on storage.objects
  for update using (
    bucket_id = 'teacher-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- An admin or superadmin may upload/replace ANY teacher's photo.
drop policy if exists "teacher-photos admin manage" on storage.objects;
create policy "teacher-photos admin manage" on storage.objects
  for all using (
    bucket_id = 'teacher-photos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role in ('admin', 'superadmin')
    )
  );

-- ---------------------------------------------------------------------
-- Note on login-blocking: with only the anon key (no Supabase service-role
-- access), this project cannot ban a Supabase Auth account outright. The
-- app instead checks profiles.active right after login and immediately
-- signs the user back out if it's false, showing "Обліковий запис
-- деактивовано". That is enforced in the client, not the database — if
-- you want a harder server-side guarantee, ask and we can look at
-- restricting it further with RLS on top of this flag.
-- ---------------------------------------------------------------------
