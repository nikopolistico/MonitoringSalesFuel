<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { supabase } from '@/lib/supabase'
import type { AccountStatus, PumpAttendant, UserAccount } from '@/lib/types'

const rows = ref<PumpAttendant[]>([])
const accounts = ref<UserAccount[]>([])
const error = ref('')
const notice = ref('')

const blankForm = () => ({
  full_name: '',
  nickname: '',
  contact_no: '',
  username: '',
  password: '',
})
const form = reactive(blankForm())
const editingId = ref<string | null>(null)

/** Inline "set login" panel for one attendant. */
const loginFor = ref<PumpAttendant | null>(null)
const login = reactive({ username: '', password: '' })

const list = computed(() => {
  const byPerson = new Map(accounts.value.map((acc) => [acc.pump_attendant_id, acc]))
  return rows.value.map((a) => ({ a, acc: byPerson.get(a.id) }))
})

async function load() {
  const [pa, ua] = await Promise.all([
    supabase
      .from('pump_attendants')
      .select('*')
      .order('is_active', { ascending: false })
      .order('full_name'),
    // explicit columns: the password hash is not readable
    supabase
      .from('user_accounts')
      .select('id, pump_attendant_id, username, role, status, created_at, last_login_at')
      .eq('role', 'ATTENDANT'),
  ])
  error.value = pa.error?.message ?? ua.error?.message ?? ''
  rows.value = pa.data ?? []
  accounts.value = (ua.data ?? []) as UserAccount[]
}

async function run(action: PromiseLike<{ error: { message: string } | null }>, ok?: string) {
  error.value = ''
  notice.value = ''
  const { error: err } = await action
  if (err) error.value = err.message
  else if (ok) notice.value = ok
  await load()
  return !err
}

function resetForm() {
  Object.assign(form, blankForm())
  editingId.value = null
}

function edit(a: PumpAttendant) {
  loginFor.value = null
  editingId.value = a.id
  Object.assign(form, blankForm(), {
    full_name: a.full_name,
    nickname: a.nickname ?? '',
    contact_no: a.contact_no ?? '',
  })
}

async function save() {
  if (editingId.value) {
    const ok = await run(
      supabase
        .from('pump_attendants')
        .update({
          full_name: form.full_name.trim(),
          nickname: form.nickname.trim() || null,
          contact_no: form.contact_no.trim() || null,
        })
        .eq('id', editingId.value),
      'Attendant updated.',
    )
    if (ok) resetForm()
    return
  }
  if (Boolean(form.username.trim()) !== Boolean(form.password)) {
    error.value = 'Enter both a username and a password, or leave both empty for no login.'
    return
  }
  const name = form.full_name.trim()
  const ok = await run(
    supabase.rpc('admin_create_attendant', {
      p_full_name: form.full_name,
      p_nickname: form.nickname,
      p_contact_no: form.contact_no,
      p_username: form.username,
      p_password: form.password,
    }),
    form.username.trim()
      ? `${name} was created. They can now sign in as "${form.username.trim().toLowerCase()}".`
      : `${name} was created (no login).`,
  )
  if (ok) resetForm()
}

function openLogin(a: PumpAttendant, acc?: UserAccount) {
  editingId.value = null
  loginFor.value = a
  Object.assign(login, { username: acc?.username ?? '', password: '' })
}

async function saveLogin() {
  if (!loginFor.value) return
  const ok = await run(
    supabase.rpc('admin_set_login', {
      p_attendant_id: loginFor.value.id,
      p_username: login.username,
      p_password: login.password,
    }),
    `Login saved for ${loginFor.value.full_name}.`,
  )
  if (ok) loginFor.value = null
}

function setStatus(acc: UserAccount, status: AccountStatus) {
  run(
    supabase.from('user_accounts').update({ status }).eq('id', acc.id),
    `${acc.username} is now ${status === 'ACTIVE' ? 'enabled' : 'disabled'}.`,
  )
}

function toggleActive(a: PumpAttendant) {
  run(supabase.from('pump_attendants').update({ is_active: !a.is_active }).eq('id', a.id))
}

onMounted(load)
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Pump Attendants</h1>
      <div class="muted">
        Create pump attendants and their logins. Attendants sign in on the main page and can only
        use Reports and New Shift.
      </div>
    </div>
  </div>

  <div v-if="error" class="alert error">{{ error }}</div>
  <div v-if="notice" class="alert ok">{{ notice }}</div>

  <div class="card">
    <div class="card-head">
      <h2>{{ editingId ? 'Edit pump attendant' : 'Create pump attendant' }}</h2>
    </div>
    <form class="card-body meta-grid" @submit.prevent="save">
      <label class="field">Full name <input v-model="form.full_name" required /></label>
      <label class="field"
        >Nickname <input v-model="form.nickname" placeholder="e.g. JEFF"
      /></label>
      <label class="field">Contact no. <input v-model="form.contact_no" type="tel" /></label>
      <template v-if="!editingId">
        <label class="field">
          Login username
          <input
            v-model="form.username"
            autocomplete="off"
            autocapitalize="none"
            pattern="[A-Za-z0-9._]{3,30}"
            title="3-30 characters: letters, numbers, dot or underscore"
            placeholder="leave empty for no login"
          />
        </label>
        <label class="field">
          Login password
          <input
            v-model="form.password"
            type="password"
            autocomplete="new-password"
            minlength="6"
            placeholder="at least 6 characters"
          />
        </label>
      </template>
      <div style="display: flex; gap: 8px; align-items: flex-end">
        <button class="btn primary">{{ editingId ? 'Update' : 'Create' }}</button>
        <button v-if="editingId" type="button" class="btn" @click="resetForm">Cancel</button>
      </div>
    </form>
  </div>

  <div v-if="loginFor" class="card">
    <div class="card-head login-panel">
      <h2>Login for {{ loginFor.full_name }}</h2>
    </div>
    <form class="card-body meta-grid login-panel" @submit.prevent="saveLogin">
      <label class="field">
        Username
        <input
          v-model="login.username"
          required
          autocomplete="off"
          autocapitalize="none"
          pattern="[A-Za-z0-9._]{3,30}"
          title="3-30 characters: letters, numbers, dot or underscore"
        />
      </label>
      <label class="field">
        New password
        <input
          v-model="login.password"
          type="password"
          required
          minlength="6"
          autocomplete="new-password"
        />
      </label>
      <div style="display: flex; gap: 8px; align-items: flex-end">
        <button class="btn primary">Save login</button>
        <button type="button" class="btn" @click="loginFor = null">Cancel</button>
      </div>
    </form>
  </div>

  <div class="card">
    <div class="table-scroll">
      <table class="sheet">
        <thead>
          <tr>
            <th style="text-align: left">Name</th>
            <th class="hidden sm:table-cell">Nickname</th>
            <th class="hidden md:table-cell">Contact</th>
            <th>Username</th>
            <th>Login</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="{ a, acc } in list" :key="a.id" :style="{ opacity: a.is_active ? 1 : 0.5 }">
            <td>
              <b>{{ a.full_name }}</b>
              <span v-if="!a.is_active" class="badge balanced" style="margin-left: 6px"
                >INACTIVE</span
              >
            </td>
            <td class="hidden text-center sm:table-cell">{{ a.nickname ?? '—' }}</td>
            <td class="hidden text-center md:table-cell">{{ a.contact_no ?? '—' }}</td>
            <td style="text-align: center">
              <template v-if="acc">{{ acc.username }}</template>
              <span v-else class="muted">no login</span>
            </td>
            <td style="text-align: center">
              <span v-if="acc" class="badge" :class="acc.status === 'ACTIVE' ? 'over' : 'short'">
                {{ acc.status === 'ACTIVE' ? 'ENABLED' : 'DISABLED' }}
              </span>
            </td>
            <td class="w-[1%] text-right [&_.btn]:m-0.5 max-sm:[&_.btn]:w-full">
              <button class="btn small" @click="openLogin(a, acc)">
                {{ acc ? 'Change login' : 'Create login' }}
              </button>
              <template v-if="acc">
                <button
                  v-if="acc.status === 'ACTIVE'"
                  class="btn small danger"
                  @click="setStatus(acc, 'DISABLED')"
                >
                  Disable login
                </button>
                <button v-else class="btn small primary" @click="setStatus(acc, 'ACTIVE')">
                  Enable login
                </button>
              </template>
              <button class="btn small" @click="edit(a)">Edit</button>
              <button class="btn small" @click="toggleActive(a)">
                {{ a.is_active ? 'Deactivate' : 'Activate' }}
              </button>
            </td>
          </tr>
          <tr v-if="!rows.length">
            <td colspan="6" class="muted" style="text-align: center; padding: 20px">
              No pump attendants yet. Create one above.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
