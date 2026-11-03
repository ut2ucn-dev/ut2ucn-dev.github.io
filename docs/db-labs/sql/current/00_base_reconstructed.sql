-- Базові таблиці проєкту, створені в Supabase до міграції 0001
-- (відновлено за кодом застосунку: index.html, mobile/lib/data/*.dart)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  first_name text,
  last_name text,
  role text not null default 'teacher'
);
create table public.students (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id),
  name text not null,
  phone text,
  parent_last_name text,
  parent_first_name text,
  photo text,
  created_at timestamptz not null default now()
);
create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id),
  series_id uuid,
  date date not null,
  time time,
  theme text,
  course text,
  format text not null default 'group',
  student_ids uuid[] not null default '{}',
  extra_print boolean not null default false,
  payroll_amount numeric not null default 0,
  created_at timestamptz not null default now()
);
create table public.works (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  photo text,
  printed boolean not null default false,
  printed_by_name text,
  printed_at timestamptz,
  trial boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.rate_cards (
  course text primary key,
  rate_group numeric, rate_individual numeric, rate_mini_group numeric,
  rate_online numeric, rate_online_group numeric, rate_extra_print numeric, rate_trial numeric
);
create or replace function public.is_admin() returns boolean language sql stable security definer as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'superadmin'))
$$;
alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.lessons enable row level security;
alter table public.works enable row level security;
alter table public.rate_cards enable row level security;
create policy rate_cards_select_all on public.rate_cards for select using (true);
create policy rate_cards_admin_write on public.rate_cards for all using (is_admin()) with check (is_admin());
