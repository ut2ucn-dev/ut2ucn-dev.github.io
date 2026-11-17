-- =====================================================================
-- CRM «Стемік». Три пошукові запити для живої демонстрації
-- (Supabase → SQL Editor). Параметри задаються в CTE params на початку
-- кожного запиту: змініть значення й натисніть Run.
-- Ті самі запити виконує сайт через функції crm_students, crm_lessons,
-- crm_debtors (файл 04_crm_api.sql).
-- =====================================================================
SET search_path TO stemik;

-- #1 ------------------------------------------------------------------
-- Пошук учня. Телефонують батьки, на екрані — лише кінець номера «010».
-- Знайти учня за фрагментом ПІБ або телефону — учня або будь-кого
-- з батьків — і показати батьків та активні абонементи.
WITH params AS (
    SELECT '010' AS q                                  -- що шукаємо
)
SELECT s.last_name || ' ' || s.first_name AS учень,
       string_agg(DISTINCT concat_ws(' ', p.last_name, p.first_name) || ' · ' || p.phone, '; ') AS батьки,
       string_agg(DISTINCT c.name || ': ' || sb.remaining_lessons || ' з ' || sb.total_lessons, '; ') AS абонементи
FROM student s
CROSS JOIN params
LEFT JOIN parent_student ps ON ps.student_id = s.student_id
LEFT JOIN parent p          ON p.parent_id = ps.parent_id
LEFT JOIN subscription sb   ON sb.student_id = s.student_id AND sb.status = 'active'
LEFT JOIN course c          ON c.course_id = sb.course_id
WHERE s.active
  AND (s.last_name || ' ' || s.first_name ILIKE '%' || params.q || '%'
       OR regexp_replace(coalesce(s.phone, ''), '\D', '', 'g') LIKE '%' || params.q || '%'
       OR concat_ws(' ', p.last_name, p.first_name) ILIKE '%' || params.q || '%'
       OR p.phone LIKE '%' || params.q || '%')
GROUP BY s.student_id, s.last_name, s.first_name
ORDER BY учень;

-- #2 ------------------------------------------------------------------
-- Розклад курсу за період. Скільки занять курсу заплановано на тиждень,
-- хто веде (з урахуванням заміни), скільки учнів записано, скільки вже
-- відмічено і чи закрите заняття.
WITH params AS (
    SELECT DATE '2026-11-16' AS date_from,
           DATE '2026-11-22' AS date_to,
           '%Tinkercad%'     AS course_pattern
)
SELECT l.lesson_date AS дата,
       to_char(l.start_time, 'HH24:MI') AS час,
       c.name AS курс,
       coalesce(sub.first_name || ' ' || sub.last_name || ' (заміна)',
                t.first_name || ' ' || t.last_name) AS викладач,
       count(ls.student_id) AS записано,
       count(a.attendance_id) AS відмічено,
       CASE WHEN l.completed THEN 'так' ELSE 'ні' END AS проведено
FROM lesson l
CROSS JOIN params
JOIN course c          ON c.course_id = l.course_id
JOIN employee t        ON t.employee_id = l.teacher_id
LEFT JOIN employee sub ON sub.employee_id = l.substitute_id
LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
LEFT JOIN attendance a      ON a.lesson_id = ls.lesson_id AND a.student_id = ls.student_id
WHERE l.lesson_date BETWEEN params.date_from AND params.date_to
  AND c.name ILIKE params.course_pattern
GROUP BY l.lesson_id, c.name, t.first_name, t.last_name, sub.first_name, sub.last_name
ORDER BY дата, час;

-- #3 ------------------------------------------------------------------
-- Боржники. Учні, які були присутні на заняттях без оплати щонайменше
-- min_visits разів: сума боргу, період і телефони батьків для дзвінка.
WITH params AS (
    SELECT 2 AS min_visits
)
SELECT s.last_name || ' ' || s.first_name AS учень,
       count(*) AS неоплачених,
       sum(a.amount) AS борг,
       min(l.lesson_date) AS з,
       max(l.lesson_date) AS по,
       (SELECT string_agg(p.phone, ', ')
        FROM parent_student ps JOIN parent p ON p.parent_id = ps.parent_id
        WHERE ps.student_id = s.student_id) AS телефони_батьків
FROM attendance a
JOIN student s ON s.student_id = a.student_id
JOIN lesson l  ON l.lesson_id = a.lesson_id
CROSS JOIN params
WHERE a.status = 'present'
  AND a.payment_method IS NULL
GROUP BY s.student_id, s.last_name, s.first_name, params.min_visits
HAVING count(*) >= params.min_visits
ORDER BY борг DESC, учень;
