import { test } from "node:test";
import assert from "node:assert/strict";
import { YandexAccountIdentity } from "./yandex.mjs";
import { OAuthHTTPClient } from "../auth/oauth-http.mjs";

const profile = { id: "123456789", client_id: "blot-yandex", default_email: "Person@yandex.ru", real_name: "Person" };
const rejectCode = code => error => error.code === code;

test("Yandex profile comes from the provider over HTTPS and must belong to this client", async () => {
  const identity = new YandexAccountIdentity("blot-yandex", new OAuthHTTPClient(async (url, options) => {
    assert.equal(url, "https://login.yandex.ru/info?format=json");
    assert.equal(options.headers.Authorization, "OAuth private-token");
    assert.equal(options.redirect, "error");
    return Response.json(profile);
  }));
  assert.deepEqual(await identity.verify("private-token"), { subject: "123456789", email: "person@yandex.ru", name: "Person", avatarURL: null });
  for (const values of [{ client_id: "another-app" }, { client_id: undefined }, { id: "" }, { id: 123 }, { default_email: undefined }, { default_email: "invalid" }]) {
    const verifier = new YandexAccountIdentity("blot-yandex", new OAuthHTTPClient(async () => Response.json({ ...profile, ...values })));
    await assert.rejects(verifier.verify("private-token"), rejectCode("yandex_identity_invalid"));
  }
  await assert.rejects(identity.verify("invalid\ntoken"), rejectCode("yandex_identity_invalid"));
  await assert.rejects(new YandexAccountIdentity("").verify("private-token"), rejectCode("yandex_unconfigured"));
});

test("Yandex API errors and missing names are handled without trusting browser profile fields", async () => {
  const unavailable = new YandexAccountIdentity("blot-yandex", new OAuthHTTPClient(async () => new Response(null, { status: 401 })));
  await assert.rejects(unavailable.verify("private-token"), rejectCode("yandex_unavailable"));
  const unnamed = new YandexAccountIdentity("blot-yandex", new OAuthHTTPClient(async () => Response.json({ ...profile, real_name: "" })));
  assert.equal((await unnamed.verify("private-token")).name, "person@yandex.ru");
});

test("Yandex imports a real portrait but never a placeholder or untrusted avatar identifier", async () => {
  for (const [extra, expected] of [
    [{ is_avatar_empty: false, default_avatar_id: "12345-avatar" }, "https://avatars.yandex.net/get-yapic/12345-avatar/islands-200"],
    [{ is_avatar_empty: false, default_avatar_id: "31804/avatar-id" }, "https://avatars.yandex.net/get-yapic/31804/avatar-id/islands-200"],
    [{ is_avatar_empty: true, default_avatar_id: "12345-avatar" }, null],
    [{ default_avatar_id: "12345-avatar" }, null],
    [{ is_avatar_empty: false, default_avatar_id: "../private" }, null],
  ]) {
    const verifier = new YandexAccountIdentity("blot-yandex", new OAuthHTTPClient(async () => Response.json({ ...profile, ...extra })));
    assert.equal((await verifier.verify("private-token")).avatarURL, expected);
  }
});
