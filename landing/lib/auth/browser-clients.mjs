import { AuthError } from "./errors.mjs";

export function browserClients() {
  const clients = { "blot-ios": "blot-agent-ios:/oauth/account", "blot-macos": "blot-agent-macos:/oauth/account" };
  const value = process.env.BLOT_WEB_APP_URL;
  if (value) {
    let url;
    try { url = new URL(value); } catch { throw new AuthError("auth_service_unconfigured", 503); }
    if (url.username || url.password || url.search || url.hash || !["", "/", "/app", "/app/"].includes(url.pathname)
        || !(url.protocol === "https:" || (url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname)))) {
      throw new AuthError("auth_service_unconfigured", 503);
    }
    clients["blot-web"] = new URL(`${url.pathname.startsWith("/app") ? "/app" : ""}/api/auth/blot/callback`, url).href;
  }
  return clients;
}

export function websiteLoginDestination(values) {
  if (Object.keys(values).some(key => !["intent", "auth_error"].includes(key)) || values.auth_error) return null;
  const callback = browserClients()["blot-web"];
  if (!callback) return null;
  const target = new URL(callback.replace(/\/callback$/, "/start"));
  if (values.intent === "register") target.searchParams.set("intent", "register");
  return target.href;
}
