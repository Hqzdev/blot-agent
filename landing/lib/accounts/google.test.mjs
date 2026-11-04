import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPair, exportJWK, createLocalJWKSet, SignJWT } from "jose";
import { GoogleAccountIdentity } from "./google.mjs";
import { randomToken } from "./security.mjs";

test("Google identities require a trusted signature, audience, issuer, nonce, expiry and verified email", async () => {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = await exportJWK(publicKey);
  const verifier = new GoogleAccountIdentity("blot-web", createLocalJWKSet({ keys: [{ ...jwk, kid: "test", alg: "RS256" }] }));
  const nonce = randomToken();
  async function token(overrides = {}, signingKey = privateKey) {
    return new SignJWT({ iss: "https://accounts.google.com", aud: "blot-web", sub: "google-person", nonce,
      email: "person@example.org", email_verified: true, name: "Person", iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 300, ...overrides }).setProtectedHeader({ alg: "RS256", kid: "test" }).sign(signingKey);
  }
  assert.equal((await verifier.verify(await token(), nonce)).subject, "google-person");
  for (const claims of [{ aud: "another-client" }, { iss: "https://attacker.org" }, { nonce: randomToken() },
    { exp: 1 }, { email_verified: false }, { email: "invalid" }]) {
    await assert.rejects(verifier.verify(await token(claims), nonce), error => error.code === "google_identity_invalid");
  }
  const attacker = await generateKeyPair("RS256");
  await assert.rejects(verifier.verify(await token({}, attacker.privateKey), nonce), error => error.code === "google_identity_invalid");
});
