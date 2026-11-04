import test from "node:test";
import assert from "node:assert/strict";
import { AppHandoff } from "./app-handoff.mjs";

const query = new URLSearchParams({ client_id: "blot-macos", redirect_uri: "blot-agent-macos:/oauth/account",
  state: "s".repeat(43), code_challenge: "p".repeat(43), code_challenge_method: "S256", response_type: "code", intent: "register" }).toString();
const issued = () => ({ callbackURL: `blot-agent-macos:/oauth/account?code=${"c".repeat(43)}&state=${"s".repeat(43)}`,
  expiresAt: new Date(Date.now() + 60_000).toISOString() });

test("authenticated registration returns to the app immediately and duplicate effects share one code", async () => {
  let release, requests = 0; const navigations = [];
  const handoff = new AppHandoff({ prepare: received => {
    assert.equal(received, query); requests++;
    return new Promise(resolve => { release = resolve; });
  }, navigate: url => navigations.push(url) });
  const first = handoff.open({ query, platform: "macos" });
  const repeated = handoff.open({ query, platform: "macos" });
  assert.equal(first, repeated);
  const result = issued(); release(result);
  await first;
  assert.equal(requests, 1);
  assert.deepEqual(navigations, [result.callbackURL]);
});

test("direct website registration starts native PKCE without putting a session token in the URL", async () => {
  const navigations = [];
  const handoff = new AppHandoff({ prepare: () => assert.fail("No native challenge exists yet"),
    navigate: url => navigations.push(url) });
  await handoff.open({ query: "", platform: "ios" });
  assert.deepEqual(navigations, ["blot-agent-ios:/oauth/start"]);
});

test("failed issuance leaves the page open and permits an explicit retry with a fresh code", async () => {
  let requests = 0; const navigations = [];
  const handoff = new AppHandoff({ prepare: async () => { if (++requests === 1) throw new Error("service_unavailable"); return issued(); },
    navigate: url => navigations.push(url) });
  await assert.rejects(handoff.open({ query }), /service_unavailable/);
  assert.deepEqual(navigations, []);
  await handoff.open({ query });
  assert.equal(requests, 2); assert.equal(navigations.length, 1);
});

test("an expired, mismatched or credential-bearing callback never closes the browser", async () => {
  for (const change of [value => { value.expiresAt = "2000-01-01"; },
    value => { value.callbackURL = value.callbackURL.replace("macos:", "ios:"); },
    value => { value.callbackURL += "&access_token=secret"; },
    value => { value.callbackURL = value.callbackURL.replace("state=s", "state=x"); }]) {
    const value = issued(); change(value);
    const handoff = new AppHandoff({ prepare: async () => value, navigate: () => assert.fail("Unsafe navigation") });
    await assert.rejects(handoff.open({ query }), /invalid_auth_response/);
  }
});
