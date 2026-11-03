-- =====================================================================
-- Лабораторна робота №3. Крок 1: створення бази даних
-- Виконується з будь-якої іншої бази (наприклад, postgres):
--   psql -d postgres -f 00_create_database.sql
-- =====================================================================

-- Повторний запуск: спершу прибрати базу, якщо вона вже є
DROP DATABASE IF EXISTS stemik_lab3;

CREATE DATABASE stemik_lab3
    WITH ENCODING   = 'UTF8'
         TEMPLATE   = template0
         LC_COLLATE = 'C.UTF-8'
         LC_CTYPE   = 'C.UTF-8';

COMMENT ON DATABASE stemik_lab3 IS 'STEM-студія «Стемік»: облік занять, відвідувань, оплат і 3D-друку';

-- У PostgreSQL немає оператора USE: до нової бази підключаються окремо
-- (у psql — метакомандою \c stemik_lab3).
