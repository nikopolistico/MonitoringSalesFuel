import type { RouteRecordRaw } from 'vue-router'

/** Admin dashboard: overview, reports, attendants and fuel types. */
export const adminRoutes: RouteRecordRaw = {
  path: '/admin',
  component: () => import('@/layouts/AdminLayout.vue'),
  meta: { area: 'ADMIN' },
  children: [
    {
      path: '',
      name: 'admin-dashboard',
      component: () => import('@/views/admin/DashboardView.vue'),
    },
    {
      path: 'reports',
      name: 'admin-reports',
      component: () => import('@/views/admin/ReportsView.vue'),
    },
    {
      path: 'reports/:id',
      name: 'admin-report',
      component: () => import('@/views/admin/ShiftReportView.vue'),
      props: true,
    },
    {
      path: 'attendants',
      name: 'admin-attendants',
      component: () => import('@/views/admin/AttendantsView.vue'),
    },
    {
      path: 'fuel-types',
      name: 'admin-fuel-types',
      component: () => import('@/views/admin/FuelTypesView.vue'),
    },
  ],
}
