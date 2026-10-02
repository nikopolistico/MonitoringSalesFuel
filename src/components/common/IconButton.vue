<script setup lang="ts">
import type { Component } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { cn } from '@/lib/utils'

/**
 * Icon-only action: a shadcn ghost Button with a tooltip.
 * `label` is both the tooltip and the accessible name. Pass `to` to render a router link.
 */
// listeners/attrs (e.g. @click) go to the real <button>, not the renderless Tooltip root
defineOptions({ inheritAttrs: false })

const props = withDefaults(
  defineProps<{
    icon: Component
    label: string
    tone?: 'default' | 'danger' | 'good'
    disabled?: boolean
    to?: RouteLocationRaw
  }>(),
  { tone: 'default', disabled: false, to: undefined },
)

const toneClass = cn(
  'text-muted-foreground',
  props.tone === 'danger' && 'hover:bg-destructive/10 hover:text-destructive',
  props.tone === 'good' && 'hover:bg-good/10 hover:text-good',
)
</script>

<template>
  <Tooltip>
    <TooltipTrigger as-child>
      <Button
        v-if="props.to"
        v-bind="$attrs"
        as-child
        variant="ghost"
        size="icon-lg"
        :class="toneClass"
      >
        <RouterLink :to="props.to" :aria-label="label">
          <component :is="icon" class="size-[18px]" />
        </RouterLink>
      </Button>
      <Button
        v-else
        v-bind="$attrs"
        variant="ghost"
        size="icon-lg"
        :class="toneClass"
        :disabled="disabled"
        :aria-label="label"
      >
        <component :is="icon" class="size-[18px]" />
      </Button>
    </TooltipTrigger>
    <TooltipContent>{{ label }}</TooltipContent>
  </Tooltip>
</template>
