-- Пошуковий запит 3: боржники. Supabase → SQL Editor → вставити → Run.
-- Боржники. Учні, які були присутні на заняттях без оплати щонайменше
-- min_visits разів: сума боргу, період і телефони батьків для дзвінка.
SET search_path TO stemik;
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
