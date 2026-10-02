<script setup lang="ts">
import ShiftReportSheet from '@/components/reports/ShiftReportSheet.vue'

defineProps<{ id: string }>()
</script>

<template>
  <ShiftReportSheet :id="id" area="admin" />
</template>
