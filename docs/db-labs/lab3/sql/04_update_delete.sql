-- =====================================================================
-- Лабораторна робота №3. Крок 5: оновлення та видалення (UPDATE, DELETE)
-- Правило: спершу SELECT із тією самою умовою WHERE, потім зміна.
-- =====================================================================
\set ON_ERROR_STOP off
\set VERBOSITY terse

\echo '--- 1. UPDATE ... FROM: перерахувати залишок абонементів за відвідуваннями'
\echo '    (спершу SELECT — що саме зміниться)'
SELECT s.first_name AS student, c.name AS course, sb.total_lessons,
       count(a.attendance_id) AS used
FROM subscription AS sb
JOIN student AS s ON s.student_id = sb.student_id
JOIN course  AS c ON c.course_id  = sb.course_id
LEFT JOIN attendance AS a ON a.subscription_id = sb.subscription_id
GROUP BY s.first_name, c.name, sb.total_lessons
ORDER BY used DESC, student;

UPDATE subscription AS sb
SET remaining_lessons = sb.total_lessons - u.used,
    status = CASE WHEN sb.total_lessons - u.used = 0 THEN 'completed' ELSE 'active' END
FROM (SELECT subscription_id, count(*) AS used
      FROM attendance
      WHERE subscription_id IS NOT NULL
      GROUP BY subscription_id) AS u
WHERE u.subscription_id = sb.subscription_id;

\echo '--- 2. UPDATE з умовою і RETURNING: +10 % до ціни групових 3D-занять'
SELECT c.name, t.tariff_type, t.lesson_price
FROM tariff t JOIN course c USING (course_id)
WHERE c.direction = '3D' AND t.tariff_type = 'group_2_6';

UPDATE tariff AS t
SET lesson_price = round(t.lesson_price * 1.10, 2)
FROM course AS c
WHERE c.course_id = t.course_id
  AND c.direction = '3D'
  AND t.tariff_type = 'group_2_6'
RETURNING c.name, t.tariff_type, t.lesson_price AS new_price;

\echo '--- 3. UPDATE: борг погашено — заняття 27.10 оплачене готівкою'
UPDATE attendance AS a
SET payment_method = 'cash', amount = l.price_amount
FROM lesson AS l, student AS s
WHERE l.lesson_id = a.lesson_id AND s.student_id = a.student_id
  AND a.status = 'present' AND a.payment_method IS NULL
RETURNING s.first_name, l.lesson_date, a.payment_method, a.amount;

\echo '--- 4. DELETE з умовою: коментар про борг більше не актуальний'
SELECT left(body, 50) AS body FROM student_comment WHERE body LIKE '%оплатити%';
DELETE FROM student_comment WHERE body LIKE '%оплатити%';

\echo '--- 5. DELETE ... RETURNING: завершити сесії, неактивні з 31.10'
DELETE FROM parent_session
WHERE last_seen_at < TIMESTAMPTZ '2026-10-31 00:00+02'
RETURNING client, last_seen_at::date AS last_seen;

\echo '--- 6. DELETE батьківського рядка, на який посилаються (RESTRICT, очікується помилка)'
DELETE FROM student WHERE first_name = 'Артем';

\echo '--- 7. DELETE з каскадом (у транзакції з відкатом): кабінет батьків Ковальчука'
BEGIN;
SELECT (SELECT count(*) FROM parent) AS parents, (SELECT count(*) FROM parent_student) AS links;
DELETE FROM parent WHERE last_name = 'Ковальчук';
SELECT (SELECT count(*) FROM parent) AS parents, (SELECT count(*) FROM parent_student) AS links;
ROLLBACK;

\echo '--- 8. Небезпека UPDATE без WHERE: змінено ВСІ рядки (відкат)'
BEGIN;
UPDATE lesson SET room = 'Клас AI';
SELECT room, count(*) FROM lesson GROUP BY room;
ROLLBACK;
SELECT room, count(*) FROM lesson GROUP BY room ORDER BY 2 DESC;
