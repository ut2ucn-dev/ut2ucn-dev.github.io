-- =====================================================================
-- Перевірка обмежень цілісності та каскадних дій (ЛР №2)
-- Кожна команда, що порушує правило, має завершитися помилкою.
-- Запуск: psql -d stemik -f 03_constraint_tests.sql
-- =====================================================================
SET search_path TO stemik;
\set ON_ERROR_STOP off
\set VERBOSITY terse

\echo '--- 1. CHECK: від''ємна ціна у тарифі'
UPDATE tariff SET lesson_price = -100 WHERE tariff_id = 1;

\echo '--- 2. CHECK: недопустимий формат заняття'
UPDATE lesson SET format = 'webinar' WHERE lesson_date = '2026-10-19';

\echo '--- 3. UNIQUE: два батьківські кабінети з одним телефоном'
INSERT INTO parent (phone) VALUES ('380501112233');

\echo '--- 4. CHECK: оплата за відсутнього учня'
UPDATE attendance SET payment_method = 'cash', amount = 400
WHERE status = 'absent';

\echo '--- 5. FK: відвідування учня, не записаного на заняття'
INSERT INTO attendance (lesson_id, student_id, status)
SELECT l.lesson_id, s.student_id, 'present'
FROM lesson l, student s
WHERE l.lesson_date = '2026-10-21' AND s.first_name = 'Вероніка';

\echo '--- 6. ON DELETE RESTRICT: видалення курсу, за яким є заняття й абонементи'
DELETE FROM course WHERE name = 'Robo AI (Ukit 6-8)';

\echo '--- 7. ON DELETE RESTRICT: видалення учня з історією занять'
DELETE FROM student WHERE first_name = 'Артем';

\echo '--- 8. ON DELETE CASCADE: видалення заняття видаляє запис, відвідування і роботи'
BEGIN;
SELECT (SELECT count(*) FROM lesson_student) AS lesson_student,
       (SELECT count(*) FROM attendance)     AS attendance,
       (SELECT count(*) FROM work)           AS work;
DELETE FROM lesson WHERE lesson_date = '2026-10-19';
SELECT (SELECT count(*) FROM lesson_student) AS lesson_student,
       (SELECT count(*) FROM attendance)     AS attendance,
       (SELECT count(*) FROM work)           AS work;
ROLLBACK;

\echo '--- 9. ON DELETE SET NULL: видалення принтера зберігає роботу, але без принтера'
BEGIN;
DELETE FROM printer WHERE name = 'Creality K1';
SELECT left(work_id::text, 8) AS work, printed, printer_id, weight_g FROM work WHERE printed;
ROLLBACK;

\echo '--- 10. DEFAULT: новий учень отримує active = true і дату створення'
BEGIN;
INSERT INTO student (last_name, first_name) VALUES ('Тестовий', 'Учень')
RETURNING last_name, first_name, active, created_at::date;
ROLLBACK;
