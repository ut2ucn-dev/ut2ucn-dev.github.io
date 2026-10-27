-- =====================================================================
-- Лабораторна робота №2. Фізична модель БД «STEM-студія "Стемік"»
-- СУБД: PostgreSQL 16 (у робочому проєкті — PostgreSQL у Supabase)
--
-- Порядок створення: спочатку довідники та «батьківські» таблиці,
-- потім таблиці з зовнішніми ключами, асоціативні таблиці — останніми.
-- Скрипт ідемпотентний: перед створенням видаляє схему stemik цілком.
-- =====================================================================

DROP SCHEMA IF EXISTS stemik CASCADE;
CREATE SCHEMA stemik;
SET search_path TO stemik;

-- ---------------------------------------------------------------------
-- 1. Співробітник (у проєкті — public.profiles)
-- ---------------------------------------------------------------------
CREATE TABLE employee (
    employee_id  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email        VARCHAR(255) NOT NULL UNIQUE,
    last_name    VARCHAR(50)  NOT NULL,
    first_name   VARCHAR(50)  NOT NULL,
    role         VARCHAR(20)  NOT NULL DEFAULT 'teacher'
                 CHECK (role IN ('teacher', 'admin', 'superadmin')),
    active       BOOLEAN      NOT NULL DEFAULT TRUE,
    photo_url    TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. Курс (напрямок навчання; у проєкті — текстове поле course)
-- ---------------------------------------------------------------------
CREATE TABLE course (
    course_id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name               VARCHAR(60)   NOT NULL UNIQUE,
    direction          VARCHAR(10)   NOT NULL
                       CHECK (direction IN ('3D', 'VR', 'ROBO')),
    age_min            SMALLINT      NOT NULL CHECK (age_min BETWEEN 4 AND 18),
    age_max            SMALLINT      NOT NULL CHECK (age_max BETWEEN 4 AND 18),
    online_print_price NUMERIC(10,2) CHECK (online_print_price >= 0),
    active             BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT course_age_range_chk CHECK (age_min <= age_max)
);

-- ---------------------------------------------------------------------
-- 3. Тариф (рядок «ЗП / ЦІНА» для пари курс × формат;
--    у проєкті — широка таблиця rate_cards із 30+ стовпцями)
-- ---------------------------------------------------------------------
CREATE TABLE tariff (
    tariff_id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id          SMALLINT      NOT NULL
                       REFERENCES course(course_id)
                       ON DELETE CASCADE ON UPDATE CASCADE,
    tariff_type        VARCHAR(20)   NOT NULL
                       CHECK (tariff_type IN ('group_1', 'group_2_6', 'individual',
                                              'individual_online', 'group_online',
                                              'extra_service')),
    teacher_pay        NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (teacher_pay >= 0),
    lesson_price       NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (lesson_price >= 0),
    subscription_price NUMERIC(10,2) CHECK (subscription_price >= 0),
    UNIQUE (course_id, tariff_type)
);

-- ---------------------------------------------------------------------
-- 4. Батьки (обліковий запис батьківського кабінету; у проєкті —
--    parent_accounts)
-- ---------------------------------------------------------------------
CREATE TABLE parent (
    parent_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    phone          VARCHAR(15) NOT NULL UNIQUE CHECK (phone ~ '^[0-9]{10,15}$'),
    last_name      VARCHAR(50),
    first_name     VARCHAR(50),
    active         BOOLEAN     NOT NULL DEFAULT TRUE,
    last_login_at  TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4a. Облікові дані батьків — зв'язок 1:1 з parent (parent_credentials)
CREATE TABLE parent_credential (
    parent_id       UUID        PRIMARY KEY
                    REFERENCES parent(parent_id)
                    ON DELETE CASCADE ON UPDATE CASCADE,
    password_hash   TEXT        NOT NULL,
    password_set_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    failed_attempts SMALLINT    NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    locked_until    TIMESTAMPTZ
);

-- ---------------------------------------------------------------------
-- 5. Учень (students)
-- ---------------------------------------------------------------------
CREATE TABLE student (
    student_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    last_name   VARCHAR(50) NOT NULL,
    first_name  VARCHAR(50) NOT NULL,
    birthday    DATE        CHECK (birthday BETWEEN DATE '2005-01-01' AND CURRENT_DATE),
    phone       VARCHAR(20),
    notes       TEXT,
    photo_url   TEXT,
    active      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by  UUID        REFERENCES employee(employee_id)
                ON DELETE SET NULL ON UPDATE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5a. Батьки ↔ Учень (M:N; parent_students)
CREATE TABLE parent_student (
    parent_id   UUID        NOT NULL REFERENCES parent(parent_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    student_id  UUID        NOT NULL REFERENCES student(student_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    relation    VARCHAR(20) NOT NULL DEFAULT 'parent'
                CHECK (relation IN ('mother', 'father', 'parent', 'guardian')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (parent_id, student_id)
);

-- ---------------------------------------------------------------------
-- 6. Абонемент (subscriptions) — пакет із N занять одного курсу
-- ---------------------------------------------------------------------
CREATE TABLE subscription (
    subscription_id   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id        UUID          NOT NULL REFERENCES student(student_id)
                      ON DELETE RESTRICT ON UPDATE CASCADE,
    course_id         SMALLINT      NOT NULL REFERENCES course(course_id)
                      ON DELETE RESTRICT ON UPDATE CASCADE,
    total_lessons     SMALLINT      NOT NULL DEFAULT 4 CHECK (total_lessons > 0),
    remaining_lessons SMALLINT      NOT NULL DEFAULT 4,
    total_price       NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total_price >= 0),
    payment_method    VARCHAR(10)   CHECK (payment_method IN ('card', 'cash')),
    status            VARCHAR(10)   NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'completed', 'cancelled')),
    purchased_at      DATE          NOT NULL DEFAULT CURRENT_DATE,
    purchased_by      UUID          REFERENCES employee(employee_id)
                      ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT subscription_remaining_chk CHECK (remaining_lessons BETWEEN 0 AND total_lessons)
);

-- ---------------------------------------------------------------------
-- 7. Заняття (lessons)
-- ---------------------------------------------------------------------
CREATE TABLE lesson (
    lesson_id        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id        SMALLINT      NOT NULL REFERENCES course(course_id)
                     ON DELETE RESTRICT ON UPDATE CASCADE,
    teacher_id       UUID          NOT NULL REFERENCES employee(employee_id)
                     ON DELETE RESTRICT ON UPDATE CASCADE,
    substitute_id    UUID          REFERENCES employee(employee_id)
                     ON DELETE SET NULL ON UPDATE CASCADE,
    series_id        UUID,
    lesson_date      DATE          NOT NULL,
    start_time       TIME,
    duration_minutes SMALLINT      NOT NULL DEFAULT 60
                     CHECK (duration_minutes BETWEEN 15 AND 240),
    format           VARCHAR(20)   NOT NULL DEFAULT 'group'
                     CHECK (format IN ('group', 'individual',
                                       'individual_online', 'group_online')),
    room             VARCHAR(30)   CHECK (room IN ('Клас AI', 'Клас VR',
                                                   'Комп''ютерний клас', 'Клас 3D')),
    theme            VARCHAR(200)  NOT NULL DEFAULT '',
    extra_service    BOOLEAN       NOT NULL DEFAULT FALSE,
    print_default    BOOLEAN       NOT NULL DEFAULT FALSE,
    completed        BOOLEAN       NOT NULL DEFAULT FALSE,
    payroll_amount   NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (payroll_amount >= 0),
    price_amount     NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (price_amount >= 0),
    CONSTRAINT lesson_substitute_chk CHECK (substitute_id IS NULL OR substitute_id <> teacher_id)
);

-- 7a. Заняття ↔ Учень — запис учня на заняття (M:N;
--     у проєкті — масив lessons.student_ids, що порушує 1НФ)
CREATE TABLE lesson_student (
    lesson_id   UUID NOT NULL REFERENCES lesson(lesson_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    student_id  UUID NOT NULL REFERENCES student(student_id)
                ON DELETE RESTRICT ON UPDATE CASCADE,
    PRIMARY KEY (lesson_id, student_id)
);

-- ---------------------------------------------------------------------
-- 8. Відвідування та оплата (lesson_attendance) — 1:1 до запису на заняття
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    lesson_id        UUID          NOT NULL,
    student_id       UUID          NOT NULL,
    status           VARCHAR(10)   NOT NULL
                     CHECK (status IN ('present', 'absent', 'excused')),
    payment_method   VARCHAR(15)   CHECK (payment_method IN
                                   ('card', 'cash', 'subscription', 'certificate')),
    amount           NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
    discount_percent NUMERIC(5,2)  NOT NULL DEFAULT 0
                     CHECK (discount_percent BETWEEN 0 AND 100),
    subscription_id  UUID          REFERENCES subscription(subscription_id)
                     ON DELETE RESTRICT ON UPDATE CASCADE,
    print_enabled    BOOLEAN       NOT NULL DEFAULT FALSE,
    print_price      NUMERIC(10,2) CHECK (print_price >= 0),
    marked_by        UUID          REFERENCES employee(employee_id)
                     ON DELETE SET NULL ON UPDATE CASCADE,
    marked_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (lesson_id, student_id),
    FOREIGN KEY (lesson_id, student_id)
        REFERENCES lesson_student(lesson_id, student_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    -- оплата можлива лише для присутнього учня
    CONSTRAINT attendance_payment_only_present_chk CHECK (status = 'present' OR (payment_method IS NULL AND amount = 0)),
    -- посилання на абонемент — лише при оплаті абонементом
    CONSTRAINT attendance_subscription_payment_chk CHECK (subscription_id IS NULL OR payment_method = 'subscription')
);

-- ---------------------------------------------------------------------
-- 9. Обладнання й матеріали для 3D-друку (printers, filaments)
-- ---------------------------------------------------------------------
CREATE TABLE printer (
    printer_id            SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                  VARCHAR(60)  NOT NULL UNIQUE,
    power_watts           NUMERIC(6,1) NOT NULL DEFAULT 0 CHECK (power_watts >= 0),
    depreciation_per_hour NUMERIC(8,2) NOT NULL DEFAULT 0
                          CHECK (depreciation_per_hour >= 0),
    active                BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE filament (
    filament_id  SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material     VARCHAR(20)  NOT NULL,
    color        VARCHAR(30)  NOT NULL DEFAULT '',
    price_per_kg NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (price_per_kg >= 0),
    active       BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (material, color)
);

-- ---------------------------------------------------------------------
-- 10. Робота учня (works) — фото моделі та дані про її 3D-друк
-- ---------------------------------------------------------------------
CREATE TABLE work (
    work_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    lesson_id     UUID         NOT NULL,
    student_id    UUID         NOT NULL,
    photo_url     TEXT,
    is_trial      BOOLEAN      NOT NULL DEFAULT FALSE,
    printed       BOOLEAN      NOT NULL DEFAULT FALSE,
    printed_by    UUID         REFERENCES employee(employee_id)
                  ON DELETE SET NULL ON UPDATE CASCADE,
    printed_at    TIMESTAMPTZ,
    printer_id    SMALLINT     REFERENCES printer(printer_id)
                  ON DELETE SET NULL ON UPDATE CASCADE,
    filament_id   SMALLINT     REFERENCES filament(filament_id)
                  ON DELETE SET NULL ON UPDATE CASCADE,
    weight_g      NUMERIC(7,1) CHECK (weight_g >= 0),
    print_minutes SMALLINT     CHECK (print_minutes >= 0),
    UNIQUE (lesson_id, student_id),
    FOREIGN KEY (lesson_id, student_id)
        REFERENCES lesson_student(lesson_id, student_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT work_printed_by_chk CHECK (printed OR (printed_by IS NULL AND printed_at IS NULL))
);

-- ---------------------------------------------------------------------
-- 11. Коментар до учня (student_comments)
-- ---------------------------------------------------------------------
CREATE TABLE student_comment (
    comment_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  UUID        NOT NULL REFERENCES student(student_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    author_id   UUID        REFERENCES employee(employee_id)
                ON DELETE SET NULL ON UPDATE CASCADE,
    body        TEXT        NOT NULL CHECK (length(trim(body)) > 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 12. Налаштування студії — таблиця з рівно одним рядком (studio_settings)
-- ---------------------------------------------------------------------
CREATE TABLE studio_settings (
    id                     BOOLEAN       PRIMARY KEY DEFAULT TRUE CHECK (id),
    calc_start_date        DATE,
    electricity_tariff     NUMERIC(6,2)  NOT NULL DEFAULT 0
                           CHECK (electricity_tariff >= 0),
    filament_waste_percent NUMERIC(5,2)  NOT NULL DEFAULT 0
                           CHECK (filament_waste_percent BETWEEN 0 AND 100),
    updated_by             UUID          REFERENCES employee(employee_id)
                           ON DELETE SET NULL ON UPDATE CASCADE,
    updated_at             TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Індекси на зовнішні ключі, за якими найчастіше шукає застосунок
-- ---------------------------------------------------------------------
CREATE INDEX idx_lesson_date            ON lesson(lesson_date);
CREATE INDEX idx_lesson_teacher         ON lesson(teacher_id);
CREATE INDEX idx_lesson_student_student ON lesson_student(student_id);
CREATE INDEX idx_subscription_student   ON subscription(student_id, course_id);
CREATE INDEX idx_parent_student_student ON parent_student(student_id);
CREATE INDEX idx_comment_student        ON student_comment(student_id);

-- ---------------------------------------------------------------------
-- Коментарі до таблиць (відображаються у psql \dt+ та в pgAdmin)
-- ---------------------------------------------------------------------
COMMENT ON TABLE employee          IS 'Співробітники студії: викладачі та адміністратори';
COMMENT ON TABLE course            IS 'Курси (напрямки навчання)';
COMMENT ON TABLE tariff            IS 'Тарифи: ЗП викладача та ціна для клієнта за курсом і форматом';
COMMENT ON TABLE parent            IS 'Батьки — власники батьківського кабінету';
COMMENT ON TABLE parent_credential IS 'Пароль і блокування входу до кабінету батьків (1:1)';
COMMENT ON TABLE student           IS 'Учні студії';
COMMENT ON TABLE parent_student    IS 'Зв''язок M:N батьки — діти';
COMMENT ON TABLE subscription      IS 'Абонементи на пакет занять';
COMMENT ON TABLE lesson            IS 'Заняття за розкладом';
COMMENT ON TABLE lesson_student    IS 'Запис учня на заняття (M:N)';
COMMENT ON TABLE attendance        IS 'Відвідування (П/Н/ВПП) та оплата заняття';
COMMENT ON TABLE printer           IS '3D-принтери';
COMMENT ON TABLE filament          IS 'Пластик (філамент) для 3D-друку';
COMMENT ON TABLE work              IS 'Роботи (моделі) учнів та їх друк';
COMMENT ON TABLE student_comment   IS 'Коментарі викладачів про учня';
COMMENT ON TABLE studio_settings   IS 'Глобальні налаштування студії (один рядок)';
