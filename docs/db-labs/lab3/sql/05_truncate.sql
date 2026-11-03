-- =====================================================================
-- Лабораторна робота №3. Крок 6: TRUNCATE TABLE і відмінність від DELETE
-- Усі руйнівні команди — у транзакціях з ROLLBACK: у PostgreSQL
-- TRUNCATE транзакційний і його можна відкотити.
-- =====================================================================
\set ON_ERROR_STOP off
\set VERBOSITY terse

\echo '--- 1. DELETE усіх рядків: лічильник IDENTITY продовжує рахунок'
BEGIN;
DELETE FROM tariff;
INSERT INTO tariff (course_id, tariff_type, teacher_pay, lesson_price)
VALUES (1, 'group_1', 250, 450) RETURNING tariff_id;
ROLLBACK;

\echo '--- 2. TRUNCATE без опцій: у PostgreSQL за замовчуванням CONTINUE IDENTITY'
BEGIN;
TRUNCATE TABLE tariff;
INSERT INTO tariff (course_id, tariff_type, teacher_pay, lesson_price)
VALUES (1, 'group_1', 250, 450) RETURNING tariff_id;
ROLLBACK;

\echo '--- 3. TRUNCATE ... RESTART IDENTITY: лічильник починається з 1'
BEGIN;
TRUNCATE TABLE tariff RESTART IDENTITY;
INSERT INTO tariff (course_id, tariff_type, teacher_pay, lesson_price)
VALUES (1, 'group_1', 250, 450) RETURNING tariff_id;
ROLLBACK;
SELECT count(*) AS tariffs_after_rollback FROM tariff;

\echo '--- 4. TRUNCATE таблиці, на яку посилається FK (очікується помилка)'
TRUNCATE TABLE printer;

\echo '--- 5. DELETE тієї самої таблиці працює: FK перевіряється для кожного рядка (SET NULL)'
BEGIN;
DELETE FROM printer;
SELECT count(*) AS works, count(printer_id) AS works_with_printer FROM work;
ROLLBACK;

\echo '--- 6. TRUNCATE ... CASCADE очищає й усі залежні таблиці!'
BEGIN;
TRUNCATE TABLE printer CASCADE;
SELECT (SELECT count(*) FROM printer) AS printers, (SELECT count(*) FROM work) AS works,
       (SELECT count(*) FROM work_cost) AS work_costs;
ROLLBACK;
SELECT (SELECT count(*) FROM printer) AS printers, (SELECT count(*) FROM work) AS works;

\echo '--- 7. Швидкість на 500 000 рядків: DELETE проти TRUNCATE'
CREATE TEMP TABLE bulk_log AS
SELECT g AS id, now() - g * interval '1 second' AS logged_at, md5(g::text) AS payload
FROM generate_series(1, 500000) AS g;
\timing on
DELETE FROM bulk_log;
\timing off
INSERT INTO bulk_log
SELECT g, now() - g * interval '1 second', md5(g::text) FROM generate_series(1, 500000) AS g;
\timing on
TRUNCATE TABLE bulk_log;
\timing off
DROP TABLE bulk_log;
