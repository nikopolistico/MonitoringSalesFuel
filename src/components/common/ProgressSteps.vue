<script setup lang="ts">
import { computed } from 'vue'
import { Check, LoaderCircle, X } from '@lucide/vue'
import { Progress } from '@/components/ui/progress'
import type { Step } from '@/lib/steps'
import { cn } from '@/lib/utils'

const props = defineProps<{
  steps: Step[]
  /** Heading while running, after success, and after a failure. */
  titles: { running: string; done: string; failed: string }
  /** When true, a failed step does not stop the process (only colors that step red). */
  continueOnFail?: boolean
}>()

const failed = computed(() => props.steps.some((s) => s.state === 'failed'))
const stopped = computed(() => failed.value && !props.continueOnFail)
const progress = computed(() => {
  const finished = props.steps.filter((s) => s.state === 'done' || s.state === 'failed').length
  const active = props.steps.some((s) => s.state === 'active') ? 0.5 : 0
  return Math.round(((finished + active) / props.steps.length) * 100)
})
const title = computed(() =>
  stopped.value
    ? props.titles.failed
    : progress.value === 100
      ? props.titles.done
      : props.titles.running,
)
</script>

<template>
  <div class="rounded-lg border bg-muted/60 p-3.5" aria-live="polite">
    <div class="mb-2.5 flex items-center justify-between text-sm font-semibold">
      <span>{{ title }}</span>
      <span class="tabular-nums" :class="stopped ? 'text-destructive' : 'text-muted-foreground'">
        {{ progress }}%
      </span>
    </div>
    <Progress
      :model-value="Math.max(progress, 4)"
      :aria-label="title"
      :class="cn('h-2', stopped ? '[&>*]:bg-destructive' : '[&>*]:bg-regular')"
    />
    <ol class="mt-3 space-y-2 text-sm">
      <li v-for="s in steps" :key="s.label" class="flex items-center gap-2.5">
        <span
          :class="
            cn(
              'grid size-5 shrink-0 place-items-center rounded-full text-white',
              s.state === 'done' && 'bg-regular',
              s.state === 'failed' && 'bg-destructive',
              s.state === 'active' && 'bg-admin',
              s.state === 'waiting' && 'border-2 border-input bg-card',
            )
          "
          aria-hidden="true"
        >
          <Check v-if="s.state === 'done'" class="size-3" :stroke-width="3" />
          <X v-else-if="s.state === 'failed'" class="size-3" :stroke-width="3" />
          <LoaderCircle v-else-if="s.state === 'active'" class="size-3 motion-safe:animate-spin" />
        </span>
        <span
          :class="
            cn(
              s.state === 'waiting' && 'text-muted-foreground',
              s.state === 'active' && 'font-semibold',
              s.state === 'failed' && 'font-semibold text-destructive',
            )
          "
        >
          {{ s.label }}
        </span>
      </li>
    </ol>
  </div>
</template>
