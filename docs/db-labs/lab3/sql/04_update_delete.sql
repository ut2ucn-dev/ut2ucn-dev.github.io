-- =====================================================================
-- Лабораторна робота №3. Крок 5: оновлення та видалення (UPDATE, DELETE)
-- Правило: спершу SELECT із тією самою умовою WHERE, потім зміна.
-- Усе виконується в одній транзакції, яку в кінці відкочено: ЛР4 має
-- працювати на даних, перенесених з робочої бази без змін. Помилкові
-- оператори обгорнуто SAVEPOINT, щоб транзакція продовжувалась.
-- =====================================================================
SET search_path TO stemik;
\set ON_ERROR_STOP off
\set VERBOSITY terse
BEGIN;

\echo '--- 1. UPDATE ... FROM: залишок чинних абонементів за фактичними відвідуваннями'
\echo '    (спершу SELECT — у яких абонементів залишок не збігається з відвідуваннями)'
SELECT left(sb.subscription_id::text, 8) AS id8, c.name AS course, sb.total_lessons AS total,
       sb.remaining_lessons AS remaining, count(a.attendance_id) AS used
FROM subscription sb
JOIN course c USING (course_id)
LEFT JOIN attendance a ON a.subscription_id = sb.subscription_id
WHERE sb.status = 'active'
GROUP BY sb.subscription_id, c.name
HAVING sb.remaining_lessons <> greatest(sb.total_lessons - count(a.attendance_id), 0)
ORDER BY c.name;

UPDATE subscription AS sb
SET remaining_lessons = greatest(sb.total_lessons - u.used, 0),
    status = CASE WHEN sb.total_lessons - u.used <= 0 THEN 'completed' ELSE 'active' END
FROM (SELECT s.subscription_id, count(a.attendance_id) AS used
      FROM subscription s LEFT JOIN attendance a ON a.subscription_id = s.subscription_id
      GROUP BY s.subscription_id) AS u
WHERE u.subscription_id = sb.subscription_id
  AND sb.status = 'active'
  AND sb.remaining_lessons <> greatest(sb.total_lessons - u.used, 0)
RETURNING left(sb.subscription_id::text, 8) AS id8, sb.remaining_lessons, sb.status;

\echo '--- 2. UPDATE з умовою і RETURNING: +10 % до ціни групових 3D-занять'
UPDATE tariff AS t
SET lesson_price = round(t.lesson_price * 1.10, 2)
FROM course AS c
WHERE c.course_id = t.course_id AND c.direction = '3D' AND t.tariff_type = 'group_2_6'
RETURNING c.name, t.tariff_type, t.lesson_price AS new_price;

\echo '--- 3. UPDATE: борг погашено — неоплачені заняття учня позначено оплаченими готівкою'
UPDATE attendance AS a
SET payment_method = 'cash', amount = l.price_amount
FROM lesson AS l, student AS s
WHERE l.lesson_id = a.lesson_id AND s.student_id = a.student_id
  AND a.status = 'present' AND a.payment_method IS NULL
  AND a.student_id = (SELECT student_id FROM attendance
                       WHERE status = 'present' AND payment_method IS NULL
                       GROUP BY student_id ORDER BY count(*) DESC, student_id LIMIT 1)
RETURNING s.last_name || ' ' || s.first_name AS student, l.lesson_date, a.payment_method, a.amount;

\echo '--- 4. DELETE з умовою: скасувати решту серії занять після 31.03.2027'
\echo '    (заняття серії видаляються, записи учнів на них — каскадно)'
SELECT count(*) AS lessons_to_delete,
       (SELECT count(*) FROM lesson_student ls JOIN lesson l USING (lesson_id)
         WHERE l.series_id = x.series_id AND l.lesson_date > DATE '2027-03-31') AS enrollments
FROM lesson l
JOIN (SELECT series_id FROM lesson WHERE series_id IS NOT NULL
      GROUP BY series_id ORDER BY count(*) DESC LIMIT 1) AS x USING (series_id)
WHERE l.lesson_date > DATE '2027-03-31'
GROUP BY x.series_id;
SELECT count(*) AS lesson_student_before FROM lesson_student;
DELETE FROM lesson
WHERE series_id = (SELECT series_id FROM lesson WHERE series_id IS NOT NULL
                   GROUP BY series_id ORDER BY count(*) DESC LIMIT 1)
  AND lesson_date > DATE '2027-03-31'
  AND NOT completed;
SELECT count(*) AS lesson_student_after FROM lesson_student;

\echo '--- 5. DELETE ... RETURNING: видалити коментар'
DELETE FROM student_comment
WHERE comment_id = (SELECT comment_id FROM student_comment ORDER BY created_at LIMIT 1)
RETURNING left(body, 30) AS body, created_at::date;

\echo '--- 6. DELETE учня з абонементом (RESTRICT, очікується помилка)'
SAVEPOINT s6;
DELETE FROM student WHERE student_id = (SELECT student_id FROM subscription LIMIT 1);
ROLLBACK TO SAVEPOINT s6;

\echo '--- 7. DELETE з каскадом: кабінет батьків разом зі зв''язками з дітьми'
SELECT (SELECT count(*) FROM parent) AS parents, (SELECT count(*) FROM parent_student) AS links;
DELETE FROM parent WHERE parent_id = (SELECT parent_id FROM parent_student
                                       GROUP BY parent_id ORDER BY count(*) DESC, parent_id LIMIT 1);
SELECT (SELECT count(*) FROM parent) AS parents, (SELECT count(*) FROM parent_student) AS links;

\echo '--- 8. Небезпека UPDATE без WHERE: змінено ВСІ рядки'
SAVEPOINT s8;
UPDATE lesson SET room = 'Клас AI';
SELECT room, count(*) FROM lesson GROUP BY room;
ROLLBACK TO SAVEPOINT s8;

ROLLBACK;
\echo '--- Усі зміни відкочено: дані — як після перенесення'
SELECT (SELECT count(*) FROM lesson) AS lessons, (SELECT count(*) FROM parent) AS parents,
       (SELECT count(*) FROM student_comment) AS comments;
