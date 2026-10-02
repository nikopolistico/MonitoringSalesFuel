<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { liters, longDate, money, round2, textOn, todayIso } from '@/lib/format'
import type { FuelType, ShiftReportSummary } from '@/lib/types'

const month = ref(todayIso().slice(0, 7))
const reports = ref<ShiftReportSummary[]>([])
const fuelRows = ref<
  { fuel_type_id: string; liters: number; total_sales: number; markup: number }[]
>([])
const fuelTypes = ref<FuelType[]>([])
const shortRows = ref<
  { amount: number; pump_attendants: { full_name: string; nickname: string | null } | null }[]
>([])
const attendantCount = ref(0)
const loading = ref(false)
const error = ref('')

function nextMonthStart(ym: string): string {
  const [y, m] = ym.split('-').map(Number) as [number, number]
  return m === 12 ? `${y + 1}-01-01` : `${y}-${String(m + 1).padStart(2, '0')}-01`
}

async function load() {
  if (!month.value) return
  loading.value = true
  error.value = ''
  const from = `${month.value}-01`
  const to = nextMonthStart(month.value)

  const [rep, ft, so, pa] = await Promise.all([
    supabase
      .from('shift_report_summary')
      .select('*')
      .gte('report_date', from)
      .lt('report_date', to)
      .order('report_date', { ascending: false })
      .order('shift_id', { ascending: false }),
    supabase.from('fuel_types').select('*').order('sort_order'),
    supabase
      .from('shortage_overage')
      .select('amount, pump_attendants(full_name, nickname), shift_reports!inner(report_date)')
      .gte('shift_reports.report_date', from)
      .lt('shift_reports.report_date', to),
    supabase
      .from('pump_attendants')
      .select('id', { count: 'exact', head: true })
      .eq('is_active', true),
  ])
  const failed = [rep, ft, so, pa].find((r) => r.error)
  if (failed?.error) error.value = failed.error.message

  reports.value = (rep.data ?? []) as ShiftReportSummary[]
  fuelTypes.value = (ft.data ?? []) as FuelType[]
  shortRows.value = (so.data ?? []) as unknown as typeof shortRows.value
  attendantCount.value = pa.count ?? 0

  const ids = reports.value.map((r) => r.id)
  if (ids.length) {
    const fs = await supabase
      .from('v_fuel_sales')
      .select('fuel_type_id, liters, total_sales, markup')
      .in('shift_report_id', ids)
    if (fs.error) error.value = fs.error.message
    fuelRows.value = fs.data ?? []
  } else {
    fuelRows.value = []
  }
  loading.value = false
}

const sum = (rows: ShiftReportSummary[], key: keyof ShiftReportSummary) =>
  round2(rows.reduce((s, r) => s + Number(r[key]), 0))

const kpis = computed(() => {
  const r = reports.value
  return {
    sales: sum(r, 'total_after_error_discount'),
    liters: sum(r, 'total_liters'),
    income: sum(r, 'total_income'),
    expenses: round2(sum(r, 'total_expenses') + sum(r, 'total_supplier_payments')),
    gcash: sum(r, 'gcash_total'),
    receivable: sum(r, 'total_receivable'),
    overShort: sum(r, 'over_short'),
  }
})

/** Total sales per day, oldest → newest, for the bar chart. */
const daily = computed(() => {
  const byDay = new Map<string, number>()
  for (const r of reports.value) {
    byDay.set(r.report_date, (byDay.get(r.report_date) ?? 0) + Number(r.total_after_error_discount))
  }
  const days = [...byDay.entries()].sort(([a], [b]) => a.localeCompare(b))
  const max = Math.max(1, ...days.map(([, v]) => v))
  return days.map(([date, total]) => ({ date, total, pct: (total / max) * 100 }))
})

const byFuel = computed(() =>
  fuelTypes.value
    .map((f) => {
      const rows = fuelRows.value.filter((r) => r.fuel_type_id === f.id)
      return {
        fuel: f,
        liters: rows.reduce((s, r) => s + Number(r.liters), 0),
        sales: round2(rows.reduce((s, r) => s + Number(r.total_sales), 0)),
        income: round2(rows.reduce((s, r) => s + Number(r.liters) * Number(r.markup), 0)),
      }
    })
    .filter((x) => x.liters > 0),
)

const byAttendant = computed(() => {
  const m = new Map<string, number>()
  for (const r of shortRows.value) {
    const name = r.pump_attendants?.nickname || r.pump_attendants?.full_name || '—'
    m.set(name, round2((m.get(name) ?? 0) + Number(r.amount)))
  }
  return [...m.entries()]
    .map(([name, total]) => ({ name, total }))
    .sort((a, b) => a.total - b.total)
})

function signClass(v: number) {
  return v < 0 ? 'neg' : v > 0 ? 'pos' : ''
}

watch(month, load)
onMounted(load)
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Admin Dashboard</h1>
      <div class="muted">RCJA Powerfuel Gasoline Station — monthly overview</div>
    </div>
    <label class="field w-full sm:w-auto">Month <input v-model="month" type="month" /></label>
  </div>

  <div v-if="error" class="alert error">{{ error }}</div>

  <div class="mb-4 grid grid-cols-2 gap-2 sm:grid-cols-3 sm:gap-3 lg:grid-cols-4">
    <div class="kpi">
      <div class="label">Total sales</div>
      <div class="value">{{ money(kpis.sales) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Liters sold</div>
      <div class="value">{{ liters(kpis.liters) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Total income</div>
      <div class="value">{{ money(kpis.income) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Expenses</div>
      <div class="value">{{ money(kpis.expenses) }}</div>
    </div>
    <div class="kpi">
      <div class="label">GCash</div>
      <div class="value">{{ money(kpis.gcash) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Over / Short</div>
      <div class="value" :class="signClass(kpis.overShort)">{{ money(kpis.overShort) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Shift reports</div>
      <div class="value">{{ reports.length }}</div>
    </div>
    <div class="kpi">
      <div class="label">Active attendants</div>
      <div class="value">{{ attendantCount }}</div>
    </div>
  </div>

  <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
    <div>
      <div class="card">
        <div class="card-head"><h2>Daily sales</h2></div>
        <template v-if="daily.length">
          <div class="bars">
            <div
              v-for="d in daily"
              :key="d.date"
              class="bar"
              :style="{ height: `${d.pct}%` }"
              :title="`${longDate(d.date)}: ${money(d.total)}`"
            ></div>
          </div>
          <div class="bars-axis">
            <span>{{ longDate(daily[0]!.date) }}</span>
            <span v-if="daily.length > 1">{{ longDate(daily[daily.length - 1]!.date) }}</span>
          </div>
        </template>
        <div v-else class="card-body muted">No sales recorded this month.</div>
      </div>

      <div class="card">
        <div class="card-head">
          <h2>Recent shift reports</h2>
          <RouterLink to="/admin/reports" class="btn small">All reports</RouterLink>
        </div>
        <div class="table-scroll">
          <table class="sheet">
            <thead>
              <tr>
                <th style="text-align: left">Date</th>
                <th>Shift</th>
                <th class="hidden sm:table-cell" style="text-align: left">Prepared by</th>
                <th class="num">Total sales</th>
                <th class="num">Over / Short</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in reports.slice(0, 8)" :key="r.id">
                <td>{{ longDate(r.report_date) }}</td>
                <td style="text-align: center">{{ r.shift_name }}</td>
                <td class="hidden sm:table-cell">{{ r.prepared_by_name ?? '—' }}</td>
                <td class="num">{{ money(r.total_after_error_discount) }}</td>
                <td class="num" :class="signClass(Number(r.over_short))">
                  <b>{{ money(r.over_short) }}</b>
                </td>
                <td style="text-align: right">
                  <RouterLink :to="`/admin/reports/${r.id}`" class="btn small">Open</RouterLink>
                </td>
              </tr>
              <tr v-if="!reports.length && !loading">
                <td colspan="6" class="muted" style="text-align: center; padding: 20px">
                  No reports this month.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <div>
      <div class="card">
        <div class="card-head"><h2>Sales by fuel type</h2></div>
        <table class="sheet">
          <thead>
            <tr>
              <th style="text-align: left">Fuel</th>
              <th class="num">Liters</th>
              <th class="num">Sales</th>
              <th class="num">Income</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="f in byFuel" :key="f.fuel.id">
              <td>
                <span
                  class="fuel-tag"
                  :style="{ background: f.fuel.color, color: textOn(f.fuel.color) }"
                  >{{ f.fuel.name }}</span
                >
              </td>
              <td class="num">{{ liters(f.liters) }}</td>
              <td class="num">{{ money(f.sales) }}</td>
              <td class="num">{{ money(f.income) }}</td>
            </tr>
            <tr v-if="!byFuel.length">
              <td colspan="4" class="muted" style="text-align: center">—</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="card">
        <div class="card-head"><h2>Shortage / overage by attendant</h2></div>
        <table class="sheet">
          <tbody>
            <tr v-for="a in byAttendant" :key="a.name">
              <td>
                <b>{{ a.name }}</b>
              </td>
              <td class="num" :class="signClass(a.total)">
                <b>{{ money(a.total) }}</b>
              </td>
            </tr>
            <tr v-if="!byAttendant.length">
              <td colspan="2" class="muted" style="text-align: center">
                No shortages or overages this month.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="card">
        <div class="card-head"><h2>Quick links</h2></div>
        <div class="card-body" style="display: flex; gap: 8px; flex-wrap: wrap">
          <RouterLink to="/admin/attendants" class="btn">+ Create pump attendant</RouterLink>
          <RouterLink to="/admin/fuel-types" class="btn">Fuel types &amp; pumps</RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
