import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const isConfigured = Boolean(url && anonKey)

export const TOKEN_KEY = 'rcja.session'

function readToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY)
  } catch {
    return null
  }
}

/**
 * Every request carries our own login token in the "x-session-token" header.
 * The database policies (see supabase/schema.sql) read it to know who is signed in.
 */
export const supabase = createClient(url || 'http://localhost:54321', anonKey || 'missing-anon-key', {
  auth: { persistSession: false, autoRefreshToken: false },
  global: {
    fetch: (input, init = {}) => {
      const headers = new Headers(init.headers)
      const token = readToken()
      if (token) headers.set('x-session-token', token)
      return fetch(input, { ...init, headers })
    },
  },
})
