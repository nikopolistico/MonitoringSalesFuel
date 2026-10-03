-- =====================================================================
--  MIGRATION: each pump attendant sees ONLY their own shift reports.
--  For a database that was set up with the older schema.sql.
--  Keeps all data. Safe to run more than once.
--
--  Paste into Supabase > SQL Editor > New query > Run.
--  (A fresh install only needs schema.sql — it already includes this.)
-- =====================================================================

-- 1. Old sheets with no "prepared by": give them to the attendant who created them
update public.shift_reports s
   set prepared_by = a.pump_attendant_id
  from public.user_accounts a
 where s.prepared_by is null
   and a.id = s.created_by
   and a.pump_attendant_id is not null;

-- 2. One sheet per date + shift PER ATTENDANT (coworkers each keep their own)
alter table public.shift_reports drop constraint if exists shift_reports_report_date_shift_id_key;
alter table public.shift_reports drop constraint if exists shift_reports_report_date_shift_id_prepared_by_key;
alter table public.shift_reports
  add constraint shift_reports_report_date_shift_id_prepared_by_key
  unique (report_date, shift_id, prepared_by);
create index if not exists shift_reports_prepared_by_idx on public.shift_reports (prepared_by);

-- 3. Helpers
create or replace function public.current_attendant_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select pump_attendant_id from user_accounts where id = public.current_account_id()
$$;

create or replace function public.can_access_report(p_report uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from shift_reports
    where id = p_report
      and prepared_by = public.current_attendant_id()
  )
$$;

create or replace function public.sheet_defaults()
returns json
language sql stable security definer
set search_path = public
as $$
  select case when public.current_account_id() is null then null else json_build_object(
    'last_report', (
      select json_build_object('report_date', report_date, 'shift_id', shift_id)
      from shift_reports order by report_date desc, shift_id desc limit 1),
    'readings', coalesce((
      select json_agg(json_build_object('pump_id', pump_id, 'second_reading', second_reading))
      from (select distinct on (r.pump_id) r.pump_id, r.second_reading
            from fuel_readings r join shift_reports s on s.id = r.shift_report_id
            order by r.pump_id, s.report_date desc, s.shift_id desc, r.second_reading desc) x),
      '[]'::json),
    'prices', coalesce((
      select json_agg(json_build_object(
               'fuel_type_id', fuel_type_id, 'price_per_liter', price_per_liter, 'markup', markup))
      from (select distinct on (sp.fuel_type_id) sp.fuel_type_id, sp.price_per_liter, sp.markup
            from shift_fuel_prices sp join shift_reports s on s.id = sp.shift_report_id
            order by sp.fuel_type_id, s.report_date desc, s.shift_id desc) x),
      '[]'::json)
  ) end
$$;

-- 4. Saving: attendants always save as themselves
create or replace function public.save_shift_report(p jsonb)
returns uuid
language plpgsql security invoker
set search_path = public
as $$
declare
  v_id uuid := nullif(p->>'id', '')::uuid;
  -- attendants always save as themselves; only the admin may choose
  v_by uuid := case when public.is_admin() then nullif(p->>'prepared_by', '')::uuid
                    else public.current_attendant_id() end;
begin
  if public.current_account_id() is null then
    raise exception 'Please sign in again';
  end if;

  if v_id is null then
    insert into shift_reports
      (report_date, shift_id, prepared_by, total_error, total_discount, remarks, created_by)
    values (
      (p->>'report_date')::date,
      (p->>'shift_id')::smallint,
      v_by,
      coalesce((p->>'total_error')::numeric, 0),
      coalesce((p->>'total_discount')::numeric, 0),
      nullif(p->>'remarks', ''),
      public.current_account_id())
    returning id into v_id;
  else
    update shift_reports set
      report_date    = (p->>'report_date')::date,
      shift_id       = (p->>'shift_id')::smallint,
      prepared_by    = v_by,
      total_error    = coalesce((p->>'total_error')::numeric, 0),
      total_discount = coalesce((p->>'total_discount')::numeric, 0),
      remarks        = nullif(p->>'remarks', '')
    where id = v_id;
    if not found then
      raise exception 'Shift report % not found', v_id;
    end if;

    delete from fuel_readings     where shift_report_id = v_id;
    delete from shift_fuel_prices where shift_report_id = v_id;
    delete from expenses          where shift_report_id = v_id;
    delete from cash_counts       where shift_report_id = v_id;
    delete from shortage_overage  where shift_report_id = v_id;
    delete from receivables       where shift_report_id = v_id;
    delete from payments          where shift_report_id = v_id;
  end if;

  insert into shift_fuel_prices (shift_report_id, fuel_type_id, price_per_liter, markup)
  select v_id, x.fuel_type_id, x.price_per_liter, coalesce(x.markup, 0)
  from jsonb_to_recordset(coalesce(p->'prices', '[]'::jsonb))
    as x(fuel_type_id uuid, price_per_liter numeric, markup numeric);

  insert into fuel_readings (shift_report_id, pump_id, first_reading, second_reading)
  select v_id, x.pump_id, x.first_reading, x.second_reading
  from jsonb_to_recordset(coalesce(p->'readings', '[]'::jsonb))
    as x(pump_id uuid, first_reading numeric, second_reading numeric);

  if exists (
    select 1 from fuel_readings r
    join pumps pu on pu.id = r.pump_id
    left join shift_fuel_prices sp
      on sp.shift_report_id = r.shift_report_id and sp.fuel_type_id = pu.fuel_type_id
    where r.shift_report_id = v_id and sp.fuel_type_id is null
  ) then
    raise exception 'Every fuel type with a reading needs a price per liter';
  end if;

  insert into expenses (shift_report_id, kind, description, amount, sort_order)
  select v_id,
         coalesce(nullif(e.val->>'kind', ''), 'EXPENSE'),
         e.val->>'description',
         (e.val->>'amount')::numeric,
         e.ord::int
  from jsonb_array_elements(coalesce(p->'expenses', '[]'::jsonb)) with ordinality as e(val, ord);

  insert into cash_counts (shift_report_id, denomination_id, pieces)
  select v_id, x.denomination_id, x.pieces
  from jsonb_to_recordset(coalesce(p->'cash_counts', '[]'::jsonb))
    as x(denomination_id smallint, pieces int)
  where x.pieces > 0;

  insert into payments (shift_report_id, payment_method_id, reference_no, amount)
  select v_id, x.payment_method_id, nullif(trim(x.reference_no), ''), x.amount
  from jsonb_to_recordset(coalesce(p->'payments', '[]'::jsonb))
    as x(payment_method_id smallint, reference_no text, amount numeric)
  where x.amount > 0;

  insert into shortage_overage (shift_report_id, pump_attendant_id, amount, remarks)
  select v_id, x.pump_attendant_id, x.amount, nullif(x.remarks, '')
  from jsonb_to_recordset(coalesce(p->'shortage_overage', '[]'::jsonb))
    as x(pump_attendant_id uuid, amount numeric, remarks text);

  -- receivables: add any new company names first
  insert into companies (name)
  select distinct upper(trim(x.company_name))
  from jsonb_to_recordset(coalesce(p->'receivables', '[]'::jsonb)) as x(company_name text)
  on conflict (name) do nothing;

  insert into receivables (shift_report_id, company_id, receivable_date, liters, price_per_liter)
  select v_id, c.id, x.receivable_date, x.liters, x.price_per_liter
  from jsonb_to_recordset(coalesce(p->'receivables', '[]'::jsonb))
    as x(receivable_date date, company_name text, liters numeric, price_per_liter numeric)
  join companies c on c.name = upper(trim(x.company_name));

  return v_id;
end $$;

-- 5. Replace the "everyone can read everything" policies
do $$
declare t text;
begin
  foreach t in array array[
    'pump_attendants', 'user_accounts', 'fuel_types', 'pumps', 'shifts', 'denominations',
    'payment_methods', 'payments', 'companies', 'shift_reports', 'shift_fuel_prices',
    'fuel_readings', 'expenses', 'cash_counts', 'shortage_overage', 'receivables'
  ] loop
    execute format('drop policy if exists "signed in can read" on public.%I', t);
    execute format('drop policy if exists "signed in can write" on public.%I', t);
    execute format('drop policy if exists "own reports only" on public.%I', t);
  end loop;

  -- lookups readable by every signed-in account
  foreach t in array array[
    'fuel_types', 'pumps', 'shifts', 'denominations', 'payment_methods', 'companies'
  ] loop
    execute format(
      'create policy "signed in can read" on public.%I for select to anon, authenticated
         using (public.current_account_id() is not null)', t);
  end loop;

  -- sheet details: only whoever may open the sheet itself
  foreach t in array array[
    'shift_fuel_prices', 'fuel_readings', 'expenses',
    'cash_counts', 'payments', 'shortage_overage', 'receivables'
  ] loop
    execute format(
      'create policy "own reports only" on public.%I for all to anon, authenticated
         using (public.can_access_report(shift_report_id))
         with check (public.can_access_report(shift_report_id))', t);
  end loop;
end $$;

drop policy if exists "own person only"         on public.pump_attendants;
drop policy if exists "signed in can add"        on public.companies;
drop policy if exists "signed in can insert"     on public.shift_reports;
drop policy if exists "signed in can update"     on public.shift_reports;
drop policy if exists "own reports only insert"  on public.shift_reports;
drop policy if exists "own reports only update"  on public.shift_reports;
drop policy if exists "charge only yourself"     on public.shortage_overage;
drop policy if exists "own account only"         on public.user_accounts;

create policy "own person only" on public.pump_attendants for select to anon, authenticated
  using (public.is_admin() or id = public.current_attendant_id());

create policy "signed in can add" on public.companies for insert to anon, authenticated
  with check (public.current_account_id() is not null);

create policy "own reports only" on public.shift_reports for select to anon, authenticated
  using (public.is_admin() or prepared_by = public.current_attendant_id());
create policy "own reports only insert" on public.shift_reports for insert to anon, authenticated
  with check (public.is_admin() or prepared_by = public.current_attendant_id());
create policy "own reports only update" on public.shift_reports for update to anon, authenticated
  using (public.is_admin() or prepared_by = public.current_attendant_id())
  with check (public.is_admin() or prepared_by = public.current_attendant_id());

create policy "charge only yourself" on public.shortage_overage as restrictive
  for insert to anon, authenticated
  with check (public.is_admin() or pump_attendant_id = public.current_attendant_id());

create policy "own account only" on public.user_accounts for select to anon, authenticated
  using (public.is_admin() or id = public.current_account_id());

revoke all on function public.sheet_defaults() from public;
grant execute on function public.sheet_defaults() to anon, authenticated;
