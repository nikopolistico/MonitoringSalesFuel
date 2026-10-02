<script setup lang="ts">
import { isConfigured } from '@/lib/supabase'
</script>

<template>
  <div v-if="!isConfigured" class="config-warning">
    Supabase is not configured. Copy <code>.env.example</code> to <code>.env</code>, fill in your
    project URL and anon key, then restart <code>npm run dev</code>.
  </div>
  <RouterView />
</template>
