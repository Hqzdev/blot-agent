import { createHash } from "node:crypto";
import { AuthError } from "./errors.mjs";
import { OAuthHTTPClient } from "./oauth-http.mjs";
import { randomToken, validToken, equal } from "../accounts/security.mjs";

export class YandexAuthorization {
  #config;
  #http;
  constructor(config, http = new OAuthHTTPClient()) { this.#config = config; this.#http = http; }

  start(attempt) {
    const state = randomToken(), verifier = randomToken();
    const url = new URL("https://oauth.yandex.ru/authorize");
    url.search = new URLSearchParams({ client_id: this.#config.clientID, redirect_uri: this.#config.redirectURI,
      response_type: "code", scope: "login:info login:email login:avatar", state, force_confirm: "yes",
      code_challenge: createHash("sha256").update(verifier).digest("base64url"), code_challenge_method: "S256" }).toString();
    return { url, saved: { provider: "yandex", state, verifier, attempt } };
  }

  async exchange(query, saved) {
    if (saved?.provider !== "yandex" || !validToken(saved.state) || !validToken(saved.verifier)
        || query.getAll("state").length !== 1 || !equal(query.get("state"), saved.state)) throw new AuthError("yandex_state_invalid");
    if (query.has("error")) throw new AuthError(query.get("error") === "access_denied" ? "yandex_access_denied" : "yandex_failed");
    if (query.getAll("code").length !== 1 || !query.get("code") || query.get("code").length > 4096) throw new AuthError("yandex_failed");
    const result = await this.#http.json("https://oauth.yandex.ru/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
      body: new URLSearchParams({ grant_type: "authorization_code", code: query.get("code"), client_id: this.#config.clientID,
        client_secret: this.#config.clientSecret, redirect_uri: this.#config.redirectURI, code_verifier: saved.verifier }),
    }, "yandex_failed");
    if (result.error || typeof result.access_token !== "string" || !/^[A-Za-z0-9._~-]{1,16384}$/.test(result.access_token)
        || typeof result.token_type !== "string" || result.token_type.toLowerCase() !== "bearer") throw new AuthError("yandex_failed");
    return result.access_token;
  }
}
