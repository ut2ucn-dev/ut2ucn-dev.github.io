-- Пошуковий запит 1: пошук учня. Supabase → SQL Editor → вставити → Run.
-- Пошук учня. Телефонують батьки, на екрані — лише кінець номера «010».
-- Знайти учня за фрагментом ПІБ або телефону — учня або будь-кого
-- з батьків — і показати батьків та активні абонементи.
SET search_path TO stemik;
WITH params AS (
    SELECT '010' AS q                                  -- що шукаємо
)
SELECT concat_ws(' ', s.last_name, s.first_name) AS учень,
       string_agg(DISTINCT concat(concat_ws(' ', p.last_name, p.first_name), ' · ', p.phone), '; ') AS батьки,
       string_agg(DISTINCT concat(c.name, ': ', sb.remaining_lessons, ' з ', sb.total_lessons), '; ') AS абонементи
FROM student s
CROSS JOIN params
LEFT JOIN parent_student ps ON ps.student_id = s.student_id
LEFT JOIN parent p          ON p.parent_id = ps.parent_id
LEFT JOIN subscription sb   ON sb.student_id = s.student_id AND sb.status = 'active'
LEFT JOIN course c          ON c.course_id = sb.course_id
WHERE s.active
  AND (concat_ws(' ', s.last_name, s.first_name) ILIKE concat('%', params.q, '%')
       OR regexp_replace(coalesce(s.phone, ''), '\D', '', 'g') LIKE concat('%', params.q, '%')
       OR concat_ws(' ', p.last_name, p.first_name) ILIKE concat('%', params.q, '%')
       OR p.phone LIKE concat('%', params.q, '%'))
GROUP BY s.student_id, s.last_name, s.first_name
ORDER BY учень;
