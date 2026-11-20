import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";

const site = new URL(process.argv[2] ?? "https://blot-agent.vercel.app").origin;
const token = () => randomBytes(32).toString("base64url");
const get = (path, headers) => fetch(new URL(path, site), {
  redirect: "manual", headers, signal: AbortSignal.timeout(15_000),
});
const attempt = new URLSearchParams({
  client_id: "blot-ios", redirect_uri: "blot-agent-ios:/oauth/account", response_type: "code",
  code_challenge_method: "S256", code_challenge: token(), state: token(), intent: "login",
});

for (const [provider, origin] of [["google", "https://accounts.google.com"], ["yandex", "https://oauth.yandex.ru"]]) {
  const start = await get(`/auth/${provider}/start?${attempt}`);
  assert.ok([302, 303, 307].includes(start.status), `${provider} start returned ${start.status}`);
  const authorization = new URL(start.headers.get("location"));
  assert.equal(authorization.origin, origin);
  const cookies = start.headers.getSetCookie().map(value => value.split(";")[0]).join("; ");
  assert.ok(cookies, `${provider} did not set an attempt cookie`);
  const state = authorization.searchParams.get("state");
  assert.ok(state);
  const canceled = new URLSearchParams({ state, error: "access_denied" });
  const callback = await get(`/auth/${provider}/callback?${canceled}`, { Cookie: cookies });
  assert.ok([302, 303, 307].includes(callback.status), `${provider} callback returned ${callback.status}`);
  const login = new URL(callback.headers.get("location"));
  assert.equal(login.pathname, "/login");
  assert.equal(login.searchParams.get("state"), attempt.get("state"));
  assert.equal(login.searchParams.get("auth_error"), provider + "_access_denied");
  console.log(`${provider}: authorization redirect and return to iPhone sign-in verified`);
}

const session = await get("/api/auth/session");
assert.equal(session.status, 200);
assert.equal((await session.json()).account, null);
