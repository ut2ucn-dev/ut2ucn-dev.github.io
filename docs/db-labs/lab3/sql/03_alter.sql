-- =====================================================================
-- Лабораторна робота №3. Крок 4: зміна структури таблиць (ALTER TABLE)
-- Виконується на вже заповнених таблицях, щоб показати вплив на дані.
-- Команди, що мають завершитися помилкою, позначено «очікується помилка».
-- =====================================================================
\set ON_ERROR_STOP off
\set VERBOSITY terse

\echo '--- 1. ADD COLUMN без DEFAULT: наявні рядки отримують NULL'
ALTER TABLE student ADD COLUMN school VARCHAR(100);
SELECT count(*) AS students, count(school) AS with_school FROM student;

\echo '--- 2. ADD COLUMN NOT NULL без DEFAULT до заповненої таблиці (очікується помилка)'
ALTER TABLE employee ADD COLUMN hire_date DATE NOT NULL;

\echo '--- 3. ADD COLUMN NOT NULL разом із DEFAULT: значення отримують усі рядки'
ALTER TABLE employee ADD COLUMN hire_date DATE NOT NULL DEFAULT DATE '2025-09-01';
SELECT last_name, hire_date FROM employee ORDER BY last_name LIMIT 4;

\echo '--- 4. ALTER COLUMN TYPE: розширення VARCHAR(20) → VARCHAR(30) безпечне'
ALTER TABLE student ALTER COLUMN phone TYPE VARCHAR(30);

\echo '--- 5. ALTER COLUMN TYPE: звуження VARCHAR(60) → VARCHAR(10) (очікується помилка)'
ALTER TABLE course ALTER COLUMN name TYPE VARCHAR(10);

\echo '--- 6. ALTER COLUMN TYPE з USING: тривалість SMALLINT → INTEGER'
ALTER TABLE lesson ALTER COLUMN duration_minutes TYPE INTEGER USING duration_minutes::integer;
SELECT column_name, data_type, character_maximum_length
FROM information_schema.columns
WHERE (table_name, column_name) IN (('student', 'phone'), ('lesson', 'duration_minutes'),
                                    ('student', 'school'), ('employee', 'hire_date'))
ORDER BY 1;

\echo '--- 7. ADD CONSTRAINT: формат телефону учня +380XXXXXXXXX'
ALTER TABLE student ADD CONSTRAINT chk_student_phone_format CHECK (phone ~ '^\+380[0-9]{9}$');

\echo '--- 8. Перевірка нового обмеження (очікується помилка)'
UPDATE student SET phone = '067 123 45 67' WHERE first_name = 'Максим';

\echo '--- 9. Обмеження, яке порушують наявні дані, не додається (очікується помилка)'
ALTER TABLE student ADD CONSTRAINT chk_student_has_notes CHECK (notes IS NOT NULL);

\echo '--- 10. DROP CONSTRAINT за назвою'
ALTER TABLE student DROP CONSTRAINT chk_student_phone_format;
SELECT conname FROM pg_constraint
WHERE conrelid = 'student'::regclass AND contype = 'c'
ORDER BY 1;

\echo '--- 11. RENAME COLUMN і DROP COLUMN: повертаємо таблицю student до моделі'
ALTER TABLE student RENAME COLUMN school TO school_name;
ALTER TABLE student DROP COLUMN school_name;
