-- =====================================================================
-- Етап ЛР № 3. API для версії сайту «Таблиці й дані»
--
-- Виконується після lr3_01_create_tables.sql і lr3_02_migrate.sql.
--   lab_lr3_overview()         — звіт перенесення даних з поточної схеми
--                                в модель та кількість іменованих обмежень;
--   lab_lr3_browse(table, n)   — перші n рядків таблиці моделі (лише з
--                                переліку дозволених; без паролів і сесій);
--   lab_lr3_demos()            — 14 демонстрацій ALTER / UPDATE / DELETE /
--                                TRUNCATE / DROP. Кожна — у власному
--                                підблоці з відкатом: дані й структура
--                                після виклику не змінюються.
-- =====================================================================

create or replace function public.lab_lr3_overview()
returns json
language sql
stable
security definer
set search_path = stemik, public
as $$
select json_build_object(
  'generated_at', now(),
  'constraints', (select json_build_object(
        'pk', count(*) filter (where contype = 'p'), 'fk', count(*) filter (where contype = 'f'),
        'unique', count(*) filter (where contype = 'u'), 'check', count(*) filter (where contype = 'c'),
        'named', count(*) filter (where conname ~ '^(pk|fk|uq|chk)_'), 'total', count(*))
      from pg_constraint where connamespace = 'stemik'::regnamespace),
  'migration', (select json_agg(json_build_object('source', source, 'src', src, 'target', target, 'dst', dst, 'note', note) order by n)
    from (values
      (1,  'profiles',                (select count(*) from public.profiles),          'employee',        (select count(*) from stemik.employee),        ''),
      (2,  'назви курсів (різні)',    (select count(*) from (select course from public.lessons union select course from public.subscriptions) x where course is not null),
                                                                                       'course',          (select count(*) from stemik.course),          'написання зведено до 9 курсів'),
      (3,  'rate_cards',              (select count(*) from public.rate_cards),        'tariff',          (select count(*) from stemik.tariff),          '9 курсів × 6 типів тарифу'),
      (4,  'students',                (select count(*) from public.students),          'student',         (select count(*) from stemik.student),         'ПІБ розділено на два поля'),
      (5,  'parent_accounts',         (select count(*) from public.parent_accounts),   'parent',          (select count(*) from stemik.parent),          '+ батьки з карток учнів'),
      (6,  'parent_students',         (select count(*) from public.parent_students),   'parent_student',  (select count(*) from stemik.parent_student),  '+ зв’язки з карток учнів'),
      (7,  'lessons',                 (select count(*) from public.lessons),           'lesson',          (select count(*) from stemik.lesson),          ''),
      (8,  'lessons.student_ids (id)',(select count(*) from public.lessons, unnest(student_ids)),
                                                                                       'lesson_student',  (select count(*) from stemik.lesson_student),  'без неіснуючих учнів, + учні з відміток і робіт'),
      (9,  'lesson_attendance',       (select count(*) from public.lesson_attendance), 'attendance',      (select count(*) from stemik.attendance),      ''),
      (10, 'subscriptions',           (select count(*) from public.subscriptions),     'subscription',    (select count(*) from stemik.subscription),    'залишок обрізано до пакета'),
      (11, 'works',                   (select count(*) from public.works),             'work',            (select count(*) from stemik.work),            'дублікати об’єднано'),
      (12, 'printers / filaments',    (select count(*) from public.printers) + (select count(*) from public.filaments),
                                                                                       'printer / filament', (select count(*) from stemik.printer) + (select count(*) from stemik.filament), ''),
      (13, 'student_comments',        (select count(*) from public.student_comments),  'student_comment', (select count(*) from stemik.student_comment), ''),
      (14, 'studio_settings',         (select count(*) from public.studio_settings),   'studio_settings', (select count(*) from stemik.studio_settings), '')
    ) as x (n, source, src, target, dst, note)),
  'cleaning', json_build_object(
      'orphan_ids', (select count(*) from public.lessons l, unnest(l.student_ids) u(id)
                      where not exists (select 1 from public.students s where s.id = u.id)),
      'course_spellings', (select count(*) from (select course from public.lessons union select course from public.subscriptions) x where course is not null),
      'subscriptions_capped', (select count(*) from public.subscriptions where remaining_lessons > total_lessons),
      'work_duplicates', (select count(*) - count(distinct (lesson_id, student_id)) from public.works),
      'parents_from_cards', (select count(*) from stemik.parent p where not exists (select 1 from public.parent_accounts a where a.id = p.parent_id))),
  'tables', (select json_agg(t order by t) from unnest(array['employee','course','tariff','student','parent','parent_student',
              'lesson','lesson_student','attendance','subscription','work','printer','filament','student_comment','studio_settings']) t)
);
$$;

create or replace function public.lab_lr3_browse(p_table text, p_limit int default 20)
returns json
language plpgsql
stable
security definer
set search_path = stemik, public
as $$
declare
    v_rows json;
    v_total int;
begin
    if p_table not in ('employee','course','tariff','student','parent','parent_student','lesson','lesson_student',
                       'attendance','subscription','work','printer','filament','student_comment','studio_settings') then
        raise exception 'Таблиця % недоступна для перегляду', p_table;
    end if;
    execute format('select count(*) from stemik.%I', p_table) into v_total;
    execute format('select coalesce(json_agg(t), ''[]'') from (select * from stemik.%I limit %s) t',
                   p_table, least(greatest(coalesce(p_limit, 20), 1), 100)) into v_rows;
    return json_build_object('table', p_table, 'total', v_total, 'rows', v_rows);
end;
$$;

create or replace function public.lab_lr3_demos()
returns table (no int, category text, step text, result text, ok boolean)
language plpgsql
volatile
security definer
set search_path = stemik, public
as $$
declare
    v_con text; a1 int; a2 int; b1 int; b2 int; v_id int;
begin
    -- Оператори, що мають завершитися помилкою -------------------------------
    for no, category, step, result in
        select * from (values
          (2,  'ALTER',    'ADD COLUMN NOT NULL без DEFAULT до заповненої таблиці',
               'alter table stemik.employee add column contract_date date not null'),
          (3,  'ALTER',    'звуження типу: course.name VARCHAR(60) → VARCHAR(10)',
               'alter table stemik.course alter column name type varchar(10)'),
          (4,  'ALTER',    'ADD CONSTRAINT, яке порушують наявні дані (notes IS NOT NULL)',
               'alter table stemik.student add constraint chk_student_has_notes check (notes is not null)'),
          (7,  'DELETE',   'учень з абонементом (ON DELETE RESTRICT)',
               'delete from stemik.student where student_id = (select student_id from stemik.subscription limit 1)'),
          (10, 'TRUNCATE', 'таблиця, на яку посилається FK (printer)',
               'truncate table stemik.printer'),
          (12, 'DROP',     'батьківська таблиця course, на яку посилаються FK',
               'drop table stemik.course')
        ) t (no, category, step, sql)
    loop
        begin
            execute result;
            raise exception 'LAB_NO_ERROR';
        exception when others then
            get stacked diagnostics v_con = constraint_name;
            if sqlerrm = 'LAB_NO_ERROR' then
                result := 'помилки не було'; ok := false;
            else
                result := 'відхилено: ' || coalesce(nullif(v_con, ''), sqlerrm); ok := true;
            end if;
        end;
        return next;
    end loop;

    -- 1. ADD COLUMN без DEFAULT
    no := 1; category := 'ALTER'; step := 'ADD COLUMN student.school: наявні рядки отримують NULL';
    begin
        alter table stemik.student add column school varchar(100);
        execute 'select count(*), count(school) from stemik.student' into a1, a2;
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    result := format('рядків %s, із заповненим school %s (відкочено)', a1, a2); ok := a2 = 0 and a1 > 0;
    return next;

    -- 5. UPDATE з умовою
    no := 5; category := 'UPDATE'; step := '+10 % до ціни групових занять 3D-курсів';
    begin
        update stemik.tariff t set lesson_price = round(t.lesson_price * 1.10, 2)
          from stemik.course c
         where c.course_id = t.course_id and c.direction = '3D' and t.tariff_type = 'group_2_6';
        get diagnostics a1 = row_count;
        select count(*) into a2 from stemik.tariff;
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    result := format('змінено %s рядків із %s (відкочено)', a1, a2); ok := a1 between 1 and a2 - 1;
    return next;

    -- 6. DELETE з умовою і каскадом
    no := 6; category := 'DELETE'; step := 'скасувати решту найбільшої серії після 31.03.2027';
    begin
        select count(*) into b1 from stemik.lesson_student;
        delete from stemik.lesson
         where series_id = (select series_id from stemik.lesson where series_id is not null
                             group by series_id order by count(*) desc limit 1)
           and lesson_date > date '2027-03-31' and not completed;
        get diagnostics a1 = row_count;
        select count(*) into b2 from stemik.lesson_student;
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    result := format('видалено занять %s; записів учнів %s → %s каскадно (відкочено)', a1, b1, b2); ok := a1 > 0 and b2 < b1;
    return next;

    -- 8. UPDATE без WHERE
    no := 8; category := 'UPDATE'; step := 'UPDATE без WHERE: кабінет у всіх заняттях';
    begin
        update stemik.lesson set room = 'Клас AI';
        get diagnostics a1 = row_count;
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    select count(*) into a2 from stemik.lesson;
    result := format('змінено %s рядків — усю таблицю (відкочено)', a1); ok := a1 = a2;
    return next;

    -- 9. DELETE і TRUNCATE: лічильник IDENTITY
    no := 9; category := 'TRUNCATE'; step := 'лічильник IDENTITY після DELETE і після TRUNCATE … RESTART IDENTITY';
    begin
        delete from stemik.tariff;
        insert into stemik.tariff (course_id, tariff_type) values ((select min(course_id) from stemik.course), 'group_1')
        returning tariff_id into a1;
        truncate table stemik.tariff restart identity;
        insert into stemik.tariff (course_id, tariff_type) values ((select min(course_id) from stemik.course), 'group_1')
        returning tariff_id into a2;
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    result := format('після DELETE новий id = %s, після RESTART IDENTITY — %s (відкочено)', a1, a2); ok := a1 > 1 and a2 = 1;
    return next;

    -- 11. TRUNCATE … CASCADE
    no := 11; category := 'TRUNCATE'; step := 'TRUNCATE printer CASCADE очищає й залежні таблиці';
    begin
        select count(*) into b1 from stemik.work;
        truncate table stemik.printer cascade;
        select count(*) into b2 from stemik.work;
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    result := format('робіт %s → %s (відкочено)', b1, b2); ok := b2 = 0 and b1 > 0;
    return next;

    -- 13. DROP … CASCADE
    no := 13; category := 'DROP'; step := 'DROP TABLE course CASCADE: видаляються FK, а не дочірні таблиці';
    begin
        select count(*) into b1 from pg_constraint where connamespace = 'stemik'::regnamespace and contype = 'f';
        drop table stemik.course cascade;
        select count(*) into b2 from pg_constraint where connamespace = 'stemik'::regnamespace and contype = 'f';
        select count(*) into a1 from pg_tables where schemaname = 'stemik';
        select count(*) into a2 from stemik.lesson;
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    result := format('FK %s → %s, таблиць лишилось %s, занять %s (відкочено)', b1, b2, a1, a2); ok := b2 = b1 - 3 and a2 > 0;
    return next;

    -- 14. DROP «листової» таблиці
    no := 14; category := 'DROP'; step := 'DROP TABLE student_comment — на неї ніщо не посилається';
    begin
        drop table stemik.student_comment;
        select count(*) into a1 from pg_tables where schemaname = 'stemik';
        raise exception 'LAB_ROLLBACK';
    exception when others then null;
    end;
    select count(*) into a2 from pg_tables where schemaname = 'stemik';
    result := format('таблиць %s → %s, після відкату знову %s', a2, a1, a2); ok := a1 = a2 - 1;
    return next;
end;
$$;

revoke all on function public.lab_lr3_overview() from public;
revoke all on function public.lab_lr3_browse(text, int) from public;
revoke all on function public.lab_lr3_demos() from public;
grant execute on function public.lab_lr3_overview() to anon, authenticated;
grant execute on function public.lab_lr3_browse(text, int) to anon, authenticated;
grant execute on function public.lab_lr3_demos() to anon, authenticated;
comment on function public.lab_lr3_overview() is 'ЛР3: звіт перенесення даних і обмеження моделі';
comment on function public.lab_lr3_browse(text, int) is 'ЛР3: перегляд рядків таблиці моделі (дозволений перелік)';
comment on function public.lab_lr3_demos() is 'ЛР3: демонстрації ALTER/UPDATE/DELETE/TRUNCATE/DROP з відкатом';

notify pgrst, 'reload schema';
