-- Етап ЛР4: каталог запитів і їх виконання для сайту labs/lr4/.
-- Сайт не надсилає SQL: він передає лише номер запиту, а текст береться з таблиці lab_query.
SET search_path TO stemik;

DROP TABLE IF EXISTS stemik.lab_query;
CREATE TABLE stemik.lab_query (
    ord       SMALLINT    NOT NULL,
    query_id  VARCHAR(8)  CONSTRAINT pk_lab_query PRIMARY KEY,
    section   VARCHAR(10) NOT NULL,
    section_title TEXT    NOT NULL,
    title     TEXT        NOT NULL,
    task      TEXT        NOT NULL,
    note      TEXT        NOT NULL,
    sql_text  TEXT        NOT NULL,   -- повний текст запиту, як у протоколі
    sql_run   TEXT        NOT NULL    -- один SELECT, який виконує сайт
);
COMMENT ON TABLE stemik.lab_query IS 'ЛР4: запити з бізнес-задачами для сайту';

INSERT INTO stemik.lab_query (ord, query_id, section, section_title, title, task, note, sql_text, sql_run) VALUES
(1, '4.1', 'simple', $t$Прості запити: WHERE, ORDER BY, DISTINCT$t$, $t$Хто працює в студії$t$, $t$Адміністратор складає графік чергувань: показати всіх активних працівників студії з роллю й e-mail, спочатку адміністраторів, потім викладачів, за прізвищем.$t$,
 $t$Умова `WHERE active` відкидає звільнених (1 суперадмін неактивний). Сортування за виразом `CASE` задає порядок ролей, якого немає за абеткою.$t$,
 $q$SELECT last_name AS прізвище, first_name AS ім_я, role AS роль, email
FROM employee
WHERE active
ORDER BY CASE role WHEN 'superadmin' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END,
         last_name;$q$,
 $q$SELECT last_name AS прізвище, first_name AS ім_я, role AS роль, email
FROM employee
WHERE active
ORDER BY CASE role WHEN 'superadmin' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END,
         last_name$q$),
(2, '4.2', 'simple', $t$Прості запити: WHERE, ORDER BY, DISTINCT$t$, $t$Формати й класи занять$t$, $t$Перед плануванням розкладу на семестр з’ясувати, у яких форматах проводяться заняття і в яких класах, — без повторів.$t$,
 $t$Два запити показують, що `DISTINCT` діє на весь рядок: окремо форматів 4, а комбінацій «формат + клас» — 6, бо групові заняття проходять і в «Класі AI», і в «Класі VR», і без указаного класу (контрольне питання 4). Для DISTINCT усі NULL вважаються однаковими, тому «не вказано» для кожного формату — один рядок.$t$,
 $q$SELECT DISTINCT format AS формат
FROM lesson
ORDER BY 1;

SELECT DISTINCT format AS формат, COALESCE(room, 'не вказано') AS клас
FROM lesson
ORDER BY 1, 2;$q$,
 $q$SELECT DISTINCT format AS формат, COALESCE(room, 'не вказано') AS клас
FROM lesson
ORDER BY 1, 2$q$),
(3, '4.3', 'simple', $t$Прості запити: WHERE, ORDER BY, DISTINCT$t$, $t$Розклад наступного тижня$t$, $t$Надіслати батькам розклад на наступний тиждень (16–22 листопада 2026): дата, час, формат і тема кожного заняття в хронологічному порядку.$t$,
 $t$`BETWEEN` включає обидві межі. Сортування за двома стовпцями: спочатку день, усередині дня — час.$t$,
 $q$SELECT lesson_date AS дата, to_char(start_time, 'HH24:MI') AS час,
       format AS формат, theme AS тема
FROM lesson
WHERE lesson_date BETWEEN DATE '2026-11-16' AND DATE '2026-11-22'
ORDER BY lesson_date, start_time;$q$,
 $q$SELECT lesson_date AS дата, to_char(start_time, 'HH24:MI') AS час,
       format AS формат, theme AS тема
FROM lesson
WHERE lesson_date BETWEEN DATE '2026-11-16' AND DATE '2026-11-22'
ORDER BY lesson_date, start_time$q$),
(4, '4.4', 'simple', $t$Прості запити: WHERE, ORDER BY, DISTINCT$t$, $t$Курси для дитини 10 років$t$, $t$Батьки телефонують: дитині 10 років, які курси їй підходять? Показати активні курси, вікові межі яких охоплюють цей вік, згрупувавши за напрямом.$t$,
 $t$Тут `BETWEEN` перевіряє, чи стала (вік дитини) лежить між значеннями двох стовпців — звичний для адміністратора сценарій «підбору» курсу.$t$,
 $q$SELECT direction AS напрям, name AS курс, age_min AS від, age_max AS до
FROM course
WHERE active
  AND 10 BETWEEN age_min AND age_max
ORDER BY direction, name;$q$,
 $q$SELECT direction AS напрям, name AS курс, age_min AS від, age_max AS до
FROM course
WHERE active
  AND 10 BETWEEN age_min AND age_max
ORDER BY direction, name$q$),
(5, '4.5', 'simple', $t$Прості запити: WHERE, ORDER BY, DISTINCT$t$, $t$Незакриті заняття$t$, $t$Знайти заняття, які вже минули, але викладач так і не позначив їх проведеними: їх треба закрити, інакше не нарахується оплата праці. Спочатку найсвіжіші.$t$,
 $t$Із 118 минулих занять 86 не закрито — у навчальній копії відмітки ведуться не за всіма заняттями. `LIMIT 10` показує першу «сторінку» списку.$t$,
 $q$SELECT lesson_date AS дата, to_char(start_time, 'HH24:MI') AS час,
       format AS формат, theme AS тема
FROM lesson
WHERE lesson_date < DATE '2026-11-12'
  AND NOT completed
ORDER BY lesson_date DESC, start_time
LIMIT 10;$q$,
 $q$SELECT lesson_date AS дата, to_char(start_time, 'HH24:MI') AS час,
       format AS формат, theme AS тема
FROM lesson
WHERE lesson_date < DATE '2026-11-12'
  AND NOT completed
ORDER BY lesson_date DESC, start_time
LIMIT 10$q$),
(6, '4.6', 'simple', $t$Прості запити: WHERE, ORDER BY, DISTINCT$t$, $t$Батьки без входу в кабінет$t$, $t$Батьки, які жодного разу не входили в кабінет, не бачать відвідування й залишку абонемента. Отримати список для розсилки інструкції зі входу.$t$,
 $t$Відсутність значення перевіряється лише `IS NULL`; умова `last_login_at = NULL` дає UNKNOWN для кожного рядка й повертає 0 рядків (контрольне питання 3). Таких батьків 49 із 52.$t$,
 $q$SELECT last_name AS прізвище, first_name AS ім_я, phone AS телефон
FROM parent
WHERE active
  AND last_login_at IS NULL
ORDER BY last_name, first_name
LIMIT 10;$q$,
 $q$SELECT last_name AS прізвище, first_name AS ім_я, phone AS телефон
FROM parent
WHERE active
  AND last_login_at IS NULL
ORDER BY last_name, first_name
LIMIT 10$q$),
(7, '4.7', 'join', $t$З’єднання трьох і більше таблиць$t$, $t$Розклад дня з викладачами$t$, $t$Скласти розклад на суботу 14 листопада для рецепції: курс, час, формат, викладач і, якщо є, викладач на заміні.$t$,
 $t$Таблиця `employee` з’єднується двічі під різними псевдонімами: `t` — основний викладач (INNER, він є завжди), `s` — заміна (LEFT, бо заміни зазвичай немає).$t$,
 $q$SELECT to_char(l.start_time, 'HH24:MI') AS час, c.name AS курс, l.format AS формат,
       t.first_name || ' ' || t.last_name AS викладач,
       COALESCE(s.first_name || ' ' || s.last_name, '—') AS заміна
FROM lesson l
JOIN course c        ON c.course_id = l.course_id
JOIN employee t      ON t.employee_id = l.teacher_id
LEFT JOIN employee s ON s.employee_id = l.substitute_id
WHERE l.lesson_date = DATE '2026-11-14'
ORDER BY l.start_time;$q$,
 $q$SELECT to_char(l.start_time, 'HH24:MI') AS час, c.name AS курс, l.format AS формат,
       t.first_name || ' ' || t.last_name AS викладач,
       COALESCE(s.first_name || ' ' || s.last_name, '—') AS заміна
FROM lesson l
JOIN course c        ON c.course_id = l.course_id
JOIN employee t      ON t.employee_id = l.teacher_id
LEFT JOIN employee s ON s.employee_id = l.substitute_id
WHERE l.lesson_date = DATE '2026-11-14'
ORDER BY l.start_time$q$),
(8, '4.8', 'join', $t$З’єднання трьох і більше таблиць$t$, $t$Контакти батьків групи$t$, $t$Заняття VR ІГРОВИЙ 14 листопада переноситься — отримати список учнів групи з контактами батьків для обдзвону.$t$,
 $t$Шість таблиць: шлях заняття → записи на заняття → учень → зв’язок M:N → батьки. Батьки приєднуються LEFT JOIN, щоб учень без записаних батьків не зник зі списку.$t$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень,
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
ORDER BY учень;$q$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень,
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
ORDER BY учень$q$),
(9, '4.9', 'join', $t$З’єднання трьох і більше таблиць$t$, $t$Журнал заняття$t$, $t$Перевірити журнал заняття 3D Tinkercad FIRST 8 листопада: хто був записаний, яка відмітка й оплата, кого забули відмітити і хто не заплатив.$t$,
 $t$LEFT JOIN з `attendance` за складеним ключем (заняття, учень) зберігає записаних, яких не відмічено: у них усі стовпці відмітки NULL. `NULLS FIRST` виводить їх нагору. Двоє присутніх без способу оплати — борг, сума в них — ціна заняття.$t$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень,
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
ORDER BY a.status NULLS FIRST, учень;$q$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень,
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
ORDER BY a.status NULLS FIRST, учень$q$),
(10, '4.10', 'join', $t$З’єднання трьох і більше таблиць$t$, $t$Учні без абонемента$t$, $t$Знайти учнів, які в листопаді ходять на курс без активного абонемента на нього, — їм варто запропонувати абонемент, це вигідніше за разову оплату.$t$,
 $t$Класичний пошук відсутніх зв’язків (контрольне питання 6): LEFT JOIN + `IS NULL` у WHERE. Умова на статус абонемента стоїть в `ON`, а не у WHERE, — інакше LEFT JOIN перетворився б на INNER.$t$,
 $q$SELECT DISTINCT st.last_name || ' ' || st.first_name AS учень, c.name AS курс
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
LIMIT 15;$q$,
 $q$SELECT DISTINCT st.last_name || ' ' || st.first_name AS учень, c.name AS курс
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
LIMIT 15$q$),
(11, '4.11', 'join', $t$З’єднання трьох і більше таблиць$t$, $t$Курси: грудень проти травня$t$, $t$Порівняти, скільки занять кожного курсу заплановано в грудні 2026 і травні 2027, щоб побачити, які групи завершуються до кінця навчального року.$t$,
 $t$FULL JOIN зберігає рядки обох сторін: курс, який є лише в одному місяці, з’являється з нулем в іншому (тут — три курси, яких у травні вже немає). Назву беремо через COALESCE з того боку, де вона є. Ні LEFT, ні RIGHT JOIN поодинці не дали б повної картини (контрольне питання 7).$t$,
 $q$SELECT COALESCE(c1.name, c2.name) AS курс,
       COALESCE(dec.n, 0) AS грудень, COALESCE(may.n, 0) AS травень
FROM (SELECT course_id, count(*) AS n FROM lesson
      WHERE lesson_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31'
      GROUP BY course_id) dec
FULL JOIN (SELECT course_id, count(*) AS n FROM lesson
           WHERE lesson_date BETWEEN DATE '2027-05-01' AND DATE '2027-05-31'
           GROUP BY course_id) may ON may.course_id = dec.course_id
LEFT JOIN course c1 ON c1.course_id = dec.course_id
LEFT JOIN course c2 ON c2.course_id = may.course_id
ORDER BY курс;$q$,
 $q$SELECT COALESCE(c1.name, c2.name) AS курс,
       COALESCE(dec.n, 0) AS грудень, COALESCE(may.n, 0) AS травень
FROM (SELECT course_id, count(*) AS n FROM lesson
      WHERE lesson_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31'
      GROUP BY course_id) dec
FULL JOIN (SELECT course_id, count(*) AS n FROM lesson
           WHERE lesson_date BETWEEN DATE '2027-05-01' AND DATE '2027-05-31'
           GROUP BY course_id) may ON may.course_id = dec.course_id
LEFT JOIN course c1 ON c1.course_id = dec.course_id
LEFT JOIN course c2 ON c2.course_id = may.course_id
ORDER BY курс$q$),
(12, '4.12', 'group', $t$Групування й агрегування: GROUP BY, HAVING$t$, $t$Виручка за місяцями$t$, $t$Бухгалтерії потрібна виручка від разових оплат і списань з абонементів за кожен місяць окремо за способом оплати.$t$,
 $t$Усі неагреговані стовпці SELECT присутні в GROUP BY (контрольне питання 9). Рядки «не оплачено» — присутні учні без оплати: сума в них — ціна заняття, яку ще треба отримати.$t$,
 $q$SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       COALESCE(a.payment_method, 'не оплачено') AS оплата,
       count(*) AS відвідувань,
       sum(a.amount) AS сума
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY місяць, оплата
ORDER BY місяць, сума DESC;$q$,
 $q$SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       COALESCE(a.payment_method, 'не оплачено') AS оплата,
       count(*) AS відвідувань,
       sum(a.amount) AS сума
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY місяць, оплата
ORDER BY місяць, сума DESC$q$),
(13, '4.13', 'group', $t$Групування й агрегування: GROUP BY, HAVING$t$, $t$Навантаження викладачів$t$, $t$Для розрахунку премії: скільки занять провів кожен викладач у жовтні, скільки учнів на них було записано і який середній розмір групи. Показати лише тих, хто провів щонайменше 10 занять.$t$,
 $t$WHERE відбирає рядки (заняття жовтня) до групування, HAVING — групи (викладачів) після нього (контрольне питання 10): викладача з 7 заняттями і суперадміна з 1 заняттям HAVING відкинув. `count(DISTINCT …)` потрібен, бо після з’єднання з записами кожне заняття повторюється стільки разів, скільки в ньому учнів.$t$,
 $q$SELECT e.first_name || ' ' || e.last_name AS викладач,
       count(DISTINCT l.lesson_id) AS занять,
       count(ls.student_id) AS учнемісць,
       round(count(ls.student_id)::numeric / count(DISTINCT l.lesson_id), 1) AS сер_група
FROM lesson l
JOIN employee e ON e.employee_id = l.teacher_id
LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
WHERE l.lesson_date BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
GROUP BY e.employee_id, e.first_name, e.last_name
HAVING count(DISTINCT l.lesson_id) >= 10
ORDER BY занять DESC;$q$,
 $q$SELECT e.first_name || ' ' || e.last_name AS викладач,
       count(DISTINCT l.lesson_id) AS занять,
       count(ls.student_id) AS учнемісць,
       round(count(ls.student_id)::numeric / count(DISTINCT l.lesson_id), 1) AS сер_група
FROM lesson l
JOIN employee e ON e.employee_id = l.teacher_id
LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
WHERE l.lesson_date BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
GROUP BY e.employee_id, e.first_name, e.last_name
HAVING count(DISTINCT l.lesson_id) >= 10
ORDER BY занять DESC$q$),
(14, '4.14', 'group', $t$Групування й агрегування: GROUP BY, HAVING$t$, $t$Найпопулярніші курси$t$, $t$Визначити курси, на які ходить щонайменше 5 різних учнів, — для них варто відкривати додаткові групи.$t$,
 $t$Агрегатну функцію не можна поставити у WHERE: на момент виконання WHERE групи ще не утворено (контрольне питання 2), тому умова на кількість учнів — у HAVING.$t$,
 $q$SELECT c.direction AS напрям, c.name AS курс,
       count(DISTINCT ls.student_id) AS учнів,
       count(DISTINCT l.lesson_id) AS занять
FROM course c
JOIN lesson l          ON l.course_id = c.course_id
JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
GROUP BY c.course_id, c.direction, c.name
HAVING count(DISTINCT ls.student_id) >= 5
ORDER BY учнів DESC;$q$,
 $q$SELECT c.direction AS напрям, c.name AS курс,
       count(DISTINCT ls.student_id) AS учнів,
       count(DISTINCT l.lesson_id) AS занять
FROM course c
JOIN lesson l          ON l.course_id = c.course_id
JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
GROUP BY c.course_id, c.direction, c.name
HAVING count(DISTINCT ls.student_id) >= 5
ORDER BY учнів DESC$q$),
(15, '4.15', 'group', $t$Групування й агрегування: GROUP BY, HAVING$t$, $t$Відвідуваність курсів$t$, $t$Оцінити дисципліну на курсах: частка відміток «був» серед усіх відміток. Враховувати лише курси, де відміток щонайменше 10, щоб частка була показовою.$t$,
 $t$Конструкція `FILTER (WHERE …)` рахує в межах однієї групи кілька підмножин за один прохід — аналог `SUM(CASE WHEN … THEN 1 END)` у MS SQL Server.$t$,
 $q$SELECT c.name AS курс,
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
ORDER BY відсоток DESC;$q$,
 $q$SELECT c.name AS курс,
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
ORDER BY відсоток DESC$q$),
(16, '4.16', 'sub', $t$Підзапити у WHERE, FROM і SELECT$t$, $t$Учні, що випали з розкладу$t$, $t$Знайти активних учнів, які раніше відвідували заняття, але не записані на жодне майбутнє заняття, — адміністратор зателефонує батькам.$t$,
 $t$Обидва підзапити корельовані — посилаються на `st.student_id` зовнішнього запиту і виконуються (логічно) для кожного учня. `EXISTS` зупиняється на першому знайденому рядку (контрольні питання 11, 12).$t$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень, st.phone AS телефон
FROM student st
WHERE st.active
  AND EXISTS (SELECT 1 FROM attendance a
              WHERE a.student_id = st.student_id AND a.status = 'present')
  AND NOT EXISTS (SELECT 1
                  FROM lesson_student ls
                  JOIN lesson l ON l.lesson_id = ls.lesson_id
                  WHERE ls.student_id = st.student_id
                    AND l.lesson_date >= DATE '2026-11-12')
ORDER BY учень;$q$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень, st.phone AS телефон
FROM student st
WHERE st.active
  AND EXISTS (SELECT 1 FROM attendance a
              WHERE a.student_id = st.student_id AND a.status = 'present')
  AND NOT EXISTS (SELECT 1
                  FROM lesson_student ls
                  JOIN lesson l ON l.lesson_id = ls.lesson_id
                  WHERE ls.student_id = st.student_id
                    AND l.lesson_date >= DATE '2026-11-12')
ORDER BY учень$q$),
(17, '4.17', 'sub', $t$Підзапити у WHERE, FROM і SELECT$t$, $t$Розмір груп за курсами$t$, $t$Порівняти наповненість груп курсів: середня, найменша й найбільша кількість учнів на занятті.$t$,
 $t$Похідна таблиця `g` у FROM спочатку рахує учнів на кожному занятті, а зовнішній запит агрегує вже ці кількості — «агрегат від агрегату», який одним GROUP BY не записати (контрольне питання 13).$t$,
 $q$SELECT c.name AS курс,
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
ORDER BY середня DESC;$q$,
 $q$SELECT c.name AS курс,
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
ORDER BY середня DESC$q$),
(18, '4.18', 'sub', $t$Підзапити у WHERE, FROM і SELECT$t$, $t$Використання абонементів$t$, $t$Для кожного активного абонемента показати, скільки занять за ним уже відвідано і коли був останній візит, — щоб помітити «сплячі» абонементи.$t$,
 $t$Скалярні підзапити в SELECT мусять повертати один рядок з одним стовпцем; інакше — помилка `more than one row returned by a subquery` (контрольне питання 14). NULL в останньому стовпці — абонемент куплено, але ще жодного разу не використано.$t$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень,
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
ORDER BY останній_візит NULLS FIRST;$q$,
 $q$SELECT st.last_name || ' ' || st.first_name AS учень,
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
ORDER BY останній_візит NULLS FIRST$q$),
(19, '4.19', 'sub', $t$Підзапити у WHERE, FROM і SELECT$t$, $t$Заняття, переповнені понад середнє$t$, $t$Знайти майбутні заняття, на які записано більше учнів, ніж у середньому на заняття студії, — можливо, потрібен другий викладач.$t$,
 $t$Незалежний (некорельований) підзапит у HAVING обчислюється один раз; він сам містить похідну таблицю у FROM.$t$,
 $q$SELECT l.lesson_date AS дата, to_char(l.start_time, 'HH24:MI') AS час,
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
LIMIT 10;$q$,
 $q$SELECT l.lesson_date AS дата, to_char(l.start_time, 'HH24:MI') AS час,
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
LIMIT 10$q$),
(20, '4.20', 'view', $t$Представлення (VIEW)$t$, $t$v_schedule — розклад$t$, $t$Адміністратор щодня дивиться розклад з назвами курсів, викладачами й кількістю записаних та відмічених учнів. Створити представлення, щоб не писати з’єднання щоразу, і отримати розклад на 14 листопада.$t$,
 $t$Представлення зберігає лише текст запиту: дані щоразу читаються з базових таблиць, тож розклад завжди актуальний. Користувач працює з ним як з таблицею, не знаючи про чотири з’єднання.$t$,
 $q$CREATE OR REPLACE VIEW v_schedule AS
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
ORDER BY start_time;$q$,
 $q$SELECT to_char(start_time, 'HH24:MI') AS час, course AS курс, format AS формат,
       teacher AS викладач, enrolled AS записано, marked AS відмічено
FROM v_schedule
WHERE lesson_date = DATE '2026-11-14'
ORDER BY start_time$q$),
(21, '4.21', 'view', $t$Представлення (VIEW)$t$, $t$v_subscription_status — абонементи$t$, $t$Для нагадувань батькам потрібен стан абонементів: учень, курс, залишок занять, телефони батьків. Створити представлення й отримати активні абонементи із залишком до 2 занять.$t$,
 $t$Представлення приховує від користувача структуру M:N «учень — батьки»: телефони вже зібрано в один рядок. Крім зручності, це й захист: доступ можна дати до представлення, не відкриваючи таблиці `parent` (контрольне питання 15).$t$,
 $q$CREATE OR REPLACE VIEW v_subscription_status AS
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
ORDER BY remaining_lessons, учень;$q$,
 $q$SELECT student AS учень, course AS курс,
       remaining_lessons || ' з ' || total_lessons AS залишок, parent_phones AS телефони
FROM v_subscription_status
WHERE status = 'active' AND remaining_lessons <= 2
ORDER BY remaining_lessons, учень$q$),
(22, '4.22', 'window', $t$Віконні функції$t$, $t$Найактивніші учні курсу$t$, $t$Відзначити трьох найактивніших учнів кожного напряму за кількістю відвідувань. Порівняти нумерацію ROW_NUMBER, RANK і DENSE_RANK при однаковій кількості.$t$,
 $t$PARTITION BY ділить рядки на напрями, як GROUP BY, але не згортає їх. При рівній кількості ROW_NUMBER дає різні номери, RANK — однаковий з пропуском наступного, DENSE_RANK — без пропуску (контрольні питання 18, 19). Фільтр за рангом — лише у зовнішньому запиті: віконні функції обчислюються після WHERE.$t$,
 $q$SELECT напрям, учень, візитів, rn, rnk, drnk
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
ORDER BY напрям, rn;$q$,
 $q$SELECT напрям, учень, візитів, rn, rnk, drnk
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
ORDER BY напрям, rn$q$),
(23, '4.23', 'window', $t$Віконні функції$t$, $t$Наростаюча виручка$t$, $t$Показати виручку студії за тижнями та наростаючий підсумок з початку навчального року — для звіту засновникам.$t$,
 $t$`sum(sum(…)) OVER (ORDER BY …)`: внутрішня сума — агрегат групи (тижня), зовнішня — віконна сума від першого тижня до поточного. GROUP BY зменшив кількість рядків до тижнів, вікно кількість не змінило (контрольне питання 17).$t$,
 $q$SELECT to_char(date_trunc('week', l.lesson_date), 'YYYY-MM-DD') AS тиждень,
       sum(a.amount) AS виручка,
       sum(sum(a.amount)) OVER (ORDER BY date_trunc('week', l.lesson_date)) AS наростаючим
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY date_trunc('week', l.lesson_date)
ORDER BY 1;$q$,
 $q$SELECT to_char(date_trunc('week', l.lesson_date), 'YYYY-MM-DD') AS тиждень,
       sum(a.amount) AS виручка,
       sum(sum(a.amount)) OVER (ORDER BY date_trunc('week', l.lesson_date)) AS наростаючим
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present'
GROUP BY date_trunc('week', l.lesson_date)
ORDER BY 1$q$),
(24, '4.24', 'window', $t$Віконні функції$t$, $t$Частка способу оплати$t$, $t$Яку частку виручки кожного місяця дають картка, готівка й абонементи — щоб вирішити, чи підключати еквайринг на сайті.$t$,
 $t$Вікно `PARTITION BY місяць` дає підсумок місяця поруч із кожним рядком, тож частку рахуємо в тому самому запиті, без підзапиту чи повторного з’єднання.$t$,
 $q$SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       a.payment_method AS оплата,
       sum(a.amount) AS сума,
       round(100 * sum(a.amount) / sum(sum(a.amount)) OVER (PARTITION BY to_char(l.lesson_date, 'YYYY-MM')), 1) AS відсоток
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present' AND a.payment_method IS NOT NULL
GROUP BY місяць, a.payment_method
ORDER BY місяць, сума DESC;$q$,
 $q$SELECT to_char(l.lesson_date, 'YYYY-MM') AS місяць,
       a.payment_method AS оплата,
       sum(a.amount) AS сума,
       round(100 * sum(a.amount) / sum(sum(a.amount)) OVER (PARTITION BY to_char(l.lesson_date, 'YYYY-MM')), 1) AS відсоток
FROM attendance a
JOIN lesson l ON l.lesson_id = a.lesson_id
WHERE a.status = 'present' AND a.payment_method IS NOT NULL
GROUP BY місяць, a.payment_method
ORDER BY місяць, сума DESC$q$);

-- Каталог: усе, крім sql_run
CREATE OR REPLACE FUNCTION public.lab_lr4_catalog()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_agg(json_build_object('id', query_id, 'section', section, 'section_title', section_title,
                                    'title', title, 'task', task, 'note', note, 'sql', sql_text) ORDER BY ord)
  FROM stemik.lab_query;
$$;

-- Виконання запиту з каталогу: лише за номером, лише читання, з обмеженням часу
CREATE OR REPLACE FUNCTION public.lab_lr4_run(p_id text)
RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = stemik, public SET statement_timeout = '5s' AS $$
DECLARE
  v_sql  text;
  v_rows json;
  v_t0   timestamptz := clock_timestamp();
BEGIN
  SELECT sql_run INTO v_sql FROM stemik.lab_query WHERE query_id = p_id;
  IF v_sql IS NULL THEN
    RAISE EXCEPTION 'Невідомий запит: %', p_id;
  END IF;
  EXECUTE format('SELECT coalesce(json_agg(t), ''[]''::json) FROM (%s) t', v_sql) INTO v_rows;
  RETURN json_build_object('id', p_id, 'rows', v_rows, 'count', json_array_length(v_rows),
                           'ms', round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1));
END $$;

-- Підсумок етапу для головної сторінки розділу
CREATE OR REPLACE FUNCTION public.lab_lr4_overview()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_build_object(
    'queries', (SELECT count(*) FROM stemik.lab_query),
    'by_section', (SELECT json_object_agg(section, n) FROM (SELECT section, count(*) n FROM stemik.lab_query GROUP BY section) s),
    'views', (SELECT json_agg(json_build_object('name', c.relname, 'comment', obj_description(c.oid, 'pg_class')) ORDER BY c.relname)
              FROM pg_class c WHERE c.relnamespace = 'stemik'::regnamespace AND c.relkind = 'v'),
    'rows', json_build_object('lesson', (SELECT count(*) FROM lesson), 'attendance', (SELECT count(*) FROM attendance),
                              'lesson_student', (SELECT count(*) FROM lesson_student), 'student', (SELECT count(*) FROM student)));
$$;

REVOKE ALL ON FUNCTION public.lab_lr4_catalog(), public.lab_lr4_run(text), public.lab_lr4_overview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lab_lr4_catalog(), public.lab_lr4_run(text), public.lab_lr4_overview() TO anon, authenticated;
