-- ЛР4. Віконні функції
-- База: stemik (модель ЛР3 з реальними даними). Дата «сьогодні» зафіксована: 2026-11-12.
SET search_path TO stemik;

-- ------------------------------------------------------------------------------------
-- 4.22. Найактивніші учні курсу
-- Бізнес-задача: Відзначити трьох найактивніших учнів кожного напряму за кількістю
-- відвідувань. Порівняти нумерацію ROW_NUMBER, RANK і DENSE_RANK при однаковій
-- кількості.
-- ------------------------------------------------------------------------------------
\echo '--- 4.22. Найактивніші учні курсу'
SELECT напрям, учень, візитів, rn, rnk, drnk
FROM (SELECT c.direction AS напрям,
             st.last_name || ' ' || st.first_name AS учень,
             count(*) AS візитів,
             ROW_NUMBER() OVER w AS rn,
             RANK()       OVER w AS rnk,
             DENSE_RANK() OVER w AS drnk
      FROM attendance a
      JOIN lesson l   ON l.lesson_id = a.lesson_id
      JOIN course c   ON c.course_id = l.course_id
      JOIN student st ON st.student_id = a.student_id
      WHERE a.status = 'present'
      GROUP BY c.direction, st.student_id, st.last_name, st.first_name
      WINDOW w AS (PARTITION BY c.direction ORDER BY count(*) DESC)) t
WHERE rnk <= 3
ORDER BY напрям, rn;

-- ------------------------------------------------------------------------------------
-- 4.23. Наростаюча виручка
-- Бізнес-задача: Показати виручку студії за тижнями та наростаючий підсумок з початку
-- навчального року — для звіту засновникам.
-- ------------------------------------------------------------------------------------
\echo '--- 4.23. Наростаюча виручка'
SELECT to_char(date_trunc('week', l.lesson_date), 'YYYY-MM-DD') AS тиждень,
       sum(a.amount) AS виручка,
       sum(sum(a.amount)) OVER (ORDER BY date_trunc('week', l.lesson_date)) AS наростаючим
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY date_trunc('week', l.lesson_date)
ORDER BY 1;

-- ------------------------------------------------------------------------------------
-- 4.24. Частка способу оплати
-- Бізнес-задача: Яку частку виручки кожного місяця дають картка, готівка й абонементи
-- — щоб вирішити, чи підключати еквайринг на сайті.
-- ------------------------------------------------------------------------------------
\echo '--- 4.24. Частка способу оплати'
SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       a.payment_method AS оплата,
       sum(a.amount) AS сума,
       round(100 * sum(a.amount) / sum(sum(a.amount)) OVER (PARTITION BY to_char(l.lesson_date, 'YYYY-MM')), 1) AS відсоток
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present' AND a.payment_method IS NOT NULL
GROUP BY місяць, a.payment_method
ORDER BY місяць, сума DESC;
