import assert from "node:assert/strict";
import { test } from "node:test";
import { forwardNativeChat } from "./native-chat.mjs";

const endpoint = "https://blot-agent.vercel.app/app/api/model/chat";
const token = "a".repeat(43);
const json = JSON.stringify({ tier: "max", completion: { messages: [{ role: "user", content: "Test" }], max_tokens: 8, stream: true } });

function request(headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }) {
  return new Request(endpoint, { method: "POST", headers, body: json });
}

test("rejects anonymous requests and invalid content types before contacting the gateway", async () => {
  const unexpected = () => assert.fail("unauthorized request reached the gateway");
  assert.equal((await forwardNativeChat(request({}), unexpected)).status, 401);
  assert.equal((await forwardNativeChat(request({ Authorization: `Bearer ${token}` }), unexpected)).status, 400);
});

test("forwards the native payload and returns the original event stream", async () => {
  const native = request({ Authorization: `Bearer ${token}`, "Content-Type": "application/json", Cookie: "private=1" });
  const events = "data: {\"choices\":[]}\n\ndata: [DONE]\n\n";
  const response = await forwardNativeChat(native, async (url, init) => {
    assert.equal(url, "https://blot-web-ha1zyys-projects.vercel.app/api/model/chat");
    assert.equal(init.method, "POST");
    assert.equal(init.redirect, "error");
    assert.equal(init.signal, native.signal);
    const forwarded = new Request(url, init);
    assert.equal(forwarded.headers.get("authorization"), `Bearer ${token}`);
    assert.equal(forwarded.headers.has("cookie"), false);
    assert.equal(await forwarded.text(), json);
    return new Response(events, { headers: { "content-type": "text/event-stream", "set-cookie": "private=2" } });
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "text/event-stream");
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.has("set-cookie"), false);
  assert.equal(await response.text(), events);
});

test("retains gateway quota information and maps transport failures to HTTP 502", async () => {
  const quotaReset = "2026-11-27T00:00:00.000Z";
  const response = await forwardNativeChat(request(), async () => Response.json({ error: "quota_exceeded" }, {
    status: 429, headers: { "x-blot-quota-reset": quotaReset, "retry-after": "60" },
  }));
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("x-blot-quota-reset"), quotaReset);
  assert.equal(response.headers.get("retry-after"), "60");
  assert.deepEqual(await response.json(), { error: "quota_exceeded" });
  const unavailable = await forwardNativeChat(request(), async () => { throw new TypeError("network unavailable"); });
  assert.equal(unavailable.status, 502);
});
