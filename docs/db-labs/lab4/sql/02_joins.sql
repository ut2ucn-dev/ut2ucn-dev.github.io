-- ЛР4. З’єднання трьох і більше таблиць
-- База: stemik (модель ЛР3 з реальними даними). Дата «сьогодні» зафіксована: 2026-11-12.
SET search_path TO stemik;

-- ------------------------------------------------------------------------------------
-- 4.7. Розклад дня з викладачами
-- Бізнес-задача: Скласти розклад на суботу 14 листопада для рецепції: курс, час,
-- формат, викладач і, якщо є, викладач на заміні.
-- ------------------------------------------------------------------------------------
\echo '--- 4.7. Розклад дня з викладачами'
SELECT to_char(l.start_time, 'HH24:MI') AS час, c.name AS курс, l.format AS формат,
       t.first_name || ' ' || t.last_name AS викладач,
       COALESCE(s.first_name || ' ' || s.last_name, '—') AS заміна
FROM lesson l
JOIN course c        ON c.course_id = l.course_id
JOIN employee t      ON t.employee_id = l.teacher_id
LEFT JOIN employee s ON s.employee_id = l.substitute_id
WHERE l.lesson_date = DATE '2026-11-14'
ORDER BY l.start_time;

-- ------------------------------------------------------------------------------------
-- 4.8. Контакти батьків групи
-- Бізнес-задача: Заняття VR ІГРОВИЙ 14 листопада переноситься — отримати список учнів
-- групи з контактами батьків для обдзвону.
-- ------------------------------------------------------------------------------------
\echo '--- 4.8. Контакти батьків групи'
SELECT st.last_name || ' ' || st.first_name AS учень,
       COALESCE(p.last_name || ' ' || p.first_name, 'не вказано') AS батьки,
       p.phone AS телефон
FROM lesson l
JOIN course c              ON c.course_id = l.course_id
JOIN lesson_student ls     ON ls.lesson_id = l.lesson_id
JOIN student st            ON st.student_id = ls.student_id
LEFT JOIN parent_student ps ON ps.student_id = st.student_id
LEFT JOIN parent p          ON p.parent_id = ps.parent_id
WHERE l.lesson_date = DATE '2026-11-14'
  AND c.name = 'VR ІГРОВИЙ'
ORDER BY учень;

-- ------------------------------------------------------------------------------------
-- 4.9. Журнал заняття
-- Бізнес-задача: Перевірити журнал заняття 3D Tinkercad FIRST 8 листопада: хто був
-- записаний, яка відмітка й оплата, кого забули відмітити і хто не заплатив.
-- ------------------------------------------------------------------------------------
\echo '--- 4.9. Журнал заняття'
SELECT st.last_name || ' ' || st.first_name AS учень,
       COALESCE(a.status, 'не відмічено') AS відмітка,
       COALESCE(a.payment_method, '—') AS оплата,
       a.amount AS сума
FROM lesson l
JOIN course c          ON c.course_id = l.course_id
JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
JOIN student st        ON st.student_id = ls.student_id
LEFT JOIN attendance a ON a.lesson_id = ls.lesson_id AND a.student_id = ls.student_id
WHERE l.lesson_date = DATE '2026-11-08'
  AND c.name = '3D Tinkercad FIRST (9-12)'
ORDER BY a.status NULLS FIRST, учень;

-- ------------------------------------------------------------------------------------
-- 4.10. Учні без абонемента
-- Бізнес-задача: Знайти учнів, які в листопаді ходять на курс без активного
-- абонемента на нього, — їм варто запропонувати абонемент, це вигідніше за разову
-- оплату.
-- ------------------------------------------------------------------------------------
\echo '--- 4.10. Учні без абонемента'
SELECT DISTINCT st.last_name || ' ' || st.first_name AS учень, c.name AS курс
FROM lesson_student ls
JOIN lesson l        ON l.lesson_id = ls.lesson_id
JOIN course c        ON c.course_id = l.course_id
JOIN student st      ON st.student_id = ls.student_id
LEFT JOIN subscription sb ON sb.student_id = ls.student_id
                         AND sb.course_id = l.course_id
                         AND sb.status = 'active'
WHERE l.lesson_date BETWEEN DATE '2026-11-01' AND DATE '2026-11-30'
  AND sb.subscription_id IS NULL
ORDER BY курс, учень
LIMIT 15;

-- ------------------------------------------------------------------------------------
-- 4.11. Курси: грудень проти травня
-- Бізнес-задача: Порівняти, скільки занять кожного курсу заплановано в грудні 2026 і
-- травні 2027, щоб побачити, які групи завершуються до кінця навчального року.
-- ------------------------------------------------------------------------------------
\echo '--- 4.11. Курси: грудень проти травня'
SELECT COALESCE(c1.name, c2.name) AS курс,
       COALESCE(dec.n, 0) AS грудень, COALESCE(may.n, 0) AS травень
FROM (SELECT course_id, count(*) AS n FROM lesson
      WHERE lesson_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31'
      GROUP BY course_id) dec
FULL JOIN (SELECT course_id, count(*) AS n FROM lesson
           WHERE lesson_date BETWEEN DATE '2027-05-01' AND DATE '2027-05-31'
           GROUP BY course_id) may ON may.course_id = dec.course_id
LEFT JOIN course c1 ON c1.course_id = dec.course_id
LEFT JOIN course c2 ON c2.course_id = may.course_id
ORDER BY курс;
