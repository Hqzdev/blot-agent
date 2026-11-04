import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { AuthError, cookieKey } from "./config.mjs";

export const SESSION_COOKIE = "blot_web_session";
export const GOOGLE_COOKIE = "blot_google_attempt";
export const COOKIE_OPTIONS = { httpOnly: true, sameSite: "lax", path: "/" };
const CONTEXT = Buffer.from("BLOT-WEB-SESSION-1");

export function seal(value, lifetimeSeconds, now = Date.now()) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", cookieKey(), nonce);
  cipher.setAAD(CONTEXT);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify({ value, expires: now + lifetimeSeconds * 1000 })), cipher.final()]);
  const result = Buffer.concat([nonce, cipher.getAuthTag(), ciphertext]).toString("base64url");
  if (result.length > 3800) throw new AuthError("invalid_auth_response", 502);
  return result;
}

export function unseal(text, now = Date.now()) {
  if (typeof text !== "string" || text.length > 3800 || !/^[A-Za-z0-9_-]+$/.test(text)) return null;
  try {
    const data = Buffer.from(text, "base64url");
    if (data.length < 29) return null;
    const decipher = createDecipheriv("aes-256-gcm", cookieKey(), data.subarray(0, 12));
    decipher.setAAD(CONTEXT); decipher.setAuthTag(data.subarray(12, 28));
    const saved = JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString("utf8"));
    return Number.isSafeInteger(saved.expires) && saved.expires > now ? saved.value : null;
  } catch { return null; }
}

const CLIENTS = { "blot-ios": "blot-agent-ios:/oauth/account", "blot-macos": "blot-agent-macos:/oauth/account" };
const PARAMETERS = ["response_type", "client_id", "redirect_uri", "state", "code_challenge", "code_challenge_method", "intent"];

export function nativeAttempt(parameters) {
  const query = parameters instanceof URLSearchParams ? parameters : new URLSearchParams(parameters);
  if (!PARAMETERS.some(name => query.has(name))) return null;
  if (PARAMETERS.some(name => query.getAll(name).length !== 1) || [...query.keys()].some(name => !PARAMETERS.includes(name))
      || query.get("response_type") !== "code" || query.get("code_challenge_method") !== "S256"
      || !CLIENTS[query.get("client_id")] || query.get("redirect_uri") !== CLIENTS[query.get("client_id")]
      || !/^[A-Za-z0-9_-]{43}$/.test(query.get("state")) || !/^[A-Za-z0-9_-]{43}$/.test(query.get("code_challenge"))
      || !["login", "register"].includes(query.get("intent"))) throw new AuthError("invalid_app_request");
  return { clientID: query.get("client_id"), redirectURI: query.get("redirect_uri"),
    state: query.get("state"), codeChallenge: query.get("code_challenge"), intent: query.get("intent") };
}

export function attemptQuery(attempt) {
  if (!attempt) return "";
  return new URLSearchParams({ response_type: "code", client_id: attempt.clientID, redirect_uri: attempt.redirectURI,
    state: attempt.state, code_challenge: attempt.codeChallenge, code_challenge_method: "S256", intent: attempt.intent }).toString();
}

export function appCallback(attempt, code) {
  nativeAttempt(attemptQuery(attempt));
  if (!/^[A-Za-z0-9_-]{43}$/.test(code)) throw new AuthError("invalid_auth_response", 502);
  const url = new URL(attempt.redirectURI);
  url.search = new URLSearchParams({ code, state: attempt.state }).toString();
  return url.toString();
}
