-- =====================================================================
-- Лабораторна робота №3. Крок 8: масове генерування тестових даних
-- Аналоги прийомів із методичних вказівок (MS SQL Server) у PostgreSQL:
--   WHILE з лічильником       → цикл WHILE у блоці DO (PL/pgSQL)
--   CROSS JOIN sys.objects    → функція generate_series()
--   рекурсивний CTE           → WITH RECURSIVE (без MAXRECURSION)
--   ORDER BY NEWID()          → random(); розподіл — залишок від ділення %
-- Усе виконується в транзакції з ROLLBACK: база лишається з даними кроку 3.
-- =====================================================================
\set ON_ERROR_STOP off
\set VERBOSITY terse

BEGIN;

\echo '--- 1. Цикл WHILE у блоці DO: 100 тестових учнів по одному INSERT'
DO $$
DECLARE
    i INT := 1;
BEGIN
    WHILE i <= 100 LOOP
        INSERT INTO student (last_name, first_name, birthday, phone)
        VALUES ('Тестовий' || i,
                'Учень' || i,
                DATE '2013-01-01' + (i * 37 % 2190),           -- 2013–2018 рр.
                '+38050' || lpad(i::text, 7, '0'));
        i := i + 1;
    END LOOP;
END $$;
SELECT count(*) AS students FROM student;

\echo '--- 2. generate_series: 1000 батьківських кабінетів одним INSERT ... SELECT'
INSERT INTO parent (phone, last_name, first_name)
SELECT '38067' || lpad(seq::text, 7, '0'),
       'Батько' || seq,
       (ARRAY['Олена', 'Андрій', 'Наталія', 'Сергій', 'Ірина'])[seq % 5 + 1]
FROM generate_series(1, 1000) AS seq;
SELECT count(*) AS generated, count(DISTINCT first_name) AS distinct_names,
       min(phone), max(phone)
FROM parent WHERE last_name LIKE 'Батько%';

\echo '--- 3. WITH RECURSIVE: щотижнева серія занять до кінця навчального року'
WITH RECURSIVE week (n, d) AS (
    SELECT 1, DATE '2026-11-09'
    UNION ALL
    SELECT n + 1, d + 7 FROM week WHERE d + 7 <= DATE '2027-05-31'
),
series AS (SELECT gen_random_uuid() AS id)
INSERT INTO lesson (course_id, teacher_id, series_id, lesson_date, start_time, format, room, theme)
SELECT c.course_id, e.employee_id, series.id, week.d, TIME '16:00', 'group', 'Клас 3D',
       'Тема ' || week.n
FROM week, series,
     course   AS c,
     employee AS e
WHERE c.name = '3D Tinkercad FIRST (9-12)' AND e.email = 'shevchuk@stemik.test';
SELECT count(*) AS lessons_in_series, min(lesson_date), max(lesson_date)
FROM lesson WHERE theme LIKE 'Тема %';

\echo '--- 4. Випадковий вибір і залишок від ділення: розклад на 200 занять'
INSERT INTO lesson (course_id, teacher_id, lesson_date, start_time, format, room, theme)
SELECT (seq % 9) + 1,                                              -- курси 1..9 по колу
       (SELECT employee_id FROM employee
        WHERE role = 'teacher' AND active AND seq > 0               -- seq > 0: підзапит
        ORDER BY random() LIMIT 1),                                 --   для кожного рядка
       DATE '2026-12-01' + (seq % 120),
       TIME '14:00' + (seq % 5) * interval '1 hour',
       'group',
       (ARRAY['Клас AI', 'Клас VR', 'Комп''ютерний клас', 'Клас 3D'])[seq % 4 + 1],
       'Згенероване заняття ' || seq
FROM generate_series(1, 200) AS seq;
SELECT room, count(*) AS lessons, count(DISTINCT teacher_id) AS teachers
FROM lesson WHERE theme LIKE 'Згенероване%'
GROUP BY room ORDER BY room;

ROLLBACK;
SELECT (SELECT count(*) FROM student) AS students, (SELECT count(*) FROM parent) AS parents,
       (SELECT count(*) FROM lesson) AS lessons;

\echo '--- 5. Швидкість: 20 000 рядків циклом WHILE і одним INSERT ... SELECT'
CREATE TEMP TABLE gen_test (n INT, label TEXT);
\timing on
DO $$
DECLARE i INT := 1;
BEGIN
    WHILE i <= 20000 LOOP
        INSERT INTO gen_test VALUES (i, 'row ' || i);
        i := i + 1;
    END LOOP;
END $$;
\timing off
TRUNCATE gen_test;
\timing on
INSERT INTO gen_test SELECT g, 'row ' || g FROM generate_series(1, 20000) AS g;
\timing off
DROP TABLE gen_test;
