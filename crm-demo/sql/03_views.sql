-- CRM «Стемік» (демоверсія). Крок 3: представлення для щоденної роботи адміністратора (ЛР4).
SET search_path TO stemik;

CREATE OR REPLACE VIEW v_schedule AS
SELECT l.lesson_id, l.lesson_date, l.start_time, l.room, l.format,
       c.name AS course,
       t.first_name || ' ' || t.last_name AS teacher,
       s.first_name || ' ' || s.last_name AS substitute,
       (SELECT count(*) FROM lesson_student ls WHERE ls.lesson_id = l.lesson_id) AS enrolled,
       (SELECT count(*) FROM attendance a WHERE a.lesson_id = l.lesson_id) AS marked,
       l.completed
FROM lesson l
JOIN course c        ON c.course_id = l.course_id
JOIN employee t      ON t.employee_id = l.teacher_id
LEFT JOIN employee s ON s.employee_id = l.substitute_id;

COMMENT ON VIEW v_schedule IS 'Розклад: заняття з курсом, викладачем, заміною, кількістю записаних і відмічених';

CREATE OR REPLACE VIEW v_subscription_status AS
SELECT sb.subscription_id,
       st.last_name || ' ' || st.first_name AS student,
       c.name AS course,
       sb.total_lessons, sb.remaining_lessons, sb.status, sb.purchased_at,
       (SELECT string_agg(p.phone, ', ' ORDER BY p.phone)
        FROM parent_student ps JOIN parent p ON p.parent_id = ps.parent_id
        WHERE ps.student_id = sb.student_id) AS parent_phones
FROM subscription sb
JOIN student st ON st.student_id = sb.student_id
JOIN course c   ON c.course_id = sb.course_id;

COMMENT ON VIEW v_subscription_status IS 'Стан абонементів з контактами батьків — для нагадувань';
