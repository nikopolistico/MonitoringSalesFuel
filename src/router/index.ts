import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { adminRoutes } from './admin'
import { attendantRoutes } from './attendant'

declare module 'vue-router' {
  interface RouteMeta {
    /** Who may open the page. Pages without it are the login page. */
    area?: 'ATTENDANT' | 'ADMIN'
  }
}

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    /* one sign-in page for everyone; the role decides where they land */
    { path: '/login', name: 'login', component: () => import('@/views/auth/LoginView.vue') },
    { path: '/admin/login', redirect: '/login' },
    attendantRoutes,
    adminRoutes,
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
