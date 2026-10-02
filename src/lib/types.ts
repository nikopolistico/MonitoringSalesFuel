export interface Account {
  id: string
  username: string
  role: 'ADMIN' | 'ATTENDANT'
  /** null for the admin account (the admin is not a pump attendant) */
  pump_attendant_id: string | null
  full_name: string
}

export type AccountStatus = 'ACTIVE' | 'DISABLED'

export interface UserAccount {
  id: string
  pump_attendant_id: string | null
  username: string
  role: Account['role']
  status: AccountStatus
  created_at: string
  last_login_at: string | null
}

export interface PumpAttendant {
  id: string
  full_name: string
  nickname: string | null
  contact_no: string | null
  is_active: boolean
}

export interface FuelType {
  id: string
  name: string
  color: string
  default_price: number | null
  default_markup: number
  sort_order: number
  is_active: boolean
}

export interface Pump {
  id: string
  fuel_type_id: string
  pump_number: number
  is_active: boolean
}

export interface Shift {
  id: number
  name: string
  hours: string | null
}

export interface PaymentMethod {
  id: number
  name: string
}

export interface Denomination {
  id: number
  value: number
}

export interface ShiftReportSummary {
  id: string
  report_date: string
  shift_id: number
  shift_name: string
  shift_hours: string | null
  prepared_by: string | null
  prepared_by_name: string | null
  total_sales_machine: number
  total_liters: number
  total_income: number
  total_after_error_discount: number
  total_expenses: number
  total_supplier_payments: number
  total_cash: number
  gcash_total: number
  total_payments: number
  grand_total: number
  total_receivable: number
  total_accounted: number
  over_short: number
}

/* ---------- form models (numbers may be null while typing) ---------- */

export interface ReadingRow {
  pump_id: string
  first_reading: number | null
  second_reading: number | null
}

export interface PriceRow {
  price_per_liter: number | null
  markup: number | null
}

export interface ExpenseRow {
  kind: 'EXPENSE' | 'SUPPLIER'
  description: string
  amount: number | null
}

export interface PaymentRow {
  payment_method_id: number
  reference_no: string
  amount: number | null
}

export interface ShortageRow {
  pump_attendant_id: string
  amount: number | null
  remarks: string
}

export interface ReceivableRow {
  receivable_date: string
  company_name: string
  liters: number | null
  price_per_liter: number | null
}
