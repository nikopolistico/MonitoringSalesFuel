<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  CircleAlert,
  Eye,
  EyeOff,
  Fuel,
  LoaderCircle,
  LockKeyhole,
  LogIn,
  TriangleAlert,
  UserRound,
} from '@lucide/vue'
import ProgressSteps from '@/components/common/ProgressSteps.vue'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
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
          <li class="rounded bg-premium px-2 py-1.5 lg:py-2.5">Premium</li>
          <li class="rounded bg-regular px-2 py-1.5 lg:py-2.5">Regular</li>
          <li class="rounded bg-diesel px-2 py-1.5 text-ink lg:py-2.5">Diesel</li>
        </ul>
      </div>

      <p class="hidden px-12 pb-6 font-display text-base text-white/55 lg:block">
        Daily sales monitoring
      </p>
    </section>

    <!-- ================= sign-in card ================= -->
    <section class="flex items-start justify-center px-4 py-6 sm:py-10 lg:items-center lg:px-12">
      <Card class="w-full max-w-[420px] gap-5 py-7 shadow-[0_18px_40px_-24px_rgba(43,49,56,0.45)]">
        <CardHeader class="flex flex-row items-center gap-3 px-6 sm:px-8">
          <span
            class="grid size-11 shrink-0 place-items-center rounded-lg bg-primary text-primary-foreground"
            aria-hidden="true"
          >
            <Fuel class="size-6" />
          </span>
          <div>
            <CardTitle>
              <h1 class="m-0 font-display text-[2rem] leading-none font-bold">Sign in</h1>
            </CardTitle>
            <CardDescription class="mt-1 text-[0.95rem]">
              Pump attendants and the admin sign in here.
            </CardDescription>
          </div>
        </CardHeader>

        <CardContent class="px-6 sm:px-8">
          <form class="flex flex-col gap-4" novalidate @submit.prevent="submit">
            <div class="grid gap-1.5">
              <Label for="login-username" class="text-[0.95rem] font-semibold">Username</Label>
              <div class="relative">
                <UserRound
                  class="pointer-events-none absolute top-1/2 left-3 size-[18px] -translate-y-1/2 text-muted-foreground"
                />
                <Input
                  id="login-username"
                  v-model="username"
                  :disabled="busy"
                  autocomplete="username"
                  autocapitalize="none"
                  spellcheck="false"
                  autofocus
                  class="h-12 pl-10 text-[1.05rem] font-medium md:text-[1.05rem]"
                />
              </div>
            </div>

            <div class="grid gap-1.5">
              <Label for="login-password" class="text-[0.95rem] font-semibold">Password</Label>
              <div class="relative">
                <LockKeyhole
                  class="pointer-events-none absolute top-1/2 left-3 size-[18px] -translate-y-1/2 text-muted-foreground"
                />
                <Input
                  id="login-password"
                  v-model="password"
                  :type="showPassword ? 'text' : 'password'"
                  :disabled="busy"
                  autocomplete="current-password"
                  class="h-12 pr-12 pl-10 text-[1.05rem] font-medium md:text-[1.05rem]"
                  @keyup="onKey"
                  @keydown="onKey"
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  class="absolute top-1/2 right-2 -translate-y-1/2 text-muted-foreground"
                  :aria-label="showPassword ? 'Hide password' : 'Show password'"
                  :aria-pressed="showPassword"
                  @click="showPassword = !showPassword"
                >
                  <EyeOff v-if="showPassword" />
                  <Eye v-else />
                </Button>
              </div>
              <p
                v-if="capsLock"
                class="flex items-center gap-1.5 text-sm font-medium text-[#a16207]"
              >
                <TriangleAlert class="size-4" /> Caps Lock is on.
              </p>
            </div>

            <Button
              type="submit"
              :disabled="busy || !username.trim() || !password"
              class="mt-1 h-12 font-display text-[1.35rem] font-bold"
            >
              <LoaderCircle v-if="busy" class="size-5 motion-safe:animate-spin" />
              <LogIn v-else class="size-5" />
              {{ busy ? 'Signing in…' : 'Sign in' }}
            </Button>

            <!-- sign-in progress -->
            <ProgressSteps
              v-if="started"
              :steps="steps"
              :titles="{ running: 'Signing you in', done: 'Signed in', failed: 'Sign in stopped' }"
            />

            <p
              v-if="error"
              class="m-0 flex items-start gap-2 rounded-lg border border-destructive/25 bg-destructive/5 px-3.5 py-2.5 font-medium text-destructive"
              role="alert"
            >
              <CircleAlert class="mt-0.5 size-4 shrink-0" />
              {{ error }}
            </p>
          </form>
        </CardContent>

        <CardFooter class="border-t px-6 pt-5 sm:px-8">
          <p class="m-0 text-[0.92rem] text-muted-foreground">
            No account yet? Ask the admin to create one for you.
          </p>
        </CardFooter>
      </Card>
    </section>
  </div>
</template>

<style scoped>
/* pump LCD: pale grey-green glass with dark digits */
.lcd {
  background: var(--lcd);
  color: var(--lcd-ink);
  box-shadow:
    inset 0 2px 0 rgba(0, 0, 0, 0.18),
    0 0 0 6px #1d2228;
}
</style>
