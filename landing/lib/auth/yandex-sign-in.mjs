import { NextResponse } from "next/server.js";
import { accountRequest, AuthError, yandexConfiguration } from "./config.mjs";
import { YandexAuthorization } from "./yandex.mjs";
import { YANDEX_COOKIE, COOKIE_OPTIONS, nativeAttempt, attemptQuery, seal, unseal } from "./browser-session.mjs";
import { clientIP, setSession, PRIVATE_HEADERS } from "./route-support.mjs";

export class YandexSignIn {
  #configuration;
  #accounts;
  constructor({ configuration = yandexConfiguration, accounts = accountRequest } = {}) {
    this.#configuration = configuration; this.#accounts = accounts;
  }

  start(request) {
    let attempt;
    try {
      attempt = nativeAttempt(new URL(request.url).searchParams);
      const authorization = new YandexAuthorization(this.#configuration());
      const { url, saved } = authorization.start(attempt);
      const response = NextResponse.redirect(url, { headers: PRIVATE_HEADERS });
      response.cookies.set(YANDEX_COOKIE, seal(saved, 600), {
        ...COOKIE_OPTIONS, secure: new URL(request.url).protocol === "https:", maxAge: 600,
      });
      return response;
    } catch (error) { return this.#redirect(request, attempt, error); }
  }

  async callback(request) {
    const saved = unseal(request.cookies.get(YANDEX_COOKIE)?.value);
    let attempt, response;
    try {
      attempt = saved?.attempt ? nativeAttempt(attemptQuery(saved.attempt)) : null;
      const authorization = new YandexAuthorization(this.#configuration());
      const accessToken = await authorization.exchange(new URL(request.url).searchParams, saved);
      const tokens = await this.#accounts("yandex/login", { body: { accessToken }, clientIP: clientIP(request) });
      response = setSession(this.#redirect(request, attempt), tokens, request);
    } catch (error) { response = this.#redirect(request, attempt, error); }
    response.cookies.set(YANDEX_COOKIE, "", { ...COOKIE_OPTIONS, maxAge: 0 });
    return response;
  }

  #redirect(request, attempt, error) {
    const destination = new URL("/login", request.url);
    destination.search = attemptQuery(attempt);
    if (error) destination.searchParams.set("auth_error", error instanceof AuthError ? error.code : "yandex_failed");
    return NextResponse.redirect(destination, { headers: PRIVATE_HEADERS });
  }
}
