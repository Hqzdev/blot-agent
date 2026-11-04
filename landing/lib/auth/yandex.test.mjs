import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { NextRequest } from "next/server.js";
import { YandexAuthorization } from "./yandex.mjs";
import { YandexSignIn } from "./yandex-sign-in.mjs";
import { OAuthHTTPClient } from "./oauth-http.mjs";
import { yandexConfiguration, cookieKey, AuthError } from "./config.mjs";
import { YANDEX_COOKIE, SESSION_COOKIE, seal, unseal, nativeAttempt } from "./browser-session.mjs";
import { randomToken } from "../accounts/security.mjs";

process.env.BLOT_WEB_SESSION_SECRET = randomToken();
const config = { clientID: "blot-yandex", clientSecret: "server-only-secret", redirectURI: "https://blot.example/auth/yandex/callback" };
const rejectCode = code => error => error.code === code;

test("Yandex uses a fresh state and S256 verifier; only the server exchanges the code", async () => {
  const http = new OAuthHTTPClient(async (url, options) => {
    assert.equal(url, "https://oauth.yandex.ru/token");
    assert.equal(options.method, "POST");
    assert.equal(options.redirect, "error");
    assert.equal(options.cache, "no-store");
    assert.equal(options.body.get("client_secret"), config.clientSecret);
    assert.equal(options.body.get("redirect_uri"), config.redirectURI);
    assert.equal(options.body.get("code"), "authorization-code");
    assert.equal(createHash("sha256").update(options.body.get("code_verifier")).digest("base64url"), urlAttempt.url.searchParams.get("code_challenge"));
    return Response.json({ access_token: "private-yandex-token", token_type: "bearer" });
  });
  const authorization = new YandexAuthorization(config, http);
  const urlAttempt = authorization.start(null), second = authorization.start(null);
  const query = urlAttempt.url.searchParams;
  assert.equal(urlAttempt.url.origin, "https://oauth.yandex.ru");
  assert.equal(query.get("scope"), "login:info login:email");
  assert.equal(query.get("code_challenge_method"), "S256");
  assert.equal(query.has("client_secret"), false);
  assert.equal(query.has("code_verifier"), false);
  assert.notEqual(urlAttempt.saved.state, second.saved.state);
  assert.notEqual(urlAttempt.saved.verifier, second.saved.verifier);
  assert.equal(await authorization.exchange(new URLSearchParams({ state: urlAttempt.saved.state, code: "authorization-code" }), urlAttempt.saved), "private-yandex-token");
});

test("missing, mismatched, duplicate or cross-provider state cannot exchange a code", async () => {
  let calls = 0;
  const authorization = new YandexAuthorization(config, new OAuthHTTPClient(async () => { calls++; throw new Error(); }));
  const { saved } = authorization.start(null);
  for (const [query, attempt] of [
    [new URLSearchParams({ state: saved.state, code: "code" }), null],
    [new URLSearchParams({ state: randomToken(), code: "code" }), saved],
    [new URLSearchParams(`state=${saved.state}&state=${saved.state}&code=code`), saved],
    [new URLSearchParams({ state: saved.state, code: "code" }), { ...saved, provider: "google" }],
    [new URLSearchParams({ state: saved.state, code: "code" }), { ...saved, verifier: "" }],
  ]) await assert.rejects(authorization.exchange(query, attempt), rejectCode("yandex_state_invalid"));
  for (const query of [new URLSearchParams({ state: saved.state }), new URLSearchParams(`state=${saved.state}&code=a&code=b`)]) {
    await assert.rejects(authorization.exchange(query, saved), rejectCode("yandex_failed"));
  }
  assert.equal(calls, 0);
});

test("cancellation and invalid provider responses fail without issuing a session", async () => {
  const authorization = new YandexAuthorization(config);
  const { saved } = authorization.start(null);
  await assert.rejects(authorization.exchange(new URLSearchParams({ state: saved.state, error: "access_denied" }), saved), rejectCode("yandex_access_denied"));
  for (const response of [
    () => Response.json({ error: "invalid_grant" }, { status: 400 }),
    () => Response.json({ access_token: "token", token_type: "basic" }),
    () => Response.json({ access_token: "bad\r\ntoken", token_type: "bearer" }),
    () => new Response("not JSON"),
    () => new Response("x".repeat(65_537)),
    () => new Response("{}", { headers: { "Content-Length": "65537" } }),
    () => { throw new Error("network failure"); },
  ]) {
    const broken = new YandexAuthorization(config, new OAuthHTTPClient(async () => response()));
    await assert.rejects(broken.exchange(new URLSearchParams({ state: saved.state, code: "code" }), saved), rejectCode("yandex_failed"));
  }
});

test("callback clears expired cookies and preserves native context on cancellation", async () => {
  const signIn = new YandexSignIn({ configuration: () => config, accounts: async () => { assert.fail("No account request is allowed"); } });
  const query = new URLSearchParams({ response_type: "code", client_id: "blot-ios", redirect_uri: "blot-agent-ios:/oauth/account",
    state: randomToken(), code_challenge: randomToken(), code_challenge_method: "S256", intent: "login" });
  const start = signIn.start(new NextRequest("https://blot.example/auth/yandex/start?" + query));
  const cookie = start.cookies.get(YANDEX_COOKIE).value;
  const saved = unseal(cookie);
  const request = new NextRequest(`https://blot.example/auth/yandex/callback?state=${saved.state}&error=access_denied`, {
    headers: { cookie: `${YANDEX_COOKIE}=${cookie}` },
  });
  const response = await signIn.callback(request);
  const destination = new URL(response.headers.get("location"));
  assert.equal(destination.searchParams.get("auth_error"), "yandex_access_denied");
  destination.searchParams.delete("auth_error");
  assert.deepEqual(nativeAttempt(destination.searchParams), nativeAttempt(query));
  assert.equal(response.cookies.get(YANDEX_COOKIE).value, "");
  assert.equal(response.cookies.has(SESSION_COOKIE), false);
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.match(start.headers.get("set-cookie"), /HttpOnly/);
  assert.match(start.headers.get("set-cookie"), /Secure/);
  assert.match(start.headers.get("set-cookie"), /SameSite=lax/i);
  const expired = seal(saved, 1, 0);
  const expiredResponse = await signIn.callback(new NextRequest(request.url, { headers: { cookie: `${YANDEX_COOKIE}=${expired}` } }));
  assert.equal(new URL(expiredResponse.headers.get("location")).searchParams.get("auth_error"), "yandex_state_invalid");
  assert.equal(expiredResponse.cookies.has(SESSION_COOKIE), false);
});

test("start rejects unsafe native redirects and reports missing configuration", () => {
  const signIn = new YandexSignIn({ configuration: () => { throw new AuthError("yandex_unconfigured", 503); } });
  const invalid = signIn.start(new NextRequest("https://blot.example/auth/yandex/start?redirect_uri=https://attacker.example"));
  assert.equal(new URL(invalid.headers.get("location")).searchParams.get("auth_error"), "invalid_app_request");
  const missing = signIn.start(new NextRequest("https://blot.example/auth/yandex/start"));
  assert.equal(new URL(missing.headers.get("location")).searchParams.get("auth_error"), "yandex_unconfigured");
});

test("Yandex configuration requires the exact callback and PostgreSQL; its secret can protect cookies", () => {
  const names = ["BLOT_YANDEX_WEB_CLIENT_ID", "BLOT_YANDEX_WEB_CLIENT_SECRET", "BLOT_YANDEX_WEB_REDIRECT_URI", "DATABASE_URL", "BLOT_WEB_SESSION_SECRET", "BLOT_GOOGLE_WEB_CLIENT_SECRET"];
  const previous = Object.fromEntries(names.map(name => [name, process.env[name]]));
  try {
    process.env.BLOT_YANDEX_WEB_CLIENT_ID = config.clientID;
    process.env.BLOT_YANDEX_WEB_CLIENT_SECRET = randomToken();
    process.env.BLOT_YANDEX_WEB_REDIRECT_URI = config.redirectURI;
    process.env.DATABASE_URL = "postgresql://test.invalid/test";
    assert.equal(yandexConfiguration().redirectURI, config.redirectURI);
    for (const uri of ["invalid", "http://blot.example/auth/yandex/callback", "https://blot.example/wrong", `${config.redirectURI}?extra=1`, `https://user@blot.example/auth/yandex/callback`]) {
      process.env.BLOT_YANDEX_WEB_REDIRECT_URI = uri;
      assert.throws(yandexConfiguration, rejectCode("yandex_unconfigured"));
    }
    process.env.BLOT_YANDEX_WEB_REDIRECT_URI = "http://localhost:3000/auth/yandex/callback";
    assert.equal(yandexConfiguration().redirectURI, process.env.BLOT_YANDEX_WEB_REDIRECT_URI);
    delete process.env.DATABASE_URL;
    assert.throws(yandexConfiguration, rejectCode("auth_service_unconfigured"));
    delete process.env.BLOT_WEB_SESSION_SECRET;
    delete process.env.BLOT_GOOGLE_WEB_CLIENT_SECRET;
    assert.equal(cookieKey().length, 32);
  } finally {
    for (const name of names) { if (previous[name] === undefined) delete process.env[name]; else process.env[name] = previous[name]; }
  }
});
