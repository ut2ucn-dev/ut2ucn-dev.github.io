-- =====================================================================
-- Тестові дані для перевірки фізичної моделі (ЛР №2)
-- Імена та телефони — вигадані.
-- =====================================================================
SET search_path TO stemik;

INSERT INTO employee (email, last_name, first_name, role) VALUES
  ('director@stemik.test', 'Коваленко', 'Ірина',   'superadmin'),
  ('admin@stemik.test',    'Мельник',   'Олег',    'admin'),
  ('3d@stemik.test',       'Шевчук',    'Андрій',  'teacher'),
  ('vr@stemik.test',       'Бондар',    'Марія',   'teacher'),
  ('robo@stemik.test',     'Ткаченко',  'Дмитро',  'teacher');

INSERT INTO course (name, direction, age_min, age_max, online_print_price) VALUES
  ('3D Tinkercad FIRST (9-12)', '3D',   9, 12, 100),
  ('3D Makers FIRST (6-8)',     '3D',   6,  8, 100),
  ('VR РОЗРОБКА (Delightex)',   'VR',   9, 14, NULL),
  ('Robo AI (Ukit 6-8)',        'ROBO', 6,  8, NULL),
  ('Robo AI (UGot 9-12)',       'ROBO', 9, 12, NULL);

-- Тарифи: для кожного курсу — шість типів (ЗП / ціна / ціна абонемента)
INSERT INTO tariff (course_id, tariff_type, teacher_pay, lesson_price, subscription_price)
SELECT c.course_id, t.tariff_type, t.pay, t.price, t.sub
FROM course c
CROSS JOIN (VALUES
  ('group_1',           250, 450, 1600),
  ('group_2_6',         350, 400, 1440),
  ('individual',        300, 600, 2200),
  ('individual_online', 250, 500, 1800),
  ('group_online',      300, 350, 1200),
  ('extra_service',      50, 150, NULL)
) AS t(tariff_type, pay, price, sub);

INSERT INTO parent (phone, last_name, first_name, last_login_at) VALUES
  ('380501112233', 'Литвиненко', 'Олена',   now() - interval '2 days'),
  ('380671234567', 'Литвиненко', 'Андрій',  NULL),
  ('380931002030', 'Савченко',   'Наталія', now() - interval '5 hours'),
  ('380661234000', 'Кравчук',    'Сергій',  NULL);

INSERT INTO parent_credential (parent_id, password_hash)
SELECT parent_id, '$2a$10$demo.hash.only.for.lab.' || left(parent_id::text, 8)
FROM parent WHERE last_login_at IS NOT NULL;

INSERT INTO student (last_name, first_name, birthday, phone, notes, created_by) VALUES
  ('Литвиненко', 'Максим',   '2015-03-14', '+380501112233', 'Любить роботів',
     (SELECT employee_id FROM employee WHERE role = 'admin')),
  ('Литвиненко', 'Софія',    '2018-09-02', '+380501112233', NULL,
     (SELECT employee_id FROM employee WHERE role = 'admin')),
  ('Савченко',   'Артем',    '2014-11-21', '+380931002030', 'Алергія на арахіс',
     (SELECT employee_id FROM employee WHERE role = 'admin')),
  ('Кравчук',    'Вероніка', '2016-05-30', '+380661234000', NULL,
     (SELECT employee_id FROM employee WHERE role = 'admin')),
  ('Гончаренко', 'Тимофій',  '2013-01-08', '+380978880011', 'Пробне заняття',
     (SELECT employee_id FROM employee WHERE role = 'superadmin'));

INSERT INTO parent_student (parent_id, student_id, relation)
SELECT p.parent_id, s.student_id,
       CASE p.first_name WHEN 'Андрій' THEN 'father' WHEN 'Сергій' THEN 'father' ELSE 'mother' END
FROM parent p JOIN student s ON s.last_name = p.last_name;

-- Заняття: тиждень розкладу
INSERT INTO lesson (course_id, teacher_id, lesson_date, start_time, duration_minutes,
                    format, room, theme, completed)
SELECT c.course_id, e.employee_id, v.d::date, v.t::time, v.dur, v.fmt, v.room, v.theme, v.done
FROM (VALUES
  ('3D Tinkercad FIRST (9-12)', '3d@stemik.test',   '2026-10-19', '16:00', 60, 'group',             'Клас 3D',            'Брелок з ініціалами',       TRUE),
  ('3D Tinkercad FIRST (9-12)', '3d@stemik.test',   '2026-10-26', '16:00', 60, 'group',             'Клас 3D',            'Підставка для телефону',    TRUE),
  ('Robo AI (Ukit 6-8)',        'robo@stemik.test', '2026-10-20', '17:00', 60, 'group',             'Клас AI',            'Робот-сортувальник',        TRUE),
  ('VR РОЗРОБКА (Delightex)',   'vr@stemik.test',   '2026-10-21', '15:30', 90, 'individual',        'Клас VR',            'Перша VR-сцена',            TRUE),
  ('3D Makers FIRST (6-8)',     '3d@stemik.test',   '2026-10-22', '14:00', 45, 'individual_online', NULL,                 'Іграшка-динозавр',          TRUE),
  ('Robo AI (UGot 9-12)',       'robo@stemik.test', '2026-10-28', '17:00', 60, 'group',             'Комп''ютерний клас', 'Лінійний датчик',           FALSE)
) AS v(course, teacher, d, t, dur, fmt, room, theme, done)
JOIN course c   ON c.name  = v.course
JOIN employee e ON e.email = v.teacher;

-- Заміна: заняття 28.10 веде інший викладач
UPDATE lesson SET substitute_id = (SELECT employee_id FROM employee WHERE email = '3d@stemik.test')
WHERE lesson_date = '2026-10-28';

-- «Заморожена» ЗП та ціна заняття за тарифом (у проєкті це робить тригер)
UPDATE lesson l SET payroll_amount = t.teacher_pay, price_amount = t.lesson_price
FROM tariff t
WHERE t.course_id = l.course_id
  AND t.tariff_type = CASE l.format WHEN 'group' THEN 'group_2_6' ELSE l.format END;

-- Запис учнів на заняття
INSERT INTO lesson_student (lesson_id, student_id)
SELECT l.lesson_id, s.student_id
FROM lesson l
JOIN (VALUES
  ('2026-10-19', 'Максим'), ('2026-10-19', 'Артем'), ('2026-10-19', 'Тимофій'),
  ('2026-10-26', 'Максим'), ('2026-10-26', 'Артем'),
  ('2026-10-20', 'Софія'),  ('2026-10-20', 'Вероніка'),
  ('2026-10-21', 'Артем'),
  ('2026-10-22', 'Софія'),
  ('2026-10-28', 'Максим'), ('2026-10-28', 'Тимофій')
) AS v(d, first_name) ON l.lesson_date = v.d::date
JOIN student s ON s.first_name = v.first_name;

-- Абонементи
INSERT INTO subscription (student_id, course_id, total_lessons, remaining_lessons,
                          total_price, payment_method, purchased_at, purchased_by)
SELECT s.student_id, c.course_id, 4, v.rem, 1440, v.pm, v.d::date,
       (SELECT employee_id FROM employee WHERE role = 'admin')
FROM (VALUES
  ('Максим', '3D Tinkercad FIRST (9-12)', 2, 'card', '2026-10-19'),
  ('Софія',  'Robo AI (Ukit 6-8)',        3, 'cash', '2026-10-20')
) AS v(first_name, course, rem, pm, d)
JOIN student s ON s.first_name = v.first_name
JOIN course  c ON c.name = v.course;

-- Відвідування та оплата
INSERT INTO attendance (lesson_id, student_id, status, payment_method, amount,
                        discount_percent, subscription_id, print_enabled, marked_by)
SELECT ls.lesson_id, ls.student_id, v.st, v.pm,
       CASE WHEN v.st = 'present' AND v.pm IS NOT NULL AND v.pm <> 'subscription'
            THEN l.price_amount * (100 - v.disc) / 100 ELSE 0 END,
       v.disc,
       CASE WHEN v.pm = 'subscription' THEN
         (SELECT sb.subscription_id FROM subscription sb
          WHERE sb.student_id = ls.student_id AND sb.course_id = l.course_id) END,
       v.pr,
       (SELECT employee_id FROM employee WHERE role = 'admin')
FROM lesson_student ls
JOIN lesson  l ON l.lesson_id = ls.lesson_id
JOIN student s ON s.student_id = ls.student_id
JOIN (VALUES
  ('2026-10-19', 'Максим',   'present', 'subscription', 0,  FALSE),
  ('2026-10-19', 'Артем',    'present', 'card',         0,  FALSE),
  ('2026-10-19', 'Тимофій',  'present', 'certificate',  100, FALSE),
  ('2026-10-26', 'Максим',   'present', 'subscription', 0,  FALSE),
  ('2026-10-26', 'Артем',    'excused', NULL,           0,  FALSE),
  ('2026-10-20', 'Софія',    'present', 'subscription', 0,  FALSE),
  ('2026-10-20', 'Вероніка', 'present', NULL,           0,  FALSE),
  ('2026-10-21', 'Артем',    'present', 'cash',         10, FALSE),
  ('2026-10-22', 'Софія',    'absent',  NULL,           0,  FALSE)
) AS v(d, first_name, st, pm, disc, pr)
  ON l.lesson_date = v.d::date AND s.first_name = v.first_name;

INSERT INTO printer (name, power_watts, depreciation_per_hour) VALUES
  ('Bambu Lab P1S', 350, 6.00),
  ('Creality K1',   300, 4.00);

INSERT INTO filament (material, color, price_per_kg) VALUES
  ('PLA',  'білий',   650),
  ('PLA',  'червоний',650),
  ('PETG', 'чорний',  780);

-- Роботи учнів (моделі з занять 3D)
INSERT INTO work (lesson_id, student_id, photo_url, is_trial, printed, printed_by,
                  printed_at, printer_id, filament_id, weight_g, print_minutes)
SELECT ls.lesson_id, ls.student_id, 'works-photos/' || left(ls.student_id::text, 8) || '.jpg',
       v.trial, v.printed,
       CASE WHEN v.printed THEN (SELECT employee_id FROM employee WHERE email = '3d@stemik.test') END,
       CASE WHEN v.printed THEN l.lesson_date + time '19:00' END,
       (SELECT printer_id  FROM printer  WHERE name = v.printer),
       (SELECT filament_id FROM filament WHERE material = 'PLA' AND color = v.color),
       v.w, v.m
FROM lesson_student ls
JOIN lesson  l ON l.lesson_id = ls.lesson_id
JOIN student s ON s.student_id = ls.student_id
JOIN (VALUES
  ('2026-10-19', 'Максим',  FALSE, TRUE,  'Bambu Lab P1S', 'червоний', 12.5, 48),
  ('2026-10-19', 'Артем',   FALSE, TRUE,  'Creality K1',   'білий',    9.0,  35),
  ('2026-10-19', 'Тимофій', TRUE,  FALSE, NULL,            NULL,       NULL, NULL),
  ('2026-10-22', 'Софія',   FALSE, FALSE, NULL,            NULL,       NULL, NULL)
) AS v(d, first_name, trial, printed, printer, color, w, m)
  ON l.lesson_date = v.d::date AND s.first_name = v.first_name;

INSERT INTO student_comment (student_id, author_id, body)
SELECT s.student_id, e.employee_id, v.body
FROM (VALUES
  ('Максим', '3d@stemik.test',   'Швидко освоїв Tinkercad, можна давати складніші моделі'),
  ('Артем',  'vr@stemik.test',   'Потрібна допомога з логікою в CoBlocks'),
  ('Софія',  'robo@stemik.test', 'Перевести в групу 9-12 з наступного семестру')
) AS v(first_name, email, body)
JOIN student s  ON s.first_name = v.first_name
JOIN employee e ON e.email = v.email;

INSERT INTO studio_settings (calc_start_date, electricity_tariff, filament_waste_percent, updated_by)
VALUES ('2026-09-01', 4.32, 10, (SELECT employee_id FROM employee WHERE role = 'superadmin'));
