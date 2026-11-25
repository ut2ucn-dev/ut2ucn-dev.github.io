-- =====================================================================
-- Стемік · 24 аналітичні запити до бази студії — для Supabase SQL Editor.
-- Як виконати один запит: виділіть блок від рядка SET search_path до ';'
-- в кінці запиту й натисніть Run (Ctrl+Enter). Дата «сьогодні» в
-- запитах зафіксована: 2026-11-12.
-- =====================================================================

-- ######################################################################
-- ПРОСТІ ЗАПИТИ: WHERE, ORDER BY, DISTINCT
-- ######################################################################

-- 4.1. Хто працює в студії
-- Задача: Адміністратор складає графік чергувань: показати всіх активних працівників
-- студії з роллю й e-mail, спочатку адміністраторів, потім викладачів, за прізвищем.
SET search_path TO stemik;
SELECT last_name AS прізвище, first_name AS ім_я, role AS роль, email
FROM employee
WHERE active
ORDER BY CASE role WHEN 'superadmin' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END,
         last_name;

-- 4.2. Формати й класи занять
-- Задача: Перед плануванням розкладу на семестр з’ясувати, у яких форматах
-- проводяться заняття і в яких класах, — без повторів.
SET search_path TO stemik;
SELECT DISTINCT format AS формат
FROM lesson
ORDER BY 1;

SELECT DISTINCT format AS формат, COALESCE(room, 'не вказано') AS клас
FROM lesson
ORDER BY 1, 2;

-- 4.3. Розклад наступного тижня
-- Задача: Надіслати батькам розклад на наступний тиждень (16–22 листопада 2026):
-- дата, час, формат і тема кожного заняття в хронологічному порядку.
SET search_path TO stemik;
SELECT lesson_date AS дата, to_char(start_time, 'HH24:MI') AS час,
       format AS формат, theme AS тема
FROM lesson
WHERE lesson_date BETWEEN DATE '2026-11-16' AND DATE '2026-11-22'
ORDER BY lesson_date, start_time;

-- 4.4. Курси для дитини 10 років
-- Задача: Батьки телефонують: дитині 10 років, які курси їй підходять? Показати
-- активні курси, вікові межі яких охоплюють цей вік, згрупувавши за напрямом.
SET search_path TO stemik;
SELECT direction AS напрям, name AS курс, age_min AS від, age_max AS до
FROM course
WHERE active
  AND 10 BETWEEN age_min AND age_max
ORDER BY direction, name;

-- 4.5. Незакриті заняття
-- Задача: Знайти заняття, які вже минули, але викладач так і не позначив їх
-- проведеними: їх треба закрити, інакше не нарахується оплата праці. Спочатку
-- найсвіжіші.
SET search_path TO stemik;
SELECT lesson_date AS дата, to_char(start_time, 'HH24:MI') AS час,
       format AS формат, theme AS тема
FROM lesson
WHERE lesson_date < DATE '2026-11-12'
  AND NOT completed
ORDER BY lesson_date DESC, start_time
LIMIT 10;

-- 4.6. Батьки без входу в кабінет
-- Задача: Батьки, які жодного разу не входили в кабінет, не бачать відвідування й
-- залишку абонемента. Отримати список для розсилки інструкції зі входу.
SET search_path TO stemik;
SELECT last_name AS прізвище, first_name AS ім_я, phone AS телефон
FROM parent
WHERE active
  AND last_login_at IS NULL
ORDER BY last_name, first_name
LIMIT 10;

-- ######################################################################
-- З’ЄДНАННЯ ТРЬОХ І БІЛЬШЕ ТАБЛИЦЬ
-- ######################################################################

-- 4.7. Розклад дня з викладачами
-- Задача: Скласти розклад на суботу 14 листопада для рецепції: курс, час, формат,
-- викладач і, якщо є, викладач на заміні.
SET search_path TO stemik;
SELECT to_char(l.start_time, 'HH24:MI') AS час, c.name AS курс, l.format AS формат,
       t.first_name || ' ' || t.last_name AS викладач,
       COALESCE(s.first_name || ' ' || s.last_name, '—') AS заміна
FROM lesson l
JOIN course c        ON c.course_id = l.course_id
JOIN employee t      ON t.employee_id = l.teacher_id
LEFT JOIN employee s ON s.employee_id = l.substitute_id
WHERE l.lesson_date = DATE '2026-11-14'
ORDER BY l.start_time;

-- 4.8. Контакти батьків групи
-- Задача: Заняття VR ІГРОВИЙ 14 листопада переноситься — отримати список учнів групи
-- з контактами батьків для обдзвону.
SET search_path TO stemik;
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

-- 4.9. Журнал заняття
-- Задача: Перевірити журнал заняття 3D Tinkercad FIRST 8 листопада: хто був
-- записаний, яка відмітка й оплата, кого забули відмітити і хто не заплатив.
SET search_path TO stemik;
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

-- 4.10. Учні без абонемента
-- Задача: Знайти учнів, які в листопаді ходять на курс без активного абонемента на
-- нього, — їм варто запропонувати абонемент, це вигідніше за разову оплату.
SET search_path TO stemik;
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

-- 4.11. Курси: грудень проти травня
-- Задача: Порівняти, скільки занять кожного курсу заплановано в грудні 2026 і травні
-- 2027, щоб побачити, які групи завершуються до кінця навчального року.
SET search_path TO stemik;
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

-- ######################################################################
-- ГРУПУВАННЯ Й АГРЕГУВАННЯ: GROUP BY, HAVING
-- ######################################################################

-- 4.12. Виручка за місяцями
-- Задача: Бухгалтерії потрібна виручка від разових оплат і списань з абонементів за
-- кожен місяць окремо за способом оплати.
SET search_path TO stemik;
SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       COALESCE(a.payment_method, 'не оплачено') AS оплата,
       count(*) AS відвідувань,
       sum(a.amount) AS сума
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY місяць, оплата
ORDER BY місяць, сума DESC;

-- 4.13. Навантаження викладачів
-- Задача: Для розрахунку премії: скільки занять провів кожен викладач у жовтні,
-- скільки учнів на них було записано і який середній розмір групи. Показати лише тих,
-- хто провів щонайменше 10 занять.
SET search_path TO stemik;
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

-- 4.14. Найпопулярніші курси
-- Задача: Визначити курси, на які ходить щонайменше 5 різних учнів, — для них варто
-- відкривати додаткові групи.
SET search_path TO stemik;
SELECT c.direction AS напрям, c.name AS курс,
       count(DISTINCT ls.student_id) AS учнів,
       count(DISTINCT l.lesson_id) AS занять
FROM course c
JOIN lesson l          ON l.course_id = c.course_id
JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
GROUP BY c.course_id, c.direction, c.name
HAVING count(DISTINCT ls.student_id) >= 5
ORDER BY учнів DESC;

-- 4.15. Відвідуваність курсів
-- Задача: Оцінити дисципліну на курсах: частка відміток «був» серед усіх відміток.
-- Враховувати лише курси, де відміток щонайменше 10, щоб частка була показовою.
SET search_path TO stemik;
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

-- ######################################################################
-- ПІДЗАПИТИ У WHERE, FROM І SELECT
-- ######################################################################

-- 4.16. Учні, що випали з розкладу
-- Задача: Знайти активних учнів, які раніше відвідували заняття, але не записані на
-- жодне майбутнє заняття, — адміністратор зателефонує батькам.
SET search_path TO stemik;
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

-- 4.17. Розмір груп за курсами
-- Задача: Порівняти наповненість груп курсів: середня, найменша й найбільша кількість
-- учнів на занятті.
SET search_path TO stemik;
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

-- 4.18. Використання абонементів
-- Задача: Для кожного активного абонемента показати, скільки занять за ним уже
-- відвідано і коли був останній візит, — щоб помітити «сплячі» абонементи.
SET search_path TO stemik;
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

-- 4.19. Заняття, переповнені понад середнє
-- Задача: Знайти майбутні заняття, на які записано більше учнів, ніж у середньому на
-- заняття студії, — можливо, потрібен другий викладач.
SET search_path TO stemik;
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

-- ######################################################################
-- ПРЕДСТАВЛЕННЯ (VIEW)
-- ######################################################################

-- 4.20. v_schedule — розклад
-- Задача: Адміністратор щодня дивиться розклад з назвами курсів, викладачами й
-- кількістю записаних та відмічених учнів. Створити представлення, щоб не писати
-- з’єднання щоразу, і отримати розклад на 14 листопада.
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

SELECT to_char(start_time, 'HH24:MI') AS час, course AS курс, format AS формат,
       teacher AS викладач, enrolled AS записано, marked AS відмічено
FROM v_schedule
WHERE lesson_date = DATE '2026-11-14'
ORDER BY start_time;

-- 4.21. v_subscription_status — абонементи
-- Задача: Для нагадувань батькам потрібен стан абонементів: учень, курс, залишок
-- занять, телефони батьків. Створити представлення й отримати активні абонементи із
-- залишком до 2 занять.
SET search_path TO stemik;
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

-- ######################################################################
-- ВІКОННІ ФУНКЦІЇ
-- ######################################################################

-- 4.22. Найактивніші учні курсу
-- Задача: Відзначити трьох найактивніших учнів кожного напряму за кількістю
-- відвідувань. Порівняти нумерацію ROW_NUMBER, RANK і DENSE_RANK при однаковій
-- кількості.
SET search_path TO stemik;
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

-- 4.23. Наростаюча виручка
-- Задача: Показати виручку студії за тижнями та наростаючий підсумок з початку
-- навчального року — для звіту засновникам.
SET search_path TO stemik;
SELECT to_char(date_trunc('week', l.lesson_date), 'YYYY-MM-DD') AS тиждень,
       sum(a.amount) AS виручка,
       sum(sum(a.amount)) OVER (ORDER BY date_trunc('week', l.lesson_date)) AS наростаючим
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY date_trunc('week', l.lesson_date)
ORDER BY 1;

-- 4.24. Частка способу оплати
-- Задача: Яку частку виручки кожного місяця дають картка, готівка й абонементи — щоб
-- вирішити, чи підключати еквайринг на сайті.
SET search_path TO stemik;
SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       a.payment_method AS оплата,
       sum(a.amount) AS сума,
       round(100 * sum(a.amount) / sum(sum(a.amount)) OVER (PARTITION BY to_char(l.lesson_date, 'YYYY-MM')), 1) AS відсоток
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present' AND a.payment_method IS NOT NULL
GROUP BY місяць, a.payment_method
ORDER BY місяць, сума DESC;
