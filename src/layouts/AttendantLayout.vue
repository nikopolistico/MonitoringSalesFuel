<script setup lang="ts">
import AppHeader from '@/components/common/AppHeader.vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()

const links = [
  { to: '/', label: 'Reports', exact: true },
  { to: '/reports/new', label: 'New Shift' },
]
</script>

<template>
  <AppHeader home="/" :links="links" :name="auth.account?.full_name ?? ''" role="Pump attendant" />
  <main class="mx-auto max-w-7xl px-3 pt-4 pb-16 sm:px-5 sm:pt-5">
    <RouterView />
  </main>
</template>
