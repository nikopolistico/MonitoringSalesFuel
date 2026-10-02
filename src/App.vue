<script setup lang="ts">
import 'vue-sonner/style.css'
import { Toaster } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import { isConfigured } from '@/lib/supabase'
</script>

<template>
  <TooltipProvider :delay-duration="250">
    <div v-if="!isConfigured" class="config-warning">
      Supabase is not configured. Copy <code>.env.example</code> to <code>.env</code>, fill in your
      project URL and anon key, then restart <code>npm run dev</code>.
    </div>
    <RouterView />
    <Toaster position="top-center" rich-colors close-button />
  </TooltipProvider>
</template>
