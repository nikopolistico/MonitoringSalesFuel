<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { Check, Fuel, Pencil, Plus, Power } from '@lucide/vue'
import { toast } from 'vue-sonner'
import IconButton from '@/components/common/IconButton.vue'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { money, textOn, toNum } from '@/lib/format'
import { supabase } from '@/lib/supabase'
import type { FuelType, Pump } from '@/lib/types'
import { cn } from '@/lib/utils'

const fuelTypes = ref<FuelType[]>([])
const pumps = ref<Pump[]>([])
const loading = ref(true)

const pumpsOf = computed(() => {
  const m = new Map<string, Pump[]>()
  for (const p of pumps.value) m.set(p.fuel_type_id, [...(m.get(p.fuel_type_id) ?? []), p])
  return m
})
const activePumps = computed(
  () =>
    pumps.value.filter(
      (p) => p.is_active && fuelTypes.value.find((f) => f.id === p.fuel_type_id)?.is_active,
    ).length,
)

async function load() {
  const [ft, pu] = await Promise.all([
    supabase.from('fuel_types').select('*').order('sort_order').order('name'),
    supabase.from('pumps').select('*').order('pump_number'),
  ])
  const err = ft.error ?? pu.error
  if (err) toast.error('Could not load fuel types', { description: err.message })
  fuelTypes.value = ft.data ?? []
  pumps.value = pu.data ?? []
  loading.value = false
}

async function run(action: PromiseLike<{ error: { message: string } | null }>, ok?: string) {
  const { error } = await action
  if (error) toast.error('Could not save', { description: error.message })
  else if (ok) toast.success(ok)
  await load()
  return !error
}

/* ---------------------------------------------------- add / edit dialog */

const form = reactive({
  open: false,
  editingId: null as string | null,
  name: '',
  color: '#e11d2a',
  default_price: undefined as number | undefined,
  default_markup: 0 as number | undefined,
  sort_order: 0 as number | undefined,
  busy: false,
  error: '',
})

function openCreate() {
  Object.assign(form, {
    open: true,
    editingId: null,
    name: '',
    color: '#e11d2a',
    default_price: undefined,
    default_markup: 0,
    sort_order: fuelTypes.value.length + 1,
    error: '',
  })
}

function openEdit(f: FuelType) {
  Object.assign(form, {
    open: true,
    editingId: f.id,
    name: f.name,
    color: f.color,
    default_price: f.default_price ?? undefined,
    default_markup: f.default_markup,
    sort_order: f.sort_order,
    error: '',
  })
}

async function save() {
  form.error = ''
  const name = form.name.trim().toUpperCase()
  if (!name) {
    form.error = 'Enter the fuel type name.'
    return
  }
  const payload = {
    name,
    color: form.color,
    default_price: toNum(form.default_price),
    default_markup: toNum(form.default_markup) ?? 0,
    sort_order: toNum(form.sort_order) ?? 0,
  }
  form.busy = true
  const { error } = form.editingId
    ? await supabase.from('fuel_types').update(payload).eq('id', form.editingId)
    : await supabase.from('fuel_types').insert(payload)
  form.busy = false
  if (error) {
    form.error = error.message
    return
  }
  form.open = false
  toast.success(form.editingId ? `${name} was updated` : `${name} was added`, {
    description: form.editingId ? undefined : 'Add its pumps with the "Pump" button.',
  })
  load()
}

/* -------------------------------------------------------------- actions */

function toggleFuel(f: FuelType) {
  if (
    f.is_active &&
    !confirm(`Deactivate ${f.name}? Its pumps will not appear on new shift sheets.`)
  )
    return
  run(
    supabase.from('fuel_types').update({ is_active: !f.is_active }).eq('id', f.id),
    `${f.name} is now ${f.is_active ? 'inactive' : 'active'}`,
  )
}

function addPump(f: FuelType) {
  const next = Math.max(0, ...(pumpsOf.value.get(f.id) ?? []).map((p) => p.pump_number)) + 1
  run(
    supabase.from('pumps').insert({ fuel_type_id: f.id, pump_number: next }),
    `${f.name} ${next} was added`,
  )
}

function togglePump(f: FuelType, p: Pump) {
  run(
    supabase.from('pumps').update({ is_active: !p.is_active }).eq('id', p.id),
    `${f.name} ${p.pump_number} is now ${p.is_active ? 'off' : 'on'}`,
  )
}

onMounted(load)
</script>

<template>
  <div>
    <!-- heading -->
    <div class="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 class="m-0 font-display text-[2.4rem] leading-none font-bold">Fuel types</h1>
        <p class="mt-1.5 max-w-xl text-muted-foreground">
          {{ activePumps }} pumps are on the shift sheet. Default price and mark-up pre-fill the
          sheet; attendants can still change them per shift.
        </p>
      </div>
      <Button size="lg" class="h-11 px-4 text-base" @click="openCreate">
        <Plus />
        New fuel type
      </Button>
    </div>

    <!-- loading -->
    <div v-if="loading" class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      <Skeleton v-for="i in 3" :key="i" class="h-48 rounded-xl" />
    </div>

    <!-- fuel type cards -->
    <div v-else class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      <Card
        v-for="f in fuelTypes"
        :key="f.id"
        :class="cn('gap-0 overflow-hidden py-0', !f.is_active && 'opacity-60')"
      >
        <div class="h-1.5" :style="{ background: f.color }" aria-hidden="true"></div>

        <div class="flex items-start justify-between gap-2 px-5 pt-4">
          <div class="flex items-center gap-3">
            <span
              class="grid size-10 place-items-center rounded-lg"
              :style="{ background: f.color, color: textOn(f.color) }"
            >
              <Fuel class="size-5" />
            </span>
            <div>
              <h2 class="font-display text-2xl leading-none font-bold">{{ f.name }}</h2>
              <Badge v-if="!f.is_active" variant="secondary" class="mt-1">Inactive</Badge>
            </div>
          </div>
          <div class="-mr-2 flex">
            <IconButton :icon="Pencil" :label="`Edit ${f.name}`" @click="openEdit(f)" />
            <IconButton
              :icon="Power"
              :label="f.is_active ? `Deactivate ${f.name}` : `Activate ${f.name}`"
              :tone="f.is_active ? 'danger' : 'good'"
              @click="toggleFuel(f)"
            />
          </div>
        </div>

        <dl class="mx-5 mt-4 grid grid-cols-2 gap-px overflow-hidden rounded-lg border bg-border">
          <div class="bg-card px-3 py-2.5">
            <dt class="text-xs text-muted-foreground">Default price / liter</dt>
            <dd class="font-display text-xl font-bold tabular-nums">
              {{ f.default_price == null ? '—' : money(f.default_price) }}
            </dd>
          </div>
          <div class="bg-card px-3 py-2.5">
            <dt class="text-xs text-muted-foreground">Mark-up / liter</dt>
            <dd class="font-display text-xl font-bold tabular-nums">
              {{ money(f.default_markup) }}
            </dd>
          </div>
        </dl>

        <div class="px-5 pt-4 pb-5">
          <div class="mb-2 text-sm font-semibold">Pumps</div>
          <div class="flex flex-wrap gap-1.5">
            <Tooltip v-for="p in pumpsOf.get(f.id) ?? []" :key="p.id">
              <TooltipTrigger as-child>
                <button
                  type="button"
                  :class="
                    cn(
                      'inline-flex h-8 items-center gap-1.5 rounded-full border px-3 text-sm font-semibold transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/50',
                      p.is_active
                        ? 'border-transparent bg-admin text-white hover:bg-admin/85'
                        : 'border-dashed bg-card text-muted-foreground line-through hover:bg-muted',
                    )
                  "
                  :aria-pressed="p.is_active"
                  :aria-label="`${f.name} ${p.pump_number}: ${p.is_active ? 'on' : 'off'}`"
                  @click="togglePump(f, p)"
                >
                  <Check v-if="p.is_active" class="size-3.5" />
                  {{ f.name }} {{ p.pump_number }}
                </button>
              </TooltipTrigger>
              <TooltipContent>
                {{ p.is_active ? 'Turn off this pump' : 'Turn on this pump' }}
              </TooltipContent>
            </Tooltip>
            <Button variant="outline" size="sm" class="h-8 rounded-full px-3" @click="addPump(f)">
              <Plus />
              Pump
            </Button>
          </div>
        </div>
      </Card>

      <!-- empty -->
      <Card
        v-if="!fuelTypes.length"
        class="items-center gap-3 border-dashed px-6 py-12 text-center md:col-span-2 xl:col-span-3"
      >
        <span class="grid size-12 place-items-center rounded-full bg-muted text-muted-foreground">
          <Fuel class="size-6" />
        </span>
        <p class="m-0 font-semibold">No fuel types yet</p>
        <Button size="lg" @click="openCreate"><Plus /> New fuel type</Button>
      </Card>
    </div>

    <!-- ============ add / edit dialog ============ -->
    <Dialog :open="form.open" @update:open="(v) => !form.busy && (form.open = v)">
      <DialogContent class="max-h-[92dvh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle class="font-display text-2xl">
            {{ form.editingId ? 'Edit fuel type' : 'New fuel type' }}
          </DialogTitle>
          <DialogDescription>
            The defaults pre-fill the shift sheet; attendants can still change them per shift.
          </DialogDescription>
        </DialogHeader>

        <form id="fuel-form" class="grid gap-4" novalidate @submit.prevent="save">
          <div class="grid grid-cols-[1fr_auto] gap-3">
            <div class="grid gap-1.5">
              <Label for="f-name">Name</Label>
              <Input
                id="f-name"
                v-model="form.name"
                class="h-11 uppercase"
                placeholder="PREMIUM"
                list="fuel-names"
                autocomplete="off"
              />
              <datalist id="fuel-names">
                <option value="PREMIUM" />
                <option value="REGULAR" />
                <option value="DIESEL" />
              </datalist>
            </div>
            <div class="grid gap-1.5">
              <Label for="f-color">Label color</Label>
              <input
                id="f-color"
                v-model="form.color"
                type="color"
                class="h-11 w-16 cursor-pointer rounded-lg border border-input bg-card p-1"
              />
            </div>
          </div>
          <div class="grid gap-4 sm:grid-cols-2">
            <div class="grid gap-1.5">
              <Label for="f-price">Default price / liter</Label>
              <Input
                id="f-price"
                v-model.number="form.default_price"
                type="number"
                inputmode="decimal"
                step="0.01"
                min="0"
                class="h-11 text-right tabular-nums"
              />
            </div>
            <div class="grid gap-1.5">
              <Label for="f-markup">Mark-up / liter</Label>
              <Input
                id="f-markup"
                v-model.number="form.default_markup"
                type="number"
                inputmode="decimal"
                step="0.01"
                min="0"
                class="h-11 text-right tabular-nums"
              />
            </div>
          </div>
          <div class="grid gap-1.5 sm:w-1/2">
            <Label for="f-order">Order on the sheet</Label>
            <Input
              id="f-order"
              v-model.number="form.sort_order"
              type="number"
              class="h-11 text-right tabular-nums"
            />
          </div>

          <p
            v-if="form.error"
            class="m-0 rounded-lg border border-destructive/25 bg-destructive/5 px-3 py-2 text-sm font-medium text-destructive"
            role="alert"
          >
            {{ form.error }}
          </p>
        </form>

        <DialogFooter>
          <Button variant="outline" size="lg" :disabled="form.busy" @click="form.open = false">
            Cancel
          </Button>
          <Button type="submit" form="fuel-form" size="lg" :disabled="form.busy">
            <component :is="form.editingId ? Check : Plus" />
            {{ form.busy ? 'Saving…' : form.editingId ? 'Save changes' : 'Add fuel type' }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
