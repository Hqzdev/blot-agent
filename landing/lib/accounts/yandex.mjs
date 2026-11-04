import { AuthError } from "../auth/errors.mjs";
import { OAuthHTTPClient } from "../auth/oauth-http.mjs";
import { emailAddress } from "./security.mjs";

export class YandexAccountIdentity {
  #audience;
  #http;
  constructor(audience, http = new OAuthHTTPClient()) { this.#audience = audience; this.#http = http; }

  async verify(accessToken) {
    if (!this.#audience) throw new AuthError("yandex_unconfigured", 503);
    if (typeof accessToken !== "string" || !/^[A-Za-z0-9._~-]{1,16384}$/.test(accessToken)) throw new AuthError("yandex_identity_invalid", 401);
    const profile = await this.#http.json("https://login.yandex.ru/info?format=json", {
      headers: { "Authorization": "OAuth " + accessToken, "Accept": "application/json" },
    }, "yandex_unavailable");
    try {
      if (profile.client_id !== this.#audience || typeof profile.id !== "string" || !profile.id || profile.id.length > 255) throw new Error();
      const email = emailAddress(profile.default_email);
      const name = typeof profile.real_name === "string" && profile.real_name.trim() ? profile.real_name.trim().slice(0, 200) : email;
      return { subject: profile.id, email, name };
    } catch { throw new AuthError("yandex_identity_invalid", 401); }
  }
}
