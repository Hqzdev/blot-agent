import { createHmac } from "node:crypto";
import { AuthError } from "./errors.mjs";
export { AuthError } from "./errors.mjs";

export function accountOrigin() {
  const value = process.env.BLOT_CLOUD_ORIGIN || process.env.BLOT_ACCOUNT_SERVICE_URL;
  const url = new URL(value || (process.env.NODE_ENV !== "production" ? "http://127.0.0.1:8081" : "http://invalid"));
  if ((!value && process.env.NODE_ENV === "production") || url.username || url.password || url.search || url.hash || !["", "/"].includes(url.pathname)
      || !(url.protocol === "https:" || (url.protocol === "http:" && ["127.0.0.1", "localhost"].includes(url.hostname)))) {
    throw new AuthError("auth_service_unconfigured", 503);
  }
  return url.origin;
}

export function googleConfiguration() {
  const clientID = process.env.BLOT_GOOGLE_WEB_CLIENT_ID;
  const clientSecret = process.env.BLOT_GOOGLE_WEB_CLIENT_SECRET;
  const redirectURI = process.env.BLOT_GOOGLE_WEB_REDIRECT_URI;
  if (!clientID || !clientSecret || !redirectURI) throw new AuthError("google_unconfigured", 503);
  const url = new URL(redirectURI);
  if (url.username || url.password || url.search || url.hash || url.pathname !== "/auth/google/callback"
      || !(url.protocol === "https:" || (url.protocol === "http:" && ["127.0.0.1", "localhost"].includes(url.hostname)))) {
    throw new AuthError("google_unconfigured", 503);
  }
  return { clientID, clientSecret, redirectURI };
}

export function cookieKey() {
  const secret = process.env.BLOT_WEB_SESSION_SECRET || process.env.BLOT_GOOGLE_WEB_CLIENT_SECRET;
  if (!secret || secret.length < 24) throw new AuthError("web_session_unconfigured", 503);
  return createHmac("sha256", secret).update("BLOT-WEB-COOKIE-1").digest();
}

export async function accountRequest(path, { body, accessToken, method = "POST", clientIP } = {}) {
  if (process.env.DATABASE_URL) {
    const { localAccountService } = await import("../accounts/service.mjs");
    return localAccountService().request(path, { body, accessToken, method, clientIP });
  }
  let response;
  try {
    response = await fetch(new URL("/v1/auth/" + path, accountOrigin()), {
      method, redirect: "error", cache: "no-store", signal: AbortSignal.timeout(20_000),
      headers: { "Accept": "application/json", ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
        ...(accessToken ? { "Authorization": "Bearer " + accessToken } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch (error) {
    if (error instanceof AuthError) throw error;
    throw new AuthError("auth_service_unavailable", 503);
  }
  const length = Number(response.headers.get("content-length"));
  if (length > 65_536) throw new AuthError("invalid_auth_response", 502);
  const reader = response.body?.getReader();
  let size = 0, chunks = [];
  if (reader) {
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 65_536) throw new AuthError("invalid_auth_response", 502);
        chunks.push(Buffer.from(value));
      }
    } finally { await reader.cancel(); }
  }
  let data;
  try { data = size ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : null; }
  catch { throw new AuthError("invalid_auth_response", 502); }
  if (!response.ok) {
    const code = typeof data?.code === "string" && /^[a-z0-9_]{1,80}$/.test(data.code) ? data.code : "auth_service_unavailable";
    throw new AuthError(code, response.status);
  }
  return data;
}
