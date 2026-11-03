-- Stage 22: fix "UPDATE requires a WHERE clause" when saving the print
-- cost settings (Друк → Принтери і пластик → Зберегти).
--
-- Supabase rejects an UPDATE without a WHERE clause on API requests
-- (pg_safeupdate). studio_settings has exactly one row (id = true), and
-- both functions that write it updated "every row" with no WHERE, so
-- they failed. Same fix for both: target that one row explicitly.
-- set_calc_start_date (Тарифи → Дата початку розрахунку) had the same
-- latent bug; its lessons update already has a WHERE and is unchanged.
--
-- Run once in Supabase → SQL Editor, after 0001-0021. One transaction.

begin;

create or replace function public.set_print_cost_settings(p_tariff numeric, p_waste_percent numeric)
returns void
language plpgsql
security definer
as $function$
begin
  if not is_admin() then
    raise exception 'Лише адміністратор може змінювати ці налаштування.';
  end if;
  update public.studio_settings
    set electricity_tariff = coalesce(p_tariff, 0),
        filament_waste_percent = coalesce(p_waste_percent, 0),
        updated_at = now(),
        updated_by = auth.uid()
    where id = true;
end;
$function$;

create or replace function public.set_calc_start_date(p_date date)
returns void
language plpgsql
security definer
as $function$
begin
  if not is_superadmin() then
    raise exception 'Лише суперадміністратор може змінювати цю дату.';
  end if;

  update public.studio_settings
    set calc_start_date = p_date,
        updated_at = now(),
        updated_by = auth.uid()
    where id = true;

  if p_date is not null then
    update public.lessons
      set payroll_amount = 0, price_amount = 0
      where date < p_date
        and (payroll_amount <> 0 or price_amount <> 0);
  end if;
end;
$function$;

commit;

notify pgrst, 'reload schema';
