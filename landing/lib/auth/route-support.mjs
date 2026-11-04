import { NextResponse } from "next/server";
import { AuthError, accountRequest } from "./config.mjs";
import { COOKIE_OPTIONS, SESSION_COOKIE, seal, unseal } from "./browser-session.mjs";

export const PRIVATE_HEADERS = { "Cache-Control": "no-store, private", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff" };
export function json(value, status = 200) { return NextResponse.json(value, { status, headers: PRIVATE_HEADERS }); }
export function failure(error) { return json({ code: error instanceof AuthError ? error.code : "auth_service_unavailable" }, error instanceof AuthError ? error.status : 503); }

export async function input(request) {
  const target = new URL(request.url);
  let source;
  try { source = new URL(request.headers.get("origin")); } catch { throw new AuthError("request_not_allowed", 403); }
  if (source.origin !== request.headers.get("origin") || source.host !== request.headers.get("host")
      || source.protocol !== target.protocol || !request.headers.get("content-type")?.startsWith("application/json")) {
    throw new AuthError("request_not_allowed", 403);
  }
  const reader = request.body?.getReader();
  if (!reader) throw new AuthError("invalid_request");
  const chunks = []; let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.length; if (size > 16_384) throw new AuthError("invalid_request", 413);
      chunks.push(Buffer.from(value));
    }
  } finally { await reader.cancel(); }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value;
  } catch { throw new AuthError("invalid_request"); }
}

export function validateTokens(tokens) {
  if (!tokens || !/^[A-Za-z0-9_-]{43}$/.test(tokens.accessToken)
      || !/^[0-9a-f-]{36}$/i.test(tokens.ownerID) || !/^[0-9a-f-]{36}$/i.test(tokens.sessionID)
      || !Number.isFinite(Date.parse(tokens.expiresAt))) throw new AuthError("invalid_auth_response", 502);
  return tokens;
}

export function setSession(response, tokens, request) {
  const { refreshToken: _refreshToken, ...browserTokens } = validateTokens(tokens);
  response.cookies.set(SESSION_COOKIE, seal(browserTokens, 600), {
    ...COOKIE_OPTIONS, secure: new URL(request.url).protocol === "https:", maxAge: 600,
  });
  return response;
}

export async function currentTokens(request) {
  const tokens = unseal(request.cookies.get(SESSION_COOKIE)?.value);
  if (!tokens) throw new AuthError("web_session_expired", 401);
  validateTokens(tokens);
  if (Date.parse(tokens.expiresAt) <= Date.now() + 15_000) throw new AuthError("web_session_expired", 401);
  return tokens;
}
