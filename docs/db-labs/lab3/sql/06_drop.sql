-- =====================================================================
-- Лабораторна робота №3. Крок 7: видалення таблиць (DROP TABLE)
-- DDL у PostgreSQL транзакційний, тому кожен сценарій виконано в
-- транзакції та відкочено — база лишається цілою для ЛР №4.
-- =====================================================================
\set ON_ERROR_STOP off
\set VERBOSITY default

\echo '--- 1. DROP батьківської таблиці, на яку посилаються FK (очікується помилка)'
DROP TABLE course;

\echo '--- 2. Які зовнішні ключі тримають course'
SELECT conrelid::regclass AS child_table, conname AS constraint_name
FROM pg_constraint
WHERE confrelid = 'course'::regclass
ORDER BY 1;

\set VERBOSITY terse
\echo '--- 3. Правильний порядок — від дочірніх до батьківських (зворотний до створення)'
BEGIN;
DROP TABLE work_cost;
DROP TABLE attendance, work;
DROP TABLE lesson_student;
DROP TABLE tariff, subscription, lesson;
DROP TABLE course;
SELECT count(*) AS tables_left FROM pg_tables WHERE schemaname = 'public';
ROLLBACK;

\echo '--- 4. DROP ... CASCADE видаляє не дочірні таблиці, а їхні FK'
BEGIN;
DROP TABLE course CASCADE;
SELECT count(*) AS tables_left FROM pg_tables WHERE schemaname = 'public';
SELECT count(*) AS lessons_still_here FROM lesson;
SELECT count(*) AS fk_to_course FROM pg_constraint WHERE conname LIKE 'fk_%_course';
ROLLBACK;

\echo '--- 5. DROP «листової» таблиці, на яку ніхто не посилається'
BEGIN;
DROP TABLE student_comment;
DROP TABLE IF EXISTS student_comment;
ROLLBACK;
SELECT count(*) AS tables_after_rollback FROM pg_tables WHERE schemaname = 'public';
