import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { test } from "node:test";
import { PGlite } from "@electric-sql/pglite";
import { AccountDatabase } from "../accounts/database.mjs";
import { BrowserAuthorizationCodes } from "../accounts/browser-codes.mjs";
import { AccountSessions } from "../accounts/sessions.mjs";
import { randomToken } from "../accounts/security.mjs";
import { CliModel } from "../cli/model.mjs";
import { GigaChat } from "../cli/gigachat.mjs";
import { AppHandoff } from "./app-handoff.mjs";
import { appCallback, attemptQuery, nativeAttempt } from "./browser-session.mjs";

const clientID = "blot-cli";
const redirectURI = "http://127.0.0.1:49152/oauth/blot";
const pkce = verifier => createHash("sha256").update(verifier).digest("base64url");
const codeIs = code => error => error.code === code;

test("CLI PKCE grants one loopback session for the verified Blot owner", async () => {
  const postgres = new PGlite();
  const pg = {
    query: (sql, values) => values?.length
      ? postgres.query(sql, values) : postgres.exec(sql).then(results => results.at(-1)),
    async connect() { return { query: this.query, release() {} }; },
  };
  try {
    const database = new AccountDatabase(pg);
    await database.initialize();
    const account = { id: randomUUID(), workspace_id: randomUUID() };
    await database.query(
      "INSERT INTO blot_accounts(id, workspace_id, email, name, verified) VALUES ($1,$2,$3,$4,true)",
      [account.id, account.workspace_id, "cli@example.org", "CLI"],
    );
    const sessions = new AccountSessions(database);
    const browser = new BrowserAuthorizationCodes(database, sessions);
    const browserTokens = await sessions.create(database, account);
    const codeVerifier = randomToken();
    const attempt = { clientID, redirectURI, state: randomToken(),
      codeChallenge: pkce(codeVerifier), intent: "login" };
    assert.deepEqual(nativeAttempt(attemptQuery(attempt)), attempt);
    for (const redirect of ["http://localhost:49152/oauth/blot", "http://127.0.0.1:80/oauth/blot",
      "http://127.0.0.1:65536/oauth/blot", "http://127.0.0.1:49152/oauth/blot?next=https://example.org"]) {
      assert.throws(() => nativeAttempt(attemptQuery({ ...attempt, redirectURI: redirect })), codeIs("invalid_app_request"));
      await assert.rejects(browser.issue({ ...attempt, redirectURI: redirect }, browserTokens.accessToken),
        codeIs("browser_authorization_invalid"));
    }
    const issued = await browser.issue(attempt, browserTokens.accessToken);
    const callbackURL = appCallback(attempt, issued.code);
    let navigated;
    const handoff = new AppHandoff({
      prepare: async () => ({ callbackURL, expiresAt: issued.expiresAt }), navigate: url => { navigated = url; },
    });
    await handoff.open({ query: attemptQuery(attempt), platform: "macos" });
    assert.equal(navigated, callbackURL);
    const exchange = { ...attempt, code: issued.code, codeVerifier };
    await assert.rejects(browser.exchange({ ...exchange, codeVerifier: randomToken() }),
      codeIs("browser_authorization_invalid"));
    const cli = await browser.exchange(exchange);
    assert.equal(cli.ownerID, browserTokens.ownerID);
    await assert.rejects(browser.exchange(exchange), codeIs("browser_authorization_invalid"));
    const profile = await sessions.require(cli.accessToken);
    await sessions.logout(profile);
    await assert.rejects(sessions.require(cli.accessToken), codeIs("session_expired"));
  } finally { await postgres.close(); }
});

test("CLI model gates requests and keeps provider credentials on the server", async () => {
  const access = randomToken(), key = "fixture-provider-key", generation = [];
  const provider = new GigaChat({ key, scope: "GIGACHAT_API_PERS", transport: async (url, body, headers) => {
    if (url.endsWith("/oauth")) {
      assert.equal(headers.Authorization, "Basic " + key);
      return { status: 200, data: { access_token: "provider-token", expires_at: Date.now() + 300_000 } };
    }
    assert.equal(headers.Authorization, "Bearer provider-token");
    generation.push(JSON.parse(body));
    return { status: 200, data: { choices: [{ message: { content: "Done" } }] } };
  } });
  const rateKeys = [];
  const model = new CliModel({
    authenticate: async token => { assert.equal(token, access); return { id: "owner" }; },
    rate: { async check(key) { rateKeys.push(key); } }, provider,
    model: "GigaChat-2", contextTokens: 32768, outputTokens: 4096,
  });
  const body = { model: "ignore-the-client-model", max_tokens: 6000, stream: true,
    messages: [{ role: "system", content: "Code" }, { role: "user", content: "Read a file", attachments: ["ignored"] }],
    functions: [{ name: "read_file", description: "Read", parameters: { type: "object" } }] };
  const request = (input, token = access) => new Request("https://example.org/v1/cli/model", {
    method: "POST", headers: { "content-type": "application/json", authorization: "Bearer " + token },
    body: JSON.stringify(input),
  });
  await assert.rejects(model.handle(request(body, "")), codeIs("session_required"));
  await assert.rejects(model.handle(request({ ...body, functions: [{ name: "text2image" }] })),
    codeIs("invalid_cli_model_request"));
  const response = await model.handle(request(body));
  assert.equal(response.choices[0].message.content, "Done");
  assert.ok(!JSON.stringify(response).includes(key));
  assert.equal(generation.length, 1);
  assert.equal(generation[0].model, "GigaChat-2");
  assert.equal(generation[0].max_tokens, 4096);
  assert.equal(generation[0].stream, false);
  assert.equal(generation[0].messages[1].attachments, undefined);
  assert.deepEqual(rateKeys, ["cli-model:minute:owner", "cli-model:day:owner", "cli-model:global:day"]);
});
