<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { liters, longDate, money, todayIso } from '@/lib/format'
import type { ShiftReportSummary } from '@/lib/types'

const auth = useAuthStore()
const month = ref(todayIso().slice(0, 7))
const rows = ref<ShiftReportSummary[]>([])
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
  const { data, error: err } = await supabase
    .from('shift_report_summary')
    .select('*')
    .gte('report_date', `${month.value}-01`)
    .lt('report_date', nextMonthStart(month.value))
    .order('report_date', { ascending: false })
    .order('shift_id', { ascending: false })
  loading.value = false
  if (err) error.value = err.message
  rows.value = (data ?? []) as ShiftReportSummary[]
}

const totals = computed(() =>
  rows.value.reduce(
    (t, r) => ({
      sales: t.sales + Number(r.total_after_error_discount),
      liters: t.liters + Number(r.total_liters),
      income: t.income + Number(r.total_income),
      expenses: t.expenses + Number(r.total_expenses) + Number(r.total_supplier_payments),
      gcash: t.gcash + Number(r.gcash_total),
      overShort: t.overShort + Number(r.over_short),
    }),
    { sales: 0, liters: 0, income: 0, expenses: 0, gcash: 0, overShort: 0 },
  ),
)

function signClass(n: number) {
  return n < 0 ? 'neg' : n > 0 ? 'pos' : ''
}

async function remove(r: ShiftReportSummary) {
  const label = `${r.shift_name} shift report for ${longDate(r.report_date)}`
  if (!confirm(`Delete the ${label}? This cannot be undone.`)) return
  const { error: err } = await supabase.from('shift_reports').delete().eq('id', r.id)
  if (err) error.value = err.message
  load()
}

watch(month, load)
onMounted(load)
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Daily Sales Reports</h1>
      <div class="muted">RCJA Powerfuel Gasoline Station</div>
    </div>
    <div class="flex w-full flex-wrap items-end gap-2 sm:w-auto">
      <label class="field min-w-0 flex-1 sm:flex-none">
        Month <input v-model="month" type="month" />
      </label>
      <RouterLink v-if="!auth.isAdmin" to="/reports/new" class="btn primary py-2">
        + New Shift Report
      </RouterLink>
    </div>
  </div>

  <div v-if="error" class="alert error">{{ error }}</div>

  <div class="mb-4 grid grid-cols-2 gap-2 sm:grid-cols-3 sm:gap-3 xl:grid-cols-6">
    <div class="kpi">
      <div class="label">Total sales (month)</div>
      <div class="value">{{ money(totals.sales) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Liters sold</div>
      <div class="value">{{ liters(totals.liters) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Total income</div>
      <div class="value">{{ money(totals.income) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Expenses</div>
      <div class="value">{{ money(totals.expenses) }}</div>
    </div>
    <div class="kpi">
      <div class="label">GCash</div>
      <div class="value">{{ money(totals.gcash) }}</div>
    </div>
    <div class="kpi">
      <div class="label">Over / Short</div>
      <div class="value" :class="signClass(totals.overShort)">{{ money(totals.overShort) }}</div>
    </div>
  </div>

  <!-- phones: one card per report -->
  <div class="space-y-2 md:hidden">
    <RouterLink
      v-for="r in rows"
      :key="r.id"
      :to="`${auth.isAdmin ? '/admin' : ''}/reports/${r.id}`"
      class="card block p-3 no-underline active:bg-slate-50"
    >
      <div class="flex items-start justify-between gap-2">
        <div>
          <div class="font-bold">{{ longDate(r.report_date) }}</div>
          <div class="muted">
            {{ r.shift_name }} shift<span v-if="r.shift_hours"> ({{ r.shift_hours }})</span> ·
            {{ r.prepared_by_name ?? '—' }}
          </div>
        </div>
        <div class="text-right">
          <div class="font-bold tabular-nums">{{ money(r.total_after_error_discount) }}</div>
          <div class="text-sm font-semibold tabular-nums" :class="signClass(Number(r.over_short))">
            {{ money(r.over_short) }}
          </div>
        </div>
      </div>
      <div class="mt-2 grid grid-cols-3 gap-2 border-t border-line pt-2 text-xs text-muted">
        <span
          >Liters<br /><b class="text-ink tabular-nums">{{ liters(r.total_liters) }}</b></span
        >
        <span
          >Cash + GCash<br /><b class="text-ink tabular-nums">{{ money(r.grand_total) }}</b></span
        >
        <span
          >Income<br /><b class="text-ink tabular-nums">{{ money(r.total_income) }}</b></span
        >
      </div>
    </RouterLink>
    <p v-if="!rows.length && !loading" class="card muted p-6 text-center">
      No shift reports for this month yet.
    </p>
  </div>

  <!-- tablets & PCs: table -->
  <div class="card hidden md:block">
    <div class="table-scroll">
      <table class="sheet">
        <thead>
          <tr>
            <th style="text-align: left">Date</th>
            <th>Shift</th>
            <th style="text-align: left">Prepared by</th>
            <th class="num">Liters</th>
            <th class="num">Total sales</th>
            <th class="num">Expenses</th>
            <th class="num">Cash + GCash</th>
            <th class="num">Income</th>
            <th class="num">Over / Short</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in rows" :key="r.id">
            <td>
              <b>{{ longDate(r.report_date) }}</b>
            </td>
            <td style="text-align: center">
              {{ r.shift_name
              }}<span v-if="r.shift_hours" class="muted"> · {{ r.shift_hours }}</span>
            </td>
            <td>{{ r.prepared_by_name ?? '—' }}</td>
            <td class="num">{{ liters(r.total_liters) }}</td>
            <td class="num">{{ money(r.total_after_error_discount) }}</td>
            <td class="num">
              {{ money(Number(r.total_expenses) + Number(r.total_supplier_payments)) }}
            </td>
            <td class="num">{{ money(r.grand_total) }}</td>
            <td class="num">{{ money(r.total_income) }}</td>
            <td class="num" :class="signClass(Number(r.over_short))">
              <b>{{ money(r.over_short) }}</b>
            </td>
            <td style="text-align: right; white-space: nowrap">
              <RouterLink :to="`${auth.isAdmin ? '/admin' : ''}/reports/${r.id}`" class="btn small"
                >Open</RouterLink
              >
              <button v-if="auth.isAdmin" class="btn small danger" @click="remove(r)">
                Delete
              </button>
            </td>
          </tr>
          <tr v-if="!rows.length && !loading">
            <td colspan="10" class="muted" style="text-align: center; padding: 24px">
              No shift reports for this month yet.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
