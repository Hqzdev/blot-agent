import { createHash, randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import { googleConfiguration } from "@/lib/auth/config.mjs";
import { nativeAttempt, attemptQuery, GOOGLE_COOKIE, COOKIE_OPTIONS, seal } from "@/lib/auth/browser-session.mjs";
import { PRIVATE_HEADERS } from "@/lib/auth/route-support.mjs";

export const runtime = "nodejs";
export async function GET(request) {
  let attempt;
  try {
    attempt = nativeAttempt(new URL(request.url).searchParams);
    const config = googleConfiguration();
    const state = randomBytes(32).toString("base64url"), nonce = randomBytes(32).toString("base64url"), verifier = randomBytes(32).toString("base64url");
    const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    url.search = new URLSearchParams({ client_id: config.clientID, redirect_uri: config.redirectURI, response_type: "code",
      scope: "openid email profile", state, nonce, code_challenge: createHash("sha256").update(verifier).digest("base64url"),
      code_challenge_method: "S256", prompt: "select_account" }).toString();
    const response = NextResponse.redirect(url, { headers: PRIVATE_HEADERS });
    response.cookies.set(GOOGLE_COOKIE, seal({ state, nonce, verifier, attempt }, 600), {
      ...COOKIE_OPTIONS, secure: new URL(request.url).protocol === "https:", maxAge: 600,
    });
    return response;
  } catch {
    const url = new URL("/login", request.url);
    url.search = attemptQuery(attempt); url.searchParams.set("auth_error", "google_unconfigured");
    return NextResponse.redirect(url, { headers: PRIVATE_HEADERS });
  }
}
