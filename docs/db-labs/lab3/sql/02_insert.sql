-- =====================================================================
-- Лабораторна робота №3. Крок 3: наповнення таблиць (INSERT)
-- Імена, телефони й адреси — вигадані. Курси — справжні курси студії.
-- Стовпці переліковано явно; первинні ключі IDENTITY та UUID не
-- вказуються — їх генерує СУБД.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Співробітники (10)
-- ---------------------------------------------------------------------
INSERT INTO employee (email, last_name, first_name, role, active) VALUES
    ('director@stemik.test',  'Коваленко', 'Ірина',    'superadmin', TRUE),
    ('admin@stemik.test',     'Мельник',   'Олег',     'admin',      TRUE),
    ('admin2@stemik.test',    'Литвин',    'Юлія',     'admin',      TRUE),
    ('shevchuk@stemik.test',  'Шевчук',    'Андрій',   'teacher',    TRUE),
    ('bondar@stemik.test',    'Бондар',    'Марія',    'teacher',    TRUE),
    ('tkachenko@stemik.test', 'Ткаченко',  'Дмитро',   'teacher',    TRUE),
    ('kravets@stemik.test',   'Кравець',   'Олена',    'teacher',    TRUE),
    ('polishchuk@stemik.test','Поліщук',   'Ігор',     'teacher',    TRUE),
    ('moroz@stemik.test',     'Мороз',     'Катерина', 'teacher',    TRUE),
    ('savchuk@stemik.test',   'Савчук',    'Віктор',   'teacher',    FALSE);

-- ---------------------------------------------------------------------
-- Курси (9 — увесь перелік курсів студії) і тарифи (9 × 6 = 54)
-- ---------------------------------------------------------------------
INSERT INTO course (name, direction, age_min, age_max, online_print_price) VALUES
    ('3D Tinkercad FIRST (9-12)', '3D',    9, 12, 100),
    ('3D Tinkercad PRO (9-12)',   '3D',    9, 12, 100),
    ('3D Makers FIRST (6-8)',     '3D',    6,  8, 100),
    ('3D Makers PRO (6-8)',       '3D',    6,  8, 100),
    ('3D слайсинг',               '3D',   10, 14, 100),
    ('VR ІГРОВИЙ',                'VR',    7, 12, NULL),
    ('VR РОЗРОБКА (Delightex)',   'VR',    9, 14, NULL),
    ('Robo AI (Ukit 6-8)',        'ROBO',  6,  8, NULL),
    ('Robo AI (UGot 9-12)',       'ROBO',  9, 12, NULL);

-- Один INSERT ... SELECT: кожен курс × кожен тип тарифу
INSERT INTO tariff (course_id, tariff_type, teacher_pay, lesson_price, subscription_price)
SELECT c.course_id, t.tariff_type, t.pay, t.price,
       CASE WHEN t.sub IS NOT NULL THEN t.sub + (c.course_id % 3) * 40 END
FROM course AS c
CROSS JOIN (VALUES
    ('group_1',           250, 450, 1600),
    ('group_2_6',         350, 400, 1440),
    ('individual',        300, 600, 2200),
    ('individual_online', 250, 500, 1800),
    ('group_online',      300, 350, 1200),
    ('extra_service',      50, 150, NULL)
) AS t (tariff_type, pay, price, sub);

-- ---------------------------------------------------------------------
-- Обладнання й матеріали для 3D-друку (довідники)
-- ---------------------------------------------------------------------
INSERT INTO printer (name, power_watts, depreciation_per_hour) VALUES
    ('Bambu Lab P1S',   350, 6.00),
    ('Creality K1',     300, 4.00),
    ('Prusa MK4',       240, 5.00);

INSERT INTO filament (material, color, price_per_kg) VALUES
    ('PLA',  'білий',    650),
    ('PLA',  'червоний', 650),
    ('PLA',  'синій',    680),
    ('PETG', 'чорний',   780),
    ('PETG', 'прозорий', 820),
    ('TPU',  'жовтий',   1150);

-- ---------------------------------------------------------------------
-- Батьки (12), паролі (8), сесії входу (6)
-- ---------------------------------------------------------------------
INSERT INTO parent (phone, last_name, first_name, last_login_at) VALUES
    ('380501112233', 'Литвиненко', 'Олена',    '2026-11-01 19:05+02'),
    ('380671234567', 'Литвиненко', 'Андрій',   NULL),
    ('380931002030', 'Савченко',   'Наталія',  '2026-11-02 08:40+02'),
    ('380661234000', 'Кравчук',    'Сергій',   NULL),
    ('380962223344', 'Гончаренко', 'Тетяна',   '2026-10-30 21:15+02'),
    ('380503334455', 'Бойко',      'Ольга',    '2026-10-28 18:00+02'),
    ('380674445566', 'Шевченко',   'Ірина',    '2026-11-02 20:30+02'),
    ('380935556677', 'Романенко',  'Павло',    NULL),
    ('380686667788', 'Олійник',    'Світлана', '2026-10-25 12:10+02'),
    ('380997778899', 'Ковальчук',  'Роман',    NULL),
    ('380638889900', 'Ткачук',     'Людмила',  '2026-11-01 10:00+02'),
    ('380739990011', 'Павленко',   'Оксана',   '2026-10-31 17:45+02');

-- Пароль є лише в тих, хто вже входив у кабінет (хеш — демонстраційний)
INSERT INTO parent_credential (parent_id, password_hash, password_set_at)
SELECT parent_id, '$2a$10$demo.hash.' || right(phone, 4), last_login_at - interval '1 day'
FROM parent
WHERE last_login_at IS NOT NULL;

-- Активні сесії: зберігається лише SHA-256 токена
INSERT INTO parent_session (token_hash, parent_id, client, created_at, last_seen_at, expires_at)
SELECT encode(sha256(convert_to('demo-token-' || p.phone, 'UTF8')), 'hex'),
       p.parent_id, v.client, p.last_login_at, p.last_login_at + interval '20 minutes',
       p.last_login_at + interval '30 days'
FROM parent AS p
JOIN (VALUES ('380501112233', 'android'), ('380931002030', 'web'),
             ('380962223344', 'ios'),     ('380674445566', 'android'),
             ('380638889900', 'web'),     ('380739990011', 'macos')) AS v (phone, client)
  ON v.phone = p.phone;

-- ---------------------------------------------------------------------
-- Учні (15) і зв'язок батьки — діти (14)
-- ---------------------------------------------------------------------
INSERT INTO student (last_name, first_name, birthday, phone, notes, created_by)
SELECT v.last_name, v.first_name, v.birthday::date, v.phone, v.notes,
       (SELECT employee_id FROM employee WHERE email = 'admin@stemik.test')
FROM (VALUES
    ('Литвиненко', 'Максим',     '2015-03-14', '+380501112233', 'Любить роботів'),
    ('Литвиненко', 'Софія',      '2018-09-02', '+380501112233', NULL),
    ('Савченко',   'Артем',      '2014-11-21', '+380931002030', 'Алергія на арахіс'),
    ('Кравчук',    'Вероніка',   '2016-05-30', '+380661234000', NULL),
    ('Гончаренко', 'Тимофій',    '2013-01-08', '+380962223344', 'Прийшов на пробне заняття'),
    ('Бойко',      'Марко',      '2017-07-19', '+380503334455', NULL),
    ('Шевченко',   'Злата',      '2015-12-03', '+380674445566', NULL),
    ('Романенко',  'Остап',      '2014-04-25', '+380935556677', 'Брат у групі VR'),
    ('Олійник',    'Дарина',     '2018-02-11', '+380686667788', NULL),
    ('Ковальчук',  'Назар',      '2016-10-07', '+380997778899', NULL),
    ('Ткачук',     'Мирослава',  '2013-06-16', '+380638889900', NULL),
    ('Павленко',   'Богдан',     '2017-03-29', '+380739990011', NULL),
    ('Кузьменко',  'Ева',        '2015-08-22', '+380679876543', NULL),
    ('Гаврилюк',   'Лев',        '2014-01-30', '+380507654321', 'Ліва рука'),
    ('Марченко',   'Аліна',      '2016-09-14', '+380631237890', NULL)
) AS v (last_name, first_name, birthday, phone, notes);

INSERT INTO parent_student (parent_id, student_id, relation)
SELECT p.parent_id, s.student_id,
       CASE WHEN p.first_name IN ('Андрій', 'Сергій', 'Павло', 'Роман') THEN 'father' ELSE 'mother' END
FROM parent AS p
JOIN student AS s ON s.last_name = p.last_name;

-- ---------------------------------------------------------------------
-- Заняття (15): два тижні жовтня і початок листопада
-- ---------------------------------------------------------------------
INSERT INTO lesson (course_id, teacher_id, lesson_date, start_time, duration_minutes,
                    format, room, theme, completed)
SELECT c.course_id, e.employee_id, v.d::date, v.t::time, v.dur, v.fmt, v.room, v.theme,
       v.d::date < DATE '2026-11-03'
FROM (VALUES
    ('3D Tinkercad FIRST (9-12)', 'shevchuk',  '2026-10-12', '16:00', 60, 'group',             'Клас 3D',            'Брелок з ініціалами'),
    ('Robo AI (Ukit 6-8)',        'tkachenko', '2026-10-13', '17:00', 60, 'group',             'Клас AI',            'Робот-сортувальник'),
    ('VR РОЗРОБКА (Delightex)',   'bondar',    '2026-10-14', '15:30', 90, 'individual',        'Клас VR',            'Перша VR-сцена'),
    ('3D Makers FIRST (6-8)',     'shevchuk',  '2026-10-15', '14:00', 45, 'individual_online', NULL,                 'Іграшка-динозавр'),
    ('3D Tinkercad FIRST (9-12)', 'shevchuk',  '2026-10-19', '16:00', 60, 'group',             'Клас 3D',            'Підставка для телефону'),
    ('Robo AI (Ukit 6-8)',        'tkachenko', '2026-10-20', '17:00', 60, 'group',             'Клас AI',            'Датчик кольору'),
    ('VR ІГРОВИЙ',                'bondar',    '2026-10-21', '16:00', 60, 'group',             'Клас VR',            'Квест у віртуальному музеї'),
    ('Robo AI (UGot 9-12)',       'tkachenko', '2026-10-22', '18:00', 60, 'group',             'Комп''ютерний клас', 'Лінійний датчик'),
    ('3D Tinkercad FIRST (9-12)', 'shevchuk',  '2026-10-26', '16:00', 60, 'group',             'Клас 3D',            'Органайзер для олівців'),
    ('3D Makers PRO (6-8)',       'kravets',   '2026-10-27', '17:00', 60, 'group',             'Клас 3D',            'Будиночок для фігурок'),
    ('3D Tinkercad PRO (9-12)',   'kravets',   '2026-10-28', '15:00', 60, 'individual',        'Клас 3D',            'Шестерні та механізми'),
    ('3D слайсинг',               'shevchuk',  '2026-10-29', '16:30', 60, 'group_online',      NULL,                 'Налаштування підтримок'),
    ('3D Tinkercad FIRST (9-12)', 'shevchuk',  '2026-11-02', '16:00', 60, 'group',             'Клас 3D',            'Іменна табличка'),
    ('Robo AI (UGot 9-12)',       'tkachenko', '2026-11-05', '17:00', 60, 'group',             'Комп''ютерний клас', 'Змагання роботів'),
    ('VR РОЗРОБКА (Delightex)',   'bondar',    '2026-11-06', '15:30', 90, 'individual',        'Клас VR',            'Анімація об''єктів')
) AS v (course, teacher, d, t, dur, fmt, room, theme)
JOIN course   AS c ON c.name  = v.course
JOIN employee AS e ON e.email = v.teacher || '@stemik.test';

-- Заміна: 2 листопада заняття Шевчука веде Кравець
UPDATE lesson
SET substitute_id = (SELECT employee_id FROM employee WHERE email = 'kravets@stemik.test')
WHERE lesson_date = '2026-11-02';

-- ---------------------------------------------------------------------
-- Запис учнів на заняття (48)
-- ---------------------------------------------------------------------
INSERT INTO lesson_student (lesson_id, student_id)
SELECT l.lesson_id, s.student_id
FROM (VALUES
    ('Брелок з ініціалами',        'Максим,Артем,Тимофій,Остап,Лев'),
    ('Робот-сортувальник',         'Софія,Вероніка,Марко,Дарина'),
    ('Перша VR-сцена',             'Артем'),
    ('Іграшка-динозавр',           'Софія'),
    ('Підставка для телефону',     'Максим,Артем,Остап,Лев,Злата'),
    ('Датчик кольору',             'Софія,Вероніка,Марко,Назар'),
    ('Квест у віртуальному музеї', 'Тимофій,Мирослава,Ева,Злата'),
    ('Лінійний датчик',            'Остап,Мирослава,Лев'),
    ('Органайзер для олівців',     'Максим,Артем,Злата,Ева'),
    ('Будиночок для фігурок',      'Марко,Дарина,Богдан,Аліна'),
    ('Шестерні та механізми',      'Тимофій'),
    ('Налаштування підтримок',     'Мирослава,Ева,Лев'),
    ('Іменна табличка',            'Максим,Артем,Остап,Злата,Ева'),
    ('Змагання роботів',           'Остап,Мирослава,Лев'),
    ('Анімація об''єктів',         'Артем')
) AS v (theme, names)
CROSS JOIN LATERAL unnest(string_to_array(v.names, ',')) AS n (first_name)
JOIN lesson  AS l ON l.theme = v.theme
JOIN student AS s ON s.first_name = n.first_name;

-- «Заморожені» ЗП і ціна заняття за тарифом: група з одного учня —
-- тариф group_1, з кількох — group_2_6, інші формати — свій тариф
UPDATE lesson AS l
SET payroll_amount = t.teacher_pay,
    price_amount   = t.lesson_price
FROM tariff AS t
WHERE t.course_id = l.course_id
  AND t.tariff_type = CASE
        WHEN l.format <> 'group' THEN l.format
        WHEN (SELECT count(*) FROM lesson_student ls WHERE ls.lesson_id = l.lesson_id) > 1
             THEN 'group_2_6'
        ELSE 'group_1'
      END;

-- ---------------------------------------------------------------------
-- Абонементи (10). Залишок занять перераховується в кроці 5 (UPDATE).
-- ---------------------------------------------------------------------
INSERT INTO subscription (student_id, course_id, total_price, payment_method, purchased_at, purchased_by)
SELECT s.student_id, c.course_id, t.subscription_price, v.pm, v.d::date,
       (SELECT employee_id FROM employee WHERE email = 'admin@stemik.test')
FROM (VALUES
    ('Максим',    '3D Tinkercad FIRST (9-12)', 'card', '2026-10-12'),
    ('Злата',     '3D Tinkercad FIRST (9-12)', 'cash', '2026-10-19'),
    ('Лев',       '3D Tinkercad FIRST (9-12)', 'card', '2026-10-12'),
    ('Ева',       '3D Tinkercad FIRST (9-12)', 'card', '2026-10-26'),
    ('Софія',     'Robo AI (Ukit 6-8)',        'cash', '2026-10-13'),
    ('Вероніка',  'Robo AI (Ukit 6-8)',        'card', '2026-10-13'),
    ('Марко',     'Robo AI (Ukit 6-8)',        'card', '2026-10-13'),
    ('Остап',     'Robo AI (UGot 9-12)',       'cash', '2026-10-22'),
    ('Мирослава', 'VR ІГРОВИЙ',                'card', '2026-10-21'),
    ('Артем',     'VR РОЗРОБКА (Delightex)',   'card', '2026-10-14')
) AS v (first_name, course, pm, d)
JOIN student AS s ON s.first_name = v.first_name
JOIN course  AS c ON c.name = v.course
JOIN tariff  AS t ON t.course_id = c.course_id AND t.tariff_type = 'group_2_6';

-- ---------------------------------------------------------------------
-- Відвідування (44 — для всіх проведених занять)
-- Статус: винятки зі списку, решта — «присутній».
-- Оплата: абонемент, якщо він є на цей курс; інакше — по колу
-- картка / готівка / картка / сертифікат (залишок від ділення номера рядка).
-- ---------------------------------------------------------------------
INSERT INTO attendance (lesson_id, student_id, status, payment_method, amount,
                        discount_percent, subscription_id, marked_by, marked_at)
SELECT x.lesson_id, x.student_id, x.status,
       x.pm,
       CASE WHEN x.pm IN ('card', 'cash') THEN x.price_amount ELSE 0 END,
       CASE WHEN x.pm = 'certificate' THEN 100 ELSE 0 END,
       CASE WHEN x.pm = 'subscription' THEN x.sub_id END,
       (SELECT employee_id FROM employee WHERE email = 'admin@stemik.test'),
       x.lesson_date + time '20:00'
FROM (
    SELECT ls.lesson_id, ls.student_id, l.lesson_date, l.price_amount, sb.subscription_id AS sub_id,
           COALESCE(ex.status, 'present') AS status,
           CASE
               WHEN COALESCE(ex.status, 'present') <> 'present' THEN NULL
               WHEN ex.status IS NULL AND s.first_name = 'Аліна' THEN NULL   -- борг: не оплачено
               WHEN sb.subscription_id IS NOT NULL THEN 'subscription'
               ELSE (ARRAY['card', 'cash', 'card', 'certificate'])
                    [row_number() OVER (ORDER BY l.lesson_date, s.last_name) % 4 + 1]
           END AS pm
    FROM lesson_student AS ls
    JOIN lesson  AS l ON l.lesson_id = ls.lesson_id
    JOIN student AS s ON s.student_id = ls.student_id
    LEFT JOIN subscription AS sb
           ON sb.student_id = ls.student_id AND sb.course_id = l.course_id
    LEFT JOIN (VALUES
        ('Робот-сортувальник',         'Дарина', 'absent'),
        ('Датчик кольору',             'Назар',  'absent'),
        ('Квест у віртуальному музеї', 'Злата',  'excused'),
        ('Органайзер для олівців',     'Ева',    'excused'),
        ('Іменна табличка',            'Артем',  'absent')
    ) AS ex (theme, first_name, status)
           ON ex.theme = l.theme AND ex.first_name = s.first_name
    WHERE l.completed
) AS x;

-- ---------------------------------------------------------------------
-- Роботи учнів (13) і собівартість друку надрукованих
-- ---------------------------------------------------------------------
INSERT INTO work (lesson_id, student_id, photo_url, is_trial, printed, printed_by, printed_at,
                  printer_id, filament_id, weight_g, print_minutes)
SELECT l.lesson_id, s.student_id,
       'works-photos/' || to_char(l.lesson_date, 'YYYYMMDD') || '-' || s.first_name || '.jpg',
       v.trial, v.printer IS NOT NULL,
       CASE WHEN v.printer IS NOT NULL THEN (SELECT employee_id FROM employee WHERE email = 'shevchuk@stemik.test') END,
       CASE WHEN v.printer IS NOT NULL THEN l.lesson_date + time '19:30' END,
       p.printer_id, f.filament_id, v.w, v.m
FROM (VALUES
    ('Брелок з ініціалами',    'Максим',  FALSE, 'Bambu Lab P1S', 'червоний', 12.5, 48),
    ('Брелок з ініціалами',    'Артем',   FALSE, 'Creality K1',   'білий',     9.0, 35),
    ('Брелок з ініціалами',    'Тимофій', TRUE,  'Bambu Lab P1S', 'синій',    10.2, 40),
    ('Брелок з ініціалами',    'Остап',   FALSE, 'Prusa MK4',     'білий',    11.4, 44),
    ('Брелок з ініціалами',    'Лев',     FALSE, NULL,            NULL,       NULL, NULL),
    ('Підставка для телефону', 'Злата',   FALSE, 'Bambu Lab P1S', 'синій',    38.0, 95),
    ('Підставка для телефону', 'Лев',     FALSE, 'Creality K1',   'червоний', 41.5, 110),
    ('Органайзер для олівців', 'Ева',     FALSE, 'Prusa MK4',     'білий',    55.0, 140),
    ('Органайзер для олівців', 'Максим',  FALSE, NULL,            NULL,       NULL, NULL),
    ('Будиночок для фігурок',  'Марко',   FALSE, 'Bambu Lab P1S', 'червоний', 63.2, 155),
    ('Будиночок для фігурок',  'Богдан',  FALSE, NULL,            NULL,       NULL, NULL),
    ('Шестерні та механізми',  'Тимофій', FALSE, 'Creality K1',   'синій',    27.8, 70),
    ('Іменна табличка',        'Злата',   FALSE, NULL,            NULL,       NULL, NULL)
) AS v (theme, first_name, trial, printer, color, w, m)
JOIN lesson  AS l ON l.theme = v.theme
JOIN student AS s ON s.first_name = v.first_name
LEFT JOIN printer  AS p ON p.name = v.printer
LEFT JOIN filament AS f ON f.material = 'PLA' AND f.color = v.color;

INSERT INTO studio_settings (calc_start_date, electricity_tariff, filament_waste_percent, updated_by)
VALUES ('2026-09-01', 4.32, 10, (SELECT employee_id FROM employee WHERE role = 'superadmin'));

-- матеріал = вага × (1 + відходи) × ціна/кг; електроенергія = кВт × год × тариф;
-- амортизація = год × ставка. Ціни беруться на момент друку (знімок).
INSERT INTO work_cost (work_id, price_per_kg, waste_percent, power_watts, electricity_tariff,
                       depreciation_per_hour, material_cost, electricity_cost, depreciation_cost)
SELECT w.work_id, f.price_per_kg, st.filament_waste_percent, p.power_watts, st.electricity_tariff,
       p.depreciation_per_hour,
       round(w.weight_g / 1000 * (1 + st.filament_waste_percent / 100) * f.price_per_kg, 2),
       round(p.power_watts / 1000 * w.print_minutes / 60 * st.electricity_tariff, 2),
       round(w.print_minutes / 60.0 * p.depreciation_per_hour, 2)
FROM work AS w
JOIN printer  AS p ON p.printer_id  = w.printer_id
JOIN filament AS f ON f.filament_id = w.filament_id
CROSS JOIN studio_settings AS st
WHERE w.printed;

-- ---------------------------------------------------------------------
-- Коментарі викладачів (10)
-- ---------------------------------------------------------------------
INSERT INTO student_comment (student_id, author_id, body, created_at)
SELECT s.student_id, e.employee_id, v.body, v.at::timestamptz
FROM (VALUES
    ('Максим',    'shevchuk',  'Швидко освоїв Tinkercad, можна давати складніші моделі', '2026-10-19 18:00+03'),
    ('Артем',     'bondar',    'Потрібна допомога з логікою в CoBlocks',                 '2026-10-14 17:30+03'),
    ('Софія',     'tkachenko', 'Перевести в групу 9-12 з наступного семестру',            '2026-10-20 18:30+03'),
    ('Тимофій',   'shevchuk',  'Після пробного заняття записався на індивідуальні',       '2026-10-12 18:10+03'),
    ('Злата',     'bondar',    'Пропустила квест через хворобу, домовились на відпрацювання', '2026-10-21 17:20+03'),
    ('Остап',     'tkachenko', 'Лідер команди на змаганнях',                              '2026-10-22 19:15+03'),
    ('Марко',     'kravets',   'Акуратно працює з дрібними деталями',                     '2026-10-27 18:20+03'),
    ('Ева',       'shevchuk',  'Цікавиться слайсингом, порадити курс 3D слайсинг',        '2026-10-26 17:40+03'),
    ('Аліна',     'kravets',   'Батьки обіцяли оплатити заняття 27.10 наступного разу',   '2026-10-27 18:25+03'),
    ('Мирослава', 'shevchuk',  'Добре налаштовує підтримки, допомагає іншим',             '2026-10-29 17:45+03')
) AS v (first_name, teacher, body, at)
JOIN student  AS s ON s.first_name = v.first_name
JOIN employee AS e ON e.email = v.teacher || '@stemik.test';
