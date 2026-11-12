-- =====================================================================
-- Лабораторна робота №3. Крок 3: наповнення таблиць (INSERT ... SELECT)
--
-- Дані переносяться з поточної схеми (схема public — знеособлена копія
-- робочої бази студії) у нормалізовану модель (схема stemik). Кожен
-- INSERT ... SELECT одночасно розв'язує одну з проблем, знайдених у ЛР1:
--   • 11 написань курсу → довідник course (таблиця відповідностей нижче);
--   • 35 стовпців rate_cards → рядки tariff (розгортання «стовпці → рядки»);
--   • масив lessons.student_ids → таблиця lesson_student (unnest), без
--     ідентифікаторів учнів, яких уже немає;
--   • імена батьків у картці учня → таблиця parent і зв'язок parent_student;
--   • ПІБ одним полем → last_name + first_name;
--   • залишок абонемента більший за пакет → обрізано до розміру пакета;
--   • дублікати робіт учня на тому самому занятті → одна робота.
-- Ідентифікатори UUID зберігаються, тож зв'язки між рядками не губляться.
-- Скрипт виконується після 01_create_tables.sql одною транзакцією.
-- =====================================================================
BEGIN;
SET LOCAL search_path TO stemik, public;

-- ---------------------------------------------------------------------
-- 0. Відповідність назв курсів: як записано в даних → канонічна назва.
--    Канонічні назви — ті 9 курсів, що мають тарифи в rate_cards.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE course_alias (source_name TEXT PRIMARY KEY, canonical TEXT NOT NULL) ON COMMIT DROP;
INSERT INTO course_alias (source_name, canonical)
SELECT DISTINCT x.course,
       CASE x.course
           WHEN 'VR ігровий'         THEN 'VR ІГРОВИЙ'
           WHEN '3D TinkerCad'       THEN '3D Tinkercad FIRST (9-12)'
           WHEN '3D MakersEmpire'    THEN '3D Makers FIRST (6-8)'
           WHEN 'Робототехніка Ukit' THEN 'Robo AI (Ukit 6-8)'
           ELSE x.course
       END
FROM (SELECT course FROM public.lessons
      UNION SELECT course FROM public.subscriptions
      UNION SELECT course FROM public.rate_cards) AS x
WHERE x.course IS NOT NULL;

-- ---------------------------------------------------------------------
-- 1. Довідники
-- ---------------------------------------------------------------------
INSERT INTO stemik.employee (employee_id, email, last_name, first_name, role, active, photo_url, created_at)
SELECT id, email, last_name, first_name, role, active, photo, coalesce(created_at, now())
FROM public.profiles;

INSERT INTO stemik.course (name, direction, age_min, age_max, online_print_price)
SELECT r.course,
       CASE WHEN r.course LIKE '3D%' THEN '3D' WHEN r.course LIKE 'VR%' THEN 'VR' ELSE 'ROBO' END,
       coalesce(substring(r.course FROM '\((\d+)-\d+\)')::smallint,
                CASE r.course WHEN 'VR ІГРОВИЙ' THEN 7 WHEN '3D слайсинг' THEN 10 ELSE 9 END),
       coalesce(substring(r.course FROM '\(\d+-(\d+)\)')::smallint, 14),
       r.price_print_online
FROM public.rate_cards AS r
ORDER BY r.course;

-- Широка таблиця тарифів розгортається в рядки: один стовпець-пара → один рядок
INSERT INTO stemik.tariff (course_id, tariff_type, teacher_pay, lesson_price, subscription_price)
SELECT c.course_id, t.tariff_type, coalesce(t.pay, 0), coalesce(t.price, 0), t.sub
FROM public.rate_cards AS r
JOIN stemik.course AS c ON c.name = r.course
CROSS JOIN LATERAL (VALUES
    ('group_1',           r.zp_group_1,           r.price_group_1,           r.price_sub_group),
    ('group_2_6',         r.zp_group_2_6,         r.price_group_2_6,         r.price_sub_group),
    ('individual',        r.zp_individual,        r.price_individual,        r.price_sub_individual),
    ('individual_online', r.zp_individual_online, r.price_individual_online, r.price_sub_individual_online),
    ('group_online',      r.zp_group_online,      r.price_group_online,      r.price_sub_group_online),
    ('extra_service',     r.zp_extra_service,     r.price_extra_service,     NULL)
) AS t (tariff_type, pay, price, sub);

INSERT INTO stemik.printer (name, power_watts, depreciation_per_hour, active)
SELECT name, power_watts, depreciation_per_hour, active FROM public.printers;

INSERT INTO stemik.filament (material, color, price_per_kg, active)
SELECT material, coalesce(color, ''), price_per_kg, active FROM public.filaments;

-- ---------------------------------------------------------------------
-- 2. Учні, батьки та їхні зв'язки
-- ---------------------------------------------------------------------
INSERT INTO stemik.student (student_id, last_name, first_name, birthday, phone, notes, photo_url,
                            created_by, created_at)
SELECT id,
       split_part(trim(name), ' ', 1),
       coalesce(nullif(trim(substr(trim(name), length(split_part(trim(name), ' ', 1)) + 1)), ''), '—'),
       birthday, nullif(phone, ''), notes, photo, owner_id, coalesce(created_at, now())
FROM public.students;

-- Кабінети батьків, що вже є
INSERT INTO stemik.parent (parent_id, phone, last_name, first_name, active, last_login_at, created_at)
SELECT id, phone,
       nullif(split_part(trim(coalesce(name, '')), ' ', 1), ''),
       nullif(trim(substr(trim(coalesce(name, '')), length(split_part(trim(coalesce(name, '')), ' ', 1)) + 1)), ''),
       active, last_login_at, created_at
FROM public.parent_accounts;

-- Батьки з карток учнів (3НФ): телефон картки — лише цифри; той самий
-- телефон, що вже є в кабінеті, не дублюється
INSERT INTO stemik.parent (phone, last_name, first_name)
SELECT DISTINCT ON (regexp_replace(phone, '\D', '', 'g'))
       regexp_replace(phone, '\D', '', 'g'), nullif(parent_last_name, ''), nullif(parent_first_name, '')
FROM public.students
WHERE (parent_last_name <> '' OR parent_first_name <> '')
  AND regexp_replace(phone, '\D', '', 'g') ~ '^[0-9]{10,15}$'
ORDER BY regexp_replace(phone, '\D', '', 'g'), created_at
ON CONFLICT ON CONSTRAINT uq_parent_phone DO NOTHING;

INSERT INTO stemik.parent_student (parent_id, student_id, relation, created_at)
SELECT parent_id, student_id, 'parent', created_at FROM public.parent_students;

INSERT INTO stemik.parent_student (parent_id, student_id, relation)
SELECT p.parent_id, s.id, 'parent'
FROM public.students AS s
JOIN stemik.parent AS p ON p.phone = regexp_replace(s.phone, '\D', '', 'g')
WHERE s.parent_last_name <> '' OR s.parent_first_name <> ''
ON CONFLICT ON CONSTRAINT pk_parent_student DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. Заняття і запис учнів на них
-- ---------------------------------------------------------------------
INSERT INTO stemik.lesson (lesson_id, course_id, teacher_id, substitute_id, series_id, lesson_date, start_time,
                           duration_minutes, format, room, theme, extra_service, print_default, completed,
                           payroll_amount, price_amount)
SELECT l.id, c.course_id, l.owner_id, l.substitute_owner_id, l.series_id, l.date, nullif(l.time, '')::time,
       l.duration_minutes, l.format, l.room, coalesce(l.theme, ''), l.extra_service, l.print_default, l.completed,
       coalesce(l.payroll_amount, 0), l.price_amount
FROM public.lessons AS l
JOIN course_alias AS a ON a.source_name = l.course
JOIN stemik.course AS c ON c.name = a.canonical;

-- Масив учнів → рядки; додаємо й учнів, що мають відмітку чи роботу на
-- занятті, але відсутні в масиві. Ідентифікатори неіснуючих учнів відкидаються.
INSERT INTO stemik.lesson_student (lesson_id, student_id)
SELECT DISTINCT x.lesson_id, x.student_id
FROM (SELECT l.id AS lesson_id, u.student_id FROM public.lessons AS l, unnest(l.student_ids) AS u (student_id)
      UNION SELECT lesson_id, student_id FROM public.lesson_attendance
      UNION SELECT lesson_id, student_id FROM public.works) AS x
WHERE EXISTS (SELECT 1 FROM stemik.student AS s WHERE s.student_id = x.student_id)
  AND EXISTS (SELECT 1 FROM stemik.lesson AS l WHERE l.lesson_id = x.lesson_id);

-- ---------------------------------------------------------------------
-- 4. Абонементи, відвідування й оплати
-- ---------------------------------------------------------------------
INSERT INTO stemik.subscription (subscription_id, student_id, course_id, total_lessons, remaining_lessons,
                                 total_price, payment_method, status, purchased_at, purchased_by)
SELECT sb.id, sb.student_id, c.course_id, sb.total_lessons,
       least(greatest(sb.remaining_lessons, 0), sb.total_lessons),       -- залишок не більший за пакет
       sb.total_price, sb.payment_method, sb.status, sb.purchased_at::date, sb.purchased_by
FROM public.subscriptions AS sb
JOIN course_alias AS a ON a.source_name = sb.course
JOIN stemik.course AS c ON c.name = a.canonical;

INSERT INTO stemik.attendance (attendance_id, lesson_id, student_id, status, payment_method, amount,
                               discount_percent, subscription_id, print_enabled, print_price, marked_by, marked_at)
SELECT id, lesson_id, student_id, status, payment_method, amount, discount_percent, subscription_id,
       print_enabled, print_price, marked_by, marked_at
FROM public.lesson_attendance;

-- ---------------------------------------------------------------------
-- 5. Роботи учнів і друк
-- ---------------------------------------------------------------------
-- Кілька записів роботи одного учня на тому самому занятті → одна
-- (надрукована, якщо така є, інакше найперша)
INSERT INTO stemik.work (work_id, lesson_id, student_id, photo_url, is_trial, printed, printed_by, printed_at,
                         printer_id, filament_id, weight_g, print_minutes)
SELECT DISTINCT ON (w.lesson_id, w.student_id)
       w.id, w.lesson_id, w.student_id, w.photo, w.trial, w.printed,
       CASE WHEN w.printed THEN (SELECT e.employee_id FROM stemik.employee AS e
                                  WHERE w.printed_by_name IN (e.first_name || ' ' || e.last_name,
                                                              e.last_name || ' ' || e.first_name)
                                  LIMIT 1) END,
       CASE WHEN w.printed THEN w.printed_at END,
       np.printer_id, nf.filament_id, round(w.weight_g, 1), round(w.print_minutes)::smallint
FROM public.works AS w
LEFT JOIN public.printers  AS op ON op.id = w.printer_id
LEFT JOIN stemik.printer   AS np ON np.name = op.name
LEFT JOIN public.filaments AS of ON of.id = w.filament_id
LEFT JOIN stemik.filament  AS nf ON nf.material = of.material AND nf.color = coalesce(of.color, '')
ORDER BY w.lesson_id, w.student_id, w.printed DESC, w.created_at;

INSERT INTO stemik.work_cost (work_id, price_per_kg, waste_percent, power_watts, electricity_tariff,
                              depreciation_per_hour, material_cost, electricity_cost, depreciation_cost, computed_at)
SELECT wc.work_id, wc.price_per_kg, wc.waste_percent, wc.power_watts, wc.electricity_tariff,
       wc.depreciation_per_hour, wc.material_cost, wc.electricity_cost, wc.depreciation_cost, wc.computed_at
FROM public.work_costs AS wc
WHERE EXISTS (SELECT 1 FROM stemik.work AS w WHERE w.work_id = wc.work_id);

-- ---------------------------------------------------------------------
-- 6. Коментарі й налаштування
-- ---------------------------------------------------------------------
INSERT INTO stemik.student_comment (comment_id, student_id, author_id, body, created_at)
SELECT id, student_id, author_id, body, created_at FROM public.student_comments;

INSERT INTO stemik.studio_settings (id, calc_start_date, electricity_tariff, filament_waste_percent,
                                    updated_by, updated_at)
SELECT TRUE, calc_start_date, electricity_tariff, filament_waste_percent, updated_by, updated_at
FROM public.studio_settings;

COMMIT;

-- ---------------------------------------------------------------------
-- Звіт перенесення: скільки рядків було в поточній схемі і скільки стало
-- в моделі
-- ---------------------------------------------------------------------
SELECT x.source AS "поточна схема", x.src AS "рядків", x.target AS "модель", x.dst AS "рядків", x.note AS "примітка"
FROM (VALUES
  (1,  'profiles',                (SELECT count(*) FROM public.profiles),          'employee',        (SELECT count(*) FROM stemik.employee),        ''),
  (2,  'назви курсів (різні)',    (SELECT count(*) FROM (SELECT course FROM public.lessons UNION SELECT course FROM public.subscriptions) x WHERE course IS NOT NULL),
                                                                                   'course',          (SELECT count(*) FROM stemik.course),          'написання зведено до 9 курсів'),
  (3,  'rate_cards',              (SELECT count(*) FROM public.rate_cards),        'tariff',          (SELECT count(*) FROM stemik.tariff),          '9 курсів × 6 типів тарифу'),
  (4,  'students',                (SELECT count(*) FROM public.students),          'student',         (SELECT count(*) FROM stemik.student),         'ПІБ розділено на два поля'),
  (5,  'parent_accounts',         (SELECT count(*) FROM public.parent_accounts),   'parent',          (SELECT count(*) FROM stemik.parent),          '+ батьки з карток учнів'),
  (6,  'parent_students',         (SELECT count(*) FROM public.parent_students),   'parent_student',  (SELECT count(*) FROM stemik.parent_student),  '+ зв''язки з карток учнів'),
  (7,  'lessons',                 (SELECT count(*) FROM public.lessons),           'lesson',          (SELECT count(*) FROM stemik.lesson),          ''),
  (8,  'lessons.student_ids (id)',(SELECT count(*) FROM public.lessons, unnest(student_ids)),
                                                                                   'lesson_student',  (SELECT count(*) FROM stemik.lesson_student),  'без неіснуючих учнів, + учні з відміток і робіт'),
  (9,  'lesson_attendance',       (SELECT count(*) FROM public.lesson_attendance), 'attendance',      (SELECT count(*) FROM stemik.attendance),      ''),
  (10, 'subscriptions',           (SELECT count(*) FROM public.subscriptions),     'subscription',    (SELECT count(*) FROM stemik.subscription),    'залишок обрізано до пакета'),
  (11, 'works',                   (SELECT count(*) FROM public.works),             'work',            (SELECT count(*) FROM stemik.work),            'дублікати об''єднано'),
  (12, 'printers / filaments',    (SELECT count(*) FROM public.printers) + (SELECT count(*) FROM public.filaments),
                                                                                   'printer / filament', (SELECT count(*) FROM stemik.printer) + (SELECT count(*) FROM stemik.filament), ''),
  (13, 'student_comments',        (SELECT count(*) FROM public.student_comments),  'student_comment', (SELECT count(*) FROM stemik.student_comment), ''),
  (14, 'studio_settings',         (SELECT count(*) FROM public.studio_settings),   'studio_settings', (SELECT count(*) FROM stemik.studio_settings), '')
) AS x (n, source, src, target, dst, note)
ORDER BY x.n;
