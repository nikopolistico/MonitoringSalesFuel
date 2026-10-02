<script setup lang="ts">
import ShiftReportSheet from '@/components/reports/ShiftReportSheet.vue'

/** New sheet when there is no id, otherwise the saved sheet. */
defineProps<{ id?: string }>()
</script>

<template>
  <ShiftReportSheet :id="id" area="attendant" />
</template>
