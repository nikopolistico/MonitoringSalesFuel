import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

declare module 'vue-router' {
  interface RouteMeta {
    /** Who may open the page. Pages without it are the login pages. */
    area?: 'ATTENDANT' | 'ADMIN'
  }
}

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    /* one sign-in page for everyone; the role decides where they land */
    { path: '/login', name: 'login', component: () => import('@/views/LoginView.vue') },

    /* ---------------- pump attendant site ---------------- */
    {
      path: '/',
      component: () => import('@/layouts/AttendantLayout.vue'),
      meta: { area: 'ATTENDANT' },
      children: [
        { path: '', name: 'reports', component: () => import('@/views/ReportsView.vue') },
        { path: 'reports/new', name: 'report-new', component: () => import('@/views/ShiftReportView.vue') },
        {
          path: 'reports/:id',
          name: 'report-edit',
          component: () => import('@/views/ShiftReportView.vue'),
          props: true,
        },
      ],
    },

    /* ---------------- admin dashboard ---------------- */
    { path: '/admin/login', redirect: '/login' },
    {
      path: '/admin',
      component: () => import('@/layouts/AdminLayout.vue'),
      meta: { area: 'ADMIN' },
      children: [
        { path: '', name: 'admin-dashboard', component: () => import('@/views/AdminDashboardView.vue') },
        { path: 'reports', name: 'admin-reports', component: () => import('@/views/ReportsView.vue') },
        {
          path: 'reports/:id',
          name: 'admin-report',
          component: () => import('@/views/ShiftReportView.vue'),
          props: true,
        },
        { path: 'attendants', name: 'admin-attendants', component: () => import('@/views/AttendantsView.vue') },
        { path: 'fuel-types', name: 'admin-fuel-types', component: () => import('@/views/FuelTypesView.vue') },
      ],
    },

    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()
  const role = auth.account?.role
  const home = role === 'ADMIN' ? { name: 'admin-dashboard' } : { name: 'reports' }

  // login page: skip it when already signed in
  if (!to.meta.area) return role ? home : true

  if (!role) return { name: 'login', query: { next: to.fullPath } }
  // each role stays in its own area
  if (to.meta.area !== role) return home
})

export default router
