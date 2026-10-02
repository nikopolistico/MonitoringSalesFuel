<script setup lang="ts">
import { computed } from 'vue'
import type { Step } from '@/lib/steps'

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
  <div class="rounded-lg border border-line bg-[#f7f8f9] p-3.5" aria-live="polite">
    <div class="mb-3 flex items-center justify-between text-sm font-semibold">
      <span>{{ title }}</span>
      <span class="tabular-nums" :class="stopped ? 'text-bad' : 'text-muted'">{{ progress }}%</span>
    </div>
    <div
      class="h-2 overflow-hidden rounded-full bg-[#dfe3e7]"
      role="progressbar"
      :aria-valuenow="progress"
      aria-valuemin="0"
      aria-valuemax="100"
      :aria-label="title"
    >
      <div
        class="h-full rounded-full motion-safe:transition-[width] motion-safe:duration-300"
        :class="stopped ? 'bg-bad' : 'bg-[#16a34a]'"
        :style="{ width: `${Math.max(progress, 6)}%` }"
      ></div>
    </div>
    <ol class="mt-3 space-y-2 text-sm">
      <li v-for="s in steps" :key="s.label" class="flex items-center gap-2.5">
        <span
          class="grid h-5 w-5 shrink-0 place-items-center rounded-full text-[0.7rem] font-bold text-white"
          :class="{
            'bg-[#16a34a]': s.state === 'done',
            'bg-bad': s.state === 'failed',
            'bg-[#2b3138]': s.state === 'active',
            'border-2 border-[#c3c8cd] bg-white': s.state === 'waiting',
          }"
          aria-hidden="true"
        >
          <template v-if="s.state === 'done'">✓</template>
          <template v-else-if="s.state === 'failed'">!</template>
          <svg
            v-else-if="s.state === 'active'"
            class="h-3 w-3 motion-safe:animate-spin"
            viewBox="0 0 24 24"
            fill="none"
          >
            <path
              d="M21 12a9 9 0 0 0-9-9"
              stroke="currentColor"
              stroke-width="4"
              stroke-linecap="round"
            />
          </svg>
        </span>
        <span
          :class="{
            'text-muted': s.state === 'waiting',
            'font-semibold': s.state === 'active',
            'font-semibold text-bad': s.state === 'failed',
          }"
        >
          {{ s.label }}
        </span>
      </li>
    </ol>
  </div>
</template>
