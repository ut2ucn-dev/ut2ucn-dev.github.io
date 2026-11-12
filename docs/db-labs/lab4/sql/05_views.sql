-- ЛР4. Представлення (VIEW)
-- База: stemik (модель ЛР3 з реальними даними). Дата «сьогодні» зафіксована: 2026-11-12.
SET search_path TO stemik;

-- ------------------------------------------------------------------------------------
-- 4.20. v_schedule — розклад
-- Бізнес-задача: Адміністратор щодня дивиться розклад з назвами курсів, викладачами й
-- кількістю записаних та відмічених учнів. Створити представлення, щоб не писати
-- з’єднання щоразу, і отримати розклад на 14 листопада.
-- ------------------------------------------------------------------------------------
\echo '--- 4.20. v_schedule — розклад'
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

SELECT to_char(start_time, 'HH24:MI') AS час, course AS курс, format AS формат,
       teacher AS викладач, enrolled AS записано, marked AS відмічено
FROM v_schedule
WHERE lesson_date = DATE '2026-11-14'
ORDER BY start_time;

-- ------------------------------------------------------------------------------------
-- 4.21. v_subscription_status — абонементи
-- Бізнес-задача: Для нагадувань батькам потрібен стан абонементів: учень, курс,
-- залишок занять, телефони батьків. Створити представлення й отримати активні
-- абонементи із залишком до 2 занять.
-- ------------------------------------------------------------------------------------
\echo '--- 4.21. v_subscription_status — абонементи'
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

SELECT student AS учень, course AS курс,
       remaining_lessons || ' з ' || total_lessons AS залишок, parent_phones AS телефони
FROM v_subscription_status
WHERE status = 'active' AND remaining_lessons <= 2
ORDER BY remaining_lessons, учень;
