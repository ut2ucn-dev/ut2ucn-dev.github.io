# Лабораторні роботи 1–2 з дисципліни «Розробка баз даних»

Предметна область — STEM-студія «Стемік» (база даних цього проєкту).
Бригада: Левченко, Гвоздецька, Ігнатенко.

| Файл | Зміст |
|---|---|
| `Звіт_ЛР1_Розробка_БД.docx` / `.pdf` | ЛР №1: аналіз поточної схеми, опис предметної області, сутності, зв'язки, ER-діаграми, нормалізація |
| `Звіт_ЛР2_Розробка_БД.docx` / `.pdf` | ЛР №2: фізична модель, типи, ключі, обмеження, каскадні дії, DDL, скриншоти БД |
| `Звіт_ЛР3_Розробка_БД.docx` / `.pdf` | ЛР №3: CREATE DATABASE/TABLE, INSERT, ALTER, UPDATE/DELETE, TRUNCATE, DROP, генерування даних |
| `lab3/sql/00…07_*.sql` | Скрипти ЛР №3 (база `stemik_lab3`, 18 таблиць, 86 іменованих обмежень) |
| `lab3/img/` | Скриншоти ЛР №3 |
| `sql/01_schema.sql` | DDL-скрипт фізичної схеми (PostgreSQL 16, схема `stemik`) |
| `sql/02_seed.sql` | Тестові дані |
| `sql/03_constraint_tests.sql` | Перевірка обмежень цілісності та каскадних дій |
| `sql/current/` | Відтворення поточної схеми проєкту: заглушки Supabase, базові таблиці, `apply_project_migrations.sh` (міграції 0001–0022), дамп схеми |
| `diagrams/*.mmd` | Вихідні тексти діаграм (Mermaid) |
| `img/` | Рисунки й скриншоти звіту |

Відтворення бази:

```sh
createdb stemik
psql -d stemik -f sql/01_schema.sql
psql -d stemik -f sql/02_seed.sql
psql -d stemik -f sql/03_constraint_tests.sql
```

Відтворення поточної схеми проєкту:

```sh
createdb stemik_current
sql/current/apply_project_migrations.sh stemik_current
```

Лабораторна робота №3 (база `stemik_lab3`):

```sh
cd lab3/sql
psql -d postgres -f 00_create_database.sql
for f in 01_create_tables.sql 02_insert.sql 03_alter.sql 04_update_delete.sql \
         05_truncate.sql 06_drop.sql 07_generate.sql; do psql -d stemik_lab3 -f "$f"; done
```
