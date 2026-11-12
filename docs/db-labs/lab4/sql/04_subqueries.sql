-- ЛР4. Підзапити у WHERE, FROM і SELECT
-- База: stemik (модель ЛР3 з реальними даними). Дата «сьогодні» зафіксована: 2026-11-12.
SET search_path TO stemik;

-- ------------------------------------------------------------------------------------
-- 4.16. Учні, що випали з розкладу
-- Бізнес-задача: Знайти активних учнів, які раніше відвідували заняття, але не
-- записані на жодне майбутнє заняття, — адміністратор зателефонує батькам.
-- ------------------------------------------------------------------------------------
\echo '--- 4.16. Учні, що випали з розкладу'
SELECT st.last_name || ' ' || st.first_name AS учень, st.phone AS телефон
FROM student st
WHERE st.active
  AND EXISTS (SELECT 1 FROM attendance a
              WHERE a.student_id = st.student_id AND a.status = 'present')
  AND NOT EXISTS (SELECT 1
                  FROM lesson_student ls
                  JOIN lesson l ON l.lesson_id = ls.lesson_id
                  WHERE ls.student_id = st.student_id
                    AND l.lesson_date >= DATE '2026-11-12')
ORDER BY учень;

-- ------------------------------------------------------------------------------------
-- 4.17. Розмір груп за курсами
-- Бізнес-задача: Порівняти наповненість груп курсів: середня, найменша й найбільша
-- кількість учнів на занятті.
-- ------------------------------------------------------------------------------------
\echo '--- 4.17. Розмір груп за курсами'
SELECT c.name AS курс,
       count(*) AS занять,
       round(avg(g.n), 1) AS середня,
       min(g.n) AS мін,
       max(g.n) AS макс
FROM (SELECT l.lesson_id, l.course_id, count(ls.student_id) AS n
      FROM lesson l
      LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
      GROUP BY l.lesson_id, l.course_id) AS g
JOIN course c ON c.course_id = g.course_id
GROUP BY c.name
ORDER BY середня DESC;

-- ------------------------------------------------------------------------------------
-- 4.18. Використання абонементів
-- Бізнес-задача: Для кожного активного абонемента показати, скільки занять за ним уже
-- відвідано і коли був останній візит, — щоб помітити «сплячі» абонементи.
-- ------------------------------------------------------------------------------------
\echo '--- 4.18. Використання абонементів'
SELECT st.last_name || ' ' || st.first_name AS учень,
       c.name AS курс,
       sb.remaining_lessons || ' з ' || sb.total_lessons AS залишок,
       (SELECT count(*) FROM attendance a
        WHERE a.subscription_id = sb.subscription_id) AS відвідано,
       (SELECT max(l.lesson_date) FROM attendance a
        JOIN lesson l ON l.lesson_id = a.lesson_id
        WHERE a.subscription_id = sb.subscription_id) AS останній_візит
FROM subscription sb
JOIN student st ON st.student_id = sb.student_id
JOIN course c   ON c.course_id = sb.course_id
WHERE sb.status = 'active'
ORDER BY останній_візит NULLS FIRST;

-- ------------------------------------------------------------------------------------
-- 4.19. Заняття, переповнені понад середнє
-- Бізнес-задача: Знайти майбутні заняття, на які записано більше учнів, ніж у
-- середньому на заняття студії, — можливо, потрібен другий викладач.
-- ------------------------------------------------------------------------------------
\echo '--- 4.19. Заняття, переповнені понад середнє'
SELECT l.lesson_date AS дата, to_char(l.start_time, 'HH24:MI') AS час,
       c.name AS курс, count(*) AS учнів
FROM lesson l
JOIN course c          ON c.course_id = l.course_id
JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
WHERE l.lesson_date >= DATE '2026-11-12'
GROUP BY l.lesson_id, c.name
HAVING count(*) > (SELECT avg(n)
                   FROM (SELECT count(*) AS n FROM lesson_student
                         GROUP BY lesson_id) s)
ORDER BY дата, час
LIMIT 10;
