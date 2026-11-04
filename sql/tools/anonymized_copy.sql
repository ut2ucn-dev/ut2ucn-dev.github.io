-- Anonymized copy of the database for testing and analysis.
-- Not a migration: it changes nothing in "public". Run it whenever a
-- fresh copy is needed (Supabase → SQL Editor); each run replaces the
-- previous copy.
--
-- What it does:
--   1. (Re)creates schema "anon_copy" and copies every table of "public"
--      into it with all rows. Views (lessons_safe, report_* …) are not
--      copied: they are queries, not data.
--   2. Replaces personal data in the copy:
--        students         name → «Учень 001», phone → fake, parents'
--                         names → «Батьки 001», birthday → same year,
--                         random day; notes and photo cleared
--        profiles         names → «Викладач 01» / «Адмін 01», email →
--                         user01@example.test, photo cleared
--        parent_accounts  phone → fake, name → «Батьки 001»
--        student_comments text → «Коментар 0001»
--        works            photo and printed_by_name cleared/replaced
--        parent_credentials, parent_sessions: copied empty (passwords
--                         and logins are never copied)
--      Safety net: in any table, a column whose name looks personal
--      (phone, email, address, note, comment, photo, avatar, *_name,
--      birth…, token, password, hash, ip, url) and that step 2 didn't
--      already handle is cleared as well.
--   3. Shows a list of every text column left in the copy, so it can be
--      checked by eye before the copy is handed to anyone.
--
-- Ids stay the same, so all links (lesson → students, works → lessons…)
-- still work, and the numbers (prices, payroll, attendance) are real.
-- Logins (auth.users) and Storage files (photos) are NOT copied.
--
-- The copy is not reachable through the website or the apps: the API
-- only serves the "public" schema, and anon/authenticated get no rights
-- on "anon_copy". To take it out of Supabase:
--   pg_dump "<connection string>" --schema=anon_copy --no-owner --no-privileges > stemik_anon.sql
-- (connection string: Project Settings → Database), or Table Editor →
-- schema «anon_copy» → a table → Export to CSV.
-- To remove it: drop schema anon_copy cascade;

begin;

drop schema if exists anon_copy cascade;
create schema anon_copy;

do $$
begin
  revoke all on schema anon_copy from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema anon_copy from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema anon_copy from authenticated';
  end if;
end $$;

-- 1. Copy every base table of "public".
do $$
declare
  t record;
begin
  for t in
    select table_name from information_schema.tables
    where table_schema = 'public' and table_type = 'BASE TABLE'
    order by table_name
  loop
    if t.table_name in ('parent_credentials', 'parent_sessions') then
      execute format('create table anon_copy.%I as select * from public.%I with no data', t.table_name, t.table_name);
    else
      execute format('create table anon_copy.%I as select * from public.%I', t.table_name, t.table_name);
    end if;
  end loop;
end $$;

-- Columns step 2 sets on purpose; the safety net leaves them alone.
create temporary table anon_handled (tbl text, col text) on commit drop;

-- Runs "update anon_copy.<tbl> set <col> = <expr>" if that column exists
-- in the copy (the live schema may differ a little from what's known
-- here). <expr> may use "n": the row's number, ordered by <ord>.
create function pg_temp.anon_set(tbl text, col text, expr text, ord text default 'id') returns void
language plpgsql as $f$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'anon_copy' and table_name = tbl and column_name = col) then
    return;
  end if;
  insert into anon_handled values (tbl, col);
  if exists (select 1 from information_schema.columns
             where table_schema = 'anon_copy' and table_name = tbl and column_name = 'id') then
    execute format(
      'update anon_copy.%1$I c set %2$I = (%3$s) from (select id, row_number() over (order by %4$s) as n from anon_copy.%1$I) r where c.id = r.id',
      tbl, col, expr, ord);
  else
    -- No id to number the rows by: clear the column instead.
    execute format('update anon_copy.%I set %I = null where true', tbl, col);
  end if;
end $f$;

-- Columns used in the "order by" must not be overwritten first, so each
-- table orders by id: stable and not personal.

-- 2a. Students.
select pg_temp.anon_set('students', 'name', $$'Учень ' || lpad(n::text, 3, '0')$$);
select pg_temp.anon_set('students', 'phone', $$'+380 00 000 ' || lpad((n / 100 % 100)::text, 2, '0') || ' ' || lpad((n % 100)::text, 2, '0')$$);
select pg_temp.anon_set('students', 'parent_last_name', $$'Батьки'$$);
select pg_temp.anon_set('students', 'parent_first_name', $$lpad(n::text, 3, '0')$$);
select pg_temp.anon_set('students', 'birthday',
  $$case when c.birthday is null then null
         else make_date(extract(year from c.birthday)::int, 1 + abs(hashtext(c.id::text)) % 12, 1 + abs(hashtext(reverse(c.id::text))) % 28) end$$);
select pg_temp.anon_set('students', 'notes', $$null$$);
select pg_temp.anon_set('students', 'photo', $$null$$);

-- 2b. Staff.
select pg_temp.anon_set('profiles', 'first_name',
  $$case c.role when 'superadmin' then 'Суперадмін' when 'admin' then 'Адмін' else 'Викладач' end$$);
select pg_temp.anon_set('profiles', 'last_name', $$lpad(n::text, 2, '0')$$);
select pg_temp.anon_set('profiles', 'email', $$'user' || lpad(n::text, 2, '0') || '@example.test'$$);
select pg_temp.anon_set('profiles', 'photo', $$null$$);

-- 2c. Parents' portal.
select pg_temp.anon_set('parent_accounts', 'phone', $$'38000' || lpad(n::text, 7, '0')$$);
select pg_temp.anon_set('parent_accounts', 'name', $$'Батьки ' || lpad(n::text, 3, '0')$$);

-- 2d. Free text and photos.
select pg_temp.anon_set('student_comments', 'body', $$'Коментар ' || lpad(n::text, 4, '0')$$);
select pg_temp.anon_set('works', 'photo', $$null$$);
select pg_temp.anon_set('works', 'printed_by_name', $$case when c.printed_by_name is null then null else 'Викладач' end$$);

-- 2e. Safety net for columns not known here.
do $$
declare
  c record;
begin
  for c in
    select col.table_name, col.column_name, col.is_nullable, col.data_type
    from information_schema.columns col
    where col.table_schema = 'anon_copy'
      and col.data_type in ('text', 'character varying', 'character', 'jsonb', 'json', 'ARRAY', 'date', 'inet', 'bytea')
      and col.column_name ~* '(phone|e_?mail|address|passport|note|comment|photo|avatar|(^|_)(first|last|middle|full|parent|by)_?name$|birth|token|password|secret|hash|(^|_)ip($|_)|url)'
      and not exists (select 1 from anon_handled h where h.tbl = col.table_name and h.col = col.column_name)
  loop
    -- The copy has no NOT NULL constraints (CREATE TABLE AS doesn't carry
    -- them), so null is always allowed.
    execute format('update anon_copy.%I set %I = null where true', c.table_name, c.column_name);
    insert into anon_handled values (c.table_name, c.column_name);
    raise notice 'safety net cleared anon_copy.%.%', c.table_name, c.column_name;
  end loop;
end $$;

-- 3. What's left: every text column of the copy, and whether it was
-- anonymized. Look through the "kept" rows before handing the copy on.
create table anon_copy._anonymization_report as
select col.table_name as "таблиця",
       col.column_name as "поле",
       col.data_type as "тип",
       case when h.col is not null then 'знеособлено' else 'залишено як є' end as "стан"
from information_schema.columns col
left join (select distinct tbl, col from anon_handled) h on h.tbl = col.table_name and h.col = col.column_name
where col.table_schema = 'anon_copy'
  and col.table_name <> '_anonymization_report'
  and col.data_type in ('text', 'character varying', 'character', 'jsonb', 'json', 'ARRAY', 'date', 'inet', 'bytea')
order by 4 desc, 1, 2;

do $$
begin
  revoke all on all tables in schema anon_copy from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all tables in schema anon_copy from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on all tables in schema anon_copy from authenticated';
  end if;
end $$;

commit;

select * from anon_copy._anonymization_report;
