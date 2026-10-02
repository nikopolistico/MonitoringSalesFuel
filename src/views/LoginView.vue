<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import ProgressSteps from '@/components/ProgressSteps.vue'
import { resetSteps, runStep, type Step } from '@/lib/steps'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const username = ref('')
const password = ref('')
const showPassword = ref(false)
const capsLock = ref(false)
const error = ref('')
const busy = ref(false)

/* ------------------------------------------------ sign-in progress */

const steps = reactive<Step[]>([
  { label: 'Checking your username and password', state: 'waiting' },
  { label: 'Starting a secure session', state: 'waiting' },
  { label: 'Opening your page', state: 'waiting' },
])
const started = computed(() => steps.some((s) => s.state !== 'waiting'))
const step = <T,>(i: number, work: () => Promise<T>) => runStep(steps, i, work)

async function submit() {
  if (busy.value) return
  error.value = ''
  busy.value = true
  resetSteps(steps)
  steps[2]!.label = 'Opening your page'
  try {
    await step(0, () => auth.signIn(username.value.trim(), password.value))
    await step(1, () => auth.verifySession())

    const isAdmin = auth.isAdmin
    steps[2]!.label = isAdmin ? 'Opening the admin dashboard' : 'Opening your shift reports'
    const home = isAdmin ? '/admin' : '/'
    const next = typeof route.query.next === 'string' ? route.query.next : ''
    // only follow ?next= when it belongs to this user's area
    const target = next && next.startsWith('/admin') === isAdmin ? next : home
    await step(2, async () => {
      const failure = await router.replace(target)
      if (failure) throw new Error('Could not open the page. Please try again.')
    })
  } catch (e) {
    error.value = e instanceof Error ? e.message : String((e as { message?: string })?.message ?? e)
    busy.value = false
  }
}

function onKey(e: KeyboardEvent) {
  capsLock.value = e.getModifierState?.('CapsLock') ?? false
}

/* ------------------------------------------------ live clock */

const now = ref(new Date())
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  timer = setInterval(() => (now.value = new Date()), 1000)
})
onBeforeUnmount(() => clearInterval(timer))

const clockTime = computed(() =>
  now.value
    .toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: true })
    .replace(/\s?[AP]M$/, ''),
)
const clockPeriod = computed(() => (now.value.getHours() < 12 ? 'AM' : 'PM'))
const today = computed(() =>
  now.value.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }),
)
</script>

<template>
  <div
    class="grid min-h-dvh bg-[#e4e6e8] font-body text-ink lg:grid-cols-[minmax(360px,0.9fr)_1.1fr]"
  >
    <!-- ================= pump face ================= -->
    <section class="flex flex-col bg-[#2b3138] text-white" aria-label="RCJA Powerfuel">
      <div
        class="border-b-[6px] border-[#9e0c24] bg-brand px-5 pt-5 pb-4 lg:border-b-[10px] lg:px-12 lg:pt-10 lg:pb-8"
      >
        <p class="font-display text-[2.1rem] leading-[0.95] font-bold lg:text-6xl">
          RCJA Powerfuel
        </p>
        <p class="mt-1 font-display text-base font-medium opacity-85 lg:text-xl">
          Gasoline Station
        </p>
      </div>

      <div class="flex flex-1 flex-col justify-center gap-3 px-5 py-4 lg:gap-7 lg:px-12 lg:py-10">
        <div
          class="lcd rounded-md px-4 py-3 lg:px-6 lg:py-5"
          role="timer"
          :aria-label="`${clockTime} ${clockPeriod}, ${today}`"
        >
          <div class="grid grid-cols-[3.2rem_1fr] items-baseline gap-3 lg:grid-cols-[4.5rem_1fr]">
            <span class="text-sm font-semibold opacity-70">Time</span>
            <span
              class="text-right font-display text-[2.6rem] leading-none font-semibold tabular-nums lg:text-[5rem]"
            >
              {{ clockTime }}<small class="ml-1.5 text-[0.32em] font-bold">{{ clockPeriod }}</small>
            </span>
          </div>
          <div
            class="mt-2.5 grid grid-cols-[3.2rem_1fr] items-baseline gap-3 border-t border-[#1e2a1e]/20 pt-2.5 lg:grid-cols-[4.5rem_1fr]"
          >
            <span class="text-sm font-semibold opacity-70">Date</span>
            <span class="text-right font-display text-base font-medium lg:text-[1.35rem]">{{
              today
            }}</span>
          </div>
        </div>

        <ul
          class="grid grid-cols-3 gap-2.5 text-center text-sm font-semibold lg:text-[0.95rem]"
          aria-label="Fuel types"
        >
          <li class="rounded bg-[#e11d2a] px-2 py-1.5 lg:py-2.5">Premium</li>
          <li class="rounded bg-[#16a34a] px-2 py-1.5 lg:py-2.5">Regular</li>
          <li class="rounded bg-[#facc15] px-2 py-1.5 text-ink lg:py-2.5">Diesel</li>
        </ul>
      </div>

      <p class="hidden px-12 pb-6 font-display text-base text-white/55 lg:block">
        Daily sales monitoring
      </p>
    </section>

    <!-- ================= sign-in card ================= -->
    <section class="flex items-start justify-center px-4 py-6 sm:py-10 lg:items-center lg:px-12">
      <div
        class="w-full max-w-[420px] rounded-xl border border-black/10 bg-white p-6 shadow-[0_18px_40px_-24px_rgba(43,49,56,0.45)] sm:p-8"
      >
        <div class="mb-6 flex items-center gap-3">
          <span
            class="grid h-11 w-11 shrink-0 place-items-center rounded-lg bg-brand text-white"
            aria-hidden="true"
          >
            <!-- fuel nozzle -->
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M4 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16" />
              <path d="M3 21h12M7 8h4" />
              <path d="M14 10h2a2 2 0 0 1 2 2v4a1.5 1.5 0 0 0 3 0V8.5L18 6" />
            </svg>
          </span>
          <div>
            <h1 class="m-0 font-display text-[2rem] leading-none font-bold">Sign in</h1>
            <p class="mt-1 text-[0.95rem] text-muted">
              Pump attendants and the admin sign in here.
            </p>
          </div>
        </div>

        <form class="flex flex-col gap-4" novalidate @submit.prevent="submit">
          <!-- username -->
          <label class="flex flex-col gap-1.5">
            <span class="text-[0.95rem] font-semibold">Username</span>
            <span class="relative block">
              <svg
                class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted"
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                aria-hidden="true"
              >
                <circle cx="12" cy="8" r="4" />
                <path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6" />
              </svg>
              <input
                v-model="username"
                :disabled="busy"
                autocomplete="username"
                autocapitalize="none"
                spellcheck="false"
                required
                autofocus
                class="h-12 rounded-lg border-2 border-[#cdd2d7] bg-white pr-3 pl-10 text-[1.05rem] font-medium focus:border-[#2b3138] focus:ring-3 focus:ring-brand/25 focus:outline-none disabled:bg-slate-50"
              />
            </span>
          </label>

          <!-- password -->
          <label class="flex flex-col gap-1.5">
            <span class="text-[0.95rem] font-semibold">Password</span>
            <span class="relative block">
              <svg
                class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted"
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                aria-hidden="true"
              >
                <rect x="4" y="10" width="16" height="11" rx="2" />
                <path d="M8 10V7a4 4 0 0 1 8 0v3" />
              </svg>
              <input
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                :disabled="busy"
                autocomplete="current-password"
                required
                class="h-12 rounded-lg border-2 border-[#cdd2d7] bg-white pr-20 pl-10 text-[1.05rem] font-medium focus:border-[#2b3138] focus:ring-3 focus:ring-brand/25 focus:outline-none disabled:bg-slate-50"
                @keyup="onKey"
                @keydown="onKey"
              />
              <button
                type="button"
                class="absolute top-1/2 right-2 -translate-y-1/2 rounded-md px-2.5 py-1.5 text-sm font-semibold text-muted hover:bg-slate-100 hover:text-ink focus-visible:outline-2 focus-visible:outline-brand"
                :aria-pressed="showPassword"
                @click="showPassword = !showPassword"
              >
                {{ showPassword ? 'Hide' : 'Show' }}
              </button>
            </span>
            <span v-if="capsLock" class="text-sm font-medium text-[#a16207]">Caps Lock is on.</span>
          </label>

          <button
            type="submit"
            :disabled="busy || !username.trim() || !password"
            class="mt-1 inline-flex h-12 items-center justify-center gap-2 rounded-lg bg-brand font-display text-[1.35rem] font-bold text-white hover:bg-brand-dark focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-[#2b3138] disabled:cursor-not-allowed disabled:opacity-60"
          >
            <svg
              v-if="busy"
              class="h-5 w-5 motion-safe:animate-spin"
              viewBox="0 0 24 24"
              fill="none"
              aria-hidden="true"
            >
              <circle
                cx="12"
                cy="12"
                r="9"
                stroke="currentColor"
                stroke-opacity="0.3"
                stroke-width="3"
              />
              <path
                d="M21 12a9 9 0 0 0-9-9"
                stroke="currentColor"
                stroke-width="3"
                stroke-linecap="round"
              />
            </svg>
            {{ busy ? 'Signing in…' : 'Sign in' }}
          </button>

          <!-- sign-in progress -->
          <ProgressSteps
            v-if="started"
            :steps="steps"
            :titles="{ running: 'Signing you in', done: 'Signed in', failed: 'Sign in stopped' }"
          />

          <p
            v-if="error"
            class="m-0 rounded-lg border-l-4 border-brand bg-[#fdf2f4] px-3.5 py-2.5 font-medium text-[#8a0b20]"
            role="alert"
          >
            {{ error }}
          </p>

          <p class="m-0 text-[0.92rem] text-muted">
            No account yet? Ask the admin to create one for you.
          </p>
        </form>
      </div>
    </section>
  </div>
</template>

<style scoped>
/* pump LCD: pale grey-green glass with dark digits */
.lcd {
  background: #c9d3c0;
  color: #1e2a1e;
  box-shadow:
    inset 0 2px 0 rgba(0, 0, 0, 0.18),
    0 0 0 6px #1d2228;
}
</style>
