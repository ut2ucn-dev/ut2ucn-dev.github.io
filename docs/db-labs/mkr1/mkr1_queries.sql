-- =====================================================================
-- МКР № 1. Три пошукові запити до бази даних STEM-студії «Стемік»
-- База: навчальна знеособлена копія робочої бази (stemik_training_copy.sql),
-- PostgreSQL 16 / Supabase. Параметри пошуку задано в першому CTE кожного
-- запиту (params) — їх змінюють, не чіпаючи решти запиту; так само запит
-- можна виконати в Supabase SQL Editor.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Запит 1. Пошук учня за частиною імені, телефону або прізвища батьків
-- Бізнес-задача: адміністратор приймає дзвінок і за кількома цифрами
-- телефону чи частиною імені має швидко знайти картку учня і побачити,
-- на скільки занять він записаний, скільки відвідав, коли був востаннє
-- і чи є в нього чинний абонемент.
-- Прийоми: ILIKE з шаблоном, OR, пошук у масиві (= ANY), LEFT JOIN
-- з агрегацією, FILTER, коригувальний підзапит.
-- ---------------------------------------------------------------------
WITH params AS (
    SELECT '%' || '01' || '%' AS pattern          -- що шукаємо
)
SELECT s.name                                                AS student,
       s.phone,
       nullif(trim(s.parent_last_name || ' ' || s.parent_first_name), '') AS parent,
       (SELECT count(*) FROM lessons l
         WHERE s.id = ANY (l.student_ids))                   AS lessons_planned,
       count(a.id) FILTER (WHERE a.status = 'present')       AS visits,
       max(l2.date) FILTER (WHERE a.status = 'present')      AS last_visit,
       (SELECT string_agg(sb.course || ' (' || sb.remaining_lessons || ')', ', ')
          FROM subscriptions sb
         WHERE sb.student_id = s.id AND sb.status = 'active') AS active_subscriptions
FROM students s
CROSS JOIN params p
LEFT JOIN lesson_attendance a ON a.student_id = s.id
LEFT JOIN lessons l2          ON l2.id = a.lesson_id
WHERE s.name ILIKE p.pattern
   OR replace(s.phone, ' ', '') ILIKE replace(p.pattern, ' ', '')
   OR s.parent_last_name ILIKE p.pattern
GROUP BY s.id
ORDER BY s.name;


-- ---------------------------------------------------------------------
-- Запит 2. Пошук занять курсу за назвою і періодом
-- Бізнес-задача: керівник хоче побачити всі заняття напрямку (наприклад,
-- «vr») за обраний період: хто веде, скільки дітей записано і скільки
-- відмічено, щоб знайти заняття без відмітки відвідування.
-- Прийоми: пошук без урахування регістру (ILIKE), BETWEEN, з'єднання з
-- профілем викладача, cardinality() для масиву, LEFT JOIN + count.
-- Результат показує й аномалію поточної схеми: курс записано текстом, тому
-- «VR ІГРОВИЙ» і «VR ігровий» — для бази різні курси.
-- ---------------------------------------------------------------------
WITH params AS (
    SELECT '%vr%'::text        AS course_pattern,
           DATE '2026-08-01'   AS date_from,
           DATE '2026-12-31'   AS date_to
)
SELECT l.date,
       l.time,
       l.course,
       l.theme,
       pr.first_name || ' ' || pr.last_name           AS teacher,
       cardinality(l.student_ids)                     AS enrolled,
       count(a.id)                                    AS marked,
       CASE WHEN count(a.id) = 0 AND l.date < CURRENT_DATE
            THEN 'не відмічено' ELSE '' END           AS warning
FROM lessons l
CROSS JOIN params p
JOIN profiles pr               ON pr.id = l.owner_id
LEFT JOIN lesson_attendance a  ON a.lesson_id = l.id
WHERE l.course ILIKE p.course_pattern
  AND l.date BETWEEN p.date_from AND p.date_to
GROUP BY l.id, pr.last_name, pr.first_name
ORDER BY l.date, l.time;


-- ---------------------------------------------------------------------
-- Запит 3. Пошук боржників: були на заняттях, але не оплатили
-- Бізнес-задача: перед кінцем місяця адміністратор шукає учнів, які
-- відвідали заняття без оплати (ні карткою, ні готівкою, ні абонементом),
-- щоб нагадати батькам. Цікавлять ті, хто не оплатив щонайменше
-- задану кількість занять.
-- Прийоми: умова IS NULL, з'єднання трьох таблиць, GROUP BY з HAVING,
-- агрегати count/sum/min/max, string_agg з сортуванням.
-- ---------------------------------------------------------------------
WITH params AS (
    SELECT 2 AS min_unpaid                            -- скільки неоплачених занять
)
SELECT s.name                                         AS student,
       s.phone,
       count(*)                                       AS unpaid_lessons,
       sum(a.amount)                                  AS debt,
       min(l.date)                                    AS first_unpaid,
       max(l.date)                                    AS last_unpaid,
       string_agg(DISTINCT l.course, ', ')            AS courses
FROM lesson_attendance a
CROSS JOIN params p
JOIN students s ON s.id = a.student_id
JOIN lessons  l ON l.id = a.lesson_id
WHERE a.status = 'present'
  AND a.payment_method IS NULL
GROUP BY s.id, p.min_unpaid
HAVING count(*) >= p.min_unpaid
ORDER BY debt DESC;
