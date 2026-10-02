<script setup lang="ts">
import AppHeader from '@/components/AppHeader.vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()

const links = [
  { to: '/admin', label: 'Dashboard', exact: true },
  { to: '/admin/reports', label: 'Reports' },
  { to: '/admin/attendants', label: 'Pump Attendants' },
  { to: '/admin/fuel-types', label: 'Fuel Types' },
]
</script>

<template>
  <AppHeader
    home="/admin"
    :links="links"
    :name="auth.account?.username ?? ''"
    role="Administrator"
    admin
  />
  <main class="mx-auto max-w-7xl px-3 pt-4 pb-16 sm:px-5 sm:pt-5">
    <RouterView />
  </main>
</template>
