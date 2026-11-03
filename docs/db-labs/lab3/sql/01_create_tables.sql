-- =====================================================================
-- Лабораторна робота №3. Крок 2: створення таблиць (CREATE TABLE)
-- База: stemik_lab3 (PostgreSQL 16). Модель — з лабораторної роботи №2.
--
-- Усі обмеження названо явно, щоб їх можна було змінити чи видалити
-- через ALTER TABLE ... DROP CONSTRAINT <назва>:
--   pk_<таблиця>             первинний ключ
--   fk_<таблиця>_<посилання> зовнішній ключ
--   uq_<таблиця>_<стовпці>   унікальність
--   chk_<таблиця>_<правило>  перевірка CHECK
--
-- Порядок створення — за рівнями залежностей:
--   рівень 0: employee, course, parent, printer, filament
--   рівень 1: tariff, parent_credential, parent_session, student,
--             studio_settings, lesson
--   рівень 2: parent_student, subscription, student_comment, lesson_student
--   рівень 3: attendance, work
--   рівень 4: work_cost
-- Рівень таблиці = 1 + найбільший рівень таблиць, на які вона посилається.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Рівень 0: незалежні таблиці (без зовнішніх ключів)
-- ---------------------------------------------------------------------
CREATE TABLE employee (
    employee_id  UUID         NOT NULL DEFAULT gen_random_uuid(),
    email        VARCHAR(255) NOT NULL,
    last_name    VARCHAR(50)  NOT NULL,
    first_name   VARCHAR(50)  NOT NULL,
    role         VARCHAR(20)  NOT NULL DEFAULT 'teacher',
    active       BOOLEAN      NOT NULL DEFAULT TRUE,
    photo_url    TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_employee       PRIMARY KEY (employee_id),
    CONSTRAINT uq_employee_email UNIQUE (email),
    CONSTRAINT chk_employee_role CHECK (role IN ('teacher', 'admin', 'superadmin'))
);

CREATE TABLE course (
    course_id          SMALLINT      GENERATED ALWAYS AS IDENTITY,
    name               VARCHAR(60)   NOT NULL,
    direction          VARCHAR(10)   NOT NULL,
    age_min            SMALLINT      NOT NULL,
    age_max            SMALLINT      NOT NULL,
    online_print_price NUMERIC(10,2),
    active             BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_course            PRIMARY KEY (course_id),
    CONSTRAINT uq_course_name       UNIQUE (name),
    CONSTRAINT chk_course_direction CHECK (direction IN ('3D', 'VR', 'ROBO')),
    CONSTRAINT chk_course_age       CHECK (age_min BETWEEN 4 AND 18
                                           AND age_max BETWEEN 4 AND 18
                                           AND age_min <= age_max),
    CONSTRAINT chk_course_print     CHECK (online_print_price >= 0)
);

CREATE TABLE parent (
    parent_id      UUID        NOT NULL DEFAULT gen_random_uuid(),
    phone          VARCHAR(15) NOT NULL,
    last_name      VARCHAR(50),
    first_name     VARCHAR(50),
    active         BOOLEAN     NOT NULL DEFAULT TRUE,
    last_login_at  TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_parent        PRIMARY KEY (parent_id),
    CONSTRAINT uq_parent_phone  UNIQUE (phone),
    CONSTRAINT chk_parent_phone CHECK (phone ~ '^[0-9]{10,15}$')
);

CREATE TABLE printer (
    printer_id            SMALLINT     GENERATED ALWAYS AS IDENTITY,
    name                  VARCHAR(60)  NOT NULL,
    power_watts           NUMERIC(6,1) NOT NULL DEFAULT 0,
    depreciation_per_hour NUMERIC(8,2) NOT NULL DEFAULT 0,
    active                BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_printer         PRIMARY KEY (printer_id),
    CONSTRAINT uq_printer_name    UNIQUE (name),
    CONSTRAINT chk_printer_values CHECK (power_watts >= 0 AND depreciation_per_hour >= 0)
);

CREATE TABLE filament (
    filament_id  SMALLINT     GENERATED ALWAYS AS IDENTITY,
    material     VARCHAR(20)  NOT NULL,
    color        VARCHAR(30)  NOT NULL DEFAULT '',
    price_per_kg NUMERIC(8,2) NOT NULL DEFAULT 0,
    active       BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_filament                PRIMARY KEY (filament_id),
    CONSTRAINT uq_filament_material_color UNIQUE (material, color),
    CONSTRAINT chk_filament_price         CHECK (price_per_kg >= 0)
);

-- ---------------------------------------------------------------------
-- Рівень 1: посилаються лише на таблиці рівня 0
-- ---------------------------------------------------------------------
CREATE TABLE tariff (
    tariff_id          INT           GENERATED ALWAYS AS IDENTITY,
    course_id          SMALLINT      NOT NULL,
    tariff_type        VARCHAR(20)   NOT NULL,
    teacher_pay        NUMERIC(10,2) NOT NULL DEFAULT 0,
    lesson_price       NUMERIC(10,2) NOT NULL DEFAULT 0,
    subscription_price NUMERIC(10,2),
    CONSTRAINT pk_tariff             PRIMARY KEY (tariff_id),
    CONSTRAINT fk_tariff_course      FOREIGN KEY (course_id) REFERENCES course (course_id)
                                     ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_tariff_course_type UNIQUE (course_id, tariff_type),
    CONSTRAINT chk_tariff_type       CHECK (tariff_type IN ('group_1', 'group_2_6', 'individual',
                                                            'individual_online', 'group_online',
                                                            'extra_service')),
    CONSTRAINT chk_tariff_money      CHECK (teacher_pay >= 0 AND lesson_price >= 0
                                            AND subscription_price >= 0)
);

CREATE TABLE parent_credential (
    parent_id       UUID        NOT NULL,
    password_hash   TEXT        NOT NULL,
    password_set_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    failed_attempts SMALLINT    NOT NULL DEFAULT 0,
    locked_until    TIMESTAMPTZ,
    CONSTRAINT pk_parent_credential        PRIMARY KEY (parent_id),
    CONSTRAINT fk_parent_credential_parent FOREIGN KEY (parent_id) REFERENCES parent (parent_id)
                                           ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_parent_credential_tries CHECK (failed_attempts >= 0)
);

CREATE TABLE parent_session (
    token_hash    CHAR(64)    NOT NULL,
    parent_id     UUID        NOT NULL,
    client        VARCHAR(20),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_parent_session         PRIMARY KEY (token_hash),
    CONSTRAINT fk_parent_session_parent  FOREIGN KEY (parent_id) REFERENCES parent (parent_id)
                                         ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_parent_session_client CHECK (client IN ('web', 'android', 'ios', 'macos')),
    CONSTRAINT chk_parent_session_expiry CHECK (expires_at > created_at)
);

CREATE TABLE student (
    student_id  UUID        NOT NULL DEFAULT gen_random_uuid(),
    last_name   VARCHAR(50) NOT NULL,
    first_name  VARCHAR(50) NOT NULL,
    birthday    DATE,
    phone       VARCHAR(20),
    notes       TEXT,
    photo_url   TEXT,
    active      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_student          PRIMARY KEY (student_id),
    CONSTRAINT fk_student_employee FOREIGN KEY (created_by) REFERENCES employee (employee_id)
                                   ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_student_birthday CHECK (birthday BETWEEN DATE '2005-01-01' AND CURRENT_DATE)
);

CREATE TABLE studio_settings (
    id                     BOOLEAN      NOT NULL DEFAULT TRUE,
    calc_start_date        DATE,
    electricity_tariff     NUMERIC(6,2) NOT NULL DEFAULT 0,
    filament_waste_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
    updated_by             UUID,
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_studio_settings          PRIMARY KEY (id),
    CONSTRAINT fk_studio_settings_employee FOREIGN KEY (updated_by) REFERENCES employee (employee_id)
                                           ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_studio_settings_single  CHECK (id),
    CONSTRAINT chk_studio_settings_values  CHECK (electricity_tariff >= 0
                                                  AND filament_waste_percent BETWEEN 0 AND 100)
);

CREATE TABLE lesson (
    lesson_id        UUID          NOT NULL DEFAULT gen_random_uuid(),
    course_id        SMALLINT      NOT NULL,
    teacher_id       UUID          NOT NULL,
    substitute_id    UUID,
    series_id        UUID,
    lesson_date      DATE          NOT NULL,
    start_time       TIME,
    duration_minutes SMALLINT      NOT NULL DEFAULT 60,
    format           VARCHAR(20)   NOT NULL DEFAULT 'group',
    room             VARCHAR(30),
    theme            VARCHAR(200)  NOT NULL DEFAULT '',
    extra_service    BOOLEAN       NOT NULL DEFAULT FALSE,
    print_default    BOOLEAN       NOT NULL DEFAULT FALSE,
    completed        BOOLEAN       NOT NULL DEFAULT FALSE,
    payroll_amount   NUMERIC(10,2) NOT NULL DEFAULT 0,
    price_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT pk_lesson             PRIMARY KEY (lesson_id),
    CONSTRAINT fk_lesson_course      FOREIGN KEY (course_id) REFERENCES course (course_id)
                                     ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_lesson_teacher     FOREIGN KEY (teacher_id) REFERENCES employee (employee_id)
                                     ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_lesson_substitute  FOREIGN KEY (substitute_id) REFERENCES employee (employee_id)
                                     ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_lesson_duration   CHECK (duration_minutes BETWEEN 15 AND 240),
    CONSTRAINT chk_lesson_format     CHECK (format IN ('group', 'individual',
                                                       'individual_online', 'group_online')),
    CONSTRAINT chk_lesson_room       CHECK (room IN ('Клас AI', 'Клас VR',
                                                     'Комп''ютерний клас', 'Клас 3D')),
    CONSTRAINT chk_lesson_money      CHECK (payroll_amount >= 0 AND price_amount >= 0),
    CONSTRAINT chk_lesson_substitute CHECK (substitute_id <> teacher_id)
);

-- ---------------------------------------------------------------------
-- Рівень 2
-- ---------------------------------------------------------------------
CREATE TABLE parent_student (
    parent_id   UUID        NOT NULL,
    student_id  UUID        NOT NULL,
    relation    VARCHAR(20) NOT NULL DEFAULT 'parent',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_parent_student          PRIMARY KEY (parent_id, student_id),
    CONSTRAINT fk_parent_student_parent   FOREIGN KEY (parent_id) REFERENCES parent (parent_id)
                                          ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_parent_student_student  FOREIGN KEY (student_id) REFERENCES student (student_id)
                                          ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_parent_student_relation CHECK (relation IN ('mother', 'father', 'parent', 'guardian'))
);

CREATE TABLE subscription (
    subscription_id   UUID          NOT NULL DEFAULT gen_random_uuid(),
    student_id        UUID          NOT NULL,
    course_id         SMALLINT      NOT NULL,
    total_lessons     SMALLINT      NOT NULL DEFAULT 4,
    remaining_lessons SMALLINT      NOT NULL DEFAULT 4,
    total_price       NUMERIC(10,2) NOT NULL DEFAULT 0,
    payment_method    VARCHAR(10),
    status            VARCHAR(10)   NOT NULL DEFAULT 'active',
    purchased_at      DATE          NOT NULL DEFAULT CURRENT_DATE,
    purchased_by      UUID,
    CONSTRAINT pk_subscription           PRIMARY KEY (subscription_id),
    CONSTRAINT fk_subscription_student   FOREIGN KEY (student_id) REFERENCES student (student_id)
                                         ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_subscription_course    FOREIGN KEY (course_id) REFERENCES course (course_id)
                                         ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_subscription_employee  FOREIGN KEY (purchased_by) REFERENCES employee (employee_id)
                                         ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_subscription_lessons  CHECK (total_lessons > 0
                                                AND remaining_lessons BETWEEN 0 AND total_lessons),
    CONSTRAINT chk_subscription_price    CHECK (total_price >= 0),
    CONSTRAINT chk_subscription_payment  CHECK (payment_method IN ('card', 'cash')),
    CONSTRAINT chk_subscription_status   CHECK (status IN ('active', 'completed', 'cancelled'))
);

CREATE TABLE student_comment (
    comment_id  UUID        NOT NULL DEFAULT gen_random_uuid(),
    student_id  UUID        NOT NULL,
    author_id   UUID,
    body        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_student_comment          PRIMARY KEY (comment_id),
    CONSTRAINT fk_student_comment_student  FOREIGN KEY (student_id) REFERENCES student (student_id)
                                           ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_student_comment_employee FOREIGN KEY (author_id) REFERENCES employee (employee_id)
                                           ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_student_comment_body    CHECK (length(trim(body)) > 0)
);

-- ---------------------------------------------------------------------
-- Рівень 2 (продовження): асоціативна таблиця M:N заняття ↔ учень
-- ---------------------------------------------------------------------
CREATE TABLE lesson_student (
    lesson_id   UUID NOT NULL,
    student_id  UUID NOT NULL,
    CONSTRAINT pk_lesson_student         PRIMARY KEY (lesson_id, student_id),
    CONSTRAINT fk_lesson_student_lesson  FOREIGN KEY (lesson_id) REFERENCES lesson (lesson_id)
                                         ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_lesson_student_student FOREIGN KEY (student_id) REFERENCES student (student_id)
                                         ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ---------------------------------------------------------------------
-- Рівень 3: посилаються на запис на заняття (складений FK)
-- ---------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id    UUID          NOT NULL DEFAULT gen_random_uuid(),
    lesson_id        UUID          NOT NULL,
    student_id       UUID          NOT NULL,
    status           VARCHAR(10)   NOT NULL,
    payment_method   VARCHAR(15),
    amount           NUMERIC(10,2) NOT NULL DEFAULT 0,
    discount_percent NUMERIC(5,2)  NOT NULL DEFAULT 0,
    subscription_id  UUID,
    print_enabled    BOOLEAN       NOT NULL DEFAULT FALSE,
    print_price      NUMERIC(10,2),
    marked_by        UUID,
    marked_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT pk_attendance                PRIMARY KEY (attendance_id),
    CONSTRAINT uq_attendance_lesson_student UNIQUE (lesson_id, student_id),
    CONSTRAINT fk_attendance_lesson_student FOREIGN KEY (lesson_id, student_id)
                                            REFERENCES lesson_student (lesson_id, student_id)
                                            ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_attendance_subscription   FOREIGN KEY (subscription_id)
                                            REFERENCES subscription (subscription_id)
                                            ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_attendance_employee       FOREIGN KEY (marked_by) REFERENCES employee (employee_id)
                                            ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_attendance_status        CHECK (status IN ('present', 'absent', 'excused')),
    CONSTRAINT chk_attendance_payment       CHECK (payment_method IN
                                                   ('card', 'cash', 'subscription', 'certificate')),
    CONSTRAINT chk_attendance_money         CHECK (amount >= 0 AND print_price >= 0
                                                   AND discount_percent BETWEEN 0 AND 100),
    CONSTRAINT chk_attendance_only_present  CHECK (status = 'present'
                                                   OR (payment_method IS NULL AND amount = 0)),
    CONSTRAINT chk_attendance_subscription  CHECK (subscription_id IS NULL
                                                   OR payment_method = 'subscription')
);

CREATE TABLE work (
    work_id       UUID         NOT NULL DEFAULT gen_random_uuid(),
    lesson_id     UUID         NOT NULL,
    student_id    UUID         NOT NULL,
    photo_url     TEXT,
    is_trial      BOOLEAN      NOT NULL DEFAULT FALSE,
    printed       BOOLEAN      NOT NULL DEFAULT FALSE,
    printed_by    UUID,
    printed_at    TIMESTAMPTZ,
    printer_id    SMALLINT,
    filament_id   SMALLINT,
    weight_g      NUMERIC(7,1),
    print_minutes SMALLINT,
    CONSTRAINT pk_work                PRIMARY KEY (work_id),
    CONSTRAINT uq_work_lesson_student UNIQUE (lesson_id, student_id),
    CONSTRAINT fk_work_lesson_student FOREIGN KEY (lesson_id, student_id)
                                      REFERENCES lesson_student (lesson_id, student_id)
                                      ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_work_employee       FOREIGN KEY (printed_by) REFERENCES employee (employee_id)
                                      ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_work_printer        FOREIGN KEY (printer_id) REFERENCES printer (printer_id)
                                      ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_work_filament       FOREIGN KEY (filament_id) REFERENCES filament (filament_id)
                                      ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_work_print_inputs  CHECK (weight_g >= 0 AND print_minutes >= 0),
    CONSTRAINT chk_work_printed_by    CHECK (printed OR (printed_by IS NULL AND printed_at IS NULL))
);

-- ---------------------------------------------------------------------
-- Рівень 4: собівартість друку (1:1 з work)
-- ---------------------------------------------------------------------
CREATE TABLE work_cost (
    work_id               UUID          NOT NULL,
    price_per_kg          NUMERIC(8,2),
    waste_percent         NUMERIC(5,2)  NOT NULL DEFAULT 0,
    power_watts           NUMERIC(6,1),
    electricity_tariff    NUMERIC(6,2),
    depreciation_per_hour NUMERIC(8,2),
    material_cost         NUMERIC(10,2) NOT NULL DEFAULT 0,
    electricity_cost      NUMERIC(10,2) NOT NULL DEFAULT 0,
    depreciation_cost     NUMERIC(10,2) NOT NULL DEFAULT 0,
    computed_at           TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT pk_work_cost        PRIMARY KEY (work_id),
    CONSTRAINT fk_work_cost_work   FOREIGN KEY (work_id) REFERENCES work (work_id)
                                   ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_work_cost_input CHECK (price_per_kg >= 0 AND power_watts >= 0
                                          AND electricity_tariff >= 0 AND depreciation_per_hour >= 0
                                          AND waste_percent BETWEEN 0 AND 100),
    CONSTRAINT chk_work_cost_money CHECK (material_cost >= 0 AND electricity_cost >= 0
                                          AND depreciation_cost >= 0)
);
