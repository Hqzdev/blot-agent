import { createHmac } from "node:crypto";
import { AuthError } from "../auth/errors.mjs";
import { accountDatabase } from "./database.mjs";
import { AccountRateLimiter, EmailCodeSecurity, PasswordHasher, emailAddress } from "./security.mjs";
import { AccountEmailSender } from "./email.mjs";
import { AccountEmailChallenges } from "./challenges.mjs";
import { AccountSessions } from "./sessions.mjs";
import { EmailSignIn } from "./email-sign-in.mjs";
import { Accounts } from "./accounts.mjs";
import { BrowserAuthorizationCodes } from "./browser-codes.mjs";
import { GoogleAccountIdentity } from "./google.mjs";
import { YandexAccountIdentity } from "./yandex.mjs";
import { ProviderAccounts } from "./provider-accounts.mjs";

export class AccountService {
  #database;
  #rates;
  #accounts;
  #sessions;
  #browser;
  #google;
  #yandex;
  #emailSignIn;
  constructor({ database, email, challengeSecret, googleIdentity, yandexIdentity }) {
    this.#database = database;
    this.#rates = new AccountRateLimiter(database);
    this.#sessions = new AccountSessions(database);
    const challenges = new AccountEmailChallenges({ database, security: new EmailCodeSecurity(challengeSecret), email, rates: this.#rates });
    this.#emailSignIn = new EmailSignIn(database, challenges, this.#sessions);
    this.#accounts = new Accounts({ database, passwords: new PasswordHasher(), challenges, sessions: this.#sessions });
    this.#browser = new BrowserAuthorizationCodes(database, this.#sessions);
    this.#google = new ProviderAccounts(database, googleIdentity, this.#sessions, "google");
    this.#yandex = new ProviderAccounts(database, yandexIdentity, this.#sessions, "yandex");
  }
  async request(path, { body = {}, accessToken, method = "POST", clientIP } = {}) {
    await this.#database.initialize();
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new AuthError("invalid_request");
    if (method === "GET" && path === "me") return this.#accounts.profile(await this.#sessions.require(accessToken));
    if (method !== "POST") throw new AuthError("not_found", 404);
    if (clientIP) await this.#rates.check(`ip:${path}:${clientIP}`, 60, 900);
    if (["register", "login", "verify", "password/request", "password/reset", "email/request", "email/verify"].includes(path)) {
      const email = emailAddress(body.email);
      await this.#rates.check(`address:${path}:${email}`, path === "password/request" ? 10 : 30, 900);
      if (path === "password/request") await this.#rates.check(`reset-email:${email}`, 1, 60);
    }
    switch (path) {
      case "email/request": return this.#emailSignIn.request(body);
      case "email/verify": return this.#emailSignIn.verify(body);
      case "register": return this.#accounts.register(body);
      case "verify": return this.#accounts.verify(body);
      case "login": return this.#accounts.login(body);
      case "password/request": return this.#accounts.requestReset(body);
      case "password/reset": return this.#accounts.reset(body);
      case "refresh": return this.#sessions.refresh(body.refreshToken);
      case "browser/code": return this.#browser.issue(body, accessToken);
      case "browser/token": return this.#browser.exchange(body);
      case "google/login": return this.#google.login(body.idToken, body.nonce);
      case "yandex/login": return this.#yandex.login(body.accessToken);
      case "logout": case "revoke-sessions":
        await this.#sessions.logout(await this.#sessions.require(accessToken), path === "revoke-sessions");
        return null;
      default: throw new AuthError("not_found", 404);
    }
  }
  async authenticate(accessToken) {
    await this.#database.initialize();
    return this.#sessions.require(accessToken);
  }
}

let service;
export function localAccountService(database = accountDatabase()) {
  if (!service) {
    const secret = process.env.BLOT_AUTH_CHALLENGE_SECRET || process.env.BLOT_WEB_SESSION_SECRET || process.env.BLOT_GOOGLE_WEB_CLIENT_SECRET || process.env.BLOT_YANDEX_WEB_CLIENT_SECRET;
    if (!secret || secret.length < 24) throw new AuthError("web_session_unconfigured", 503);
    service = new AccountService({ database, email: new AccountEmailSender(),
      challengeSecret: createHmac("sha256", secret).update("BLOT-EMAIL-CODE-1").digest("hex"),
      googleIdentity: new GoogleAccountIdentity(process.env.BLOT_GOOGLE_WEB_CLIENT_ID),
      yandexIdentity: new YandexAccountIdentity(process.env.BLOT_YANDEX_WEB_CLIENT_ID) });
  }
  return service;
}
