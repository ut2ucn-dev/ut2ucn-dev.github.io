-- =====================================================================
-- CRM «Стемік» (демоверсія): функції, через які сайт працює з базою.
-- Виконувати після 01_schema.sql, 02_data_1…6.sql, 03_views.sql.
--
-- Схема stemik не відкрита в REST API Supabase: сайт бачить лише функції
-- public.crm_*. Вони SECURITY DEFINER (виконуються з правами власника) і
-- мають фіксований search_path.
--   crm_ping()  — доступна без входу (роль anon): перевірка підключення.
--   решта       — лише після входу (роль authenticated).
-- =====================================================================
SET search_path TO stemik, public;

-- ---------------------------------------------------------------------
-- Хто виконує дію: працівник з e-mail користувача, що увійшов
-- (з JWT, який Supabase передає в request.jwt.claims). Якщо такого
-- працівника немає — перший активний адміністратор.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_actor()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT employee_id FROM employee
  WHERE active
  ORDER BY (lower(email) = lower(coalesce(current_setting('request.jwt.claims', true)::json ->> 'email', ''))) DESC,
           CASE role WHEN 'admin' THEN 1 WHEN 'superadmin' THEN 2 ELSE 3 END, created_at
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------
-- Перевірка підключення (ping): без персональних даних
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_ping()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_build_object(
    'ok', true,
    'server_time', to_char(now() AT TIME ZONE 'Europe/Kyiv', 'YYYY-MM-DD HH24:MI:SS'),
    'database', current_database(),
    'postgres', current_setting('server_version'),
    'tables', (SELECT count(*) FROM pg_class WHERE relnamespace = 'stemik'::regnamespace AND relkind = 'r'),
    'rows', json_build_object(
      'students', (SELECT count(*) FROM student),
      'lessons', (SELECT count(*) FROM lesson),
      'attendance', (SELECT count(*) FROM attendance),
      'subscriptions', (SELECT count(*) FROM subscription)));
$$;

-- ---------------------------------------------------------------------
-- Довідники для випадних списків
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_refs()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_build_object(
    'courses', (SELECT json_agg(json_build_object('id', course_id, 'name', name, 'direction', direction,
                                                  'age', age_min || '–' || age_max) ORDER BY direction, name)
                FROM course WHERE active),
    'teachers', (SELECT json_agg(json_build_object('id', employee_id, 'name', first_name || ' ' || last_name,
                                                   'role', role) ORDER BY role DESC, last_name)
                 FROM employee WHERE active),
    'me', (SELECT json_build_object('id', employee_id, 'name', first_name || ' ' || last_name, 'role', role)
           FROM employee WHERE employee_id = public.crm_actor()));
$$;

-- ---------------------------------------------------------------------
-- Огляд дня для адміністратора
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_dashboard(p_date date DEFAULT CURRENT_DATE)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_build_object(
    'date', p_date,
    'lessons', (SELECT coalesce(json_agg(json_build_object(
                   'lesson_id', lesson_id, 'time', to_char(start_time, 'HH24:MI'), 'course', course,
                   'teacher', teacher, 'substitute', substitute, 'format', format,
                   'enrolled', enrolled, 'marked', marked, 'completed', completed)
                   ORDER BY start_time), '[]')
                FROM v_schedule WHERE lesson_date = p_date),
    'kpi', json_build_object(
      'students', (SELECT count(*) FROM student WHERE active),
      'week_lessons', (SELECT count(*) FROM lesson
                       WHERE lesson_date BETWEEN date_trunc('week', p_date)::date
                                             AND date_trunc('week', p_date)::date + 6),
      'active_subscriptions', (SELECT count(*) FROM subscription WHERE status = 'active'),
      'ending_subscriptions', (SELECT count(*) FROM subscription WHERE status = 'active' AND remaining_lessons <= 1),
      'unpaid_visits', (SELECT count(*) FROM attendance WHERE status = 'present' AND payment_method IS NULL),
      'unpaid_sum', (SELECT coalesce(sum(amount), 0) FROM attendance WHERE status = 'present' AND payment_method IS NULL)));
$$;

-- ---------------------------------------------------------------------
-- ПОШУКОВИЙ ЗАПИТ 1. Пошук учня за фрагментом ПІБ, телефону учня
-- або ПІБ / телефону батьків
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_students(p_q text DEFAULT '', p_active_only boolean DEFAULT true)
RETURNS TABLE (student_id uuid, student text, phone text, parents text, courses text,
               subscriptions text, last_visit date, unpaid bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  WITH params AS (
    SELECT '%' || trim(coalesce(p_q, '')) || '%' AS pattern,
           nullif(regexp_replace(coalesce(p_q, ''), '\D', '', 'g'), '') AS digits
  )
  SELECT s.student_id,
         s.last_name || ' ' || s.first_name,
         s.phone,
         (SELECT string_agg(concat_ws(' ', p.last_name, p.first_name) || ' · ' || p.phone, '; ')
          FROM parent_student ps JOIN parent p ON p.parent_id = ps.parent_id
          WHERE ps.student_id = s.student_id),
         (SELECT string_agg(DISTINCT c.name, ', ')
          FROM lesson_student ls JOIN lesson l ON l.lesson_id = ls.lesson_id
          JOIN course c ON c.course_id = l.course_id
          WHERE ls.student_id = s.student_id AND l.lesson_date >= CURRENT_DATE - 60),
         (SELECT string_agg(c.name || ': ' || sb.remaining_lessons || ' з ' || sb.total_lessons, '; ')
          FROM subscription sb JOIN course c ON c.course_id = sb.course_id
          WHERE sb.student_id = s.student_id AND sb.status = 'active'),
         (SELECT max(l.lesson_date) FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
          WHERE a.student_id = s.student_id AND a.status = 'present'),
         (SELECT count(*) FROM attendance a
          WHERE a.student_id = s.student_id AND a.status = 'present' AND a.payment_method IS NULL)
  FROM student s, params
  WHERE (NOT p_active_only OR s.active)
    AND (s.last_name || ' ' || s.first_name ILIKE params.pattern
         OR s.first_name || ' ' || s.last_name ILIKE params.pattern
         OR (params.digits IS NOT NULL AND regexp_replace(coalesce(s.phone, ''), '\D', '', 'g') LIKE '%' || params.digits || '%')
         OR EXISTS (SELECT 1 FROM parent_student ps JOIN parent p ON p.parent_id = ps.parent_id
                    WHERE ps.student_id = s.student_id
                      AND (concat_ws(' ', p.last_name, p.first_name) ILIKE params.pattern
                           OR (params.digits IS NOT NULL AND p.phone LIKE '%' || params.digits || '%'))))
  ORDER BY s.last_name, s.first_name
  LIMIT 100;
$$;

-- ---------------------------------------------------------------------
-- Картка учня
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_student(p_id uuid)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_build_object(
    'student', json_build_object('student_id', s.student_id, 'last_name', s.last_name, 'first_name', s.first_name,
                                 'phone', s.phone, 'birthday', s.birthday, 'notes', s.notes, 'active', s.active),
    'parents', (SELECT coalesce(json_agg(json_build_object('last_name', p.last_name, 'first_name', p.first_name,
                                 'phone', p.phone, 'relation', ps.relation)), '[]')
                FROM parent_student ps JOIN parent p ON p.parent_id = ps.parent_id WHERE ps.student_id = s.student_id),
    'subscriptions', (SELECT coalesce(json_agg(json_build_object('course', c.name, 'total', sb.total_lessons,
                                 'remaining', sb.remaining_lessons, 'price', sb.total_price, 'status', sb.status,
                                 'purchased_at', sb.purchased_at) ORDER BY sb.purchased_at DESC), '[]')
                      FROM subscription sb JOIN course c ON c.course_id = sb.course_id WHERE sb.student_id = s.student_id),
    'visits', (SELECT coalesce(json_agg(v ORDER BY v.date DESC), '[]') FROM (
                 SELECT l.lesson_date AS date, c.name AS course, a.status, a.payment_method AS payment, a.amount
                 FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id JOIN course c ON c.course_id = l.course_id
                 WHERE a.student_id = s.student_id ORDER BY l.lesson_date DESC LIMIT 15) v),
    'upcoming', (SELECT coalesce(json_agg(u ORDER BY u.date, u.time), '[]') FROM (
                 SELECT l.lesson_id, l.lesson_date AS date, to_char(l.start_time, 'HH24:MI') AS time, c.name AS course
                 FROM lesson_student ls JOIN lesson l ON l.lesson_id = ls.lesson_id JOIN course c ON c.course_id = l.course_id
                 WHERE ls.student_id = s.student_id AND l.lesson_date >= CURRENT_DATE
                 ORDER BY l.lesson_date, l.start_time LIMIT 5) u),
    'comments', (SELECT coalesce(json_agg(json_build_object('body', body, 'created_at', to_char(created_at, 'YYYY-MM-DD'))
                                 ORDER BY created_at DESC), '[]')
                 FROM student_comment WHERE student_id = s.student_id))
  FROM student s WHERE s.student_id = p_id;
$$;

-- ---------------------------------------------------------------------
-- Новий учень / зміна даних учня + батьки (за телефоном, без дублів)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_student_save(
  p_id uuid, p_last_name text, p_first_name text, p_phone text DEFAULT NULL, p_birthday date DEFAULT NULL,
  p_notes text DEFAULT NULL, p_parent_last_name text DEFAULT NULL, p_parent_first_name text DEFAULT NULL,
  p_parent_phone text DEFAULT NULL, p_relation text DEFAULT 'parent')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
DECLARE
  v_id uuid := p_id;
  v_parent uuid;
  v_digits text := nullif(regexp_replace(coalesce(p_parent_phone, ''), '\D', '', 'g'), '');
BEGIN
  IF coalesce(trim(p_last_name), '') = '' OR coalesce(trim(p_first_name), '') = '' THEN
    RAISE EXCEPTION 'Вкажіть прізвище та ім’я учня';
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO student (last_name, first_name, phone, birthday, notes, created_by)
    VALUES (trim(p_last_name), trim(p_first_name), nullif(trim(p_phone), ''), p_birthday, nullif(trim(p_notes), ''), public.crm_actor())
    RETURNING student_id INTO v_id;
  ELSE
    UPDATE student SET last_name = trim(p_last_name), first_name = trim(p_first_name),
                       phone = nullif(trim(p_phone), ''), birthday = p_birthday, notes = nullif(trim(p_notes), '')
    WHERE student_id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Учня не знайдено'; END IF;
  END IF;
  IF v_digits IS NOT NULL THEN
    INSERT INTO parent (phone, last_name, first_name)
    VALUES (v_digits, nullif(trim(p_parent_last_name), ''), nullif(trim(p_parent_first_name), ''))
    ON CONFLICT ON CONSTRAINT uq_parent_phone DO UPDATE
      SET last_name = coalesce(EXCLUDED.last_name, parent.last_name),
          first_name = coalesce(EXCLUDED.first_name, parent.first_name)
    RETURNING parent_id INTO v_parent;
    INSERT INTO parent_student (parent_id, student_id, relation)
    VALUES (v_parent, v_id, coalesce(nullif(p_relation, ''), 'parent'))
    ON CONFLICT ON CONSTRAINT pk_parent_student DO UPDATE SET relation = EXCLUDED.relation;
  END IF;
  RETURN v_id;
END $$;

-- ---------------------------------------------------------------------
-- ПОШУКОВИЙ ЗАПИТ 2. Розклад за період з фільтром курсу й викладача
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_lessons(p_from date, p_to date, p_course smallint DEFAULT NULL, p_teacher uuid DEFAULT NULL)
RETURNS TABLE (lesson_id uuid, lesson_date date, start_time text, course text, teacher text, format text,
               theme text, enrolled bigint, marked bigint, present bigint, completed boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT l.lesson_id, l.lesson_date, to_char(l.start_time, 'HH24:MI'), c.name,
         coalesce(sub.first_name || ' ' || sub.last_name || ' (заміна)', t.first_name || ' ' || t.last_name),
         l.format, l.theme,
         count(ls.student_id),
         count(a.attendance_id),
         count(a.attendance_id) FILTER (WHERE a.status = 'present'),
         l.completed
  FROM lesson l
  JOIN course c          ON c.course_id = l.course_id
  JOIN employee t        ON t.employee_id = l.teacher_id
  LEFT JOIN employee sub ON sub.employee_id = l.substitute_id
  LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
  LEFT JOIN attendance a      ON a.lesson_id = ls.lesson_id AND a.student_id = ls.student_id
  WHERE l.lesson_date BETWEEN p_from AND p_to
    AND (p_course IS NULL OR l.course_id = p_course)
    AND (p_teacher IS NULL OR p_teacher IN (l.teacher_id, l.substitute_id))
  GROUP BY l.lesson_id, c.name, t.first_name, t.last_name, sub.first_name, sub.last_name
  ORDER BY l.lesson_date, l.start_time
  LIMIT 300;
$$;

-- ---------------------------------------------------------------------
-- Журнал заняття: учні, відмітки, залишок абонемента на цей курс
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_lesson(p_id uuid)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_build_object(
    'lesson', json_build_object('lesson_id', l.lesson_id, 'date', l.lesson_date, 'time', to_char(l.start_time, 'HH24:MI'),
              'course_id', l.course_id, 'course', c.name, 'teacher', t.first_name || ' ' || t.last_name,
              'format', l.format, 'theme', l.theme, 'price', l.price_amount, 'completed', l.completed,
              'duration', l.duration_minutes),
    'students', (SELECT coalesce(json_agg(r ORDER BY r.student), '[]') FROM (
       SELECT s.student_id, s.last_name || ' ' || s.first_name AS student,
              a.status, a.payment_method AS payment, a.amount,
              (SELECT sb.remaining_lessons || ' з ' || sb.total_lessons FROM subscription sb
               WHERE sb.student_id = s.student_id AND sb.course_id = l.course_id AND sb.status = 'active'
               ORDER BY sb.purchased_at LIMIT 1) AS subscription
       FROM lesson_student ls
       JOIN student s ON s.student_id = ls.student_id
       LEFT JOIN attendance a ON a.lesson_id = ls.lesson_id AND a.student_id = ls.student_id
       WHERE ls.lesson_id = l.lesson_id) r))
  FROM lesson l
  JOIN course c   ON c.course_id = l.course_id
  JOIN employee t ON t.employee_id = l.teacher_id
  WHERE l.lesson_id = p_id;
$$;

-- ---------------------------------------------------------------------
-- Нове заняття: ціна й оплата викладача — з тарифу курсу
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_lesson_create(
  p_course smallint, p_teacher uuid, p_date date, p_time time, p_duration integer DEFAULT 60,
  p_format text DEFAULT 'group', p_theme text DEFAULT '', p_students uuid[] DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
DECLARE
  v_id uuid;
  v_t tariff%ROWTYPE;
BEGIN
  SELECT * INTO v_t FROM tariff
  WHERE course_id = p_course
    AND tariff_type = CASE p_format WHEN 'group' THEN 'group_2_6' ELSE p_format END;
  INSERT INTO lesson (course_id, teacher_id, lesson_date, start_time, duration_minutes, format, theme,
                      price_amount, payroll_amount)
  VALUES (p_course, p_teacher, p_date, p_time, coalesce(p_duration, 60), coalesce(p_format, 'group'),
          coalesce(p_theme, ''), coalesce(v_t.lesson_price, 0), coalesce(v_t.teacher_pay, 0))
  RETURNING lesson_id INTO v_id;
  INSERT INTO lesson_student (lesson_id, student_id)
  SELECT v_id, x FROM unnest(coalesce(p_students, '{}')) AS x
  ON CONFLICT DO NOTHING;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.crm_lesson_add_student(p_lesson uuid, p_student uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = stemik, public AS $$
  INSERT INTO lesson_student (lesson_id, student_id) VALUES (p_lesson, p_student) ON CONFLICT DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION public.crm_lesson_complete(p_lesson uuid, p_completed boolean DEFAULT true)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = stemik, public AS $$
  UPDATE lesson SET completed = p_completed WHERE lesson_id = p_lesson;
$$;

-- ---------------------------------------------------------------------
-- Відмітка відвідування з оплатою.
--   present + card/cash   → сума = ціна заняття
--   present + subscription → списання 1 заняття з активного абонемента
--   present без оплати    → борг (сума = ціна, спосіб оплати NULL)
--   absent / excused      → без оплати
-- Повторна відмітка спочатку повертає заняття на абонемент, якщо його
-- було списано (у робочому застосунку саме тут була помилка, що давала
-- залишок, більший за пакет, — див. ЛР1).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_mark(p_lesson uuid, p_student uuid, p_status text, p_payment text DEFAULT NULL)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
DECLARE
  v_old attendance%ROWTYPE;
  v_lesson lesson%ROWTYPE;
  v_sub subscription%ROWTYPE;
  v_amount numeric(10,2) := 0;
  v_payment text := NULL;
  v_sub_id uuid := NULL;
BEGIN
  SELECT * INTO v_lesson FROM lesson WHERE lesson_id = p_lesson;
  IF NOT FOUND THEN RAISE EXCEPTION 'Заняття не знайдено'; END IF;
  IF p_status NOT IN ('present', 'absent', 'excused') THEN RAISE EXCEPTION 'Невідомий статус: %', p_status; END IF;

  -- 1. повернути списане раніше заняття на абонемент
  SELECT * INTO v_old FROM attendance WHERE lesson_id = p_lesson AND student_id = p_student FOR UPDATE;
  IF FOUND AND v_old.subscription_id IS NOT NULL THEN
    UPDATE subscription
    SET remaining_lessons = least(remaining_lessons + 1, total_lessons),
        status = CASE WHEN status = 'completed' THEN 'active' ELSE status END
    WHERE subscription_id = v_old.subscription_id;
  END IF;

  -- 2. нова оплата
  IF p_status = 'present' THEN
    IF p_payment = 'subscription' THEN
      SELECT * INTO v_sub FROM subscription
      WHERE student_id = p_student AND course_id = v_lesson.course_id
        AND status = 'active' AND remaining_lessons > 0
      ORDER BY purchased_at LIMIT 1 FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'У учня немає активного абонемента на цей курс';
      END IF;
      UPDATE subscription
      SET remaining_lessons = remaining_lessons - 1,
          status = CASE WHEN remaining_lessons - 1 = 0 THEN 'completed' ELSE status END
      WHERE subscription_id = v_sub.subscription_id;
      v_sub_id := v_sub.subscription_id;
      v_payment := 'subscription';
      v_amount := round(v_sub.total_price / v_sub.total_lessons, 2);
    ELSE
      v_payment := nullif(p_payment, '');   -- NULL = борг
      v_amount := v_lesson.price_amount;
    END IF;
  END IF;

  INSERT INTO attendance (lesson_id, student_id, status, payment_method, amount, subscription_id, marked_by, marked_at)
  VALUES (p_lesson, p_student, p_status, v_payment, v_amount, v_sub_id, public.crm_actor(), now())
  ON CONFLICT ON CONSTRAINT uq_attendance_lesson_student DO UPDATE
    SET status = EXCLUDED.status, payment_method = EXCLUDED.payment_method, amount = EXCLUDED.amount,
        subscription_id = EXCLUDED.subscription_id, marked_by = EXCLUDED.marked_by, marked_at = now();

  RETURN json_build_object('status', p_status, 'payment', v_payment, 'amount', v_amount,
    'subscription', (SELECT remaining_lessons || ' з ' || total_lessons FROM subscription WHERE subscription_id = v_sub_id));
END $$;

-- ---------------------------------------------------------------------
-- Абонементи
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_subscriptions(p_status text DEFAULT 'active')
RETURNS TABLE (subscription_id uuid, student_id uuid, student text, course text, remaining smallint, total smallint,
               price numeric, payment text, status text, purchased_at date, parent_phones text, last_visit date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT v.subscription_id, sb.student_id, v.student, v.course, v.remaining_lessons, v.total_lessons,
         sb.total_price, sb.payment_method, v.status, v.purchased_at, v.parent_phones,
         (SELECT max(l.lesson_date) FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
          WHERE a.subscription_id = v.subscription_id)
  FROM v_subscription_status v
  JOIN subscription sb ON sb.subscription_id = v.subscription_id
  WHERE p_status IS NULL OR p_status = '' OR v.status = p_status
  ORDER BY v.remaining_lessons, v.student;
$$;

CREATE OR REPLACE FUNCTION public.crm_subscription_sell(p_student uuid, p_course smallint, p_lessons integer DEFAULT 4,
                                                        p_price numeric DEFAULT NULL, p_payment text DEFAULT 'card')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
DECLARE v_id uuid; v_price numeric;
BEGIN
  v_price := coalesce(p_price, (SELECT subscription_price FROM tariff WHERE course_id = p_course AND tariff_type = 'group_2_6'), 0);
  INSERT INTO subscription (student_id, course_id, total_lessons, remaining_lessons, total_price, payment_method, purchased_by)
  VALUES (p_student, p_course, p_lessons, p_lessons, v_price, p_payment, public.crm_actor())
  RETURNING subscription_id INTO v_id;
  RETURN v_id;
END $$;

-- ---------------------------------------------------------------------
-- ПОШУКОВИЙ ЗАПИТ 3. Боржники: присутні на заняттях без оплати,
-- щонайменше p_min разів, з контактами батьків
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_debtors(p_min integer DEFAULT 1)
RETURNS TABLE (student_id uuid, student text, parent_phones text, unpaid_visits bigint, debt numeric,
               first_unpaid date, last_unpaid date, courses text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT s.student_id, s.last_name || ' ' || s.first_name,
         (SELECT string_agg(p.phone, ', ') FROM parent_student ps JOIN parent p ON p.parent_id = ps.parent_id
          WHERE ps.student_id = s.student_id),
         count(*), sum(a.amount), min(l.lesson_date), max(l.lesson_date),
         string_agg(DISTINCT c.name, ', ')
  FROM attendance a
  JOIN student s ON s.student_id = a.student_id
  JOIN lesson l  ON l.lesson_id = a.lesson_id
  JOIN course c  ON c.course_id = l.course_id
  WHERE a.status = 'present' AND a.payment_method IS NULL
  GROUP BY s.student_id, s.last_name, s.first_name
  HAVING count(*) >= coalesce(p_min, 1)
  ORDER BY sum(a.amount) DESC, 2;
$$;

-- ---------------------------------------------------------------------
-- Права: ping — усім; решта — лише користувачам, що увійшли
-- ---------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOR f IN SELECT p.oid::regprocedure::text FROM pg_proc p
           WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'crm\_%' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.crm_ping() TO anon;
