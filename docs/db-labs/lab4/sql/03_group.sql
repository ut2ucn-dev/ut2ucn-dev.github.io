-- ЛР4. Групування й агрегування: GROUP BY, HAVING
-- База: stemik (модель ЛР3 з реальними даними). Дата «сьогодні» зафіксована: 2026-11-12.
SET search_path TO stemik;

-- ------------------------------------------------------------------------------------
-- 4.12. Виручка за місяцями
-- Бізнес-задача: Бухгалтерії потрібна виручка від разових оплат і списань з
-- абонементів за кожен місяць окремо за способом оплати.
-- ------------------------------------------------------------------------------------
\echo '--- 4.12. Виручка за місяцями'
SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       COALESCE(a.payment_method, 'не оплачено') AS оплата,
       count(*) AS відвідувань,
       sum(a.amount) AS сума
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY місяць, оплата
ORDER BY місяць, сума DESC;

-- ------------------------------------------------------------------------------------
-- 4.13. Навантаження викладачів
-- Бізнес-задача: Для розрахунку премії: скільки занять провів кожен викладач у
-- жовтні, скільки учнів на них було записано і який середній розмір групи. Показати
-- лише тих, хто провів щонайменше 10 занять.
-- ------------------------------------------------------------------------------------
\echo '--- 4.13. Навантаження викладачів'
SELECT e.first_name || ' ' || e.last_name AS викладач,
       count(DISTINCT l.lesson_id) AS занять,
       count(ls.student_id) AS учнемісць,
       round(count(ls.student_id)::numeric / count(DISTINCT l.lesson_id), 1) AS сер_група
FROM lesson l
JOIN employee e ON e.employee_id = l.teacher_id
LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
WHERE l.lesson_date BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
GROUP BY e.employee_id, e.first_name, e.last_name
HAVING count(DISTINCT l.lesson_id) >= 10
ORDER BY занять DESC;

-- ------------------------------------------------------------------------------------
-- 4.14. Найпопулярніші курси
-- Бізнес-задача: Визначити курси, на які ходить щонайменше 5 різних учнів, — для них
-- варто відкривати додаткові групи.
-- ------------------------------------------------------------------------------------
\echo '--- 4.14. Найпопулярніші курси'
SELECT c.direction AS напрям, c.name AS курс,
       count(DISTINCT ls.student_id) AS учнів,
       count(DISTINCT l.lesson_id) AS занять
FROM course c
JOIN lesson l          ON l.course_id = c.course_id
JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
GROUP BY c.course_id, c.direction, c.name
HAVING count(DISTINCT ls.student_id) >= 5
ORDER BY учнів DESC;

-- ------------------------------------------------------------------------------------
-- 4.15. Відвідуваність курсів
-- Бізнес-задача: Оцінити дисципліну на курсах: частка відміток «був» серед усіх
-- відміток. Враховувати лише курси, де відміток щонайменше 10, щоб частка була
-- показовою.
-- ------------------------------------------------------------------------------------
\echo '--- 4.15. Відвідуваність курсів'
SELECT c.name AS курс,
       count(*) AS відміток,
       count(*) FILTER (WHERE a.status = 'present') AS був,
       count(*) FILTER (WHERE a.status = 'excused') AS поважна,
       count(*) FILTER (WHERE a.status = 'absent') AS прогул,
       round(100.0 * count(*) FILTER (WHERE a.status = 'present') / count(*), 1) AS відсоток
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
JOIN course c ON c.course_id = l.course_id
GROUP BY c.name
HAVING count(*) >= 10
ORDER BY відсоток DESC;
