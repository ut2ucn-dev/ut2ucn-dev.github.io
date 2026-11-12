-- =====================================================================
-- Етап ЛР № 3. Зміни структури, які свідомо залишаються після ЛР3
-- (решту демонстрацій ALTER TABLE сайт виконує функцією lab_lr3_demos()
-- з відкатом, а в psql — скриптом lab3/sql/03_alter.sql).
-- =====================================================================
SET search_path TO stemik;

-- Дата прийому на роботу — знадобиться для запитів ЛР № 4
ALTER TABLE employee ADD COLUMN IF NOT EXISTS hire_date DATE NOT NULL DEFAULT DATE '2025-09-01';
-- Телефон учня з пробілами й кодом країни: розширення типу безпечне
ALTER TABLE student ALTER COLUMN phone TYPE VARCHAR(30);
-- Тривалість заняття: SMALLINT → INTEGER з явним перетворенням
ALTER TABLE lesson ALTER COLUMN duration_minutes TYPE INTEGER USING duration_minutes::integer;
