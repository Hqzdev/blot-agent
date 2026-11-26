// The existing two-domain deployment serves the web app at its own root.
export function billingPath(path: string) {
  return (process.env.NEXT_PUBLIC_BLOT_BILLING_BASE ?? '') + path;
}
