import { isCliCallback } from "./cli-callback.mjs";

/** Owns one in-flight app handoff, including React's repeated effect calls. */
export class AppHandoff {
  #prepare;
  #navigate;
  #pending = null;

  constructor({ prepare, navigate }) { this.#prepare = prepare; this.#navigate = navigate; }

  open({ query, platform }) {
    if (this.#pending) return this.#pending;
    this.#pending = this.#open(query, platform).finally(() => { this.#pending = null; });
    return this.#pending;
  }

  async #open(query, platform) {
    if (!query) {
      if (!["ios", "macos"].includes(platform)) throw new Error("invalid_app_request");
      const callbackURL = `blot-agent-${platform}:/oauth/start`;
      this.#navigate(callbackURL);
      return { callbackURL };
    }
    const result = await this.#prepare(query);
    const attempt = new URLSearchParams(query);
    const callback = new URL(result.callbackURL);
    const expected = new URL(attempt.get("redirect_uri"));
    const web = attempt.get("client_id") === "blot-web";
    const cli = attempt.get("client_id") === "blot-cli";
    const validDestination = cli
      ? callback.origin === expected.origin && isCliCallback("blot-cli", expected.href)
      : web
        ? callback.origin === expected.origin && (callback.protocol === "https:" || (callback.protocol === "http:" && ["localhost", "127.0.0.1"].includes(callback.hostname)))
        : !callback.host && /^blot-agent-(ios|macos):$/.test(callback.protocol);
    if (!validDestination || callback.protocol !== expected.protocol || callback.pathname !== expected.pathname
        || callback.hash || callback.username || callback.password
        || callback.searchParams.getAll("state").length !== 1
        || callback.searchParams.get("state") !== attempt.get("state")
        || callback.searchParams.getAll("code").length !== 1
        || !/^[A-Za-z0-9_-]{43}$/.test(callback.searchParams.get("code"))
        || [...callback.searchParams.keys()].some(key => !["code", "state"].includes(key))
        || !(Date.parse(result.expiresAt) > Date.now())) throw new Error("invalid_auth_response");
    this.#navigate(result.callbackURL);
    return result;
  }
}
