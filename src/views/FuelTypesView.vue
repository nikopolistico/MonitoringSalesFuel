<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { money, textOn, toNum } from '@/lib/format'
import type { FuelType, Pump } from '@/lib/types'

const fuelTypes = ref<FuelType[]>([])
const pumps = ref<Pump[]>([])
const error = ref('')
const editingId = ref<string | null>(null)

const blank = () => ({
  name: '',
  color: '#e11d2a',
  default_price: null as number | null,
  default_markup: 0 as number | null,
  sort_order: 0 as number | null,
})
const form = reactive(blank())

const pumpsOf = computed(() => {
  const m = new Map<string, Pump[]>()
  for (const p of pumps.value) m.set(p.fuel_type_id, [...(m.get(p.fuel_type_id) ?? []), p])
  return m
})

async function load() {
  const [ft, pu] = await Promise.all([
    supabase.from('fuel_types').select('*').order('sort_order').order('name'),
    supabase.from('pumps').select('*').order('pump_number'),
  ])
  error.value = ft.error?.message ?? pu.error?.message ?? ''
  fuelTypes.value = ft.data ?? []
  pumps.value = pu.data ?? []
}

async function run(action: PromiseLike<{ error: { message: string } | null }>) {
  error.value = ''
  const { error: err } = await action
  if (err) error.value = err.message
  await load()
  return !err
}

function resetForm() {
  Object.assign(form, blank(), { sort_order: fuelTypes.value.length + 1 })
  editingId.value = null
}

function edit(f: FuelType) {
  editingId.value = f.id
  Object.assign(form, {
    name: f.name,
    color: f.color,
    default_price: f.default_price,
    default_markup: f.default_markup,
    sort_order: f.sort_order,
  })
}

async function save() {
  const payload = {
    name: form.name.trim().toUpperCase(),
    color: form.color,
    default_price: toNum(form.default_price),
    default_markup: toNum(form.default_markup) ?? 0,
    sort_order: toNum(form.sort_order) ?? 0,
  }
  const ok = await run(
    editingId.value
      ? supabase.from('fuel_types').update(payload).eq('id', editingId.value)
      : supabase.from('fuel_types').insert(payload),
  )
  if (ok) resetForm()
}

function toggleFuel(f: FuelType) {
  run(supabase.from('fuel_types').update({ is_active: !f.is_active }).eq('id', f.id))
}

function addPump(f: FuelType) {
  const next = Math.max(0, ...(pumpsOf.value.get(f.id) ?? []).map((p) => p.pump_number)) + 1
  run(supabase.from('pumps').insert({ fuel_type_id: f.id, pump_number: next }))
}

function togglePump(p: Pump) {
  run(supabase.from('pumps').update({ is_active: !p.is_active }).eq('id', p.id))
}

onMounted(async () => {
  await load()
  resetForm()
})
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Fuel Types &amp; Pumps</h1>
      <div class="muted">
        Each fuel type has numbered pumps (e.g. DIESEL 1–4). Default price and mark up pre-fill the
        shift sheet, where the attendant can still change them.
      </div>
    </div>
  </div>

  <div v-if="error" class="alert error">{{ error }}</div>

  <div class="card">
    <div class="card-head">
      <h2>{{ editingId ? 'Edit fuel type' : 'Add fuel type' }}</h2>
    </div>
    <form class="card-body meta-grid" @submit.prevent="save">
      <label class="field"
        >Fuel type <input v-model="form.name" required placeholder="e.g. PREMIUM"
      /></label>
      <label class="field">
        Default price / liter
        <input v-model.number="form.default_price" type="number" step="0.01" min="0" class="num" />
      </label>
      <label class="field">
        Default mark up / liter
        <input v-model.number="form.default_markup" type="number" step="0.01" min="0" class="num" />
      </label>
      <label class="field">
        Label color
        <input v-model="form.color" type="color" style="height: 34px; padding: 2px" />
      </label>
      <label class="field"
        >Sort order <input v-model.number="form.sort_order" type="number" class="num"
      /></label>
      <div style="display: flex; gap: 8px; align-items: flex-end">
        <button class="btn primary">{{ editingId ? 'Update' : 'Add' }}</button>
        <button v-if="editingId" type="button" class="btn" @click="resetForm">Cancel</button>
      </div>
    </form>
  </div>

  <div class="card">
    <div class="table-scroll">
      <table class="sheet">
        <thead>
          <tr>
            <th style="text-align: left">Fuel type</th>
            <th class="num hidden sm:table-cell">Default price</th>
            <th class="num hidden sm:table-cell">Mark up</th>
            <th style="text-align: left">Pumps (click to turn on/off)</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="f in fuelTypes" :key="f.id" :style="{ opacity: f.is_active ? 1 : 0.5 }">
            <td>
              <span class="fuel-tag" :style="{ background: f.color, color: textOn(f.color) }">{{
                f.name
              }}</span>
            </td>
            <td class="num hidden sm:table-cell">
              {{ f.default_price == null ? '—' : money(f.default_price) }}
            </td>
            <td class="num hidden sm:table-cell">{{ money(f.default_markup) }}</td>
            <td>
              <button
                v-for="p in pumpsOf.get(f.id) ?? []"
                :key="p.id"
                class="pump-chip"
                :style="{
                  opacity: p.is_active ? 1 : 0.4,
                  textDecoration: p.is_active ? 'none' : 'line-through',
                }"
                :title="p.is_active ? 'Turn off this pump' : 'Turn on this pump'"
                @click="togglePump(p)"
              >
                {{ f.name }} {{ p.pump_number }}
              </button>
              <button class="btn small" @click="addPump(f)">+ Pump</button>
            </td>
            <td class="w-[1%] text-right [&_.btn]:m-0.5 max-sm:[&_.btn]:w-full">
              <button class="btn small" @click="edit(f)">Edit</button>
              <button class="btn small" @click="toggleFuel(f)">
                {{ f.is_active ? 'Deactivate' : 'Activate' }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
