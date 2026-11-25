-- =====================================================================
-- Стемік · ЛР3 наживо в Supabase SQL Editor — «пісочниця» demo.
-- Усі команди працюють з окремою схемою demo і НЕ зачіпають дані CRM
-- (схема stemik). Виконуйте ПО ОДНІЙ команді: виділіть її → Run.
-- Повна прибирання в кінці: DROP SCHEMA demo CASCADE;
-- =====================================================================

-- ---------- П.1  «База даних» ----------
-- У Supabase одна база на проєкт, тож замість CREATE DATABASE — окрема схема.
CREATE SCHEMA demo;

-- ---------- П.2  CREATE TABLE: спочатку батьківська, потім дочірня ----------
CREATE TABLE demo.course (
    course_id  SMALLINT    GENERATED ALWAYS AS IDENTITY,
    name       VARCHAR(60) NOT NULL,
    direction  VARCHAR(10) NOT NULL,
    age_min    SMALLINT    NOT NULL DEFAULT 6,
    CONSTRAINT pk_course           PRIMARY KEY (course_id),
    CONSTRAINT uq_course_name      UNIQUE (name),
    CONSTRAINT chk_course_direction CHECK (direction IN ('3D', 'VR', 'ROBO'))
);

CREATE TABLE demo.lesson (
    lesson_id   INT           GENERATED ALWAYS AS IDENTITY,
    course_id   SMALLINT      NOT NULL,
    lesson_date DATE          NOT NULL,
    theme       VARCHAR(200)  NOT NULL DEFAULT '',
    price       NUMERIC(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT pk_lesson        PRIMARY KEY (lesson_id),
    CONSTRAINT fk_lesson_course FOREIGN KEY (course_id) REFERENCES demo.course (course_id)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_lesson_price CHECK (price >= 0)
);

-- Таблиці й обмеження схеми demo
SELECT conrelid::regclass AS таблиця, conname AS обмеження, pg_get_constraintdef(oid) AS визначення
FROM pg_constraint WHERE connamespace = 'demo'::regnamespace ORDER BY 1, 2;

-- ---------- П.4  INSERT ----------
-- а) явний перелік стовпців, без course_id (його генерує IDENTITY)
INSERT INTO demo.course (name, direction, age_min)
VALUES ('3D Makers FIRST (6-8)', '3D', 6),
       ('VR ІГРОВИЙ', 'VR', 7);

-- б) спроба вказати значення автоінкремента → помилка
INSERT INTO demo.course (course_id, name, direction) VALUES (100, 'Тест', '3D');

-- в) INSERT … SELECT: решта курсів і заняття листопада з реальної бази студії
INSERT INTO demo.course (name, direction, age_min)
SELECT name, direction, age_min FROM stemik.course
WHERE name NOT IN (SELECT name FROM demo.course);

INSERT INTO demo.lesson (course_id, lesson_date, theme, price)
SELECT dc.course_id, l.lesson_date, l.theme, l.price_amount
FROM stemik.lesson l
JOIN stemik.course c ON c.course_id = l.course_id
JOIN demo.course dc  ON dc.name = c.name
WHERE l.lesson_date BETWEEN DATE '2026-11-01' AND DATE '2026-11-30';

SELECT (SELECT count(*) FROM demo.course) AS курсів, (SELECT count(*) FROM demo.lesson) AS занять;

-- ---------- П.3  ALTER TABLE ----------
-- а) новий стовпець без DEFAULT: у наявних рядках — NULL
ALTER TABLE demo.lesson ADD COLUMN room VARCHAR(30);
SELECT lesson_id, theme, room FROM demo.lesson LIMIT 3;

-- б) NOT NULL без DEFAULT на заповненій таблиці → помилка
ALTER TABLE demo.lesson ADD COLUMN completed BOOLEAN NOT NULL;
-- … з DEFAULT — працює: наявні рядки отримують false
ALTER TABLE demo.lesson ADD COLUMN completed BOOLEAN NOT NULL DEFAULT false;

-- в) зміна типу: звузити VARCHAR, коли є довші значення → помилка; розширити — можна
ALTER TABLE demo.lesson ALTER COLUMN theme TYPE VARCHAR(5);
ALTER TABLE demo.lesson ALTER COLUMN theme TYPE VARCHAR(300);

-- г) додати / видалити обмеження (за ІМЕНЕМ)
ALTER TABLE demo.lesson ADD CONSTRAINT chk_lesson_room CHECK (room IN ('Клас AI', 'Клас VR', 'Клас 3D'));
ALTER TABLE demo.lesson DROP CONSTRAINT chk_lesson_price;

-- ---------- П.5  UPDATE і DELETE з WHERE ----------
-- спершу SELECT з тією самою умовою — переконатися, що зачепимо саме ці рядки
SELECT lesson_id, lesson_date, price FROM demo.lesson
WHERE course_id = (SELECT course_id FROM demo.course WHERE name = 'VR ІГРОВИЙ');

UPDATE demo.lesson SET price = price * 1.10
WHERE course_id = (SELECT course_id FROM demo.course WHERE name = 'VR ІГРОВИЙ')
RETURNING lesson_id, lesson_date, price;

DELETE FROM demo.lesson WHERE lesson_date > DATE '2026-11-25'
RETURNING lesson_id, lesson_date, theme;

-- RESTRICT: курс, на який посилаються заняття, видалити не можна → помилка
DELETE FROM demo.course WHERE name = 'VR ІГРОВИЙ';

-- ---------- П.6  TRUNCATE проти DELETE ----------
-- таблицю, на яку посилається FK, TRUNCATE не очистить → помилка
TRUNCATE TABLE demo.course;

-- DELETE без WHERE: лічильник IDENTITY продовжується
DELETE FROM demo.lesson;
INSERT INTO demo.lesson (course_id, lesson_date) VALUES (1, DATE '2026-12-01') RETURNING lesson_id;

-- TRUNCATE … RESTART IDENTITY: таблиця порожня, лічильник — знову з 1
TRUNCATE TABLE demo.lesson RESTART IDENTITY;
INSERT INTO demo.lesson (course_id, lesson_date) VALUES (1, DATE '2026-12-01') RETURNING lesson_id;

-- ---------- П.7  DROP TABLE ----------
-- батьківську таблицю, на яку є FK, видалити не можна → помилка
DROP TABLE demo.course;
-- правильно: спершу дочірню, потім батьківську
DROP TABLE demo.lesson;
DROP TABLE demo.course;

-- ---------- Генерування тестових даних (контрольні питання 21–25) ----------
CREATE TABLE demo.gen (id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, code UUID, course_no INT, price INT);
INSERT INTO demo.gen (code, course_no, price)
SELECT gen_random_uuid(), (g % 9) + 1, 300 + (random() * 300)::int
FROM generate_series(1, 1000) AS g;
SELECT count(*), min(course_no), max(course_no), count(DISTINCT code) FROM demo.gen;

-- ---------- Прибирання ----------
DROP SCHEMA demo CASCADE;
