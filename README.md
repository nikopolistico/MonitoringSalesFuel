# RCJA Powerfuel — Daily Sales Monitoring

Website version of the RCJA Powerfuel Gasoline Station daily sales sheet (Vue 3 + Supabase).

## What it does

| Pump attendant types | System computes automatically |
| --- | --- |
| First & second reading per pump, price per liter per fuel type | Liters, total sales per pump, total sales from machine |
| Total error / total discount | Total after error & discount |
| Mark up per fuel type | Income per liter and total income |
| Expenses and payments to suppliers | Expense totals |
| Denomination pieces (1000 … 1) | Sub totals, total cash |
| GCash payments (amount + reference no.) | Total GCash, grand total |
| Receivables (company, liters, price/L) | Receivable amount and total |
| Who is charged the shortage/overage | **Over / Short** = cash + GCash + expenses + suppliers + receivables − total after error & discount |

A new sheet pre-fills each pump's **first reading from the previous shift's second reading**, and
prices / mark ups from the last shift.

## Database (3NF) — `supabase/schema.sql`

| Group | Tables |
| --- | --- |
| People & login | `pump_attendants`, `user_accounts` (username + bcrypt password, ADMIN / ATTENDANT, enabled/disabled), `user_sessions` |
| Master data | `fuel_types`, `pumps`, `shifts`, `denominations`, `payment_methods`, `companies` |
| Shift sheet | `shift_reports` (header), `shift_fuel_prices`, `fuel_readings`, `expenses`, `cash_counts`, `payments`, `shortage_overage`, `receivables` |

Computed values (liters, sales, sub totals, totals, over/short) are **not stored**; they come from
the views `v_fuel_sales` and `shift_report_summary`, so they can never disagree with the inputs.

## Two separate areas (no email needed)

| | Pump attendant site | Admin dashboard |
| --- | --- | --- |
| Sign in at | `/login` | `/admin/login` |
| Login | created by the admin | `nikoadmin` / `niko16131` (created by `schema.sql`) |
| Can use | Reports, New Shift | Dashboard, Reports, Pump Attendants, Fuel Types |

- The admin creates each pump attendant and (optionally) their username + password.
- The admin can change an attendant's login, disable/enable it, and delete reports.
- Each role can only sign in on its own page.

## Setup

1. Create a project at [supabase.com](https://supabase.com).
2. Supabase → **SQL Editor** → New query → paste all of [`supabase/schema.sql`](supabase/schema.sql) → **Run**.
   ⚠️ Re-running it **drops and recreates** all tables, deleting saved data.
3. Copy `.env.example` to `.env` and fill in **Project Settings → API**: Project URL and anon key.
4. Run:

```sh
npm install
npm run dev
```

5. Open `/admin/login`, sign in as `nikoadmin`, and create your pump attendants under
   **Pump Attendants**. Attendants then sign in at `/login`.

## Build for hosting

```sh
npm run build   # output in dist/
```

Deploy `dist/` to Netlify, Vercel, etc., with the same `VITE_` env vars, and add an SPA rewrite
(all paths → `/index.html`).
