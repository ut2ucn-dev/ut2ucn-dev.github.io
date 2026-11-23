-- =====================================================================
-- API сайту для розділу «Предметна область»
--
-- Виконується в проєкті Supabase ПІСЛЯ 01_current_db_part1…7.sql
-- (SQL Editor → вставити → Run). Повторний запуск безпечний.
--
-- Сайт не читає таблиці напряму: він викликає одну функцію через
-- REST API Supabase (POST /rest/v1/rpc/site_current_db) з публічним
-- ключем anon. Функція SECURITY DEFINER повертає лише знеособлену
-- статистику схеми та аномалії поточної бази — жодних
-- рядків з даними.
-- =====================================================================

create or replace function public.site_current_db()
returns json
language sql
stable
security definer
set search_path = public
as $$
with tbl as (
    select c.oid, c.relname as name,
           (select count(*) from pg_attribute a
             where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as columns,
           (select count(*) from pg_constraint k where k.conrelid = c.oid and k.contype = 'f') as fks,
           c.relrowsecurity as rls
    from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
      and c.relname not like '\_%'
),
cnt as (
    select t.*,
           (xpath('/row/n/text()',
                  query_to_xml(format('select count(*) as n from public.%I', t.name), false, true, '')))[1]::text::int as rows
    from tbl t
)
select json_build_object(
    'generated_at', now(),
    'tables', (select json_agg(json_build_object('name', name, 'rows', rows, 'columns', columns,
                                                 'fks', fks, 'rls', rls) order by rows desc, name) from cnt),
    'objects', json_build_object(
        'tables',    (select count(*) from cnt),
        'views',     (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'v'),
        'functions', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                                                    and proname not like 'lab\_%'),
        'triggers',  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
                       where not t.tgisinternal and c.relnamespace = 'public'::regnamespace)),
    'foreign_keys', (select json_agg(json_build_object('child', c.relname, 'parent', p.relname,
                                                       'columns', (select string_agg(attname, ', ')
                                                                     from pg_attribute
                                                                    where attrelid = k.conrelid and attnum = any (k.conkey)))
                                     order by p.relname, c.relname)
                     from pg_constraint k
                     join pg_class c on c.oid = k.conrelid
                     join pg_class p on p.oid = k.confrelid
                     where k.contype = 'f' and c.relnamespace = 'public'::regnamespace
                       and p.relnamespace = 'public'::regnamespace),
    'anomalies', json_build_object(
        -- 1НФ: учні заняття — масивом, без зовнішнього ключа
        'student_ids_total',  (select count(*) from lessons, unnest(student_ids)),
        'student_ids_orphan', (select count(*) from lessons l, unnest(l.student_ids) u(id)
                                where not exists (select 1 from students s where s.id = u.id)),
        'attendance_not_in_lesson', (select count(*) from lesson_attendance a join lessons l on l.id = a.lesson_id
                                      where not (a.student_id = any (l.student_ids))),
        -- 3НФ: курс записано текстом у кількох таблицях
        'course_spellings', (select json_agg(json_build_object('course', course, 'rows', n) order by course)
                               from (select course, count(*) as n
                                       from (select course from lessons union all select course from subscriptions) x
                                      where course is not null group by course) y),
        'courses_in_rate_cards', (select count(*) from rate_cards),
        -- 1НФ: повторювана група «формат → ЗП / ціна» у стовпцях rate_cards
        'rate_cards_columns', (select count(*) from information_schema.columns
                                where table_schema = 'public' and table_name = 'rate_cards'),
        -- 3НФ: імена батьків у картці учня, ім'я «хто надрукував» текстом
        'students_with_parent_names', (select count(*) from students where parent_last_name <> ''),
        'works_with_printed_by_name', (select count(*) from works where printed_by_name is not null)
    )
);
$$;

revoke all on function public.site_current_db() from public;
grant execute on function public.site_current_db() to anon, authenticated;
comment on function public.site_current_db() is 'статистика поточної схеми та її аномалії для сайту (лише агрегати)';

notify pgrst, 'reload schema';
