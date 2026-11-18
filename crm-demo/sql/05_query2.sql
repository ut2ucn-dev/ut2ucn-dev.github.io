-- Пошуковий запит 2: розклад курсу. Supabase → SQL Editor → вставити → Run.
-- Розклад курсу за період. Скільки занять курсу заплановано на тиждень,
-- хто веде (з урахуванням заміни), скільки учнів записано, скільки вже
-- відмічено і чи закрите заняття.
SET search_path TO stemik;
WITH params AS (
    SELECT DATE '2026-11-16' AS date_from,
           DATE '2026-11-22' AS date_to,
           '%Tinkercad%'     AS course_pattern
)
SELECT l.lesson_date AS дата,
       to_char(l.start_time, 'HH24:MI') AS час,
       c.name AS курс,
       CASE WHEN sub.employee_id IS NOT NULL
            THEN concat(sub.first_name, ' ', sub.last_name, ' (заміна)')
            ELSE concat(t.first_name, ' ', t.last_name) END AS викладач,
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
GROUP BY l.lesson_id, c.name, t.first_name, t.last_name, sub.employee_id, sub.first_name, sub.last_name
ORDER BY дата, час;
