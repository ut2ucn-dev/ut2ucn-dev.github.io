-- =====================================================================
-- Стемік CRM. Крок 5: функції для керування даними та звітів.
-- Виконувати ПІСЛЯ 04_crm_api.sql. Доповнює CRM:
--   • зміна й видалення занять, деактивація учня, скасування абонемента,
--     редагування тарифів (UPDATE / DELETE);
--   • аналітичні звіти: виручка, наростаючий підсумок, навантаження
--     викладачів, курси, учні без майбутніх занять (GROUP BY, HAVING,
--     підзапити, віконні функції).
-- Усі функції — лише для користувачів, що увійшли (роль authenticated).
-- =====================================================================
SET search_path TO stemik, public;

-- ---------------------------------------------------------------------
-- Журнал заняття: та сама функція, що й у 04_crm_api.sql, але віддає ще
-- id викладача, формат і час — потрібні формі редагування заняття
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_lesson(p_id uuid)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT json_build_object(
    'lesson', json_build_object('lesson_id', l.lesson_id, 'date', l.lesson_date, 'time', to_char(l.start_time, 'HH24:MI'),
              'course_id', l.course_id, 'course', c.name, 'teacher_id', l.teacher_id, 'teacher', t.first_name || ' ' || t.last_name,
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
-- UPDATE: змінити заняття. Ціна й оплата викладача перераховуються за
-- тарифом, лише поки на занятті немає жодної відмітки.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_lesson_update(
  p_id uuid, p_course smallint, p_teacher uuid, p_date date, p_time time,
  p_duration integer DEFAULT 60, p_format text DEFAULT 'group', p_theme text DEFAULT '')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
DECLARE v_t tariff%ROWTYPE; v_marked boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM attendance WHERE lesson_id = p_id) INTO v_marked;
  SELECT * INTO v_t FROM tariff
  WHERE course_id = p_course AND tariff_type = CASE p_format WHEN 'group' THEN 'group_2_6' ELSE p_format END;
  UPDATE lesson
  SET course_id = p_course, teacher_id = p_teacher, lesson_date = p_date, start_time = p_time,
      duration_minutes = coalesce(p_duration, 60), format = coalesce(p_format, 'group'), theme = coalesce(p_theme, ''),
      price_amount   = CASE WHEN v_marked THEN price_amount   ELSE coalesce(v_t.lesson_price, price_amount) END,
      payroll_amount = CASE WHEN v_marked THEN payroll_amount ELSE coalesce(v_t.teacher_pay, payroll_amount) END
  WHERE lesson_id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Заняття не знайдено'; END IF;
END $$;

-- ---------------------------------------------------------------------
-- DELETE: видалити заняття. Записи учнів на нього видаляються каскадно
-- (ON DELETE CASCADE), але заняття з відмітками відвідування видалити не
-- можна: це фінансова історія (оплати, списання з абонементів).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_lesson_delete(p_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
DECLARE v_enrolled int; v_marked int;
BEGIN
  SELECT count(*) INTO v_marked FROM attendance WHERE lesson_id = p_id;
  IF v_marked > 0 THEN
    RAISE EXCEPTION 'Заняття вже має відмітки відвідування (%), тому його не можна видалити: це історія оплат', v_marked;
  END IF;
  SELECT count(*) INTO v_enrolled FROM lesson_student WHERE lesson_id = p_id;
  DELETE FROM lesson WHERE lesson_id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Заняття не знайдено'; END IF;
  RETURN json_build_object('deleted', true, 'enrolled_removed', v_enrolled);
END $$;

-- Прибрати учня із запису на заняття (лише якщо його ще не відмічено)
CREATE OR REPLACE FUNCTION public.crm_lesson_remove_student(p_lesson uuid, p_student uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM attendance WHERE lesson_id = p_lesson AND student_id = p_student) THEN
    RAISE EXCEPTION 'Учня вже відмічено на цьому занятті — прибрати його із запису не можна';
  END IF;
  DELETE FROM lesson_student WHERE lesson_id = p_lesson AND student_id = p_student;
END $$;

-- ---------------------------------------------------------------------
-- UPDATE замість DELETE: учня з історією не видаляють (RESTRICT),
-- а деактивують — він зникає з пошуку активних, історія лишається
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_student_set_active(p_id uuid, p_active boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
BEGIN
  UPDATE student SET active = p_active WHERE student_id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Учня не знайдено'; END IF;
END $$;

-- Скасувати абонемент (статус cancelled); використані заняття лишаються в історії
CREATE OR REPLACE FUNCTION public.crm_subscription_cancel(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
BEGIN
  UPDATE subscription SET status = 'cancelled' WHERE subscription_id = p_id AND status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'Активного абонемента не знайдено'; END IF;
END $$;

-- ---------------------------------------------------------------------
-- Тарифи: перегляд і зміна цін (UPDATE). Змінюються лише майбутні
-- заняття — ціна вже проведених зафіксована в самому занятті.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_tariffs()
RETURNS TABLE (tariff_id int, course_id smallint, course text, direction text, tariff_type text,
               teacher_pay numeric, lesson_price numeric, subscription_price numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT t.tariff_id, c.course_id, c.name, c.direction, t.tariff_type, t.teacher_pay, t.lesson_price, t.subscription_price
  FROM tariff t JOIN course c ON c.course_id = t.course_id
  WHERE c.active
  ORDER BY c.direction, c.name,
           array_position(ARRAY['group_1','group_2_6','group_online','individual','individual_online','extra_service'], t.tariff_type::text);
$$;

CREATE OR REPLACE FUNCTION public.crm_tariff_save(p_id int, p_teacher_pay numeric, p_lesson_price numeric, p_subscription_price numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = stemik, public AS $$
BEGIN
  UPDATE tariff SET teacher_pay = p_teacher_pay, lesson_price = p_lesson_price, subscription_price = p_subscription_price
  WHERE tariff_id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Тариф не знайдено'; END IF;
END $$;

-- ======================= ЗВІТИ =======================
-- Виручка за місяцями та способами оплати + частка способу в місяці
-- (GROUP BY + віконна функція SUM() OVER (PARTITION BY …))
CREATE OR REPLACE FUNCTION public.crm_report_revenue(p_from date, p_to date)
RETURNS TABLE (month text, payment text, visits bigint, amount numeric, share numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT to_char(l.lesson_date, 'YYYY-MM'),
         coalesce(a.payment_method, 'debt'),
         count(*), sum(a.amount),
         round(100 * sum(a.amount) / nullif(sum(sum(a.amount)) OVER (PARTITION BY to_char(l.lesson_date, 'YYYY-MM')), 0), 1)
  FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
  WHERE a.status = 'present' AND l.lesson_date BETWEEN p_from AND p_to
  GROUP BY 1, 2
  ORDER BY 1, 4 DESC;
$$;

-- Виручка за тижнями з наростаючим підсумком (SUM(SUM(…)) OVER (ORDER BY …))
CREATE OR REPLACE FUNCTION public.crm_report_weekly(p_from date, p_to date)
RETURNS TABLE (week date, paid numeric, debt numeric, cumulative numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT w.week, w.paid, w.debt, sum(w.paid) OVER (ORDER BY w.week)
  FROM (SELECT date_trunc('week', l.lesson_date)::date AS week,
               coalesce(sum(a.amount) FILTER (WHERE a.payment_method IS NOT NULL), 0) AS paid,
               coalesce(sum(a.amount) FILTER (WHERE a.payment_method IS NULL), 0) AS debt
        FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
        WHERE a.status = 'present' AND l.lesson_date BETWEEN p_from AND p_to
        GROUP BY 1) w
  ORDER BY w.week;
$$;

-- Навантаження викладачів за період (WHERE до групування, HAVING після)
CREATE OR REPLACE FUNCTION public.crm_report_teachers(p_from date, p_to date, p_min_lessons int DEFAULT 1)
RETURNS TABLE (teacher text, role text, lessons bigint, completed bigint, seats bigint, avg_group numeric, payroll numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT e.first_name || ' ' || e.last_name, e.role,
         count(DISTINCT l.lesson_id),
         count(DISTINCT l.lesson_id) FILTER (WHERE l.completed),
         count(ls.student_id),
         round(count(ls.student_id)::numeric / nullif(count(DISTINCT l.lesson_id), 0), 1),
         (SELECT coalesce(sum(l2.payroll_amount), 0) FROM lesson l2
          WHERE l2.teacher_id = e.employee_id AND l2.completed AND l2.lesson_date BETWEEN p_from AND p_to)
  FROM lesson l
  JOIN employee e ON e.employee_id = l.teacher_id
  LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
  WHERE l.lesson_date BETWEEN p_from AND p_to
  GROUP BY e.employee_id, e.first_name, e.last_name, e.role
  HAVING count(DISTINCT l.lesson_id) >= coalesce(p_min_lessons, 1)
  ORDER BY 3 DESC;
$$;

-- Курси: учні, заняття, середня група (похідна таблиця), відвідуваність
CREATE OR REPLACE FUNCTION public.crm_report_courses(p_from date, p_to date)
RETURNS TABLE (course text, direction text, students bigint, lessons bigint, avg_group numeric, max_group bigint,
               marked bigint, present_pct numeric, revenue numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT c.name, c.direction,
         (SELECT count(DISTINCT ls.student_id) FROM lesson_student ls JOIN lesson l ON l.lesson_id = ls.lesson_id
          WHERE l.course_id = c.course_id AND l.lesson_date BETWEEN p_from AND p_to),
         count(g.lesson_id), round(avg(g.n), 1), max(g.n),
         (SELECT count(*) FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
          WHERE l.course_id = c.course_id AND l.lesson_date BETWEEN p_from AND p_to),
         (SELECT round(100.0 * count(*) FILTER (WHERE a.status = 'present') / nullif(count(*), 0), 1)
          FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
          WHERE l.course_id = c.course_id AND l.lesson_date BETWEEN p_from AND p_to),
         (SELECT coalesce(sum(a.amount), 0) FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
          WHERE l.course_id = c.course_id AND a.status = 'present' AND a.payment_method IS NOT NULL
            AND l.lesson_date BETWEEN p_from AND p_to)
  FROM course c
  JOIN (SELECT l.lesson_id, l.course_id, count(ls.student_id) AS n
        FROM lesson l LEFT JOIN lesson_student ls ON ls.lesson_id = l.lesson_id
        WHERE l.lesson_date BETWEEN p_from AND p_to
        GROUP BY l.lesson_id, l.course_id) g ON g.course_id = c.course_id
  GROUP BY c.course_id, c.name, c.direction
  ORDER BY 3 DESC, 1;
$$;

-- Учні, що випали з розкладу: відвідували, але не записані на жодне майбутнє
-- заняття (корельовані підзапити EXISTS / NOT EXISTS)
CREATE OR REPLACE FUNCTION public.crm_report_dropped(p_today date DEFAULT CURRENT_DATE)
RETURNS TABLE (student_id uuid, student text, last_visit date, visits bigint, courses text, parent_phones text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = stemik, public AS $$
  SELECT s.student_id, s.last_name || ' ' || s.first_name,
         (SELECT max(l.lesson_date) FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
          WHERE a.student_id = s.student_id AND a.status = 'present'),
         (SELECT count(*) FROM attendance a WHERE a.student_id = s.student_id AND a.status = 'present'),
         (SELECT string_agg(DISTINCT c.name, ', ') FROM attendance a JOIN lesson l ON l.lesson_id = a.lesson_id
          JOIN course c ON c.course_id = l.course_id WHERE a.student_id = s.student_id),
         (SELECT string_agg(p.phone, ', ') FROM parent_student ps JOIN parent p ON p.parent_id = ps.parent_id
          WHERE ps.student_id = s.student_id)
  FROM student s
  WHERE s.active
    AND EXISTS (SELECT 1 FROM attendance a WHERE a.student_id = s.student_id AND a.status = 'present')
    AND NOT EXISTS (SELECT 1 FROM lesson_student ls JOIN lesson l ON l.lesson_id = ls.lesson_id
                    WHERE ls.student_id = s.student_id AND l.lesson_date >= p_today)
  ORDER BY 3 DESC NULLS LAST, 2;
$$;

-- ---------------------------------------------------------------------
-- Права: лише для користувачів, що увійшли
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
