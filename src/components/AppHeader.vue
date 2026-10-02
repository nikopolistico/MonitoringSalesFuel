<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import ProgressSteps from '@/components/ProgressSteps.vue'
import { resetSteps, runStep, type Step } from '@/lib/steps'
import { useAuthStore } from '@/stores/auth'

defineProps<{
  home: string
  links: { to: string; label: string; exact?: boolean }[]
  name: string
  role: string
  admin?: boolean
}>()

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const open = ref(false)
// close the phone menu after navigating
watch(
  () => route.fullPath,
  () => (open.value = false),
)

/* ---------- sign-out: confirm, then show progress ---------- */
const confirmDialog = ref<HTMLDialogElement | null>(null)
const signingOut = ref(false)
const steps = reactive<Step[]>([
  { label: 'Ending your session on the server', state: 'waiting' },
  { label: 'Removing your login from this device', state: 'waiting' },
  { label: 'Returning to the sign-in page', state: 'waiting' },
])
const started = computed(() => steps.some((s) => s.state !== 'waiting'))

function askLogout() {
  open.value = false
  resetSteps(steps)
  confirmDialog.value?.showModal()
}

async function confirmLogout() {
  signingOut.value = true
  // a server failure (e.g. no internet) must not leave anyone signed in on this device
  await runStep(steps, 0, () => auth.endServerSession()).catch(() => {})
  await runStep(steps, 1, async () => auth.clearLocalSession())
  await runStep(steps, 2, async () => {
    await router.replace({ name: 'login' })
  }).catch(() => (window.location.href = '/login'))
  signingOut.value = false
}
</script>

<template>
  <header
    class="no-print sticky top-0 z-20 text-white shadow-sm"
    :class="admin ? 'bg-admin' : 'bg-brand'"
  >
    <div class="mx-auto flex max-w-7xl items-center gap-3 px-3 py-2.5 sm:px-5">
      <RouterLink :to="home" class="flex items-center gap-2 text-lg tracking-wide no-underline">
        <span class="text-xl">⛽</span>
        <span>RCJA <b>Powerfuel</b><span v-if="admin" class="admin-tag">ADMIN</span></span>
      </RouterLink>

      <!-- tablet & desktop nav -->
      <nav class="ml-4 hidden flex-1 gap-1 md:flex">
        <RouterLink
          v-for="l in links"
          :key="l.to"
          :to="l.to"
          class="rounded-md px-3 py-1.5 no-underline opacity-85 hover:bg-white/10 hover:opacity-100"
          :exact-active-class="l.exact ? '!bg-white/20 !opacity-100 font-semibold' : ''"
          :active-class="l.exact ? '' : '!bg-white/20 !opacity-100 font-semibold'"
        >
          {{ l.label }}
        </RouterLink>
      </nav>

      <div class="ml-auto hidden items-center gap-3 md:flex">
        <span class="flex flex-col items-end text-sm leading-tight">
          {{ name }}
          <small class="text-xs opacity-80">{{ role }}</small>
        </span>
        <button
          class="rounded-md border border-white/50 px-3 py-1.5 text-sm hover:bg-white/10"
          @click="askLogout"
        >
          Sign out
        </button>
      </div>

      <!-- phone menu button -->
      <button
        class="ml-auto inline-flex h-10 w-10 items-center justify-center rounded-md hover:bg-white/10 md:hidden"
        :aria-expanded="open"
        aria-label="Menu"
        @click="open = !open"
      >
        <svg
          width="22"
          height="22"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
        >
          <path v-if="open" d="M6 6l12 12M18 6L6 18" />
          <path v-else d="M4 7h16M4 12h16M4 17h16" />
        </svg>
      </button>
    </div>

    <!-- phone menu -->
    <div v-if="open" class="border-t border-white/15 px-3 pb-3 md:hidden">
      <nav class="flex flex-col py-2">
        <RouterLink
          v-for="l in links"
          :key="l.to"
          :to="l.to"
          class="rounded-md px-3 py-3 text-base no-underline hover:bg-white/10"
          :exact-active-class="l.exact ? 'bg-white/20 font-semibold' : ''"
          :active-class="l.exact ? '' : 'bg-white/20 font-semibold'"
        >
          {{ l.label }}
        </RouterLink>
      </nav>
      <div class="flex items-center justify-between border-t border-white/15 px-3 pt-3">
        <span class="text-sm leading-tight">
          {{ name }}<br />
          <small class="text-xs opacity-80">{{ role }}</small>
        </span>
        <button class="rounded-md border border-white/50 px-4 py-2 text-sm" @click="askLogout">
          Sign out
        </button>
      </div>
    </div>
  </header>

  <!-- sign-out confirmation (native dialog: traps focus, Esc cancels) -->
  <dialog
    ref="confirmDialog"
    class="no-print m-auto w-[min(92vw,400px)] rounded-xl border-0 bg-white p-0 text-ink shadow-2xl backdrop:bg-[#1d2329]/55"
    aria-labelledby="signout-title"
    @cancel="(signingOut || started) && $event.preventDefault()"
  >
    <div class="p-6">
      <div class="flex items-start gap-3">
        <span
          class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#fdf2f4] text-brand"
          aria-hidden="true"
        >
          <svg
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
            <path d="M16 17l5-5-5-5M21 12H9" />
          </svg>
        </span>
        <div>
          <h2 id="signout-title" class="text-lg font-bold">
            {{ started ? 'Signing out' : 'Sign out?' }}
          </h2>
          <p v-if="!started" class="mt-1 text-[0.95rem] text-muted">
            You're signed in as <b class="text-ink">{{ name }}</b
            >.
            {{
              admin
                ? 'You will need your admin password to open the dashboard again.'
                : 'Changes you have not saved on a shift report will be lost.'
            }}
          </p>
        </div>
      </div>
      <ProgressSteps
        v-if="started"
        class="mt-5"
        :steps="steps"
        :titles="{ running: 'Signing you out', done: 'Signed out', failed: 'Signed out' }"
        continue-on-fail
      />
      <div v-else class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <button
          type="button"
          class="btn py-2.5 sm:py-2"
          :disabled="signingOut"
          autofocus
          @click="confirmDialog?.close()"
        >
          Stay signed in
        </button>
        <button
          type="button"
          class="btn primary py-2.5 sm:py-2"
          :disabled="signingOut"
          @click="confirmLogout"
        >
          {{ signingOut ? 'Signing out…' : 'Sign out' }}
        </button>
      </div>
    </div>
  </dialog>
</template>
