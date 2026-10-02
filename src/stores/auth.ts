import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { supabase, TOKEN_KEY } from '@/lib/supabase'
import type { Account } from '@/lib/types'

function saveToken(token: string | null) {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token)
    else localStorage.removeItem(TOKEN_KEY)
  } catch {
    /* storage unavailable: session lasts until the tab closes */
  }
}

export const useAuthStore = defineStore('auth', () => {
  const account = ref<Account | null>(null)
  const isAdmin = computed(() => account.value?.role === 'ADMIN')
  let ready: Promise<void> | null = null

  /** Restore the session from the saved token (validated by the database). */
  function init(): Promise<void> {
    ready ??= (async () => {
      const { data, error } = await supabase.rpc('me')
      account.value = error ? null : ((data as Account | null) ?? null)
      if (!account.value) saveToken(null)
    })()
    return ready
  }

  async function signIn(username: string, password: string) {
    const { data, error } = await supabase.rpc('sign_in', {
      p_username: username,
      p_password: password,
    })
    if (error) throw error
    const res = data as { token: string; account: Account }
    saveToken(res.token)
    account.value = res.account
  }

  /** Confirms the new session works by asking the database who is signed in. */
  async function verifySession() {
    const { data, error } = await supabase.rpc('me')
    if (error || !data) {
      saveToken(null)
      account.value = null
      throw new Error('Could not start your session. Please try again.')
    }
    account.value = data as Account
  }

  /** Deletes the session in the database so the token stops working everywhere. */
  async function endServerSession() {
    const { error } = await supabase.rpc('sign_out')
    if (error)
      throw new Error('Could not reach the server; you are signed out on this device only.')
  }

  /** Forgets the token on this device. */
  function clearLocalSession() {
    saveToken(null)
    account.value = null
  }

  return {
    account,
    isAdmin,
    init,
    signIn,
    verifySession,
    endServerSession,
    clearLocalSession,
  }
})
