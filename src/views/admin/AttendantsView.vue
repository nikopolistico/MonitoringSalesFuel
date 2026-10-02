<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import {
  Check,
  Eye,
  EyeOff,
  KeyRound,
  Lock,
  LockOpen,
  Pencil,
  Power,
  Search,
  UserPlus,
  Users,
} from '@lucide/vue'
import { toast } from 'vue-sonner'
import IconButton from '@/components/common/IconButton.vue'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
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
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { supabase } from '@/lib/supabase'
import type { AccountStatus, PumpAttendant, UserAccount } from '@/lib/types'
import { cn } from '@/lib/utils'

const rows = ref<PumpAttendant[]>([])
const accounts = ref<UserAccount[]>([])
const loading = ref(true)

/* ---------------------------------------------------------------- data */

async function load() {
  const [pa, ua] = await Promise.all([
    supabase.from('pump_attendants').select('*').order('full_name'),
    // explicit columns: the password hash is not readable
    supabase
      .from('user_accounts')
      .select('id, pump_attendant_id, username, role, status, created_at, last_login_at')
      .eq('role', 'ATTENDANT'),
  ])
  const err = pa.error ?? ua.error
  if (err) toast.error('Could not load attendants', { description: err.message })
  rows.value = pa.data ?? []
  accounts.value = (ua.data ?? []) as UserAccount[]
  loading.value = false
}

/* ------------------------------------------------------- list & filters */

type Filter = 'all' | 'active' | 'inactive' | 'nologin'
const filter = ref<Filter>('all')
const search = ref('')

const list = computed(() => {
  const byPerson = new Map(accounts.value.map((acc) => [acc.pump_attendant_id, acc]))
  return rows.value
    .map((a) => ({ a, acc: byPerson.get(a.id) }))
    .sort((x, y) => Number(y.a.is_active) - Number(x.a.is_active))
})

const visible = computed(() => {
  const q = search.value.trim().toLowerCase()
  return list.value.filter(({ a, acc }) => {
    if (filter.value === 'active' && !a.is_active) return false
    if (filter.value === 'inactive' && a.is_active) return false
    if (filter.value === 'nologin' && acc) return false
    if (!q) return true
    return [a.full_name, a.nickname, a.contact_no, acc?.username]
      .filter(Boolean)
      .some((v) => v!.toLowerCase().includes(q))
  })
})

const counts = computed(() => ({
  all: list.value.length,
  active: list.value.filter((x) => x.a.is_active).length,
  inactive: list.value.filter((x) => !x.a.is_active).length,
  nologin: list.value.filter((x) => !x.acc).length,
}))
const canSignIn = computed(
  () => list.value.filter((x) => x.a.is_active && x.acc?.status === 'ACTIVE').length,
)

const filters: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'inactive', label: 'Inactive' },
  { key: 'nologin', label: 'No login' },
]

function initials(name: string) {
  const parts = name.trim().split(/\s+/)
  return (
    (parts[0]?.[0] ?? '') + (parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? '') : '')
  ).toUpperCase()
}

function lastSignIn(iso: string | null) {
  if (!iso) return 'Never signed in'
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
  if (mins < 2) return 'Signed in just now'
  if (mins < 60) return `Signed in ${mins} min ago`
  const hours = Math.round(mins / 60)
  if (hours < 24) return `Signed in ${hours} h ago`
  const days = Math.round(hours / 24)
  if (days < 31) return `Signed in ${days} day${days > 1 ? 's' : ''} ago`
  return `Last signed in ${new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`
}

/* ------------------------------------------------- create / edit dialog */

const person = reactive({
  open: false,
  editingId: null as string | null,
  full_name: '',
  nickname: '',
  contact_no: '',
  withLogin: true,
  username: '',
  password: '',
  showPassword: false,
  busy: false,
  error: '',
})

function openCreate() {
  Object.assign(person, {
    open: true,
    editingId: null,
    full_name: '',
    nickname: '',
    contact_no: '',
    withLogin: true,
    username: '',
    password: '',
    showPassword: false,
    error: '',
  })
}

function openEdit(a: PumpAttendant) {
  Object.assign(person, {
    open: true,
    editingId: a.id,
    full_name: a.full_name,
    nickname: a.nickname ?? '',
    contact_no: a.contact_no ?? '',
    withLogin: false,
    error: '',
  })
}

async function savePerson() {
  person.error = ''
  const name = person.full_name.trim()
  if (!name) {
    person.error = 'Enter the full name.'
    return
  }
  if (
    !person.editingId &&
    person.withLogin &&
    (!person.username.trim() || person.password.length < 6)
  ) {
    person.error =
      'Enter a username and a password of at least 6 characters, or turn off "Give a login".'
    return
  }
  person.busy = true
  const { error } = person.editingId
    ? await supabase
        .from('pump_attendants')
        .update({
          full_name: name,
          nickname: person.nickname.trim() || null,
          contact_no: person.contact_no.trim() || null,
        })
        .eq('id', person.editingId)
    : await supabase.rpc('admin_create_attendant', {
        p_full_name: name,
        p_nickname: person.nickname,
        p_contact_no: person.contact_no,
        p_username: person.withLogin ? person.username : '',
        p_password: person.withLogin ? person.password : '',
      })
  person.busy = false
  if (error) {
    person.error = error.message
    return
  }
  person.open = false
  if (person.editingId) toast.success(`${name} was updated`)
  else
    toast.success(`${name} was created`, {
      description: person.withLogin
        ? `They can sign in as "${person.username.trim().toLowerCase()}".`
        : 'No login was given.',
    })
  load()
}

/* ------------------------------------------------------- login dialog */

const login = reactive({
  open: false,
  attendant: null as PumpAttendant | null,
  hasLogin: false,
  username: '',
  password: '',
  showPassword: false,
  busy: false,
  error: '',
})

function openLogin(a: PumpAttendant, acc?: UserAccount) {
  Object.assign(login, {
    open: true,
    attendant: a,
    hasLogin: Boolean(acc),
    username: acc?.username ?? '',
    password: '',
    showPassword: false,
    error: '',
  })
}

async function saveLogin() {
  if (!login.attendant) return
  login.error = ''
  login.busy = true
  const { error } = await supabase.rpc('admin_set_login', {
    p_attendant_id: login.attendant.id,
    p_username: login.username,
    p_password: login.password,
  })
  login.busy = false
  if (error) {
    login.error = error.message
    return
  }
  login.open = false
  toast.success(`Login saved for ${login.attendant.full_name}`, {
    description: 'They must sign in again with the new password.',
  })
  load()
}

/* ------------------------------------------------------- quick actions */

async function setLoginStatus(a: PumpAttendant, acc: UserAccount, status: AccountStatus) {
  if (
    status === 'DISABLED' &&
    !confirm(`Disable the login of ${a.full_name}? They will be signed out.`)
  )
    return
  const { error } = await supabase.from('user_accounts').update({ status }).eq('id', acc.id)
  if (error) toast.error('Could not change the login', { description: error.message })
  else
    toast.success(
      `${a.full_name} ${status === 'ACTIVE' ? 'can sign in again' : 'can no longer sign in'}`,
    )
  load()
}

async function toggleActive(a: PumpAttendant) {
  if (
    a.is_active &&
    !confirm(`Deactivate ${a.full_name}? They will no longer appear on new shift reports.`)
  )
    return
  const { error } = await supabase
    .from('pump_attendants')
    .update({ is_active: !a.is_active })
    .eq('id', a.id)
  if (error) toast.error('Could not update the attendant', { description: error.message })
  else toast.success(`${a.full_name} is now ${a.is_active ? 'inactive' : 'active'}`)
  load()
}

onMounted(load)
</script>

<template>
  <div>
    <!-- heading -->
    <div class="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 class="m-0 font-display text-[2.4rem] leading-none font-bold">Pump attendants</h1>
        <p class="mt-1.5 text-muted-foreground">
          {{ counts.active }} active, {{ canSignIn }} can sign in to the attendant site.
        </p>
      </div>
      <Button size="lg" class="h-11 px-4 text-base" @click="openCreate">
        <UserPlus />
        New attendant
      </Button>
    </div>

    <!-- toolbar -->
    <div class="mb-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
      <div class="relative sm:w-80">
        <Search
          class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
        />
        <Input
          v-model="search"
          type="search"
          aria-label="Search attendants"
          placeholder="Search name, nickname or username"
          class="h-10 bg-card pl-9"
        />
      </div>
      <Tabs v-model="filter">
        <TabsList class="h-10 max-w-full overflow-x-auto">
          <TabsTrigger v-for="f in filters" :key="f.key" :value="f.key" class="px-3">
            {{ f.label }}
            <span class="ml-1 tabular-nums opacity-60">{{ counts[f.key] }}</span>
          </TabsTrigger>
        </TabsList>
      </Tabs>
    </div>

    <!-- list -->
    <Card class="gap-0 overflow-hidden py-0">
      <div
        class="hidden grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)_9rem_10rem] gap-4 border-b bg-muted/60 px-4 py-2.5 text-[0.8rem] font-semibold text-muted-foreground md:grid"
      >
        <span>Attendant</span>
        <span>Login</span>
        <span>Status</span>
        <span class="text-right">Actions</span>
      </div>

      <!-- loading -->
      <ul v-if="loading" class="divide-y">
        <li v-for="i in 4" :key="i" class="flex items-center gap-3 px-4 py-4">
          <Skeleton class="size-10 rounded-full" />
          <div class="flex-1 space-y-2">
            <Skeleton class="h-4 w-48" />
            <Skeleton class="h-3 w-32" />
          </div>
        </li>
      </ul>

      <ul v-else class="divide-y">
        <li
          v-for="{ a, acc } in visible"
          :key="a.id"
          :class="
            cn(
              'grid grid-cols-[auto_minmax(0,1fr)] items-center gap-x-3 gap-y-2 px-4 py-3.5 md:grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)_9rem_10rem] md:gap-4',
              !a.is_active && 'bg-muted/40',
            )
          "
        >
          <!-- attendant -->
          <div class="col-span-2 flex min-w-0 items-center gap-3 md:col-span-1">
            <Avatar class="size-10">
              <AvatarFallback
                :class="
                  cn(
                    'font-display text-lg font-bold',
                    a.is_active ? 'bg-admin text-white' : 'bg-muted text-muted-foreground',
                  )
                "
              >
                {{ initials(a.full_name) }}
              </AvatarFallback>
            </Avatar>
            <div class="min-w-0">
              <div :class="cn('truncate font-semibold', !a.is_active && 'text-muted-foreground')">
                {{ a.full_name }}
                <span v-if="a.nickname" class="font-normal text-muted-foreground">
                  ({{ a.nickname }})
                </span>
              </div>
              <div class="truncate text-sm text-muted-foreground">
                {{ a.contact_no || 'No contact number' }}
              </div>
            </div>
          </div>

          <!-- login -->
          <div class="col-start-2 min-w-0 md:col-start-auto">
            <template v-if="acc">
              <div class="truncate font-medium">{{ acc.username }}</div>
              <div class="truncate text-sm text-muted-foreground">
                {{ lastSignIn(acc.last_login_at) }}
              </div>
            </template>
            <span v-else class="text-sm text-muted-foreground">No login</span>
          </div>

          <!-- status -->
          <div class="col-start-2 md:col-start-auto">
            <Badge v-if="!a.is_active" variant="secondary">Inactive</Badge>
            <Badge
              v-else-if="acc"
              variant="outline"
              :class="
                acc.status === 'ACTIVE'
                  ? 'border-regular/30 bg-regular/10 text-[#166534]'
                  : 'border-destructive/30 bg-destructive/10 text-destructive'
              "
            >
              <span
                :class="
                  cn(
                    'size-1.5 rounded-full',
                    acc.status === 'ACTIVE' ? 'bg-regular' : 'bg-destructive',
                  )
                "
              ></span>
              {{ acc.status === 'ACTIVE' ? 'Can sign in' : 'Login disabled' }}
            </Badge>
            <Badge v-else variant="outline" class="text-muted-foreground">
              Shift records only
            </Badge>
          </div>

          <!-- actions -->
          <div
            class="col-start-2 -ml-2 flex items-center gap-0.5 md:col-start-auto md:ml-0 md:justify-end"
          >
            <IconButton :icon="Pencil" label="Edit details" @click="openEdit(a)" />
            <IconButton
              :icon="KeyRound"
              :label="acc ? 'Change username or password' : 'Create a login'"
              @click="openLogin(a, acc)"
            />
            <IconButton
              v-if="acc"
              :icon="acc.status === 'ACTIVE' ? Lock : LockOpen"
              :label="acc.status === 'ACTIVE' ? 'Disable login' : 'Enable login'"
              :tone="acc.status === 'ACTIVE' ? 'danger' : 'good'"
              @click="setLoginStatus(a, acc, acc.status === 'ACTIVE' ? 'DISABLED' : 'ACTIVE')"
            />
            <span v-else class="inline-block size-9" aria-hidden="true"></span>
            <IconButton
              :icon="Power"
              :label="a.is_active ? 'Deactivate attendant' : 'Activate attendant'"
              :tone="a.is_active ? 'danger' : 'good'"
              @click="toggleActive(a)"
            />
          </div>
        </li>
      </ul>

      <!-- empty states -->
      <div
        v-if="!loading && !rows.length"
        class="flex flex-col items-center gap-3 px-6 py-12 text-center"
      >
        <span class="grid size-12 place-items-center rounded-full bg-muted text-muted-foreground">
          <Users class="size-6" />
        </span>
        <div>
          <p class="m-0 font-semibold">No pump attendants yet</p>
          <p class="m-0 text-muted-foreground">
            Create one so they can sign in and fill in shift reports.
          </p>
        </div>
        <Button size="lg" @click="openCreate">
          <UserPlus />
          New attendant
        </Button>
      </div>
      <p
        v-else-if="!loading && !visible.length"
        class="m-0 px-6 py-10 text-center text-muted-foreground"
      >
        No attendants match this search.
      </p>
    </Card>

    <!-- ============ create / edit dialog ============ -->
    <Dialog :open="person.open" @update:open="(v) => !person.busy && (person.open = v)">
      <DialogContent class="max-h-[92dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle class="font-display text-2xl">
            {{ person.editingId ? 'Edit attendant' : 'New attendant' }}
          </DialogTitle>
          <DialogDescription>
            {{
              person.editingId
                ? 'Change the name or contact details.'
                : 'Add the person, and optionally a login for the attendant site.'
            }}
          </DialogDescription>
        </DialogHeader>

        <form id="person-form" class="grid gap-4" novalidate @submit.prevent="savePerson">
          <div class="grid gap-1.5">
            <Label for="p-name">Full name</Label>
            <Input id="p-name" v-model="person.full_name" class="h-11" autocomplete="off" />
          </div>
          <div class="grid gap-4 sm:grid-cols-2">
            <div class="grid gap-1.5">
              <Label for="p-nick">
                Nickname <span class="font-normal text-muted-foreground">(optional)</span>
              </Label>
              <Input
                id="p-nick"
                v-model="person.nickname"
                class="h-11"
                placeholder="e.g. JEFF"
                autocomplete="off"
              />
            </div>
            <div class="grid gap-1.5">
              <Label for="p-contact">
                Contact no. <span class="font-normal text-muted-foreground">(optional)</span>
              </Label>
              <Input
                id="p-contact"
                v-model="person.contact_no"
                class="h-11"
                type="tel"
                autocomplete="off"
              />
            </div>
          </div>

          <template v-if="!person.editingId">
            <Label
              for="p-withlogin"
              class="flex cursor-pointer items-start gap-3 rounded-lg border bg-muted/50 p-3 font-normal"
            >
              <Checkbox id="p-withlogin" v-model="person.withLogin" class="mt-0.5 size-5" />
              <span class="grid gap-0.5">
                <span class="font-semibold">Give a login</span>
                <span class="text-sm text-muted-foreground">
                  Lets them sign in to fill in shift reports. Leave off for someone who only appears
                  on shortage / overage.
                </span>
              </span>
            </Label>

            <div v-if="person.withLogin" class="grid gap-4 sm:grid-cols-2">
              <div class="grid gap-1.5">
                <Label for="p-user">Username</Label>
                <Input
                  id="p-user"
                  v-model="person.username"
                  class="h-11"
                  autocomplete="off"
                  autocapitalize="none"
                  spellcheck="false"
                  placeholder="e.g. jeff"
                />
                <p class="text-xs text-muted-foreground">Letters, numbers, dot or underscore.</p>
              </div>
              <div class="grid gap-1.5">
                <Label for="p-pass">Password</Label>
                <div class="relative">
                  <Input
                    id="p-pass"
                    v-model="person.password"
                    :type="person.showPassword ? 'text' : 'password'"
                    class="h-11 pr-11"
                    autocomplete="new-password"
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    class="absolute top-1/2 right-1.5 -translate-y-1/2 text-muted-foreground"
                    :aria-label="person.showPassword ? 'Hide password' : 'Show password'"
                    @click="person.showPassword = !person.showPassword"
                  >
                    <EyeOff v-if="person.showPassword" />
                    <Eye v-else />
                  </Button>
                </div>
                <p class="text-xs text-muted-foreground">At least 6 characters.</p>
              </div>
            </div>
          </template>

          <p
            v-if="person.error"
            class="m-0 rounded-lg border border-destructive/25 bg-destructive/5 px-3 py-2 text-sm font-medium text-destructive"
            role="alert"
          >
            {{ person.error }}
          </p>
        </form>

        <DialogFooter>
          <Button variant="outline" size="lg" :disabled="person.busy" @click="person.open = false">
            Cancel
          </Button>
          <Button type="submit" form="person-form" size="lg" :disabled="person.busy">
            <component :is="person.editingId ? Check : UserPlus" />
            {{ person.busy ? 'Saving…' : person.editingId ? 'Save changes' : 'Create attendant' }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- ============ login dialog ============ -->
    <Dialog :open="login.open" @update:open="(v) => !login.busy && (login.open = v)">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle class="font-display text-2xl">
            {{ login.hasLogin ? 'Change login' : 'Create a login' }}
          </DialogTitle>
          <DialogDescription v-if="login.attendant">
            For {{ login.attendant.full_name }}
          </DialogDescription>
        </DialogHeader>

        <form id="login-form" class="grid gap-4" novalidate @submit.prevent="saveLogin">
          <div class="grid gap-1.5">
            <Label for="l-user">Username</Label>
            <Input
              id="l-user"
              v-model="login.username"
              class="h-11"
              autocomplete="off"
              autocapitalize="none"
              spellcheck="false"
            />
          </div>
          <div class="grid gap-1.5">
            <Label for="l-pass">{{ login.hasLogin ? 'New password' : 'Password' }}</Label>
            <div class="relative">
              <Input
                id="l-pass"
                v-model="login.password"
                :type="login.showPassword ? 'text' : 'password'"
                class="h-11 pr-11"
                autocomplete="new-password"
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                class="absolute top-1/2 right-1.5 -translate-y-1/2 text-muted-foreground"
                :aria-label="login.showPassword ? 'Hide password' : 'Show password'"
                @click="login.showPassword = !login.showPassword"
              >
                <EyeOff v-if="login.showPassword" />
                <Eye v-else />
              </Button>
            </div>
            <p class="text-xs text-muted-foreground">
              At least 6 characters.<template v-if="login.hasLogin">
                They will be signed out and must use the new password.</template
              >
            </p>
          </div>

          <p
            v-if="login.error"
            class="m-0 rounded-lg border border-destructive/25 bg-destructive/5 px-3 py-2 text-sm font-medium text-destructive"
            role="alert"
          >
            {{ login.error }}
          </p>
        </form>

        <DialogFooter>
          <Button variant="outline" size="lg" :disabled="login.busy" @click="login.open = false">
            Cancel
          </Button>
          <Button type="submit" form="login-form" size="lg" :disabled="login.busy">
            <KeyRound />
            {{ login.busy ? 'Saving…' : 'Save login' }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
