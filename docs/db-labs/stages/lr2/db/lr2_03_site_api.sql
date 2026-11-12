-- =====================================================================
-- Етап ЛР № 2. API для версії сайту «Модель даних у СУБД»
--
-- Виконується в навчальному проєкті Supabase ПІСЛЯ lr2_01_schema.sql і
-- lr2_02_seed.sql. Повторний запуск безпечний.
--
-- lab_lr2_model()            — каталог фізичної моделі (схема stemik):
--                              таблиці, стовпці, ключі, FK з каскадними
--                              діями, CHECK-обмеження, відповідність
--                              поточній схемі.
-- lab_lr2_constraint_tests() — 10 перевірок обмежень цілісності. Кожна
--                              виконується у власному підблоці, і всі
--                              зміни відкочуються: дані не змінюються.
-- =====================================================================

create or replace function public.lab_lr2_model()
returns json
language sql
stable
security definer
set search_path = stemik, public
as $$
select json_build_object(
  'generated_at', now(),
  'counts', json_build_object(
      'tables', (select count(*) from pg_class where relnamespace = 'stemik'::regnamespace and relkind = 'r'),
      'pk',     (select count(*) from pg_constraint where connamespace = 'stemik'::regnamespace and contype = 'p'),
      'fk',     (select count(*) from pg_constraint where connamespace = 'stemik'::regnamespace and contype = 'f'),
      'unique', (select count(*) from pg_constraint where connamespace = 'stemik'::regnamespace and contype = 'u'),
      'check',  (select count(*) from pg_constraint where connamespace = 'stemik'::regnamespace and contype = 'c'),
      'rows',   (select sum((xpath('/row/n/text()', query_to_xml(format('select count(*) as n from stemik.%I', relname),
                                                             false, true, '')))[1]::text::int)
                   from pg_class where relnamespace = 'stemik'::regnamespace and relkind = 'r')),
  'tables', (
    select json_agg(json_build_object(
             'name', c.relname,
             'comment', obj_description(c.oid, 'pg_class'),
             'rows', (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from stemik.%I', c.relname),
                                                         false, true, '')))[1]::text::int,
             'columns', (select json_agg(json_build_object(
                                  'name', a.attname,
                                  'type', format_type(a.atttypid, a.atttypmod),
                                  'not_null', a.attnotnull,
                                  'default', pg_get_expr(d.adbin, d.adrelid),
                                  'keys', (select string_agg(case k.contype when 'p' then 'PK' when 'f' then 'FK' else 'UK' end, ','
                                                             order by k.contype desc)
                                             from pg_constraint k
                                            where k.conrelid = c.oid and k.contype in ('p', 'f', 'u')
                                              and a.attnum = any (k.conkey)))
                                order by a.attnum)
                           from pg_attribute a
                           left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
                          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped))
           order by c.relname)
    from pg_class c
    where c.relnamespace = 'stemik'::regnamespace and c.relkind = 'r'),
  'foreign_keys', (
    select json_agg(json_build_object(
             'name', k.conname, 'child', c.relname, 'parent', p.relname,
             'columns', (select string_agg(attname, ', ') from pg_attribute
                          where attrelid = k.conrelid and attnum = any (k.conkey)),
             'on_delete', case k.confdeltype when 'c' then 'CASCADE' when 'r' then 'RESTRICT'
                                             when 'n' then 'SET NULL' else 'NO ACTION' end,
             'on_update', case k.confupdtype when 'c' then 'CASCADE' else 'NO ACTION' end)
           order by c.relname, k.conname)
    from pg_constraint k
    join pg_class c on c.oid = k.conrelid
    join pg_class p on p.oid = k.confrelid
    where k.connamespace = 'stemik'::regnamespace and k.contype = 'f'),
  'checks', (
    select json_agg(json_build_object('table', c.relname, 'name', k.conname,
                                      'definition', regexp_replace(pg_get_constraintdef(k.oid),
                                                    '::(character varying|text|numeric)(\[\])?', '', 'g'))
           order by c.relname, k.conname)
    from pg_constraint k join pg_class c on c.oid = k.conrelid
    where k.connamespace = 'stemik'::regnamespace and k.contype = 'c'),
  -- Відповідність таблиць поточної схеми (Supabase) і моделі (схема stemik)
  'mapping', '[
    {"current":"profiles","model":"employee","change":"email NOT NULL UNIQUE, CHECK на role"},
    {"current":"— (текст course)","model":"course","change":"новий довідник замість 11 написань курсу"},
    {"current":"rate_cards (35 стовпців)","model":"tariff","change":"рядок на пару курс × формат; 16 застарілих стовпців зникли"},
    {"current":"students","model":"student","change":"name → last_name + first_name; імена батьків → parent; active"},
    {"current":"parent_accounts","model":"parent","change":"name → last_name + first_name; пароль → parent_credential"},
    {"current":"parent_credentials","model":"parent_credential","change":"1:1 з parent, без змін за змістом"},
    {"current":"parent_sessions","model":"parent_session","change":"token_hash CHAR(64), CHECK терміну дії"},
    {"current":"parent_students","model":"parent_student","change":"додано relation"},
    {"current":"lessons","model":"lesson","change":"course_id FK; owner_id → teacher_id; без масиву учнів"},
    {"current":"— (масив lessons.student_ids)","model":"lesson_student","change":"асоціативна таблиця M:N із FK на учня"},
    {"current":"lesson_attendance","model":"attendance","change":"складений FK на lesson_student; без owner_id; CHECK оплати"},
    {"current":"subscriptions","model":"subscription","change":"course_id FK; RESTRICT замість CASCADE; CHECK залишку"},
    {"current":"works","model":"work","change":"складений FK; printed_by_name → FK printed_by; без owner_id"},
    {"current":"work_costs","model":"work_cost","change":"без weight_g, print_minutes, total_cost"},
    {"current":"printers, filaments","model":"printer, filament","change":"SMALLINT IDENTITY; UNIQUE назви / (матеріал, колір)"},
    {"current":"student_comments","model":"student_comment","change":"CHECK непорожнього тексту"},
    {"current":"studio_settings","model":"studio_settings","change":"один рядок: PK BOOLEAN + CHECK (id)"}
  ]'::json
);
$$;

create or replace function public.lab_lr2_constraint_tests()
returns table (no int, test text, expected text, result text, ok boolean)
language plpgsql
volatile
security definer
set search_path = stemik, public
as $$
declare
    v_con text;
    v_msg text;
    b1 int; b2 int; b3 int; a1 int; a2 int; a3 int;
    v_lesson uuid; v_student uuid; v_printer smallint;
    v_active boolean; v_created date;

    -- Виконати оператор, який ПОВИНЕН завершитися помилкою; зміни відкотити.
    -- Повертає назву порушеного обмеження або текст «помилки не було».
begin
    -- 1–7: оператори, що мають бути відхилені -------------------------------
    for no, test, expected, v_msg in
        select * from (values
          (1, 'CHECK: від’ємна ціна в тарифі', 'відхилено',
              'update stemik.tariff set lesson_price = -100 where tariff_id = (select min(tariff_id) from stemik.tariff)'),
          (2, 'CHECK: недопустимий формат заняття', 'відхилено',
              'update stemik.lesson set format = ''webinar'' where lesson_id = (select lesson_id from stemik.lesson limit 1)'),
          (3, 'UNIQUE: другий кабінет батьків з тим самим телефоном', 'відхилено',
              'insert into stemik.parent (phone) select phone from stemik.parent limit 1'),
          (4, 'CHECK: оплата за відсутнього учня', 'відхилено',
              'update stemik.attendance set payment_method = ''cash'', amount = 400 where attendance_id = (select attendance_id from stemik.attendance where status <> ''present'' limit 1)'),
          (5, 'FK: відмітка учня, не записаного на заняття', 'відхилено',
              'insert into stemik.attendance (lesson_id, student_id, status) select l.lesson_id, s.student_id, ''present'' from stemik.lesson l cross join stemik.student s where not exists (select 1 from stemik.lesson_student ls where ls.lesson_id = l.lesson_id and ls.student_id = s.student_id) limit 1'),
          (6, 'RESTRICT: видалення курсу, за яким є заняття', 'відхилено',
              'delete from stemik.course where course_id = (select course_id from stemik.lesson limit 1)'),
          (7, 'RESTRICT: видалення учня з історією занять', 'відхилено',
              'delete from stemik.student where student_id = (select student_id from stemik.lesson_student limit 1)')
        ) t (no, test, expected, sql)
    loop
        begin
            execute v_msg;
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

    -- 8: CASCADE — видалення заняття забирає записи, відмітки й роботи -------
    no := 8; test := 'ON DELETE CASCADE: видалення заняття'; expected := 'залежні рядки видалено';
    select w.lesson_id into v_lesson from stemik.work w group by w.lesson_id order by count(*) desc limit 1;
    begin
        select count(*) into b1 from stemik.lesson_student where lesson_id = v_lesson;
        select count(*) into b2 from stemik.attendance where lesson_id = v_lesson;
        select count(*) into b3 from stemik.work where lesson_id = v_lesson;
        delete from stemik.lesson where lesson_id = v_lesson;
        select count(*) into a1 from stemik.lesson_student where lesson_id = v_lesson;
        select count(*) into a2 from stemik.attendance where lesson_id = v_lesson;
        select count(*) into a3 from stemik.work where lesson_id = v_lesson;
        raise exception 'LAB_ROLLBACK';
    exception when others then
        null;
    end;
    result := format('записи %s→%s, відмітки %s→%s, роботи %s→%s (відкочено)', b1, a1, b2, a2, b3, a3);
    ok := a1 = 0 and a2 = 0 and a3 = 0 and b1 > 0;
    return next;

    -- 9: SET NULL — видалення принтера залишає роботи без принтера -----------
    no := 9; test := 'ON DELETE SET NULL: видалення принтера'; expected := 'роботи лишились, printer_id = NULL';
    select printer_id into v_printer from stemik.work where printer_id is not null limit 1;
    begin
        select count(*) into b1 from stemik.work where printer_id = v_printer;
        select count(*) into b2 from stemik.work;
        delete from stemik.printer where printer_id = v_printer;
        select count(*) into a1 from stemik.work where printer_id = v_printer;
        select count(*) into a2 from stemik.work;
        raise exception 'LAB_ROLLBACK';
    exception when others then
        null;
    end;
    result := format('роботи з принтером %s→%s, усього робіт %s→%s (відкочено)', b1, a1, b2, a2);
    ok := a1 = 0 and a2 = b2 and b1 > 0;
    return next;

    -- 10: DEFAULT — новий учень отримує active і дату створення -------------
    no := 10; test := 'DEFAULT: новий учень без active і created_at'; expected := 'active = true, дата — сьогодні';
    begin
        insert into stemik.student (last_name, first_name) values ('Тестовий', 'Учень')
        returning active, created_at::date into v_active, v_created;
        raise exception 'LAB_ROLLBACK';
    exception when others then
        null;
    end;
    result := format('active = %s, created_at = %s (відкочено)', v_active, v_created);
    ok := v_active and v_created = current_date;
    return next;
end;
$$;

revoke all on function public.lab_lr2_model() from public;
revoke all on function public.lab_lr2_constraint_tests() from public;
grant execute on function public.lab_lr2_model() to anon, authenticated;
grant execute on function public.lab_lr2_constraint_tests() to anon, authenticated;
comment on function public.lab_lr2_model() is 'ЛР2: каталог фізичної моделі (схема stemik) для сайту';
comment on function public.lab_lr2_constraint_tests() is 'ЛР2: перевірка обмежень цілісності з відкатом усіх змін';

notify pgrst, 'reload schema';
