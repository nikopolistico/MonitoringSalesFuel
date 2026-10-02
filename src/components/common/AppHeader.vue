<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Fuel, LogOut, Menu } from '@lucide/vue'
import ProgressSteps from '@/components/common/ProgressSteps.vue'
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { resetSteps, runStep, type Step } from '@/lib/steps'
import { cn } from '@/lib/utils'
import { useAuthStore } from '@/stores/auth'

const props = defineProps<{
  home: string
  links: { to: string; label: string; exact?: boolean }[]
  name: string
  role: string
  admin?: boolean
}>()

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const menuOpen = ref(false)
watch(
  () => route.fullPath,
  () => (menuOpen.value = false),
)

function isActive(l: { to: string; exact?: boolean }) {
  return l.exact ? route.path === l.to : route.path.startsWith(l.to)
}

const initials = computed(() =>
  props.name
    .split(/\s+/)
    .filter(Boolean)
    .map((p) => p[0])
    .slice(0, 2)
    .join('')
    .toUpperCase(),
)

/* ---------- sign-out: confirm, then show progress ---------- */
const confirmOpen = ref(false)
const signingOut = ref(false)
const steps = reactive<Step[]>([
  { label: 'Ending your session on the server', state: 'waiting' },
  { label: 'Removing your login from this device', state: 'waiting' },
  { label: 'Returning to the sign-in page', state: 'waiting' },
])
const started = computed(() => steps.some((s) => s.state !== 'waiting'))

function askLogout() {
  menuOpen.value = false
  resetSteps(steps)
  confirmOpen.value = true
}

function onOpenChange(v: boolean) {
  // keep the dialog up while signing out
  if (!v && (signingOut.value || started.value)) return
  confirmOpen.value = v
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
    :class="
      cn(
        'no-print sticky top-0 z-30 text-white shadow-[0_1px_0_rgba(0,0,0,0.08)]',
        admin ? 'bg-admin' : 'bg-brand',
      )
    "
  >
    <div class="mx-auto flex h-14 max-w-7xl items-center gap-3 px-3 sm:px-5">
      <RouterLink
        :to="home"
        class="flex items-center gap-2.5 rounded-md outline-none focus-visible:ring-2 focus-visible:ring-white/60"
      >
        <span
          :class="
            cn('grid size-8 place-items-center rounded-md', admin ? 'bg-brand' : 'bg-white/15')
          "
        >
          <Fuel class="size-[18px]" />
        </span>
        <span class="font-display text-xl leading-none font-bold tracking-wide">
          RCJA Powerfuel
        </span>
        <span
          v-if="admin"
          class="rounded bg-highlight px-1.5 py-0.5 text-[0.65rem] font-extrabold text-ink"
        >
          ADMIN
        </span>
      </RouterLink>

      <!-- tablet & desktop -->
      <nav class="ml-6 hidden flex-1 items-center gap-1 md:flex" aria-label="Main">
        <RouterLink
          v-for="l in links"
          :key="l.to"
          :to="l.to"
          :class="
            cn(
              'rounded-md px-3 py-1.5 text-[0.95rem] font-medium text-white/80 transition-colors hover:bg-white/10 hover:text-white',
              isActive(l) && 'bg-white/15 text-white',
            )
          "
          :aria-current="isActive(l) ? 'page' : undefined"
        >
          {{ l.label }}
        </RouterLink>
      </nav>

      <div class="ml-auto hidden items-center gap-3 md:flex">
        <div class="flex items-center gap-2.5">
          <Avatar class="size-8 border border-white/25">
            <AvatarFallback class="bg-white/15 text-xs font-bold text-white">
              {{ initials }}
            </AvatarFallback>
          </Avatar>
          <div class="text-sm leading-tight">
            <div class="font-semibold">{{ name }}</div>
            <div class="text-xs text-white/70">{{ role }}</div>
          </div>
        </div>
        <Button
          variant="ghost"
          size="lg"
          class="text-white hover:bg-white/10 hover:text-white"
          @click="askLogout"
        >
          <LogOut />
          Sign out
        </Button>
      </div>

      <!-- phones -->
      <Sheet v-model:open="menuOpen">
        <SheetTrigger as-child>
          <Button
            variant="ghost"
            size="icon-lg"
            class="ml-auto text-white hover:bg-white/10 hover:text-white md:hidden"
            aria-label="Open menu"
          >
            <Menu class="size-5" />
          </Button>
        </SheetTrigger>
        <SheetContent side="right" class="w-[86vw] max-w-xs gap-0 p-0">
          <SheetHeader class="border-b p-4">
            <div class="flex items-center gap-3">
              <Avatar class="size-10">
                <AvatarFallback class="bg-admin font-bold text-white">
                  {{ initials }}
                </AvatarFallback>
              </Avatar>
              <div>
                <SheetTitle class="text-base">{{ name }}</SheetTitle>
                <SheetDescription>{{ role }}</SheetDescription>
              </div>
            </div>
          </SheetHeader>
          <nav class="flex flex-col gap-1 p-3" aria-label="Main">
            <RouterLink
              v-for="l in links"
              :key="l.to"
              :to="l.to"
              :class="
                cn(
                  'rounded-lg px-3 py-3 text-base font-medium hover:bg-muted',
                  isActive(l) && 'bg-primary/10 text-primary',
                )
              "
              :aria-current="isActive(l) ? 'page' : undefined"
            >
              {{ l.label }}
            </RouterLink>
          </nav>
          <div class="mt-auto border-t p-3">
            <Button variant="outline" size="lg" class="h-11 w-full" @click="askLogout">
              <LogOut />
              Sign out
            </Button>
          </div>
        </SheetContent>
      </Sheet>
    </div>
  </header>

  <!-- sign-out confirmation -->
  <AlertDialog :open="confirmOpen" @update:open="onOpenChange">
    <AlertDialogContent class="sm:max-w-md">
      <AlertDialogHeader>
        <AlertDialogTitle class="font-display text-2xl">
          {{ started ? 'Signing out' : 'Sign out?' }}
        </AlertDialogTitle>
        <AlertDialogDescription v-if="!started">
          You're signed in as <b class="text-foreground">{{ name }}</b
          >.
          {{
            admin
              ? 'You will need your admin password to open the dashboard again.'
              : 'Changes you have not saved on a shift report will be lost.'
          }}
        </AlertDialogDescription>
        <AlertDialogDescription v-else class="sr-only">Sign-out progress</AlertDialogDescription>
      </AlertDialogHeader>

      <ProgressSteps
        v-if="started"
        :steps="steps"
        :titles="{ running: 'Signing you out', done: 'Signed out', failed: 'Signed out' }"
        continue-on-fail
      />

      <AlertDialogFooter v-else>
        <AlertDialogCancel size="lg">Stay signed in</AlertDialogCancel>
        <Button size="lg" :disabled="signingOut" @click="confirmLogout">
          <LogOut />
          Sign out
        </Button>
      </AlertDialogFooter>
    </AlertDialogContent>
  </AlertDialog>
</template>
