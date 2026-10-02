<script setup lang="ts">
import { computed, nextTick, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { toJpeg, toPng } from 'html-to-image'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { liters, longDate, money, monthName, round2, textOn, toNum, todayIso } from '@/lib/format'
import type {
  Denomination,
  ExpenseRow,
  FuelType,
  PaymentMethod,
  PaymentRow,
  PriceRow,
  Pump,
  PumpAttendant,
  ReadingRow,
  ReceivableRow,
  Shift,
  ShortageRow,
} from '@/lib/types'

const props = defineProps<{ id?: string }>()
const router = useRouter()
const auth = useAuthStore()
const base = computed(() => (auth.isAdmin ? '/admin/reports' : ''))

/* ------------------------------------------------------------------ state */

const loading = ref(true)
const saving = ref(false)
const error = ref('')
const notice = ref('')
const sheetEl = ref<HTMLElement | null>(null)
const exporting = ref(false)

const fuelTypes = ref<FuelType[]>([])
const pumps = ref<Pump[]>([])
const shifts = ref<Shift[]>([])
const denominations = ref<Denomination[]>([])
const paymentMethods = ref<PaymentMethod[]>([])
const attendants = ref<PumpAttendant[]>([])
const companies = ref<string[]>([])

const meta = reactive({
  report_date: todayIso(),
  shift_id: 1,
  prepared_by: '',
  total_error: null as number | null,
  total_discount: null as number | null,
  remarks: '',
})

const readings = ref<ReadingRow[]>([])
const prices = reactive<Record<string, PriceRow>>({})
const expenses = ref<ExpenseRow[]>([])
const suppliers = ref<ExpenseRow[]>([])
const pieces = reactive<Record<number, number | null>>({})
const payments = ref<PaymentRow[]>([])
const shortages = ref<ShortageRow[]>([])
const receivables = ref<ReceivableRow[]>([])

/* ---------------------------------------------------------------- lookups */

const fuelById = computed(() => new Map(fuelTypes.value.map((f) => [f.id, f])))
const pumpById = computed(() => new Map(pumps.value.map((p) => [p.id, p])))
const currentShift = computed(() => shifts.value.find((s) => s.id === meta.shift_id))
const gcashMethodId = computed(
  () =>
    paymentMethods.value.find((m) => m.name === 'GCASH')?.id ?? paymentMethods.value[0]?.id ?? 1,
)

function fuelOf(pumpId: string): FuelType | undefined {
  const p = pumpById.value.get(pumpId)
  return p ? fuelById.value.get(p.fuel_type_id) : undefined
}
function pumpName(pumpId: string): string {
  return `${fuelOf(pumpId)?.name ?? '?'} ${pumpById.value.get(pumpId)?.pump_number ?? ''}`
}
function priceOf(pumpId: string): PriceRow {
  const ft = fuelOf(pumpId)
  return ft
    ? (prices[ft.id] ??= { price_per_liter: ft.default_price, markup: ft.default_markup })
    : { price_per_liter: null, markup: null }
}

function blankExpense(kind: ExpenseRow['kind']): ExpenseRow {
  return { kind, description: '', amount: null }
}
function blankPayment(): PaymentRow {
  return { payment_method_id: gcashMethodId.value, reference_no: '', amount: null }
}

async function loadLookups() {
  const res = await Promise.all([
    supabase.from('fuel_types').select('*').order('sort_order').order('name'),
    supabase.from('pumps').select('*').order('pump_number'),
    supabase.from('shifts').select('*').order('id'),
    supabase.from('denominations').select('*').order('value', { ascending: false }),
    supabase.from('payment_methods').select('*').order('id'),
    supabase.from('pump_attendants').select('*').order('full_name'),
    supabase.from('companies').select('name').order('name'),
  ])
  const failed = res.find((r) => r.error)
  if (failed?.error) throw failed.error
  const [ft, pu, sh, dn, pm, pa, co] = res
  fuelTypes.value = (ft.data ?? []) as FuelType[]
  pumps.value = (pu.data ?? []) as Pump[]
  shifts.value = (sh.data ?? []) as Shift[]
  denominations.value = (dn.data ?? []) as Denomination[]
  paymentMethods.value = (pm.data ?? []) as PaymentMethod[]
  attendants.value = (pa.data ?? []) as PumpAttendant[]
  companies.value = ((co.data ?? []) as { name: string }[]).map((c) => c.name)
  for (const d of denominations.value) pieces[d.id] = null
}

/** Pumps shown on the sheet, in sheet order (fuel type sort order, then pump number). */
function sheetPumps(include: Set<string>): Pump[] {
  const order = new Map(fuelTypes.value.map((f, i) => [f.id, i]))
  return pumps.value
    .filter(
      (p) => include.has(p.id) || (p.is_active && fuelById.value.get(p.fuel_type_id)?.is_active),
    )
    .sort(
      (a, b) =>
        (order.get(a.fuel_type_id) ?? 0) - (order.get(b.fuel_type_id) ?? 0) ||
        a.pump_number - b.pump_number,
    )
}

/** New sheet: first reading = previous shift's second reading; prices = last prices used. */
async function prepareNew() {
  const { data: last, error: err } = await supabase
    .from('shift_reports')
    .select(
      'report_date, shift_id, fuel_readings(pump_id, second_reading), shift_fuel_prices(fuel_type_id, price_per_liter, markup)',
    )
    .order('report_date', { ascending: false })
    .order('shift_id', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (err) throw err

  const prevReading = new Map(
    (last?.fuel_readings ?? []).map((r: { pump_id: string; second_reading: number }) => [
      r.pump_id,
      Number(r.second_reading),
    ]),
  )
  for (const sp of (last?.shift_fuel_prices ?? []) as {
    fuel_type_id: string
    price_per_liter: number
    markup: number
  }[]) {
    prices[sp.fuel_type_id] = {
      price_per_liter: Number(sp.price_per_liter),
      markup: Number(sp.markup),
    }
  }
  for (const f of fuelTypes.value) {
    prices[f.id] ??= { price_per_liter: f.default_price, markup: Number(f.default_markup) }
  }

  readings.value = sheetPumps(new Set()).map((p) => ({
    pump_id: p.id,
    first_reading: prevReading.get(p.id) ?? null,
    second_reading: null,
  }))

  // Suggest the shift that follows the last saved one.
  meta.shift_id = shifts.value[0]?.id ?? 1
  if (last) {
    const next = shifts.value.find((s) => s.id > last.shift_id)
    if (next) {
      meta.report_date = last.report_date
      meta.shift_id = next.id
    }
  }
  meta.prepared_by = auth.account?.pump_attendant_id ?? ''
  expenses.value = [blankExpense('EXPENSE')]
  suppliers.value = [blankExpense('SUPPLIER')]
  payments.value = [blankPayment()]
}

type Saved = {
  report_date: string
  shift_id: number
  prepared_by: string | null
  total_error: number
  total_discount: number
  remarks: string | null
  shift_fuel_prices: { fuel_type_id: string; price_per_liter: number; markup: number }[]
  fuel_readings: { pump_id: string; first_reading: number; second_reading: number }[]
  expenses: { kind: ExpenseRow['kind']; description: string; amount: number; sort_order: number }[]
  cash_counts: { denomination_id: number; pieces: number }[]
  payments: { payment_method_id: number; reference_no: string | null; amount: number }[]
  shortage_overage: { pump_attendant_id: string; amount: number; remarks: string | null }[]
  receivables: {
    receivable_date: string | null
    liters: number
    price_per_liter: number
    companies: { name: string } | null
  }[]
}

async function loadExisting(id: string) {
  const { data, error: err } = await supabase
    .from('shift_reports')
    .select(
      '*, shift_fuel_prices(*), fuel_readings(*), expenses(*), cash_counts(*), payments(*), shortage_overage(*), receivables(*, companies(name))',
    )
    .eq('id', id)
    .single()
  if (err) throw err
  const d = data as unknown as Saved

  Object.assign(meta, {
    report_date: d.report_date,
    shift_id: d.shift_id,
    prepared_by: d.prepared_by ?? '',
    total_error: Number(d.total_error) || null,
    total_discount: Number(d.total_discount) || null,
    remarks: d.remarks ?? '',
  })

  for (const sp of d.shift_fuel_prices) {
    prices[sp.fuel_type_id] = {
      price_per_liter: Number(sp.price_per_liter),
      markup: Number(sp.markup),
    }
  }
  for (const f of fuelTypes.value) {
    prices[f.id] ??= { price_per_liter: f.default_price, markup: Number(f.default_markup) }
  }

  const saved = new Map(d.fuel_readings.map((r) => [r.pump_id, r]))
  readings.value = sheetPumps(new Set(saved.keys())).map((p) => {
    const r = saved.get(p.id)
    return {
      pump_id: p.id,
      first_reading: r ? Number(r.first_reading) : null,
      second_reading: r ? Number(r.second_reading) : null,
    }
  })

  const exp = [...d.expenses].sort((a, b) => a.sort_order - b.sort_order)
  const toRow = (e: Saved['expenses'][number]): ExpenseRow => ({
    kind: e.kind,
    description: e.description,
    amount: Number(e.amount),
  })
  expenses.value = exp.filter((e) => e.kind === 'EXPENSE').map(toRow)
  suppliers.value = exp.filter((e) => e.kind === 'SUPPLIER').map(toRow)
  if (!expenses.value.length) expenses.value.push(blankExpense('EXPENSE'))
  if (!suppliers.value.length) suppliers.value.push(blankExpense('SUPPLIER'))

  for (const c of d.cash_counts) pieces[c.denomination_id] = c.pieces || null

  payments.value = d.payments.map((p) => ({
    payment_method_id: p.payment_method_id,
    reference_no: p.reference_no ?? '',
    amount: Number(p.amount),
  }))
  if (!payments.value.length) payments.value.push(blankPayment())

  shortages.value = d.shortage_overage.map((s) => ({
    pump_attendant_id: s.pump_attendant_id,
    amount: Number(s.amount),
    remarks: s.remarks ?? '',
  }))

  receivables.value = d.receivables.map((r) => ({
    receivable_date: r.receivable_date ?? '',
    company_name: r.companies?.name ?? '',
    liters: Number(r.liters),
    price_per_liter: Number(r.price_per_liter),
  }))
}

async function init() {
  loading.value = true
  error.value = ''
  try {
    await loadLookups()
    if (props.id) await loadExisting(props.id)
    else await prepareNew()
  } catch (e) {
    error.value = e instanceof Error ? e.message : String((e as { message?: string })?.message ?? e)
  } finally {
    loading.value = false
  }
}

watch(() => props.id, init, { immediate: true })

/* ------------------------------------------------------------ computations */

const n = (v: unknown) => toNum(v) ?? 0

function rowLiters(r: ReadingRow): number {
  const a = toNum(r.first_reading)
  const b = toNum(r.second_reading)
  return a === null || b === null ? 0 : b - a
}
function rowSales(r: ReadingRow): number {
  return round2(rowLiters(r) * n(priceOf(r.pump_id).price_per_liter))
}
function rowInvalid(r: ReadingRow): boolean {
  const a = toNum(r.first_reading)
  const b = toNum(r.second_reading)
  return a !== null && b !== null && b < a
}
function hasReading(r: ReadingRow): boolean {
  return toNum(r.first_reading) !== null || toNum(r.second_reading) !== null
}

/** Readings grouped by fuel type, in sheet order. */
const groups = computed(() => {
  const out: { fuel: FuelType; rows: ReadingRow[] }[] = []
  for (const r of readings.value) {
    const fuel = fuelOf(r.pump_id)
    if (!fuel) continue
    const g = out.find((x) => x.fuel.id === fuel.id)
    if (g) g.rows.push(r)
    else out.push({ fuel, rows: [r] })
  }
  return out
})

const incomeRows = computed(() =>
  groups.value.map((g) => {
    const sales = round2(g.rows.reduce((s, r) => s + rowSales(r), 0))
    const ltrs = g.rows.reduce((s, r) => s + rowLiters(r), 0)
    const markup = n(prices[g.fuel.id]?.markup)
    return { fuel: g.fuel, sales, liters: ltrs, markup, income: round2(ltrs * markup) }
  }),
)

const sumAmounts = (rows: { amount: number | null }[]) =>
  round2(rows.reduce((s, e) => s + n(e.amount), 0))

const totalMachine = computed(() => round2(readings.value.reduce((s, r) => s + rowSales(r), 0)))
const totalLiters = computed(() => readings.value.reduce((s, r) => s + rowLiters(r), 0))
const totalIncome = computed(() =>
  round2(incomeRows.value.reduce((s, g) => s + g.liters * g.markup, 0)),
)
const totalAfter = computed(() =>
  round2(totalMachine.value - n(meta.total_error) - n(meta.total_discount)),
)
const totalExpenses = computed(() => sumAmounts(expenses.value))
const totalSuppliers = computed(() => sumAmounts(suppliers.value))
const totalReceivable = computed(() =>
  round2(receivables.value.reduce((s, r) => s + round2(n(r.liters) * n(r.price_per_liter)), 0)),
)
const totalCash = computed(() =>
  denominations.value.reduce((s, d) => s + d.value * n(pieces[d.id]), 0),
)
const totalPayments = computed(() => sumAmounts(payments.value))
const paymentTotalsByMethod = computed(() =>
  paymentMethods.value
    .map((m) => ({
      name: m.name,
      total: sumAmounts(payments.value.filter((p) => p.payment_method_id === m.id)),
    }))
    .filter((m) => m.total !== 0 || m.name === 'GCASH'),
)
const grandTotal = computed(() => round2(totalCash.value + totalPayments.value))
const totalAccounted = computed(() =>
  round2(grandTotal.value + totalExpenses.value + totalSuppliers.value + totalReceivable.value),
)
const overShort = computed(() => round2(totalAccounted.value - totalAfter.value))
const allocated = computed(() => sumAmounts(shortages.value))
const unallocated = computed(() => round2(overShort.value - allocated.value))

function statusOf(v: number) {
  return v < 0 ? 'SHORT' : v > 0 ? 'OVER' : 'BALANCED'
}
function signClass(v: number) {
  return v < 0 ? 'neg' : v > 0 ? 'pos' : ''
}

/* ---------------------------------------------------------------- actions */

const selectableAttendants = computed(() =>
  attendants.value.filter(
    (a) =>
      a.is_active ||
      a.id === meta.prepared_by ||
      shortages.value.some((s) => s.pump_attendant_id === a.id),
  ),
)

function addShortage() {
  shortages.value.push({
    pump_attendant_id: shortages.value.length ? '' : meta.prepared_by,
    amount: unallocated.value || null,
    remarks: '',
  })
}

function splitEvenly() {
  const count = shortages.value.length
  if (!count) return
  const each = round2(overShort.value / count)
  shortages.value.forEach((s) => (s.amount = each))
  shortages.value[count - 1]!.amount = round2(each + (overShort.value - each * count))
}

function validate(): string | null {
  if (!meta.report_date) return 'Please set the report date.'
  for (const r of readings.value) {
    if (!hasReading(r)) continue
    const name = pumpName(r.pump_id)
    if (toNum(r.first_reading) === null || toNum(r.second_reading) === null)
      return `${name}: enter both the first and second reading.`
    if (rowInvalid(r)) return `${name}: second reading cannot be lower than the first reading.`
    if (toNum(priceOf(r.pump_id).price_per_liter) === null)
      return `${name}: enter the price per liter.`
  }
  for (const e of [...expenses.value, ...suppliers.value]) {
    if (e.description.trim() && toNum(e.amount) === null)
      return `Expense "${e.description}" has no amount.`
    if (!e.description.trim() && toNum(e.amount) !== null)
      return 'An expense amount has no description.'
  }
  const ids = shortages.value
    .filter((s) => toNum(s.amount) !== null)
    .map((s) => s.pump_attendant_id)
  if (ids.some((id) => !id)) return 'Choose the pump attendant for each shortage / overage line.'
  if (new Set(ids).size !== ids.length)
    return 'Each attendant can appear only once in shortage / overage.'
  for (const r of receivables.value) {
    if (!r.company_name.trim() && (toNum(r.liters) || toNum(r.price_per_liter)))
      return 'A receivable line has no company name.'
  }
  return null
}

async function save() {
  error.value = ''
  notice.value = ''
  const problem = validate()
  if (problem) {
    error.value = problem
    return
  }

  // No split entered: charge the full over/short to whoever prepared the sheet.
  if (
    overShort.value !== 0 &&
    !shortages.value.some((s) => toNum(s.amount) !== null) &&
    meta.prepared_by
  ) {
    shortages.value = [
      { pump_attendant_id: meta.prepared_by, amount: overShort.value, remarks: '' },
    ]
  }
  if (unallocated.value !== 0 && shortages.value.length) {
    const ok = confirm(
      `Over/short is ${money(overShort.value)} but only ${money(allocated.value)} is assigned to attendants. Save anyway?`,
    )
    if (!ok) return
  }

  const entered = readings.value.filter(hasReading)
  const usedFuelIds = new Set(entered.map((r) => fuelOf(r.pump_id)?.id).filter(Boolean) as string[])

  const payload = {
    id: props.id ?? null,
    report_date: meta.report_date,
    shift_id: meta.shift_id,
    prepared_by: meta.prepared_by || null,
    total_error: n(meta.total_error),
    total_discount: n(meta.total_discount),
    remarks: meta.remarks,
    prices: [...usedFuelIds].map((id) => ({
      fuel_type_id: id,
      price_per_liter: n(prices[id]?.price_per_liter),
      markup: n(prices[id]?.markup),
    })),
    readings: entered.map((r) => ({
      pump_id: r.pump_id,
      first_reading: n(r.first_reading),
      second_reading: n(r.second_reading),
    })),
    expenses: [...expenses.value, ...suppliers.value]
      .filter((e) => e.description.trim())
      .map((e) => ({ kind: e.kind, description: e.description.trim(), amount: n(e.amount) })),
    cash_counts: denominations.value
      .filter((d) => n(pieces[d.id]) > 0)
      .map((d) => ({ denomination_id: d.id, pieces: n(pieces[d.id]) })),
    payments: payments.value
      .filter((p) => n(p.amount) > 0)
      .map((p) => ({
        payment_method_id: p.payment_method_id,
        reference_no: p.reference_no,
        amount: n(p.amount),
      })),
    shortage_overage: shortages.value
      .filter((s) => toNum(s.amount) !== null)
      .map((s) => ({
        pump_attendant_id: s.pump_attendant_id,
        amount: n(s.amount),
        remarks: s.remarks,
      })),
    receivables: receivables.value
      .filter((r) => r.company_name.trim())
      .map((r) => ({
        receivable_date: r.receivable_date || null,
        company_name: r.company_name,
        liters: n(r.liters),
        price_per_liter: n(r.price_per_liter),
      })),
  }

  saving.value = true
  const { data, error: err } = await supabase.rpc('save_shift_report', { p: payload })
  saving.value = false
  if (err) {
    error.value = err.message.includes('shift_reports_report_date_shift_id_key')
      ? `A ${currentShift.value?.name} shift report for ${longDate(meta.report_date)} already exists.`
      : err.message
    return
  }
  notice.value = 'Shift report saved.'
  if (!props.id) router.replace(`${base.value || '/reports'}/${data}`)
}

function printSheet() {
  window.print()
}

/**
 * Save the sheet as an image. While exporting, the sheet is laid out at a fixed
 * desktop width with inputs shown as plain text (see .exporting in main.css),
 * so the picture looks the same whether it is taken on a phone or a PC.
 */
async function exportImage(format: 'png' | 'jpeg') {
  if (!sheetEl.value) return
  error.value = ''
  exporting.value = true
  await nextTick()
  try {
    const node = sheetEl.value
    const options = {
      backgroundColor: '#ffffff',
      pixelRatio: 2,
      skipFonts: true,
      width: node.scrollWidth,
      height: node.scrollHeight,
      filter: (el: HTMLElement) => !el.classList?.contains('no-print'),
    }
    const dataUrl =
      format === 'png'
        ? await toPng(node, options)
        : await toJpeg(node, { ...options, quality: 0.95 })
    const link = document.createElement('a')
    link.href = dataUrl
    link.download = `RCJA-${meta.report_date}-${currentShift.value?.name ?? ''}-shift.${format === 'png' ? 'png' : 'jpg'}`
    link.click()
  } catch (e) {
    error.value = `Could not create the image: ${e instanceof Error ? e.message : String(e)}`
  } finally {
    exporting.value = false
  }
}
</script>

<template>
  <div v-if="loading" class="muted">Loading…</div>

  <template v-else>
    <div class="page-head no-print">
      <div>
        <h1>{{ props.id ? 'Shift Report' : 'New Shift Report' }}</h1>
        <div class="muted">
          White cells are typed by the pump attendant; grey cells are computed automatically.
        </div>
      </div>
      <div class="grid w-full grid-cols-2 gap-2 sm:flex sm:w-auto">
        <RouterLink :to="base || '/'" class="btn">← Back</RouterLink>
        <button class="btn" @click="printSheet">Print</button>
        <button class="btn" :disabled="exporting" @click="exportImage('png')">Save as PNG</button>
        <button class="btn" :disabled="exporting" @click="exportImage('jpeg')">Save as JPEG</button>
      </div>
    </div>

    <div v-if="error" class="alert error no-print">{{ error }}</div>
    <div v-if="notice" class="alert ok no-print">{{ notice }}</div>

    <div class="export-frame">
      <div ref="sheetEl" class="sheet-export @container" :class="{ exporting }">
        <!-- ===== Sheet header ===== -->
        <div class="card">
          <div class="card-body">
            <div class="sheet-title">
              <div class="station">RCJA POWERFUEL GASOLINE STATION</div>
              <div class="sub">DAILY SALES FOR THE MONTH OF {{ monthName(meta.report_date) }}</div>
              <div class="sub">
                {{ currentShift?.name }} SHIFT – {{ longDate(meta.report_date).toUpperCase() }}
              </div>
            </div>
            <div class="meta-grid no-print">
              <label class="field"
                >Date <input v-model="meta.report_date" type="date" required
              /></label>
              <label class="field">
                Shift
                <select v-model.number="meta.shift_id">
                  <option v-for="s in shifts" :key="s.id" :value="s.id">
                    {{ s.name }} shift{{ s.hours ? ` (${s.hours})` : '' }}
                  </option>
                </select>
              </label>
              <label class="field">
                Prepared by (pump attendant)
                <select v-model="meta.prepared_by">
                  <option value="">— select —</option>
                  <option v-for="a in selectableAttendants" :key="a.id" :value="a.id">
                    {{ a.full_name }}
                  </option>
                </select>
              </label>
            </div>
          </div>
        </div>

        <div class="mt-4 grid items-start gap-4 @4xl:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)]">
          <!-- ================= LEFT COLUMN ================= -->
          <div>
            <!-- Fuel readings -->
            <div class="card">
              <!-- phones: one card per pump -->
              <div class="divide-y divide-line @2xl:hidden">
                <template v-for="g in groups" :key="g.fuel.id">
                  <div v-for="r in g.rows" :key="r.pump_id" class="p-3">
                    <div class="mb-2 flex items-center justify-between gap-2">
                      <span
                        class="fuel-tag"
                        :style="{ background: g.fuel.color, color: textOn(g.fuel.color) }"
                      >
                        {{ pumpName(r.pump_id) }}
                      </span>
                      <span class="font-bold tabular-nums">{{ money(rowSales(r)) }}</span>
                    </div>
                    <div class="grid grid-cols-2 gap-2">
                      <label class="field">
                        First reading
                        <input
                          v-model.number="r.first_reading"
                          type="number"
                          inputmode="decimal"
                          step="any"
                          min="0"
                          class="num"
                        />
                      </label>
                      <label class="field">
                        Second reading
                        <input
                          v-model.number="r.second_reading"
                          type="number"
                          inputmode="decimal"
                          step="any"
                          min="0"
                          class="num"
                          :class="{ invalid: rowInvalid(r) }"
                        />
                      </label>
                      <label class="field">
                        Price per liter
                        <input
                          v-model.number="priceOf(r.pump_id).price_per_liter"
                          type="number"
                          inputmode="decimal"
                          step="0.01"
                          min="0"
                          class="num"
                        />
                      </label>
                      <div class="field">
                        <span>Liters</span>
                        <span
                          class="rounded-[5px] bg-slate-50 px-2.5 py-2 text-right text-base font-semibold text-ink tabular-nums"
                          :class="{ neg: rowInvalid(r) }"
                        >
                          {{ liters(rowLiters(r)) }}
                        </span>
                      </div>
                    </div>
                  </div>
                </template>
                <p v-if="!readings.length" class="muted p-4 text-center">
                  No active pumps. An admin can add them under Fuel Types.
                </p>
              </div>

              <!-- tablets & PCs: the sheet table -->
              <div class="table-scroll hidden @2xl:block">
                <table class="sheet">
                  <thead>
                    <tr>
                      <th>Fuel type</th>
                      <th>First reading</th>
                      <th>Second reading</th>
                      <th class="num">Liters</th>
                      <th>Price per liter</th>
                      <th class="num">Total sales</th>
                    </tr>
                  </thead>
                  <tbody>
                    <template v-for="(g, gi) in groups" :key="g.fuel.id">
                      <tr v-if="gi > 0" class="group-gap">
                        <td colspan="6"></td>
                      </tr>
                      <tr v-for="r in g.rows" :key="r.pump_id">
                        <td>
                          <span
                            class="fuel-tag"
                            :style="{ background: g.fuel.color, color: textOn(g.fuel.color) }"
                          >
                            {{ pumpName(r.pump_id) }}
                          </span>
                        </td>
                        <td>
                          <input
                            v-model.number="r.first_reading"
                            type="number"
                            step="any"
                            min="0"
                            class="num"
                          />
                        </td>
                        <td>
                          <input
                            v-model.number="r.second_reading"
                            type="number"
                            step="any"
                            min="0"
                            class="num"
                            :class="{ invalid: rowInvalid(r) }"
                          />
                        </td>
                        <td class="auto" :class="{ neg: rowInvalid(r) }">
                          {{ liters(rowLiters(r)) }}
                        </td>
                        <td style="width: 100px">
                          <input
                            v-model.number="priceOf(r.pump_id).price_per_liter"
                            type="number"
                            step="0.01"
                            min="0"
                            class="num"
                            :title="`Price for all ${g.fuel.name} pumps`"
                          />
                        </td>
                        <td class="auto">{{ money(rowSales(r)) }}</td>
                      </tr>
                    </template>
                    <tr v-if="!readings.length">
                      <td colspan="6" class="muted" style="text-align: center; padding: 16px">
                        No active pumps. An admin can add them under Fuel Types.
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div class="total-row">
                <span>TOTAL SALES FROM MACHINE | DISPENSER</span>
                <span class="amount">{{ money(totalMachine) }}</span>
              </div>
              <div class="sub-row">
                <span>LESS: TOTAL ERROR</span>
                <input
                  v-model.number="meta.total_error"
                  type="number"
                  step="0.01"
                  min="0"
                  class="num"
                />
              </div>
              <div class="sub-row">
                <span>LESS: TOTAL DISCOUNT</span>
                <input
                  v-model.number="meta.total_discount"
                  type="number"
                  step="0.01"
                  min="0"
                  class="num"
                />
              </div>
              <div class="total-row">
                <span>TOTAL AFTER ERROR &amp; DISCOUNT</span>
                <span class="amount">{{ money(totalAfter) }}</span>
              </div>
            </div>

            <!-- Expenses & supplier payments -->
            <div
              v-for="block in [
                {
                  title: 'Input your expenses here',
                  rows: expenses,
                  kind: 'EXPENSE' as const,
                  total: totalExpenses,
                  label: 'TOTAL EXPENSES',
                  ph: 'Description (e.g. GENSET – DIESEL 2L)',
                },
                {
                  title: 'Input your payment to suppliers here',
                  rows: suppliers,
                  kind: 'SUPPLIER' as const,
                  total: totalSuppliers,
                  label: 'TOTAL PAYMENT TO SUPPLIERS',
                  ph: 'Supplier / description',
                },
              ]"
              :key="block.kind"
              class="card"
            >
              <div class="card-head yellow">
                <h2>{{ block.title }}</h2>
                <button
                  class="btn small no-print"
                  @click="block.rows.push(blankExpense(block.kind))"
                >
                  + Add
                </button>
              </div>
              <table class="sheet">
                <tbody>
                  <tr v-for="(e, i) in block.rows" :key="i">
                    <td><input v-model="e.description" :placeholder="block.ph" /></td>
                    <td class="w-28 @md:w-[150px]">
                      <input
                        v-model.number="e.amount"
                        type="number"
                        step="0.01"
                        min="0"
                        class="num"
                        placeholder="0.00"
                      />
                    </td>
                    <td style="width: 30px" class="no-print">
                      <button class="icon-btn" title="Remove" @click="block.rows.splice(i, 1)">
                        ✕
                      </button>
                    </td>
                  </tr>
                </tbody>
                <tfoot>
                  <tr>
                    <td>{{ block.label }}</td>
                    <td class="num">{{ money(block.total) }}</td>
                    <td class="no-print"></td>
                  </tr>
                </tfoot>
              </table>
            </div>

            <!-- Receivables -->
            <div class="card">
              <div class="card-head yellow">
                <h2>Receivable details</h2>
                <button
                  class="btn small no-print"
                  @click="
                    receivables.push({
                      receivable_date: meta.report_date,
                      company_name: '',
                      liters: null,
                      price_per_liter: null,
                    })
                  "
                >
                  + Add
                </button>
              </div>
              <datalist id="company-list">
                <option v-for="c in companies" :key="c" :value="c" />
              </datalist>
              <div class="table-scroll">
                <table class="sheet min-w-[560px]">
                  <thead>
                    <tr>
                      <th>Date</th>
                      <th>Company name</th>
                      <th>Liters</th>
                      <th>Price/L</th>
                      <th class="num">Amount</th>
                      <th class="no-print"></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="(r, i) in receivables" :key="i">
                      <td style="width: 140px">
                        <input v-model="r.receivable_date" type="date" />
                      </td>
                      <td><input v-model="r.company_name" list="company-list" /></td>
                      <td style="width: 100px">
                        <input
                          v-model.number="r.liters"
                          type="number"
                          step="any"
                          min="0"
                          class="num"
                        />
                      </td>
                      <td style="width: 90px">
                        <input
                          v-model.number="r.price_per_liter"
                          type="number"
                          step="0.01"
                          min="0"
                          class="num"
                        />
                      </td>
                      <td class="auto">{{ money(round2(n(r.liters) * n(r.price_per_liter))) }}</td>
                      <td style="width: 30px" class="no-print">
                        <button class="icon-btn" title="Remove" @click="receivables.splice(i, 1)">
                          ✕
                        </button>
                      </td>
                    </tr>
                    <tr v-if="!receivables.length">
                      <td colspan="6" class="muted" style="text-align: center">
                        No credit sales this shift.
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div class="total-row">
                <span>TOTAL RECEIVABLE</span>
                <span class="amount">{{ money(totalReceivable) }}</span>
              </div>
            </div>
          </div>

          <!-- ================= RIGHT COLUMN ================= -->
          <div>
            <!-- Income per liter -->
            <div class="card">
              <div class="card-head" style="justify-content: center"><h2>INCOME PER LITER</h2></div>
              <div class="table-scroll">
                <table class="sheet">
                  <thead>
                    <tr>
                      <th style="text-align: left">Fuel</th>
                      <th class="num hidden @md:table-cell">Total sales</th>
                      <th class="num">Total liters</th>
                      <th>Mark up</th>
                      <th class="num">Income</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="g in incomeRows" :key="g.fuel.id">
                      <td>
                        <b>{{ g.fuel.name }}</b>
                      </td>
                      <td class="num hidden @md:table-cell">{{ money(g.sales) }}</td>
                      <td class="num">{{ liters(g.liters) }}</td>
                      <td class="w-20 @md:w-[85px]">
                        <input
                          v-model.number="prices[g.fuel.id]!.markup"
                          type="number"
                          step="0.01"
                          min="0"
                          class="num"
                        />
                      </td>
                      <td class="auto">{{ money(g.income) }}</td>
                    </tr>
                  </tbody>
                  <tfoot>
                    <tr>
                      <td>TOTAL</td>
                      <td class="num hidden @md:table-cell">{{ money(totalMachine) }}</td>
                      <td class="num">{{ liters(totalLiters) }}</td>
                      <td></td>
                      <td class="num">{{ money(totalIncome) }}</td>
                    </tr>
                  </tfoot>
                </table>
              </div>
              <div class="total-row">
                <span>TOTAL INCOME</span>
                <span class="amount">{{ money(totalIncome) }}</span>
              </div>
            </div>

            <!-- Denomination -->
            <div class="card">
              <div class="card-head" style="justify-content: center">
                <h2>DENOMINATION OF MONEY (SALES)</h2>
              </div>
              <table class="sheet">
                <thead>
                  <tr>
                    <th class="num">Bills</th>
                    <th>Pieces</th>
                    <th class="num">Sub total</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="d in denominations" :key="d.id">
                    <td class="num">
                      <b>{{ d.value.toLocaleString() }}</b>
                    </td>
                    <td class="w-24 @md:w-[120px]">
                      <input
                        v-model.number="pieces[d.id]"
                        type="number"
                        min="0"
                        step="1"
                        inputmode="numeric"
                        class="num"
                        placeholder="0"
                      />
                    </td>
                    <td class="auto">{{ money(d.value * n(pieces[d.id])) }}</td>
                  </tr>
                </tbody>
                <tfoot>
                  <tr>
                    <td class="num">TOTAL CASH</td>
                    <td></td>
                    <td class="num">{{ money(totalCash) }}</td>
                  </tr>
                </tfoot>
              </table>
            </div>

            <!-- Payments (GCash etc.) -->
            <div class="card">
              <div class="card-head" style="justify-content: space-between">
                <h2>GCASH / E-PAYMENTS</h2>
                <button class="btn small no-print" @click="payments.push(blankPayment())">
                  + Add
                </button>
              </div>
              <table class="sheet">
                <thead>
                  <tr>
                    <th style="text-align: left">Method</th>
                    <th style="text-align: left">Reference no.</th>
                    <th class="num">Amount</th>
                    <th class="no-print"></th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(p, i) in payments" :key="i">
                    <td class="w-24 @md:w-[110px]">
                      <select v-model.number="p.payment_method_id">
                        <option v-for="m in paymentMethods" :key="m.id" :value="m.id">
                          {{ m.name }}
                        </option>
                      </select>
                    </td>
                    <td><input v-model="p.reference_no" placeholder="optional" /></td>
                    <td class="w-28 @md:w-[130px]">
                      <input
                        v-model.number="p.amount"
                        type="number"
                        step="0.01"
                        min="0"
                        class="num"
                        placeholder="0.00"
                      />
                    </td>
                    <td style="width: 30px" class="no-print">
                      <button class="icon-btn" title="Remove" @click="payments.splice(i, 1)">
                        ✕
                      </button>
                    </td>
                  </tr>
                </tbody>
                <tfoot>
                  <tr v-for="m in paymentTotalsByMethod" :key="m.name">
                    <td colspan="2">TOTAL {{ m.name }}</td>
                    <td class="num">{{ money(m.total) }}</td>
                    <td class="no-print"></td>
                  </tr>
                </tfoot>
              </table>
              <div class="total-row">
                <span>GRAND TOTAL</span>
                <span class="amount">{{ money(grandTotal) }}</span>
              </div>
            </div>

            <!-- Over / short -->
            <div class="card">
              <div class="card-head" style="justify-content: center">
                <h2>SHORTAGE / OVERAGE</h2>
              </div>
              <table class="sheet">
                <tbody>
                  <tr>
                    <td>Grand total (cash + GCash)</td>
                    <td class="num">{{ money(grandTotal) }}</td>
                  </tr>
                  <tr>
                    <td>+ Expenses</td>
                    <td class="num">{{ money(totalExpenses) }}</td>
                  </tr>
                  <tr>
                    <td>+ Payment to suppliers</td>
                    <td class="num">{{ money(totalSuppliers) }}</td>
                  </tr>
                  <tr>
                    <td>+ Receivables</td>
                    <td class="num">{{ money(totalReceivable) }}</td>
                  </tr>
                  <tr>
                    <td><b>Total accounted</b></td>
                    <td class="num">
                      <b>{{ money(totalAccounted) }}</b>
                    </td>
                  </tr>
                  <tr>
                    <td>− Total after error &amp; discount</td>
                    <td class="num">{{ money(totalAfter) }}</td>
                  </tr>
                </tbody>
              </table>
              <div class="overshort" style="border-top: 2px solid var(--ink)">
                <span>
                  OVER | SHORT
                  <span class="badge" :class="statusOf(overShort).toLowerCase()">{{
                    statusOf(overShort)
                  }}</span>
                </span>
                <span class="amount" :class="signClass(overShort)">{{ money(overShort) }}</span>
              </div>

              <div class="card-head" style="border-top: 1px solid var(--line)">
                <h2 style="font-size: 0.85rem">Charged to pump attendant</h2>
                <span class="no-print" style="display: flex; gap: 6px">
                  <button v-if="shortages.length > 1" class="btn small" @click="splitEvenly">
                    Split evenly
                  </button>
                  <button class="btn small" @click="addShortage">+ Add</button>
                </span>
              </div>
              <table class="sheet">
                <tbody>
                  <tr v-for="(s, i) in shortages" :key="i">
                    <td>
                      <select v-model="s.pump_attendant_id">
                        <option value="">— attendant —</option>
                        <option v-for="a in selectableAttendants" :key="a.id" :value="a.id">
                          {{ a.nickname || a.full_name }}
                        </option>
                      </select>
                      <input v-model="s.remarks" placeholder="remarks" class="mt-1 @md:hidden" />
                    </td>
                    <td class="w-28 align-top @md:w-[120px] @md:align-middle">
                      <input v-model.number="s.amount" type="number" step="0.01" class="num" />
                    </td>
                    <td class="hidden @md:table-cell">
                      <input v-model="s.remarks" placeholder="remarks" />
                    </td>
                    <td style="width: 30px" class="no-print">
                      <button class="icon-btn" title="Remove" @click="shortages.splice(i, 1)">
                        ✕
                      </button>
                    </td>
                  </tr>
                  <tr v-if="!shortages.length">
                    <td colspan="4" class="muted" style="font-size: 0.82rem">
                      If left empty, the full amount is charged to the attendant who prepared the
                      sheet.
                    </td>
                  </tr>
                </tbody>
                <tfoot v-if="shortages.length">
                  <tr>
                    <td>Unassigned</td>
                    <td class="num" :class="{ neg: unallocated !== 0 }">
                      {{ money(unallocated) }}
                    </td>
                    <td colspan="2"></td>
                  </tr>
                </tfoot>
              </table>
            </div>

            <div class="card">
              <div class="card-body">
                <label class="field">Remarks <textarea v-model="meta.remarks" rows="2" /></label>
              </div>
            </div>
          </div>
        </div>

        <div class="signature">
          BY:
          {{
            attendants.find((a) => a.id === meta.prepared_by)?.full_name?.toUpperCase() ??
            '________'
          }}
          <template v-if="currentShift?.hours"> &gt; {{ currentShift.hours }}</template>
        </div>
      </div>
    </div>

    <div class="sticky-actions no-print flex-wrap">
      <span class="muted mr-auto sm:mr-0">
        Over/Short: <b :class="signClass(overShort)">{{ money(overShort) }}</b>
      </span>
      <button class="btn primary w-full py-2.5 sm:w-auto" :disabled="saving" @click="save">
        {{ saving ? 'Saving…' : 'Save shift report' }}
      </button>
    </div>
  </template>
</template>
