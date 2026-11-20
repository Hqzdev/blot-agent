import { supabaseRootCA } from './supabase-ca.mjs';

export function databaseTLS(connectionString) {
  const url = new URL(connectionString);
  if (
    !url.hostname.endsWith('.supabase.com') &&
    !url.hostname.endsWith('.supabase.co')
  )
    return {};
  return {
    ssl: {
      ca: supabaseRootCA,
      rejectUnauthorized: true,
    },
  };
}
