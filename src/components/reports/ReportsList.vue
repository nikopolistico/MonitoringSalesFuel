<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { ChevronRight, Eye, FilePlus2, FileText, Trash2 } from '@lucide/vue'
import { toast } from 'vue-sonner'
import IconButton from '@/components/common/IconButton.vue'
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Table,
  TableBody,
  TableCell,
  TableFooter,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { liters, longDate, money, todayIso } from '@/lib/format'
import { supabase } from '@/lib/supabase'
import type { ShiftReportSummary } from '@/lib/types'
import { cn } from '@/lib/utils'

/**
 * Month list of shift reports, shared by both areas.
 * - attendant: links to /reports/…, can start a new report
 * - admin: links to /admin/reports/…, can delete reports
 */
const props = defineProps<{ area: 'admin' | 'attendant' }>()
const isAdmin = computed(() => props.area === 'admin')
const month = ref(todayIso().slice(0, 7))
const rows = ref<ShiftReportSummary[]>([])
const loading = ref(true)

const base = computed(() => (isAdmin.value ? '/admin' : ''))

function nextMonthStart(ym: string): string {
  const [y, m] = ym.split('-').map(Number) as [number, number]
  return m === 12 ? `${y + 1}-01-01` : `${y}-${String(m + 1).padStart(2, '0')}-01`
}

async function load() {
  if (!month.value) return
  loading.value = true
  const { data, error } = await supabase
    .from('shift_report_summary')
    .select('*')
    .gte('report_date', `${month.value}-01`)
    .lt('report_date', nextMonthStart(month.value))
    .order('report_date', { ascending: false })
    .order('shift_id', { ascending: false })
  loading.value = false
  if (error) toast.error('Could not load reports', { description: error.message })
  rows.value = (data ?? []) as ShiftReportSummary[]
}

const monthLabel = computed(() =>
  month.value
    ? new Date(`${month.value}-01T00:00:00`).toLocaleDateString('en-US', {
        month: 'long',
        year: 'numeric',
      })
    : '',
)

const totals = computed(() =>
  rows.value.reduce(
    (t, r) => ({
      sales: t.sales + Number(r.total_after_error_discount),
      liters: t.liters + Number(r.total_liters),
      income: t.income + Number(r.total_income),
      expenses: t.expenses + Number(r.total_expenses) + Number(r.total_supplier_payments),
      cash: t.cash + Number(r.grand_total),
      gcash: t.gcash + Number(r.gcash_total),
      overShort: t.overShort + Number(r.over_short),
    }),
    { sales: 0, liters: 0, income: 0, expenses: 0, cash: 0, gcash: 0, overShort: 0 },
  ),
)

const stats = computed<{ label: string; value: string; cls?: string }[]>(() => [
  { label: 'Sales', value: money(totals.value.sales) },
  { label: 'Liters sold', value: liters(totals.value.liters) },
  { label: 'Income', value: money(totals.value.income) },
  { label: 'Expenses', value: money(totals.value.expenses) },
  { label: 'GCash', value: money(totals.value.gcash) },
  {
    label: 'Over / short',
    value: money(totals.value.overShort),
    cls: signClass(totals.value.overShort),
  },
])

function signClass(n: number) {
  return n < 0 ? 'text-destructive' : n > 0 ? 'text-good' : ''
}

/* ------------------------------------------------------------ delete */
const toDelete = ref<ShiftReportSummary | null>(null)
const deleting = ref(false)

async function confirmDelete() {
  const r = toDelete.value
  if (!r) return
  deleting.value = true
  const { error } = await supabase.from('shift_reports').delete().eq('id', r.id)
  deleting.value = false
  toDelete.value = null
  if (error) toast.error('Could not delete the report', { description: error.message })
  else toast.success(`${r.shift_name} shift of ${longDate(r.report_date)} was deleted`)
  load()
}

watch(month, load)
onMounted(load)
</script>

<template>
  <div>
    <!-- heading -->
    <div class="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 class="m-0 font-display text-[2.4rem] leading-none font-bold">
          {{ isAdmin ? 'Shift reports' : 'My shift reports' }}
        </h1>
        <p class="mt-1.5 text-muted-foreground">
          {{ rows.length }} report{{ rows.length === 1 ? '' : 's' }} in {{ monthLabel }}.
        </p>
      </div>
      <div class="flex w-full flex-wrap items-end gap-2 sm:w-auto">
        <div class="grid min-w-0 flex-1 gap-1.5 sm:w-48 sm:flex-none">
          <Label for="reports-month" class="text-muted-foreground">Month</Label>
          <Input id="reports-month" v-model="month" type="month" class="h-10 bg-card" />
        </div>
        <Button v-if="!isAdmin" as-child size="lg" class="h-10 px-4">
          <RouterLink to="/reports/new">
            <FilePlus2 />
            New shift report
          </RouterLink>
        </Button>
      </div>
    </div>

    <!-- month totals -->
    <Card class="mb-4 grid grid-cols-2 gap-0 py-0 sm:grid-cols-3 lg:grid-cols-6">
      <div
        v-for="(s, i) in stats"
        :key="s.label"
        :class="
          cn(
            'min-w-0 border-border px-4 py-3',
            i % 2 === 0 && 'max-sm:border-r',
            i < 4 && 'max-sm:border-b',
            'sm:max-lg:[&:not(:nth-child(3n))]:border-r sm:max-lg:[&:nth-child(-n+3)]:border-b',
            'lg:[&:not(:last-child)]:border-r',
          )
        "
      >
        <div class="text-[0.8rem] text-muted-foreground">{{ s.label }}</div>
        <div :class="cn('truncate font-display text-xl font-bold tabular-nums', s.cls)">
          {{ s.value }}
        </div>
      </div>
    </Card>

    <!-- loading -->
    <Card v-if="loading" class="gap-0 py-0">
      <div v-for="i in 4" :key="i" class="flex items-center gap-4 border-b px-4 py-4 last:border-0">
        <Skeleton class="h-4 w-40" />
        <Skeleton class="ml-auto h-4 w-24" />
      </div>
    </Card>

    <!-- empty -->
    <Card v-else-if="!rows.length" class="items-center gap-3 border-dashed px-6 py-12 text-center">
      <span class="grid size-12 place-items-center rounded-full bg-muted text-muted-foreground">
        <FileText class="size-6" />
      </span>
      <div>
        <p class="m-0 font-semibold">No shift reports in {{ monthLabel }}</p>
        <p v-if="!isAdmin" class="m-0 text-muted-foreground">
          Start one at the beginning of your shift.
        </p>
      </div>
      <Button v-if="!isAdmin" as-child size="lg">
        <RouterLink to="/reports/new"><FilePlus2 /> New shift report</RouterLink>
      </Button>
    </Card>

    <template v-else>
      <!-- phones: one card per report -->
      <div class="space-y-2 md:hidden">
        <RouterLink
          v-for="r in rows"
          :key="r.id"
          :to="`${base}/reports/${r.id}`"
          class="block rounded-xl outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
        >
          <Card class="gap-0 px-4 py-3 transition-colors active:bg-muted">
            <div class="flex items-center gap-3">
              <div class="min-w-0 flex-1">
                <div class="truncate font-semibold">{{ longDate(r.report_date) }}</div>
                <div class="line-clamp-2 text-sm text-muted-foreground">
                  {{ r.shift_name }} shift<template v-if="r.prepared_by_name">
                    by {{ r.prepared_by_name }}</template
                  >
                </div>
              </div>
              <div class="text-right tabular-nums">
                <div class="font-bold">{{ money(r.total_after_error_discount) }}</div>
                <div :class="cn('text-sm font-semibold', signClass(Number(r.over_short)))">
                  {{ money(r.over_short) }}
                </div>
              </div>
              <ChevronRight class="size-5 shrink-0 text-muted-foreground" />
            </div>
          </Card>
        </RouterLink>
      </div>

      <!-- tablets & PCs: table -->
      <Card class="hidden gap-0 overflow-hidden py-0 md:block">
        <Table>
          <TableHeader class="bg-muted/60">
            <TableRow>
              <TableHead class="pl-4">Date</TableHead>
              <TableHead>Shift</TableHead>
              <TableHead>Prepared by</TableHead>
              <TableHead class="text-right">Liters</TableHead>
              <TableHead class="text-right">Sales</TableHead>
              <TableHead class="hidden text-right lg:table-cell">Expenses</TableHead>
              <TableHead class="hidden text-right lg:table-cell">Cash + GCash</TableHead>
              <TableHead class="hidden text-right xl:table-cell">Income</TableHead>
              <TableHead class="text-right">Over / short</TableHead>
              <TableHead class="w-24 pr-4"><span class="sr-only">Actions</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="r in rows" :key="r.id">
              <TableCell class="pl-4 font-semibold">{{ longDate(r.report_date) }}</TableCell>
              <TableCell>
                {{ r.shift_name }}
                <span v-if="r.shift_hours" class="text-muted-foreground"
                  >({{ r.shift_hours }})</span
                >
              </TableCell>
              <TableCell>{{ r.prepared_by_name ?? '—' }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ liters(r.total_liters) }}</TableCell>
              <TableCell class="text-right font-semibold tabular-nums">
                {{ money(r.total_after_error_discount) }}
              </TableCell>
              <TableCell class="hidden text-right tabular-nums lg:table-cell">
                {{ money(Number(r.total_expenses) + Number(r.total_supplier_payments)) }}
              </TableCell>
              <TableCell class="hidden text-right tabular-nums lg:table-cell">
                {{ money(r.grand_total) }}
              </TableCell>
              <TableCell class="hidden text-right tabular-nums xl:table-cell">
                {{ money(r.total_income) }}
              </TableCell>
              <TableCell
                :class="
                  cn('text-right font-semibold tabular-nums', signClass(Number(r.over_short)))
                "
              >
                {{ money(r.over_short) }}
              </TableCell>
              <TableCell class="pr-4 text-right whitespace-nowrap">
                <IconButton :icon="Eye" label="Open report" :to="`${base}/reports/${r.id}`" />
                <IconButton
                  v-if="isAdmin"
                  :icon="Trash2"
                  label="Delete report"
                  tone="danger"
                  @click="toDelete = r"
                />
              </TableCell>
            </TableRow>
          </TableBody>
          <TableFooter>
            <TableRow class="font-bold">
              <TableCell class="pl-4" colspan="3">Total for {{ monthLabel }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ liters(totals.liters) }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ money(totals.sales) }}</TableCell>
              <TableCell class="hidden text-right tabular-nums lg:table-cell">
                {{ money(totals.expenses) }}
              </TableCell>
              <TableCell class="hidden text-right tabular-nums lg:table-cell">
                {{ money(totals.cash) }}
              </TableCell>
              <TableCell class="hidden text-right tabular-nums xl:table-cell">
                {{ money(totals.income) }}
              </TableCell>
              <TableCell :class="cn('text-right tabular-nums', signClass(totals.overShort))">
                {{ money(totals.overShort) }}
              </TableCell>
              <TableCell />
            </TableRow>
          </TableFooter>
        </Table>
      </Card>
    </template>

    <!-- delete confirmation -->
    <AlertDialog :open="!!toDelete" @update:open="(v) => !v && !deleting && (toDelete = null)">
      <AlertDialogContent class="sm:max-w-md">
        <AlertDialogHeader>
          <AlertDialogTitle class="font-display text-2xl">Delete this report?</AlertDialogTitle>
          <AlertDialogDescription v-if="toDelete">
            The {{ toDelete.shift_name }} shift of {{ longDate(toDelete.report_date) }} and all its
            readings, expenses and cash count will be removed. This cannot be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel size="lg" :disabled="deleting">Keep it</AlertDialogCancel>
          <Button variant="destructive" size="lg" :disabled="deleting" @click="confirmDelete">
            <Trash2 />
            {{ deleting ? 'Deleting…' : 'Delete report' }}
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>
</template>
