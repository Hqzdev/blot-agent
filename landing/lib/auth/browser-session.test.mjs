import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { seal, unseal, nativeAttempt, appCallback, attemptQuery } from "./browser-session.mjs";
process.env.BLOT_WEB_SESSION_SECRET = randomBytes(32).toString("base64url");

function query(platform = "ios") {
  return new URLSearchParams({ response_type: "code", client_id: "blot-" + platform, redirect_uri: `blot-agent-${platform}:/oauth/account`,
    state: "s".repeat(43), code_challenge: "c".repeat(43), code_challenge_method: "S256", intent: "login" });
}
test("encrypted browser cookies reject tampering, expiry and malformed input", () => {
  const value = { accessToken: "private-test-value", ownerID: "account" };
  const cookie = seal(value, 60, 1000);
  assert.ok(!cookie.includes("private-test-value"));
  assert.deepEqual(unseal(cookie, 1001), value);
  assert.equal(unseal(cookie, 61_000), null);
  const bytes = Buffer.from(cookie, "base64url"); bytes[29] ^= 1;
  assert.equal(unseal(bytes.toString("base64url"), 1001), null);
  assert.equal(unseal("invalid"), null);
});
test("native handoff is bound to a platform callback and preserves state", () => {
  for (const platform of ["ios", "macos"]) {
    const attempt = nativeAttempt(query(platform));
    assert.deepEqual(nativeAttempt(attemptQuery(attempt)), attempt);
    const url = new URL(appCallback(attempt, "x".repeat(43)));
    assert.equal(url.protocol, `blot-agent-${platform}:`);
    assert.equal(url.searchParams.get("state"), "s".repeat(43));
    assert.equal(url.searchParams.get("code"), "x".repeat(43));
    assert.equal(url.searchParams.has("access_token"), false);
  }
  assert.equal(nativeAttempt(new URLSearchParams()), null);
});
test("redirect injection, duplicate state and non-PKCE attempts are rejected", () => {
  for (const mutation of [q => q.set("redirect_uri", "https://attacker.example"), q => q.append("state", "other"),
    q => q.set("code_challenge_method", "plain"), q => q.append("access_token", "value"), q => q.set("client_id", "blot-macos")]) {
    const changed = query(); mutation(changed); assert.throws(() => nativeAttempt(changed));
  }
});
