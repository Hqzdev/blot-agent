import { NextResponse } from "next/server";
import { accountRequest, AuthError, googleConfiguration } from "@/lib/auth/config.mjs";
import { GOOGLE_COOKIE, COOKIE_OPTIONS, unseal, attemptQuery } from "@/lib/auth/browser-session.mjs";
import { setSession, PRIVATE_HEADERS } from "@/lib/auth/route-support.mjs";

export const runtime = "nodejs";
export async function GET(request) {
  const saved = unseal(request.cookies.get(GOOGLE_COOKIE)?.value);
  const destination = new URL("/login", request.url);
  if (saved?.attempt) destination.search = attemptQuery(saved.attempt);
  let tokens;
  try {
    const query = new URL(request.url).searchParams;
    if (!saved || query.getAll("state").length !== 1 || query.get("state") !== saved.state) throw new AuthError("google_state_invalid");
    if (query.has("error")) throw new AuthError(query.get("error") === "access_denied" ? "google_access_denied" : "google_failed");
    if (query.getAll("code").length !== 1 || !query.get("code") || query.get("code").length > 4096) throw new AuthError("google_failed");
    const config = googleConfiguration();
    const response = await fetch("https://oauth2.googleapis.com/token", { method: "POST", redirect: "error", cache: "no-store",
      signal: AbortSignal.timeout(15_000), headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "authorization_code", code: query.get("code"), client_id: config.clientID,
        client_secret: config.clientSecret, redirect_uri: config.redirectURI, code_verifier: saved.verifier }) });
    if (!response.ok || Number(response.headers.get("content-length")) > 65_536) throw new AuthError("google_failed");
    const reader = response.body.getReader(); const chunks = []; let size = 0;
    try {
      while (true) { const { value, done } = await reader.read(); if (done) break; size += value.length;
        if (size > 65_536) throw new AuthError("google_failed"); chunks.push(Buffer.from(value)); }
    } finally { await reader.cancel(); }
    const identity = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (typeof identity.id_token !== "string" || identity.id_token.length > 16_384) throw new AuthError("google_failed");
    tokens = await accountRequest("google/login", { body: { idToken: identity.id_token, nonce: saved.nonce } });
  } catch (error) {
    destination.searchParams.set("auth_error", error instanceof AuthError ? error.code : "google_failed");
  }
  const result = NextResponse.redirect(destination, { headers: PRIVATE_HEADERS });
  result.cookies.set(GOOGLE_COOKIE, "", { ...COOKIE_OPTIONS, maxAge: 0 });
  return tokens ? setSession(result, tokens, request) : result;
}
