-- ============================================================
-- Stemik · облік моделей — схема бази даних для Supabase
-- Вставте цей файл повністю у Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1. Профілі користувачів (кожен викладач + суперадмін)
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'teacher' check (role in ('teacher','admin')),
  created_at timestamptz default now()
);

-- Автоматично створює профіль одразу після реєстрації нового користувача
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Учні (роздільна база для кожного викладача)
create table if not exists students (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references profiles(id) on delete cascade not null,
  name text not null,
  created_at timestamptz default now()
);

-- 3. Заняття
create table if not exists lessons (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references profiles(id) on delete cascade not null,
  series_id uuid,
  date date not null,
  time text,
  theme text not null,
  student_ids uuid[] not null default '{}',
  created_at timestamptz default now()
);

-- 4. Роботи учнів (фото + статус друку) — по одній на пару "учень + заняття"
create table if not exists works (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references profiles(id) on delete cascade not null,
  lesson_id uuid references lessons(id) on delete cascade not null,
  student_id uuid references students(id) on delete cascade not null,
  photo text,
  printed boolean not null default false,
  created_at timestamptz default now()
);

-- ============================================================
-- Row Level Security: кожен викладач бачить і редагує лише своє,
-- а користувач з роллю admin бачить (тільки переглядає) все.
-- ============================================================

alter table profiles enable row level security;
alter table students enable row level security;
alter table lessons enable row level security;
alter table works enable row level security;

-- допоміжна функція: чи є поточний користувач адміном
create or replace function public.is_admin()
returns boolean as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$ language sql security definer stable;

-- profiles
drop policy if exists "profiles_select_own_or_admin" on profiles;
create policy "profiles_select_own_or_admin" on profiles
  for select using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles_update_own" on profiles;
create policy "profiles_update_own" on profiles
  for update using (id = auth.uid());

-- students
drop policy if exists "students_all_own" on students;
create policy "students_all_own" on students
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "students_select_admin" on students;
create policy "students_select_admin" on students
  for select using (public.is_admin());

-- lessons
drop policy if exists "lessons_all_own" on lessons;
create policy "lessons_all_own" on lessons
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "lessons_select_admin" on lessons;
create policy "lessons_select_admin" on lessons
  for select using (public.is_admin());

-- works
drop policy if exists "works_all_own" on works;
create policy "works_all_own" on works
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "works_select_admin" on works;
create policy "works_select_admin" on works
  for select using (public.is_admin());

-- ============================================================
-- Готово. Останній крок — зробити СЕБЕ суперадміністратором:
-- 1. Зареєструйтесь один раз у самому застосунку (звичайна реєстрація).
-- 2. Тут-таки в SQL Editor виконайте (підставивши свій email):
--
--    update profiles set role = 'admin' where email = 'ваш@email.com';
--
-- ============================================================
