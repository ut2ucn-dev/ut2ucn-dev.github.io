# Стемік — сайт бази даних STEM-студії

Сайт-конструктор: з кожним етапом у ньому вмикаються нові розділи. Номер етапу задається
одним числом у `config.js` (`stage`). Розділи наступних етапів на сайті не показуються зовсім.

| Етап | Розділи сайту | Що показують |
|---|---|---|
| 1 | Огляд, Предметна область | діяльність студії, ролі, ER-діаграма, 18 сутностей, аналіз поточної бази (аномалії) |
| 2 | + Модель даних, Таблиці, Цілісність, DDL-скрипт | фізична схема, зв’язки й каскадні правила, розрив M:N; стовпці, типи, NOT NULL, DEFAULT, PK/FK/UK, CHECK кожної таблиці; перевірка обмежень наживо; DDL-скрипт |

Сайт працює з тим самим проєктом Supabase, що й CRM (**Stemik_bd**), і не заважає їй:
модель етапу 2 лежить в окремій схемі `stemik_model`, а CRM — у схемі `stemik`.

```
studio/
├── index.html, app.js, app.css
├── config.js          ← адреса й ключ Supabase, номер етапу
├── img/               ER-діаграма й фізична схема
├── sql/schema.sql     DDL-скрипт, який показує сайт
└── db/                SQL для розгортання в Supabase (на сайті не показується)
    ├── stage1/        01_current_db_part1…7.sql, 02_site_api.sql
    └── stage2/        01_schema.sql, 02_seed.sql, 03_site_api.sql
```

## 1. База даних (Supabase → проєкт Stemik_bd → SQL Editor)

Кожен файл: **+ New query → відкрити файл у Блокноті → Ctrl+A, Ctrl+C → вставити → Run**.
Текст беріть **з файлу**, а не з чату/месенджера. На вікно про RLS — **Run and enable RLS**.

**Етап 1** — суворо по черзі:

1. `db/stage1/01_current_db_part1.sql` … `01_current_db_part7.sql` — знеособлена копія поточної бази студії (схема `public`);
2. `db/stage1/02_site_api.sql` — функція сайту `site_current_db()`.

Перевірка: `select site_current_db()->'anomalies'->>'student_ids_orphan';` → `41`.

**Етап 2** — суворо по черзі:

1. `db/stage2/01_schema.sql` — фізична модель: схема `stemik_model`, 18 таблиць;
2. `db/stage2/02_seed.sql` — тестові дані (102 рядки);
3. `db/stage2/03_site_api.sql` — функції сайту `site_model()`, `site_integrity_tests()`.

Перевірка: `select count(*) filter (where ok) from site_integrity_tests();` → `10`.

Після кожного етапу CRM має працювати як і раніше: `select crm_ping();` → 52 учні.

> Після етапу 1 у **Authentication → Users** з’являться 8 службових записів
> `user0X@example.test` — це працівники з копії бази, **без паролів**: увійти ними неможливо,
> входу в CRM вони не заважають.

## 2. Файли сайту на GitHub

У репозиторій, де вже лежить CRM, завантажте теку **`studio`** цілком
(**Add file → Upload files** → перетягнути теку → **Commit changes**).

Якщо раніше завантажували теки `labs` і `docs` — вони більше не потрібні, їх можна видалити.

## 3. Налаштування `studio/config.js`

Ті самі адреса й ключ, що в `config.js` CRM, і номер етапу:

```js
window.STEMIK_CONFIG = {
  url: 'https://eiexcdqzwtgagwyvajqt.supabase.co',
  anonKey: 'eyJ…',      // anon (Legacy) або sb_publishable_… — не service_role!
  stage: 2,
};
```

## 4. Відкрити

`https://skywalker345.github.io/stemikprg.github.io/studio/`

У правому верхньому куті зелена позначка «база підключена» означає, що сайт отримав дані з Supabase.
Схеми відкриваються на весь екран кліком.

Вхід на сайт не потрібен: функції `site_*` лише читають структуру бази, а перевірка
цілісності виконує кожну спробу з відкатом — дані не змінюються.
