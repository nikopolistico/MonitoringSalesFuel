-- =====================================================================
--  RCJA POWERFUEL — Gasoline Station Daily Sales Monitoring
--  Normalized to 3NF. Uses its own username/password accounts
--  (no Supabase email auth needed).
--
--  Admin dashboard login (created at the bottom of this file):
--      username: nikoadmin      password: niko16131
--  Pump attendant logins are created by the admin in the dashboard.
--
--  Paste this whole file into Supabase > SQL Editor > New query > Run.
--  WARNING: re-running DROPS and recreates every app table (data is lost).
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
--  Clean slate (also removes tables from the earlier version)
-- ---------------------------------------------------------------------
drop view     if exists public.shift_report_summary;
drop view     if exists public.v_fuel_sales;
drop function if exists public.save_shift_report(jsonb);
drop function if exists public.sign_up(text, text, text, text, text);
drop function if exists public.admin_create_attendant(text, text, text, text, text);
drop function if exists public.admin_set_login(uuid, text, text);
drop function if exists public.sign_in(text, text);
drop function if exists public.sign_out();
drop function if exists public.me();
drop function if exists public.admin_reset_password(uuid, text);
drop table    if exists public.payments          cascade;
drop table    if exists public.payment_methods   cascade;
drop table    if exists public.receivables       cascade;
drop table    if exists public.companies         cascade;
drop table    if exists public.shortage_overage  cascade;
drop table    if exists public.cash_counts       cascade;
drop table    if exists public.denominations     cascade;
drop table    if exists public.expenses          cascade;
drop table    if exists public.fuel_readings     cascade;
drop table    if exists public.shift_fuel_prices cascade;
drop table    if exists public.shift_reports     cascade;
drop table    if exists public.shifts            cascade;
drop table    if exists public.pumps             cascade;
drop table    if exists public.fuel_types        cascade;
drop table    if exists public.user_sessions     cascade;
drop table    if exists public.user_accounts     cascade;
drop table    if exists public.pump_attendants   cascade;
drop function if exists public.current_account_id();
drop function if exists public.is_admin();
drop function if exists public.set_updated_at();

create function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- =====================================================================
--  PEOPLE & ACCOUNTS
-- =====================================================================

-- 1. PUMP ATTENDANTS — the person
create table public.pump_attendants (
  id          uuid primary key default gen_random_uuid(),
  full_name   text not null,
  nickname    text,
  contact_no  text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- 2. USER ACCOUNTS — login credentials, kept apart from the person
--    ADMIN accounts log in to the admin dashboard and are not pump attendants.
--    ATTENDANT accounts always belong to exactly one pump attendant.
create table public.user_accounts (
  id                 uuid primary key default gen_random_uuid(),
  pump_attendant_id  uuid unique references public.pump_attendants(id) on delete cascade,
  username           text not null unique check (username ~ '^[a-z0-9._]{3,30}$'),
  password_hash      text not null,
  role               text not null default 'ATTENDANT' check (role in ('ADMIN', 'ATTENDANT')),
  status             text not null default 'ACTIVE' check (status in ('ACTIVE', 'DISABLED')),
  created_at         timestamptz not null default now(),
  last_login_at      timestamptz,
  constraint attendant_account_has_person
    check ((role = 'ADMIN') = (pump_attendant_id is null))
);

-- 3. USER SESSIONS — login tokens (never readable from the website)
create table public.user_sessions (
  token            text primary key default gen_random_uuid()::text,
  user_account_id  uuid not null references public.user_accounts(id) on delete cascade,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default now() + interval '7 days'
);
create index on public.user_sessions (user_account_id);

-- =====================================================================
--  MASTER DATA (lookups)
-- =====================================================================

-- 4. FUEL TYPES — PREMIUM / REGULAR / DIESEL
create table public.fuel_types (
  id              uuid primary key default gen_random_uuid(),
  name            text not null unique,
  color           text not null default '#9ca3af',
  default_price   numeric(10,2),                        -- pre-fills Price per Liter
  default_markup  numeric(10,2) not null default 0,     -- pre-fills Mark Up
  sort_order      int  not null default 0,
  is_active       boolean not null default true
);

-- 5. PUMPS — the numbered nozzle of a fuel type (PREMIUM 1, DIESEL 3, ...)
create table public.pumps (
  id            uuid primary key default gen_random_uuid(),
  fuel_type_id  uuid not null references public.fuel_types(id) on delete restrict,
  pump_number   int  not null check (pump_number > 0),
  is_active     boolean not null default true,
  unique (fuel_type_id, pump_number)
);

-- 6. SHIFTS — 1st / 2nd with their hours
create table public.shifts (
  id          smallint primary key,
  name        text not null unique,
  hours       text
);

-- 7. DENOMINATIONS — bills / coins counted in the cash count
create table public.denominations (
  id     smallint primary key,
  value  int not null unique check (value > 0)
);

-- 8. COMPANIES — customers with receivables (credit)
create table public.companies (
  id    uuid primary key default gen_random_uuid(),
  name  text not null unique
);

-- 9. PAYMENT METHODS — non-cash payments (GCASH, ...)
create table public.payment_methods (
  id    smallint primary key,
  name  text not null unique
);

-- =====================================================================
--  TRANSACTIONS (one sheet = one shift report)
-- =====================================================================

-- 10. SHIFT REPORTS — the sheet header only
create table public.shift_reports (
  id              uuid primary key default gen_random_uuid(),
  report_date     date not null default current_date,
  shift_id        smallint not null references public.shifts(id),
  prepared_by     uuid references public.pump_attendants(id) on delete set null,
  total_error     numeric(12,2) not null default 0 check (total_error >= 0),
  total_discount  numeric(12,2) not null default 0 check (total_discount >= 0),
  remarks         text,
  created_by      uuid references public.user_accounts(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (report_date, shift_id)
);
create trigger shift_reports_updated_at
  before update on public.shift_reports
  for each row execute function public.set_updated_at();

-- 11. SHIFT FUEL PRICES — price per liter & mark up for each fuel type in that shift
create table public.shift_fuel_prices (
  shift_report_id  uuid not null references public.shift_reports(id) on delete cascade,
  fuel_type_id     uuid not null references public.fuel_types(id) on delete restrict,
  price_per_liter  numeric(10,2) not null check (price_per_liter >= 0),
  markup           numeric(10,2) not null default 0,
  primary key (shift_report_id, fuel_type_id)
);

-- 12. FUEL READINGS — only the two meter readings are stored;
--     liters and total sales are derived in the views below.
create table public.fuel_readings (
  shift_report_id  uuid not null references public.shift_reports(id) on delete cascade,
  pump_id          uuid not null references public.pumps(id) on delete restrict,
  first_reading    numeric(14,3) not null check (first_reading >= 0),
  second_reading   numeric(14,3) not null,
  primary key (shift_report_id, pump_id),
  constraint second_reading_not_lower check (second_reading >= first_reading)
);

-- 13. EXPENSES — EXPENSE = "input your expenses", SUPPLIER = "payment to suppliers"
create table public.expenses (
  id               uuid primary key default gen_random_uuid(),
  shift_report_id  uuid not null references public.shift_reports(id) on delete cascade,
  kind             text not null default 'EXPENSE' check (kind in ('EXPENSE', 'SUPPLIER')),
  description      text not null,
  amount           numeric(12,2) not null check (amount >= 0),
  sort_order       int not null default 0
);
create index on public.expenses (shift_report_id);

-- 14. CASH COUNTS — pieces per denomination (sub total derived in view)
create table public.cash_counts (
  shift_report_id  uuid not null references public.shift_reports(id) on delete cascade,
  denomination_id  smallint not null references public.denominations(id),
  pieces           int not null check (pieces >= 0),
  primary key (shift_report_id, denomination_id)
);

-- 15. SHORTAGE / OVERAGE — charged per attendant (negative = short, positive = over)
create table public.shortage_overage (
  id                uuid primary key default gen_random_uuid(),
  shift_report_id   uuid not null references public.shift_reports(id) on delete cascade,
  pump_attendant_id uuid not null references public.pump_attendants(id) on delete restrict,
  amount            numeric(12,2) not null,
  remarks           text,
  unique (shift_report_id, pump_attendant_id)
);
create index on public.shortage_overage (pump_attendant_id);

-- 16. RECEIVABLES — credit sales (amount derived in view)
create table public.receivables (
  id               uuid primary key default gen_random_uuid(),
  shift_report_id  uuid not null references public.shift_reports(id) on delete cascade,
  company_id       uuid not null references public.companies(id) on delete restrict,
  receivable_date  date,
  liters           numeric(12,3) not null check (liters >= 0),
  price_per_liter  numeric(10,2) not null check (price_per_liter >= 0)
);
create index on public.receivables (shift_report_id);

-- 17. PAYMENTS — non-cash payments received in the shift (each GCash transfer)
create table public.payments (
  id                 uuid primary key default gen_random_uuid(),
  shift_report_id    uuid not null references public.shift_reports(id) on delete cascade,
  payment_method_id  smallint not null references public.payment_methods(id),
  reference_no       text,
  amount             numeric(12,2) not null check (amount > 0)
);
create index on public.payments (shift_report_id);

-- =====================================================================
--  ACCOUNT HELPERS — the website sends the login token in the
--  "x-session-token" request header; policies use these helpers.
-- =====================================================================
create function public.current_account_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select a.id
  from user_sessions s
  join user_accounts a on a.id = s.user_account_id
  where s.token = nullif(current_setting('request.headers', true), '')::json ->> 'x-session-token'
    and s.expires_at > now()
    and a.status = 'ACTIVE'
$$;

create function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from user_accounts
    where id = public.current_account_id() and role = 'ADMIN'
  )
$$;

-- Account JSON returned to the website
create function public.me()
returns json
language sql stable security definer
set search_path = public
as $$
  select json_build_object(
    'id', a.id, 'username', a.username, 'role', a.role,
    'pump_attendant_id', a.pump_attendant_id,
    'full_name', coalesce(p.full_name, 'Administrator'))
  from user_accounts a
  left join pump_attendants p on p.id = a.pump_attendant_id
  where a.id = public.current_account_id()
$$;

-- ADMIN: give a pump attendant a login (or change their username + password)
create function public.admin_set_login(p_attendant_id uuid, p_username text, p_password text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_username text := lower(trim(p_username));
begin
  if not public.is_admin() then
    raise exception 'Only the admin can manage logins';
  end if;
  if v_username !~ '^[a-z0-9._]{3,30}$' then
    raise exception 'Username must be 3-30 characters: letters, numbers, dot or underscore';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if exists (select 1 from user_accounts
             where username = v_username
               and pump_attendant_id is distinct from p_attendant_id) then
    raise exception 'Username "%" is already taken', v_username;
  end if;

  insert into user_accounts (pump_attendant_id, username, password_hash, role)
  values (p_attendant_id, v_username, crypt(p_password, gen_salt('bf')), 'ATTENDANT')
  on conflict (pump_attendant_id) do update
    set username = excluded.username, password_hash = excluded.password_hash;

  -- sign the attendant out everywhere so the new password takes effect
  delete from user_sessions s using user_accounts a
  where a.id = s.user_account_id and a.pump_attendant_id = p_attendant_id;
end $$;

-- ADMIN: create a pump attendant, with a login when username + password are given
create function public.admin_create_attendant(
  p_full_name text, p_nickname text, p_contact_no text, p_username text, p_password text)
returns uuid
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_person uuid;
begin
  if not public.is_admin() then
    raise exception 'Only the admin can create pump attendants';
  end if;
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'Full name is required';
  end if;

  insert into pump_attendants (full_name, nickname, contact_no)
  values (trim(p_full_name), nullif(trim(p_nickname), ''), nullif(trim(p_contact_no), ''))
  returning id into v_person;

  if coalesce(trim(p_username), '') <> '' or coalesce(p_password, '') <> '' then
    perform public.admin_set_login(v_person, p_username, p_password);
  end if;
  return v_person;
end $$;

-- SIGN IN — returns { token, account }
create function public.sign_in(p_username text, p_password text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  a      user_accounts;
  v_tok  text;
begin
  select * into a from user_accounts where username = lower(trim(p_username));
  if a.id is null or a.password_hash <> crypt(p_password, a.password_hash) then
    raise exception 'Invalid username or password';
  end if;
  if a.status = 'DISABLED' then
    raise exception 'Your account is disabled. Please contact the admin';
  end if;

  delete from user_sessions where expires_at < now();
  insert into user_sessions (user_account_id) values (a.id) returning token into v_tok;
  update user_accounts set last_login_at = now() where id = a.id;

  return json_build_object(
    'token', v_tok,
    'account', (select json_build_object(
                  'id', a.id, 'username', a.username, 'role', a.role,
                  'pump_attendant_id', a.pump_attendant_id,
                  'full_name', coalesce(p.full_name, 'Administrator'))
                from (select 1) one
                left join pump_attendants p on p.id = a.pump_attendant_id));
end $$;

create function public.sign_out()
returns void
language sql security definer
set search_path = public
as $$
  delete from user_sessions
  where token = nullif(current_setting('request.headers', true), '')::json ->> 'x-session-token'
$$;

-- =====================================================================
--  VIEWS — every computed column on the sheet
-- =====================================================================

-- Per pump: LITERS and TOTAL SALES
create view public.v_fuel_sales
with (security_invoker = true) as
select r.shift_report_id,
       r.pump_id,
       ft.id                                   as fuel_type_id,
       ft.name || ' ' || p.pump_number         as pump_name,
       r.first_reading,
       r.second_reading,
       r.second_reading - r.first_reading      as liters,
       sp.price_per_liter,
       sp.markup,
       round((r.second_reading - r.first_reading) * sp.price_per_liter, 2) as total_sales
from public.fuel_readings r
join public.pumps p              on p.id = r.pump_id
join public.fuel_types ft        on ft.id = p.fuel_type_id
join public.shift_fuel_prices sp on sp.shift_report_id = r.shift_report_id
                                and sp.fuel_type_id    = p.fuel_type_id;

-- One row per sheet with every total
--   over_short = (cash + payments(gcash) + expenses + suppliers + receivables) - total_after_error_discount
create view public.shift_report_summary
with (security_invoker = true) as
with fs as (
  select shift_report_id,
         sum(total_sales)                  as total_sales_machine,
         sum(liters)                       as total_liters,
         round(sum(liters * markup), 2)    as total_income
  from public.v_fuel_sales group by shift_report_id
), ex as (
  select shift_report_id,
         sum(amount) filter (where kind = 'EXPENSE')  as total_expenses,
         sum(amount) filter (where kind = 'SUPPLIER') as total_supplier_payments
  from public.expenses group by shift_report_id
), cc as (
  select c.shift_report_id, sum(d.value * c.pieces)::numeric(14,2) as total_cash
  from public.cash_counts c join public.denominations d on d.id = c.denomination_id
  group by c.shift_report_id
), pm as (
  select p.shift_report_id,
         sum(p.amount)                                as total_payments,
         sum(p.amount) filter (where m.name = 'GCASH') as gcash_total
  from public.payments p join public.payment_methods m on m.id = p.payment_method_id
  group by p.shift_report_id
), rc as (
  select shift_report_id, sum(round(liters * price_per_liter, 2)) as total_receivable
  from public.receivables group by shift_report_id
), base as (
  select s.id, s.report_date, s.shift_id,
         sh.name                                         as shift_name,
         sh.hours                                        as shift_hours,
         s.prepared_by,
         pa.full_name                                    as prepared_by_name,
         s.total_error, s.total_discount, s.remarks,
         coalesce(fs.total_sales_machine, 0)             as total_sales_machine,
         coalesce(fs.total_liters, 0)                    as total_liters,
         coalesce(fs.total_income, 0)                    as total_income,
         coalesce(fs.total_sales_machine, 0) - s.total_error - s.total_discount
                                                         as total_after_error_discount,
         coalesce(ex.total_expenses, 0)                  as total_expenses,
         coalesce(ex.total_supplier_payments, 0)         as total_supplier_payments,
         coalesce(cc.total_cash, 0)                      as total_cash,
         coalesce(pm.gcash_total, 0)                     as gcash_total,
         coalesce(pm.total_payments, 0)                  as total_payments,
         coalesce(cc.total_cash, 0) + coalesce(pm.total_payments, 0)
                                                         as grand_total,
         coalesce(rc.total_receivable, 0)                as total_receivable
  from public.shift_reports s
  join public.shifts sh               on sh.id = s.shift_id
  left join public.pump_attendants pa on pa.id = s.prepared_by
  left join fs on fs.shift_report_id = s.id
  left join ex on ex.shift_report_id = s.id
  left join cc on cc.shift_report_id = s.id
  left join pm on pm.shift_report_id = s.id
  left join rc on rc.shift_report_id = s.id
)
select base.*,
       grand_total + total_expenses + total_supplier_payments + total_receivable
         as total_accounted,
       grand_total + total_expenses + total_supplier_payments + total_receivable
         - total_after_error_discount
         as over_short
from base;

-- =====================================================================
--  SAVE A WHOLE SHEET IN ONE TRANSACTION
--  supabase.rpc('save_shift_report', { p: {...} })
-- =====================================================================
create function public.save_shift_report(p jsonb)
returns uuid
language plpgsql security invoker
set search_path = public
as $$
declare
  v_id uuid := nullif(p->>'id', '')::uuid;
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
      nullif(p->>'prepared_by', '')::uuid,
      coalesce((p->>'total_error')::numeric, 0),
      coalesce((p->>'total_discount')::numeric, 0),
      nullif(p->>'remarks', ''),
      public.current_account_id())
    returning id into v_id;
  else
    update shift_reports set
      report_date    = (p->>'report_date')::date,
      shift_id       = (p->>'shift_id')::smallint,
      prepared_by    = nullif(p->>'prepared_by', '')::uuid,
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

-- =====================================================================
--  SECURITY (Row Level Security)
--    * any ACTIVE account can read everything and enter shift data
--    * only ADMIN can manage master data, approve accounts, delete reports
--    * password hashes and session tokens are never exposed
-- =====================================================================
do $$
declare t text;
begin
  -- readable by every signed-in account
  foreach t in array array[
    'pump_attendants', 'user_accounts', 'fuel_types', 'pumps', 'shifts', 'denominations',
    'payment_methods', 'payments', 'companies', 'shift_reports', 'shift_fuel_prices', 'fuel_readings', 'expenses',
    'cash_counts', 'shortage_overage', 'receivables'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "signed in can read" on public.%I for select to anon, authenticated
         using (public.current_account_id() is not null)', t);
  end loop;

  -- master data: admin only
  foreach t in array array['pump_attendants', 'fuel_types', 'pumps', 'shifts', 'denominations', 'payment_methods'] loop
    execute format(
      'create policy "admin can write" on public.%I for all to anon, authenticated
         using (public.is_admin()) with check (public.is_admin())', t);
  end loop;

  -- shift data: any active account
  foreach t in array array[
    'companies', 'shift_fuel_prices', 'fuel_readings', 'expenses',
    'cash_counts', 'payments', 'shortage_overage', 'receivables'
  ] loop
    execute format(
      'create policy "signed in can write" on public.%I for all to anon, authenticated
         using (public.current_account_id() is not null)
         with check (public.current_account_id() is not null)', t);
  end loop;
end $$;

alter table public.user_sessions enable row level security;   -- no policies = no access

create policy "signed in can insert" on public.shift_reports for insert to anon, authenticated
  with check (public.current_account_id() is not null);
create policy "signed in can update" on public.shift_reports for update to anon, authenticated
  using (public.current_account_id() is not null);
create policy "admin can delete" on public.shift_reports for delete to anon, authenticated
  using (public.is_admin());
create policy "admin can update" on public.user_accounts for update to anon, authenticated
  using (public.is_admin()) with check (public.is_admin());

-- hide password hashes & tokens: only safe columns are granted
revoke all on public.user_accounts from anon, authenticated;
revoke all on public.user_sessions from anon, authenticated;
grant select (id, pump_attendant_id, username, role, status, created_at, last_login_at)
  on public.user_accounts to anon, authenticated;
grant update (status) on public.user_accounts to anon, authenticated;

grant select on public.v_fuel_sales, public.shift_report_summary to anon, authenticated;

revoke all on function public.save_shift_report(jsonb)            from public;
revoke all on function public.admin_set_login(uuid, text, text)   from public;
revoke all on function public.admin_create_attendant(text, text, text, text, text) from public;
grant execute on function public.admin_set_login(uuid, text, text)     to anon, authenticated;
grant execute on function public.admin_create_attendant(text, text, text, text, text)
  to anon, authenticated;
grant execute on function public.sign_in(text, text)                   to anon, authenticated;
grant execute on function public.sign_out()                            to anon, authenticated;
grant execute on function public.me()                                  to anon, authenticated;
grant execute on function public.save_shift_report(jsonb)              to anon, authenticated;

-- =====================================================================
--  SEED DATA
-- =====================================================================

-- Admin dashboard account. To change the password later, run:
--   update public.user_accounts
--      set password_hash = extensions.crypt('NEW-PASSWORD', extensions.gen_salt('bf'))
--    where username = 'nikoadmin';
insert into public.user_accounts (username, password_hash, role)
values ('nikoadmin', extensions.crypt('niko16131', extensions.gen_salt('bf')), 'ADMIN');

insert into public.shifts (id, name, hours) values
  (1, '1st', '6PM-6AM'),
  (2, '2nd', '6AM-6PM');

insert into public.payment_methods (id, name) values
  (1, 'GCASH');

insert into public.denominations (id, value) values
  (1, 1000), (2, 500), (3, 200), (4, 100), (5, 50), (6, 20), (7, 10), (8, 5), (9, 1);

insert into public.fuel_types (name, color, default_price, default_markup, sort_order) values
  ('PREMIUM', '#e11d2a', 88.40, 5.00, 1),
  ('REGULAR', '#16a34a', 88.20, 4.75, 2),
  ('DIESEL',  '#facc15', 98.00, 5.55, 3);

insert into public.pumps (fuel_type_id, pump_number)
select ft.id, n
from public.fuel_types ft
cross join lateral generate_series(1, case ft.name when 'DIESEL' then 4 else 2 end) as n;
