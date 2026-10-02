import type { RouteRecordRaw } from 'vue-router'

/** Pump attendant site: shift reports only. */
export const attendantRoutes: RouteRecordRaw = {
  path: '/',
  component: () => import('@/layouts/AttendantLayout.vue'),
  meta: { area: 'ATTENDANT' },
  children: [
    { path: '', name: 'reports', component: () => import('@/views/attendant/ReportsView.vue') },
    {
      path: 'reports/new',
      name: 'report-new',
      component: () => import('@/views/attendant/ShiftReportView.vue'),
    },
    {
      path: 'reports/:id',
      name: 'report-edit',
      component: () => import('@/views/attendant/ShiftReportView.vue'),
      props: true,
    },
  ],
}
