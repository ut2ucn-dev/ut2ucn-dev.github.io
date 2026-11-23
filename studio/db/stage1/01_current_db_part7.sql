-- STEMIK · знеособлена копія робочої бази · частина 7 з 7: зв’язки (FK), тригери, політики доступу; завершення
-- Виконуйте СУВОРО по черзі: 01_current_db_part1 → … → 01_current_db_part7. Кожна частина — окрема транзакція.
begin;
set local check_function_bodies = false;
set local client_min_messages = warning;
set local search_path = public, extensions;

-- Зв'язки між таблицями
alter table public.lesson_attendance add constraint "lesson_attendance_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES lessons(id) ON DELETE CASCADE;
alter table public.lesson_attendance add constraint "lesson_attendance_marked_by_fkey" FOREIGN KEY (marked_by) REFERENCES profiles(id);
alter table public.lesson_attendance add constraint "lesson_attendance_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id);
alter table public.lesson_attendance add constraint "lesson_attendance_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.lesson_attendance add constraint "lesson_attendance_subscription_id_fkey" FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);
alter table public.lessons add constraint "lessons_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.lessons add constraint "lessons_substitute_owner_id_fkey" FOREIGN KEY (substitute_owner_id) REFERENCES profiles(id);
alter table public.parent_credentials add constraint "parent_credentials_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES parent_accounts(id) ON DELETE CASCADE;
alter table public.parent_sessions add constraint "parent_sessions_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES parent_accounts(id) ON DELETE CASCADE;
alter table public.parent_students add constraint "parent_students_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES parent_accounts(id) ON DELETE CASCADE;
alter table public.parent_students add constraint "parent_students_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.profiles add constraint "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.student_comments add constraint "student_comments_author_id_fkey" FOREIGN KEY (author_id) REFERENCES profiles(id);
alter table public.student_comments add constraint "student_comments_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.students add constraint "students_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.studio_settings add constraint "studio_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id);
alter table public.subscriptions add constraint "subscriptions_purchased_by_fkey" FOREIGN KEY (purchased_by) REFERENCES profiles(id);
alter table public.subscriptions add constraint "subscriptions_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public.work_costs add constraint "work_costs_work_id_fkey" FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE;
alter table public.works add constraint "works_filament_id_fkey" FOREIGN KEY (filament_id) REFERENCES filaments(id) ON DELETE SET NULL;
alter table public.works add constraint "works_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES lessons(id) ON DELETE CASCADE;
alter table public.works add constraint "works_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.works add constraint "works_printer_id_fkey" FOREIGN KEY (printer_id) REFERENCES printers(id) ON DELETE SET NULL;
alter table public.works add constraint "works_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

-- Індекси
CREATE INDEX idx_lesson_attendance_lesson ON public.lesson_attendance USING btree (lesson_id);
CREATE INDEX idx_lesson_attendance_student ON public.lesson_attendance USING btree (student_id);
CREATE INDEX idx_subscriptions_student_course ON public.subscriptions USING btree (student_id, course);
CREATE INDEX parent_sessions_parent_idx ON public.parent_sessions USING btree (parent_id);
CREATE INDEX parent_students_student_idx ON public.parent_students USING btree (student_id);

-- Подання (views)
create view public.filaments_safe as
 SELECT id,
    material,
    color,
    active,
    created_at,
        CASE
            WHEN is_admin() THEN price_per_kg
            ELSE NULL::numeric
        END AS price_per_kg
   FROM filaments;
create view public.lessons_safe as
 SELECT id,
    owner_id,
    date,
    "time",
    theme,
    course,
    format,
    student_ids,
    extra_service,
    series_id,
    payroll_amount,
        CASE
            WHEN is_admin() THEN price_amount
            ELSE NULL::numeric
        END AS price_amount,
    duration_minutes,
    room,
    substitute_owner_id,
    completed,
    print_default
   FROM lessons;
create view public.printers_safe as
 SELECT id,
    name,
    active,
    created_at,
        CASE
            WHEN is_admin() THEN power_watts
            ELSE NULL::numeric
        END AS power_watts,
        CASE
            WHEN is_admin() THEN depreciation_per_hour
            ELSE NULL::numeric
        END AS depreciation_per_hour
   FROM printers;
create view public.rate_cards_safe as
 SELECT course,
    zp_group_1,
    zp_group_2_6,
    zp_individual,
    zp_individual_online,
    zp_group_online,
    zp_extra_service,
        CASE
            WHEN is_admin() THEN price_group_1
            ELSE NULL::numeric
        END AS price_group_1,
        CASE
            WHEN is_admin() THEN price_group_2_6
            ELSE NULL::numeric
        END AS price_group_2_6,
        CASE
            WHEN is_admin() THEN price_individual
            ELSE NULL::numeric
        END AS price_individual,
        CASE
            WHEN is_admin() THEN price_individual_online
            ELSE NULL::numeric
        END AS price_individual_online,
        CASE
            WHEN is_admin() THEN price_group_online
            ELSE NULL::numeric
        END AS price_group_online,
        CASE
            WHEN is_admin() THEN price_extra_service
            ELSE NULL::numeric
        END AS price_extra_service,
        CASE
            WHEN is_admin() THEN price_print_online
            ELSE NULL::numeric
        END AS price_print_online,
        CASE
            WHEN is_admin() THEN price_sub_group
            ELSE NULL::numeric
        END AS price_sub_group,
        CASE
            WHEN is_admin() THEN price_sub_individual
            ELSE NULL::numeric
        END AS price_sub_individual,
        CASE
            WHEN is_admin() THEN price_sub_individual_online
            ELSE NULL::numeric
        END AS price_sub_individual_online,
        CASE
            WHEN is_admin() THEN price_sub_group_online
            ELSE NULL::numeric
        END AS price_sub_group_online
   FROM rate_cards;
create view public.report_debt as
 SELECT la.id,
    la.lesson_id,
    la.student_id,
    la.owner_id,
    la.marked_at,
    l.date AS lesson_date,
    l.course,
    l.theme,
    l.price_amount +
        CASE
            WHEN la.print_enabled THEN lesson_print_surcharge(l.id, la.print_price)
            ELSE 0::numeric
        END AS price_amount,
    s.name AS student_name
   FROM lesson_attendance la
     JOIN lessons l ON l.id = la.lesson_id
     JOIN students s ON s.id = la.student_id
  WHERE la.status = 'present'::text AND la.payment_method IS NULL AND is_superadmin();
create view public.report_paid as
 SELECT la.id,
    la.lesson_id,
    la.student_id,
    la.owner_id,
    la.payment_method,
    la.amount,
    la.marked_at,
    l.date AS lesson_date,
    l.course,
    l.theme,
    s.name AS student_name
   FROM lesson_attendance la
     JOIN lessons l ON l.id = la.lesson_id
     JOIN students s ON s.id = la.student_id
  WHERE la.status = 'present'::text AND la.payment_method IS NOT NULL AND is_superadmin();
create view public.report_print_costs as
 SELECT w.id AS work_id,
    w.lesson_id,
    w.student_id,
    w.owner_id,
    COALESCE((w.printed_at AT TIME ZONE 'Europe/Kyiv'::text)::date, l.date) AS print_date,
    l.date AS lesson_date,
    l.course,
    l.theme,
    s.name AS student_name,
    w.weight_g,
    w.print_minutes,
    w.printer_id,
    w.filament_id,
    p.name AS printer_name,
    f.material AS filament_material,
    f.color AS filament_color,
    wc.material_cost,
    wc.electricity_cost,
    wc.depreciation_cost,
    wc.total_cost
   FROM works w
     JOIN lessons l ON l.id = w.lesson_id
     LEFT JOIN students s ON s.id = w.student_id
     LEFT JOIN printers p ON p.id = w.printer_id
     LEFT JOIN filaments f ON f.id = w.filament_id
     LEFT JOIN work_costs wc ON wc.work_id = w.id
  WHERE w.printed AND is_admin();
create view public.report_unused_excused as
 SELECT la.id,
    la.lesson_id,
    la.student_id,
    la.owner_id,
    la.payment_method,
    la.amount,
    la.marked_at,
    l.date AS lesson_date,
    l.course,
    l.theme,
    s.name AS student_name
   FROM lesson_attendance la
     JOIN lessons l ON l.id = la.lesson_id
     JOIN students s ON s.id = la.student_id
  WHERE la.status = 'excused'::text AND la.payment_method IS NOT NULL AND is_superadmin();
create view public.report_unused_subscriptions as
 SELECT sub.id AS subscription_id,
    sub.student_id,
    sub.course,
    sub.remaining_lessons,
    sub.total_lessons,
    sub.purchased_at,
    s.name AS student_name
   FROM subscriptions sub
     JOIN students s ON s.id = sub.student_id
  WHERE sub.status = 'active'::text AND sub.remaining_lessons > 0 AND is_superadmin();

-- Правила доступу (RLS)
alter table public.filaments enable row level security;
alter table public.lesson_attendance enable row level security;
alter table public.lessons enable row level security;
alter table public.parent_accounts enable row level security;
alter table public.parent_credentials enable row level security;
alter table public.parent_sessions enable row level security;
alter table public.parent_students enable row level security;
alter table public.printers enable row level security;
alter table public.profiles enable row level security;
alter table public.rate_cards enable row level security;
alter table public.student_comments enable row level security;
alter table public.students enable row level security;
alter table public.studio_settings enable row level security;
alter table public.subscriptions enable row level security;
alter table public.work_costs enable row level security;
alter table public.works enable row level security;
create policy "filaments_admin_all" on public.filaments as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "lesson_attendance_admin_all" on public.lesson_attendance as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "lesson_attendance_read_all" on public.lesson_attendance as permissive for select to public
  using (true);
create policy "lessons_admin_all" on public.lessons as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "lessons_select_scoped" on public.lessons as permissive for select to public
  using (((owner_id = auth.uid()) OR is_admin() OR (student_ids && my_taught_student_ids())));
create policy "parent_accounts_superadmin" on public.parent_accounts as permissive for all to authenticated
  using (is_superadmin())
  with check (is_superadmin());
create policy "parent_students_superadmin" on public.parent_students as permissive for all to authenticated
  using (is_superadmin())
  with check (is_superadmin());
create policy "printers_admin_all" on public.printers as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "profiles_select_own_or_admin" on public.profiles as permissive for select to public
  using (((id = auth.uid()) OR is_admin()));
create policy "profiles_update_own_or_admin" on public.profiles as permissive for update to public
  using (((id = auth.uid()) OR is_admin()));
create policy "rate_cards_admin_write" on public.rate_cards as permissive for all to public
  using (is_superadmin())
  with check (is_superadmin());
create policy "rate_cards_select_all" on public.rate_cards as permissive for select to public
  using (is_admin());
create policy "student_comments_insert" on public.student_comments as permissive for insert to public
  with check ((auth.uid() IS NOT NULL));
create policy "student_comments_read" on public.student_comments as permissive for select to public
  using (true);
create policy "students_delete_admin" on public.students as permissive for delete to public
  using (is_admin());
create policy "students_insert_shared" on public.students as permissive for insert to public
  with check ((auth.uid() IS NOT NULL));
create policy "students_select_shared" on public.students as permissive for select to public
  using ((auth.uid() IS NOT NULL));
create policy "students_update_shared" on public.students as permissive for update to public
  using ((auth.uid() IS NOT NULL))
  with check ((auth.uid() IS NOT NULL));
create policy "studio_settings_admin_read" on public.studio_settings as permissive for select to public
  using (is_admin());
create policy "subscriptions_admin_all" on public.subscriptions as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "work_costs_admin_read" on public.work_costs as permissive for select to public
  using (is_admin());
create policy "works_admin_all" on public.works as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "works_all_own" on public.works as permissive for all to public
  using ((owner_id = auth.uid()))
  with check ((owner_id = auth.uid()));
create policy "works_select_scoped" on public.works as permissive for select to public
  using (((owner_id = auth.uid()) OR is_admin() OR (student_id = ANY (my_taught_student_ids()))));

-- Тригери
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();
CREATE TRIGGER trg_cleanup_deleted_student_from_lessons AFTER DELETE ON public.students FOR EACH ROW EXECUTE FUNCTION cleanup_deleted_student_from_lessons();
CREATE TRIGGER trg_compute_lesson_amounts BEFORE INSERT OR UPDATE OF course, format, student_ids, extra_service ON public.lessons FOR EACH ROW EXECUTE FUNCTION compute_lesson_amounts();
CREATE TRIGGER trg_compute_work_cost AFTER INSERT OR UPDATE OF weight_g, print_minutes, printer_id, filament_id ON public.works FOR EACH ROW EXECUTE FUNCTION compute_work_cost();
CREATE TRIGGER trg_lesson_print_default AFTER UPDATE OF print_default ON public.lessons FOR EACH ROW WHEN ((new.print_default IS DISTINCT FROM old.print_default)) EXECUTE FUNCTION apply_lesson_print_default();
CREATE TRIGGER trg_parent_accounts_normalize BEFORE INSERT OR UPDATE OF phone, name ON public.parent_accounts FOR EACH ROW EXECUTE FUNCTION parent_accounts_normalize();

-- Права ролей
revoke all on public.filaments from public, anon, authenticated, service_role;
grant all on public.filaments to anon;
grant all on public.filaments to authenticated;
grant all on public.filaments to service_role;
revoke all on public.filaments_safe from public, anon, authenticated, service_role;
grant all on public.filaments_safe to anon;
grant all on public.filaments_safe to authenticated;
grant all on public.filaments_safe to service_role;
revoke all on public.lesson_attendance from public, anon, authenticated, service_role;
grant all on public.lesson_attendance to anon;
grant all on public.lesson_attendance to authenticated;
grant all on public.lesson_attendance to service_role;
revoke all on public.lessons from public, anon, authenticated, service_role;
grant all on public.lessons to anon;
grant all on public.lessons to authenticated;
grant all on public.lessons to service_role;
revoke all on public.lessons_safe from public, anon, authenticated, service_role;
grant all on public.lessons_safe to anon;
grant all on public.lessons_safe to authenticated;
grant all on public.lessons_safe to service_role;
revoke all on public.parent_accounts from public, anon, authenticated, service_role;
grant all on public.parent_accounts to authenticated;
grant all on public.parent_accounts to service_role;
revoke all on public.parent_credentials from public, anon, authenticated, service_role;
grant all on public.parent_credentials to service_role;
revoke all on public.parent_sessions from public, anon, authenticated, service_role;
grant all on public.parent_sessions to service_role;
revoke all on public.parent_students from public, anon, authenticated, service_role;
grant all on public.parent_students to authenticated;
grant all on public.parent_students to service_role;
revoke all on public.printers from public, anon, authenticated, service_role;
grant all on public.printers to anon;
grant all on public.printers to authenticated;
grant all on public.printers to service_role;
revoke all on public.printers_safe from public, anon, authenticated, service_role;
grant all on public.printers_safe to anon;
grant all on public.printers_safe to authenticated;
grant all on public.printers_safe to service_role;
revoke all on public.profiles from public, anon, authenticated, service_role;
grant all on public.profiles to anon;
grant all on public.profiles to authenticated;
grant all on public.profiles to service_role;
revoke all on public.rate_cards from public, anon, authenticated, service_role;
grant all on public.rate_cards to anon;
grant all on public.rate_cards to authenticated;
grant all on public.rate_cards to service_role;
revoke all on public.rate_cards_safe from public, anon, authenticated, service_role;
grant all on public.rate_cards_safe to anon;
grant all on public.rate_cards_safe to authenticated;
grant all on public.rate_cards_safe to service_role;
revoke all on public.report_debt from public, anon, authenticated, service_role;
grant all on public.report_debt to anon;
grant all on public.report_debt to authenticated;
grant all on public.report_debt to service_role;
revoke all on public.report_paid from public, anon, authenticated, service_role;
grant all on public.report_paid to anon;
grant all on public.report_paid to authenticated;
grant all on public.report_paid to service_role;
revoke all on public.report_print_costs from public, anon, authenticated, service_role;
grant all on public.report_print_costs to anon;
grant all on public.report_print_costs to authenticated;
grant all on public.report_print_costs to service_role;
revoke all on public.report_unused_excused from public, anon, authenticated, service_role;
grant all on public.report_unused_excused to anon;
grant all on public.report_unused_excused to authenticated;
grant all on public.report_unused_excused to service_role;
revoke all on public.report_unused_subscriptions from public, anon, authenticated, service_role;
grant all on public.report_unused_subscriptions to anon;
grant all on public.report_unused_subscriptions to authenticated;
grant all on public.report_unused_subscriptions to service_role;
revoke all on public.student_comments from public, anon, authenticated, service_role;
grant all on public.student_comments to anon;
grant all on public.student_comments to authenticated;
grant all on public.student_comments to service_role;
revoke all on public.students from public, anon, authenticated, service_role;
grant all on public.students to anon;
grant all on public.students to authenticated;
grant all on public.students to service_role;
revoke all on public.studio_settings from public, anon, authenticated, service_role;
grant all on public.studio_settings to anon;
grant all on public.studio_settings to authenticated;
grant all on public.studio_settings to service_role;
revoke all on public.subscriptions from public, anon, authenticated, service_role;
grant all on public.subscriptions to anon;
grant all on public.subscriptions to authenticated;
grant all on public.subscriptions to service_role;
revoke all on public.work_costs from public, anon, authenticated, service_role;
grant all on public.work_costs to anon;
grant all on public.work_costs to authenticated;
grant all on public.work_costs to service_role;
revoke all on public.works from public, anon, authenticated, service_role;
grant all on public.works to anon;
grant all on public.works to authenticated;
grant all on public.works to service_role;
revoke all on function public.apply_lesson_print_default() from public, anon, authenticated, service_role;
grant execute on function public.apply_lesson_print_default() to public;
grant execute on function public.apply_lesson_print_default() to anon;
grant execute on function public.apply_lesson_print_default() to authenticated;
grant execute on function public.apply_lesson_print_default() to service_role;
revoke all on function public.cleanup_deleted_student_from_lessons() from public, anon, authenticated, service_role;
grant execute on function public.cleanup_deleted_student_from_lessons() to public;
grant execute on function public.cleanup_deleted_student_from_lessons() to anon;
grant execute on function public.cleanup_deleted_student_from_lessons() to authenticated;
grant execute on function public.cleanup_deleted_student_from_lessons() to service_role;
revoke all on function public.compute_lesson_amounts() from public, anon, authenticated, service_role;
grant execute on function public.compute_lesson_amounts() to public;
grant execute on function public.compute_lesson_amounts() to anon;
grant execute on function public.compute_lesson_amounts() to authenticated;
grant execute on function public.compute_lesson_amounts() to service_role;
revoke all on function public.compute_work_cost() from public, anon, authenticated, service_role;
grant execute on function public.compute_work_cost() to public;
grant execute on function public.compute_work_cost() to anon;
grant execute on function public.compute_work_cost() to authenticated;
grant execute on function public.compute_work_cost() to service_role;
revoke all on function public.handle_new_user() from public, anon, authenticated, service_role;
grant execute on function public.handle_new_user() to public;
grant execute on function public.handle_new_user() to anon;
grant execute on function public.handle_new_user() to authenticated;
grant execute on function public.handle_new_user() to service_role;
revoke all on function public.is_admin() from public, anon, authenticated, service_role;
grant execute on function public.is_admin() to public;
grant execute on function public.is_admin() to anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin() to service_role;
revoke all on function public.is_superadmin() from public, anon, authenticated, service_role;
grant execute on function public.is_superadmin() to public;
grant execute on function public.is_superadmin() to anon;
grant execute on function public.is_superadmin() to authenticated;
grant execute on function public.is_superadmin() to service_role;
revoke all on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) from public, anon, authenticated, service_role;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to public;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to anon;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to authenticated;
grant execute on function public.lesson_print_surcharge(p_lesson_id uuid, p_price numeric) to service_role;
revoke all on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) from public, anon, authenticated, service_role;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to public;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to anon;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to authenticated;
grant execute on function public.mark_attendance(p_lesson_id uuid, p_student_id uuid, p_status text, p_payment_method text, p_discount_percent numeric, p_purchase_date date, p_purchase_method text) to service_role;
revoke all on function public.my_taught_student_ids() from public, anon, authenticated, service_role;
grant execute on function public.my_taught_student_ids() to public;
grant execute on function public.my_taught_student_ids() to anon;
grant execute on function public.my_taught_student_ids() to authenticated;
grant execute on function public.my_taught_student_ids() to service_role;
revoke all on function public.parent_accounts_normalize() from public, anon, authenticated, service_role;
grant execute on function public.parent_accounts_normalize() to public;
grant execute on function public.parent_accounts_normalize() to anon;
grant execute on function public.parent_accounts_normalize() to authenticated;
grant execute on function public.parent_accounts_normalize() to service_role;
revoke all on function public.parent_create_account(p_phone text, p_name text, p_student_ids uuid[]) from public, anon, authenticated, service_role;
grant execute on function public.parent_create_account(p_phone text, p_name text, p_student_ids uuid[]) to authenticated;
grant execute on function public.parent_create_account(p_phone text, p_name text, p_student_ids uuid[]) to service_role;
revoke all on function public.parent_generate_password() from public, anon, authenticated, service_role;
grant execute on function public.parent_generate_password() to public;
grant execute on function public.parent_generate_password() to anon;
grant execute on function public.parent_generate_password() to authenticated;
grant execute on function public.parent_generate_password() to service_role;
revoke all on function public.parent_login(p_phone text, p_password text, p_client text) from public, anon, authenticated, service_role;
grant execute on function public.parent_login(p_phone text, p_password text, p_client text) to anon;
grant execute on function public.parent_login(p_phone text, p_password text, p_client text) to authenticated;
grant execute on function public.parent_login(p_phone text, p_password text, p_client text) to service_role;
revoke all on function public.parent_logout(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.parent_logout(p_token text) to anon;
grant execute on function public.parent_logout(p_token text) to authenticated;
grant execute on function public.parent_logout(p_token text) to service_role;
revoke all on function public.parent_normalize_phone(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.parent_normalize_phone(p_phone text) to public;
grant execute on function public.parent_normalize_phone(p_phone text) to anon;
grant execute on function public.parent_normalize_phone(p_phone text) to authenticated;
grant execute on function public.parent_normalize_phone(p_phone text) to service_role;
revoke all on function public.parent_password_for_student(p_student_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.parent_password_for_student(p_student_id uuid) to authenticated;
grant execute on function public.parent_password_for_student(p_student_id uuid) to service_role;
revoke all on function public.parent_portal(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.parent_portal(p_token text) to anon;
grant execute on function public.parent_portal(p_token text) to authenticated;
grant execute on function public.parent_portal(p_token text) to service_role;
revoke all on function public.parent_reset_credentials(p_parent_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.parent_reset_credentials(p_parent_id uuid) to service_role;
revoke all on function public.parent_reset_password(p_parent_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.parent_reset_password(p_parent_id uuid) to authenticated;
grant execute on function public.parent_reset_password(p_parent_id uuid) to service_role;
revoke all on function public.parent_session_account(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.parent_session_account(p_token text) to service_role;
revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;
grant execute on function public.rls_auto_enable() to public;
grant execute on function public.rls_auto_enable() to anon;
grant execute on function public.rls_auto_enable() to authenticated;
grant execute on function public.rls_auto_enable() to service_role;
revoke all on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) from public, anon, authenticated, service_role;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to public;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to anon;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to authenticated;
grant execute on function public.set_attendance_print(p_lesson_id uuid, p_student_id uuid, p_enabled boolean, p_price numeric) to service_role;
revoke all on function public.set_calc_start_date(p_date date) from public, anon, authenticated, service_role;
grant execute on function public.set_calc_start_date(p_date date) to public;
grant execute on function public.set_calc_start_date(p_date date) to anon;
grant execute on function public.set_calc_start_date(p_date date) to authenticated;
grant execute on function public.set_calc_start_date(p_date date) to service_role;
revoke all on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) from public, anon, authenticated, service_role;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to public;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to anon;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to authenticated;
grant execute on function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric) to service_role;
revoke all on function public.studio_report_summary(p_from date, p_to date) from public, anon, authenticated, service_role;
grant execute on function public.studio_report_summary(p_from date, p_to date) to public;
grant execute on function public.studio_report_summary(p_from date, p_to date) to anon;
grant execute on function public.studio_report_summary(p_from date, p_to date) to authenticated;
grant execute on function public.studio_report_summary(p_from date, p_to date) to service_role;
revoke all on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to public;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to anon;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to authenticated;
grant execute on function public.unmark_attendance(p_lesson_id uuid, p_student_id uuid) to service_role;

-- Лише для Supabase: realtime, сховище фото (без самих файлів), автоувімкнення RLS
do $rt$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'lesson_attendance') then alter publication supabase_realtime add table public.lesson_attendance; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'lessons') then alter publication supabase_realtime add table public.lessons; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles') then alter publication supabase_realtime add table public.profiles; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rate_cards') then alter publication supabase_realtime add table public.rate_cards; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'student_comments') then alter publication supabase_realtime add table public.student_comments; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'students') then alter publication supabase_realtime add table public.students; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'subscriptions') then alter publication supabase_realtime add table public.subscriptions; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'works') then alter publication supabase_realtime add table public.works; end if;
  end if;
end $rt$;
do $st$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('student-photos', 'student-photos', true, null, null) on conflict (id) do nothing$q$;
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('teacher-photos', 'teacher-photos', true, null, null) on conflict (id) do nothing$q$;
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('works-photos', 'works-photos', true, null, null) on conflict (id) do nothing$q$;
    execute $q$drop policy if exists "student_photos_admin_write_delete" on storage.objects$q$;
    execute $q$create policy "student_photos_admin_write_delete" on storage.objects as permissive for delete to authenticated
  using (((bucket_id = 'student-photos'::text) AND is_admin()))$q$;
    execute $q$drop policy if exists "student_photos_admin_write_insert" on storage.objects$q$;
    execute $q$create policy "student_photos_admin_write_insert" on storage.objects as permissive for insert to authenticated
  with check (((bucket_id = 'student-photos'::text) AND is_admin()))$q$;
    execute $q$drop policy if exists "student_photos_admin_write_update" on storage.objects$q$;
    execute $q$create policy "student_photos_admin_write_update" on storage.objects as permissive for update to authenticated
  using (((bucket_id = 'student-photos'::text) AND is_admin()))$q$;
    execute $q$drop policy if exists "student_photos_public_read" on storage.objects$q$;
    execute $q$create policy "student_photos_public_read" on storage.objects as permissive for select to public
  using ((bucket_id = 'student-photos'::text))$q$;
    execute $q$drop policy if exists "teacher-photos admin manage" on storage.objects$q$;
    execute $q$create policy "teacher-photos admin manage" on storage.objects as permissive for all to public
  using (((bucket_id = 'teacher-photos'::text) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['admin'::text, 'superadmin'::text])))))))$q$;
    execute $q$drop policy if exists "teacher-photos read" on storage.objects$q$;
    execute $q$create policy "teacher-photos read" on storage.objects as permissive for select to public
  using ((bucket_id = 'teacher-photos'::text))$q$;
    execute $q$drop policy if exists "teacher-photos self update" on storage.objects$q$;
    execute $q$create policy "teacher-photos self update" on storage.objects as permissive for update to public
  using (((bucket_id = 'teacher-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)))$q$;
    execute $q$drop policy if exists "teacher-photos self upload" on storage.objects$q$;
    execute $q$create policy "teacher-photos self upload" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'teacher-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)))$q$;
    execute $q$drop policy if exists "works_photos_delete_own" on storage.objects$q$;
    execute $q$create policy "works_photos_delete_own" on storage.objects as permissive for delete to authenticated
  using (((bucket_id = 'works-photos'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR is_admin())))$q$;
    execute $q$drop policy if exists "works_photos_insert_own" on storage.objects$q$;
    execute $q$create policy "works_photos_insert_own" on storage.objects as permissive for insert to authenticated
  with check (((bucket_id = 'works-photos'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR is_admin())))$q$;
    execute $q$drop policy if exists "works_photos_public_read" on storage.objects$q$;
    execute $q$create policy "works_photos_public_read" on storage.objects as permissive for select to public
  using ((bucket_id = 'works-photos'::text))$q$;
    execute $q$drop policy if exists "works_photos_update_own" on storage.objects$q$;
    execute $q$create policy "works_photos_update_own" on storage.objects as permissive for update to authenticated
  using (((bucket_id = 'works-photos'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR is_admin())))$q$;
  end if;
end $st$;
do $ev$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'ensure_rls') then
    create event trigger ensure_rls on ddl_command_end execute function public.rls_auto_enable();
  end if;
exception when insufficient_privilege then
  raise notice 'ensure_rls: немає прав на event trigger, пропущено';
end $ev$;

commit;

notify pgrst, 'reload schema';

-- Рядків у копії: filaments 30, lesson_attendance 250, lessons 496, parent_accounts 3, parent_credentials 0, parent_sessions 0, parent_students 4, printers 2, profiles 8, rate_cards 9, student_comments 8, students 52, studio_settings 1, subscriptions 34, work_costs 0, works 195
