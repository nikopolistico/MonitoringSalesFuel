<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import type { Component } from 'vue'
import { ArrowRight, Eye, Fuel, ReceiptText, Users, Wallet } from '@lucide/vue'
import IconButton from '@/components/common/IconButton.vue'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { supabase } from '@/lib/supabase'
import { liters, longDate, money, round2, todayIso } from '@/lib/format'
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

const monthLabel = computed(() =>
  month.value
    ? new Date(`${month.value}-01T00:00:00`).toLocaleDateString('en-US', {
        month: 'long',
        year: 'numeric',
      })
    : '',
)

const overShortText = computed(() =>
  kpis.value.overShort < 0
    ? 'Less cash than sales this month.'
    : kpis.value.overShort > 0
      ? 'More cash than sales this month.'
      : 'Cash matched sales this month.',
)

const stats = computed<{ icon: Component; label: string; value: string }[]>(() => [
  { icon: ReceiptText, label: 'Expenses & suppliers', value: money(kpis.value.expenses) },
  { icon: Wallet, label: 'GCash received', value: money(kpis.value.gcash) },
  { icon: Fuel, label: 'Receivables', value: money(kpis.value.receivable) },
  { icon: Users, label: 'Active attendants', value: String(attendantCount.value) },
])

const fuelMax = computed(() => Math.max(1, ...byFuel.value.map((f) => f.liters)))
const bestDay = computed(() =>
  daily.value.reduce<(typeof daily.value)[number] | undefined>(
    (best, d) => (!best || d.total > best.total ? d : best),
    undefined,
  ),
)

function shortDate(iso: string) {
  return new Date(`${iso}T00:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

/** The peso amount split so the centavos can be drawn smaller on the meter. */
function meter(v: number) {
  const [whole, cents] = money(v).split('.')
  return { whole: whole ?? '', cents: cents ?? '00' }
}

watch(month, load)
onMounted(load)
</script>

<template>
  <div class="font-body">
    <!-- heading -->
    <div class="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 class="m-0 font-display text-[2.4rem] leading-none font-bold">Dashboard</h1>
        <p class="mt-1.5 text-muted-foreground">How RCJA Powerfuel did in {{ monthLabel }}.</p>
      </div>
      <div class="grid w-full gap-1.5 sm:w-48">
        <Label for="dash-month" class="text-muted-foreground">Month</Label>
        <Input id="dash-month" v-model="month" type="month" class="h-10 bg-card" />
      </div>
    </div>

    <p
      v-if="error"
      class="mb-4 rounded-lg border border-destructive/25 bg-destructive/5 px-3.5 py-2.5 font-medium text-destructive"
      role="alert"
    >
      {{ error }}
    </p>

    <!-- ============ meter + over/short ============ -->
    <div class="grid gap-4 lg:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)]">
      <!-- pump meter -->
      <section class="rounded-xl bg-admin p-3 text-white sm:p-4" aria-label="Sales this month">
        <div class="lcd rounded-lg px-4 py-4 sm:px-6 sm:py-5">
          <div class="grid grid-cols-[4.5rem_1fr] items-baseline gap-3 sm:grid-cols-[6rem_1fr]">
            <span class="text-sm font-semibold opacity-70">Sales</span>
            <span
              class="text-right font-display text-[2.5rem] leading-none font-semibold tabular-nums sm:text-[4.25rem]"
            >
              {{ meter(kpis.sales).whole
              }}<small class="text-[0.5em]">.{{ meter(kpis.sales).cents }}</small>
            </span>
          </div>
          <div
            class="mt-3 grid grid-cols-[4.5rem_1fr] items-baseline gap-3 border-t border-[#1e2a1e]/20 pt-3 sm:grid-cols-[6rem_1fr]"
          >
            <span class="text-sm font-semibold opacity-70">Liters</span>
            <span
              class="text-right font-display text-[1.6rem] leading-none font-semibold tabular-nums sm:text-[2.2rem]"
            >
              {{ liters(kpis.liters) }}
            </span>
          </div>
          <div
            class="mt-3 grid grid-cols-[4.5rem_1fr] items-baseline gap-3 border-t border-[#1e2a1e]/20 pt-3 sm:grid-cols-[6rem_1fr]"
          >
            <span class="text-sm font-semibold opacity-70">Income</span>
            <span
              class="text-right font-display text-[1.6rem] leading-none font-semibold tabular-nums sm:text-[2.2rem]"
            >
              {{ money(kpis.income) }}
            </span>
          </div>
        </div>
        <div
          class="flex flex-wrap items-center justify-between gap-2 px-1 pt-3 text-sm text-white/70"
        >
          <span>
            {{ reports.length }} shift report{{ reports.length === 1 ? '' : 's' }} in
            {{ monthLabel }}
          </span>
          <span v-if="bestDay"
            >Best day: {{ shortDate(bestDay.date) }}, {{ money(bestDay.total) }}</span
          >
        </div>
      </section>

      <!-- over / short -->
      <Card class="gap-0 py-0 flex flex-col" aria-label="Shortage and overage">
        <div class="px-5 pt-5">
          <h2 class="font-display text-xl font-bold">Over / short</h2>
          <p
            class="mt-1 font-display text-[2.6rem] leading-none font-bold tabular-nums"
            :class="signClass(kpis.overShort)"
          >
            {{ money(kpis.overShort) }}
          </p>
          <p class="mt-1 text-sm text-muted-foreground">{{ overShortText }}</p>
        </div>
        <ul class="mt-4 flex-1 divide-y divide-border border-t border-border">
          <li
            v-for="a in byAttendant.slice(0, 5)"
            :key="a.name"
            class="flex items-center justify-between gap-3 px-5 py-2.5"
          >
            <span class="font-medium">{{ a.name }}</span>
            <span class="font-semibold tabular-nums" :class="signClass(a.total)">
              {{ money(a.total) }}
            </span>
          </li>
          <li v-if="!byAttendant.length" class="px-5 py-4 text-sm text-muted-foreground">
            No shortage or overage charged to anyone.
          </li>
        </ul>
      </Card>
    </div>

    <!-- ============ other totals ============ -->
    <Card
      class="gap-0 py-0 mt-4 grid grid-cols-2 sm:grid-cols-4 sm:divide-x sm:divide-border"
      aria-label="Other totals"
    >
      <div
        v-for="(s, i) in stats"
        :key="s.label"
        class="flex items-center gap-3 border-border px-4 py-3.5"
        :class="{ 'max-sm:border-b': i < 2, 'max-sm:border-r': i % 2 === 0 }"
      >
        <span
          class="hidden size-9 shrink-0 place-items-center rounded-lg bg-muted text-muted-foreground sm:grid"
        >
          <component :is="s.icon" class="size-[18px]" />
        </span>
        <div class="min-w-0">
          <div class="text-[0.8rem] leading-tight text-muted-foreground">{{ s.label }}</div>
          <div class="font-display text-lg font-bold tabular-nums sm:text-xl">{{ s.value }}</div>
        </div>
      </div>
    </Card>

    <!-- ============ charts ============ -->
    <div class="mt-4 grid items-start gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
      <Card class="gap-0 py-0" aria-label="Daily sales">
        <div class="flex items-baseline justify-between gap-2 px-5 pt-4">
          <h2 class="font-display text-xl font-bold">Daily sales</h2>
          <span class="text-sm text-muted-foreground">
            {{ daily.length }} day{{ daily.length === 1 ? '' : 's' }} with reports
          </span>
        </div>
        <template v-if="daily.length">
          <div class="flex h-44 items-end gap-[3px] px-5 pt-4 pb-2">
            <div
              v-for="d in daily"
              :key="d.date"
              class="flex-1 rounded-t-[3px] bg-brand hover:bg-brand-dark"
              :style="{ height: `${Math.max(d.pct, 2)}%` }"
              :title="`${longDate(d.date)}: ${money(d.total)}`"
            ></div>
          </div>
          <div class="flex justify-between px-5 pb-4 text-xs text-muted-foreground">
            <span>{{ shortDate(daily[0]!.date) }}</span>
            <span v-if="daily.length > 1">{{ shortDate(daily[daily.length - 1]!.date) }}</span>
          </div>
        </template>
        <p v-else class="m-0 px-5 py-10 text-center text-muted-foreground">
          No sales recorded in {{ monthLabel }}.
        </p>
      </Card>

      <Card class="gap-0 py-0" aria-label="Sales by fuel type">
        <h2 class="px-5 pt-4 font-display text-xl font-bold">By fuel type</h2>
        <ul class="space-y-4 px-5 pt-4 pb-5">
          <li v-for="f in byFuel" :key="f.fuel.id">
            <div class="mb-1.5 flex items-baseline justify-between gap-2">
              <span class="font-semibold">{{ f.fuel.name }}</span>
              <span class="text-sm text-muted-foreground tabular-nums"
                >{{ liters(f.liters) }} L</span
              >
            </div>
            <div class="h-3 overflow-hidden rounded-full bg-muted">
              <div
                class="h-full rounded-full"
                :style="{ width: `${(f.liters / fuelMax) * 100}%`, background: f.fuel.color }"
              ></div>
            </div>
            <div class="mt-1 flex justify-between text-sm tabular-nums">
              <span>{{ money(f.sales) }}</span>
              <span class="text-muted-foreground">Income {{ money(f.income) }}</span>
            </div>
          </li>
          <li v-if="!byFuel.length" class="py-6 text-center text-muted-foreground">
            Nothing sold yet.
          </li>
        </ul>
      </Card>
    </div>

    <!-- ============ recent reports ============ -->
    <Card class="gap-0 py-0 mt-4" aria-label="Recent shift reports">
      <div class="flex items-center justify-between gap-2 px-5 pt-4 pb-3">
        <h2 class="font-display text-xl font-bold">Recent shift reports</h2>
        <RouterLink
          to="/admin/reports"
          class="inline-flex items-center gap-1 text-sm font-semibold text-brand hover:underline"
        >
          All reports <ArrowRight class="size-4" />
        </RouterLink>
      </div>
      <ul class="divide-y divide-border border-t border-border">
        <li v-for="r in reports.slice(0, 8)" :key="r.id" class="flex items-center gap-4 px-5 py-3">
          <div class="min-w-0 flex-1">
            <div class="truncate font-semibold">{{ longDate(r.report_date) }}</div>
            <div class="line-clamp-2 text-sm text-muted-foreground">
              {{ r.shift_name }} shift<template v-if="r.prepared_by_name">
                by {{ r.prepared_by_name }}</template
              >
            </div>
          </div>
          <div class="text-right tabular-nums">
            <div class="font-semibold">{{ money(r.total_after_error_discount) }}</div>
            <div class="text-sm font-semibold" :class="signClass(Number(r.over_short))">
              {{ money(r.over_short) }}
            </div>
          </div>
          <IconButton :icon="Eye" label="Open report" :to="`/admin/reports/${r.id}`" />
        </li>
        <li v-if="!reports.length && !loading" class="px-5 py-8 text-center text-muted-foreground">
          No shift reports in {{ monthLabel }}.
        </li>
      </ul>
    </Card>
  </div>
</template>

<style scoped>
/* pump LCD, same as the sign-in page */
.lcd {
  background: var(--lcd);
  color: var(--lcd-ink);
  box-shadow:
    inset 0 2px 0 rgba(0, 0, 0, 0.18),
    0 0 0 5px #1d2228;
}
</style>
