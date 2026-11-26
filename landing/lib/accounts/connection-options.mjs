import { readFileSync } from "node:fs";

export function accountConnectionOptions(connectionString) {
  const url = new URL(connectionString);
  if (!url.hostname.endsWith(".supabase.com") && !url.hostname.endsWith(".supabase.co")) return { connectionString };
  // pg's URL SSL parameters override its explicit ssl object.
  for (const key of ["ssl", "sslmode", "sslrootcert", "sslcert", "sslkey", "uselibpqcompat"]) url.searchParams.delete(key);
  return { connectionString: url.href, ssl: {
    ca: readFileSync(new URL("./supabase-ca.crt", import.meta.url), "utf8"),
    rejectUnauthorized: true,
  } };
}
