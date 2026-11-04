import { LoginPage } from "@/components/auth/LoginPage";
import { nativeAttempt, attemptQuery } from "@/lib/auth/browser-session.mjs";
import { yandexConfiguration } from "@/lib/auth/config.mjs";

export const metadata = { title: "Войти в Blot", robots: { index: false, follow: false }, referrer: "no-referrer" };
export default async function Login({ searchParams }) {
  const values = await searchParams;
  const query = new URLSearchParams();
  const standalone = Object.keys(values).every(key => ["intent", "auth_error"].includes(key));
  for (const [key, value] of Object.entries(values)) {
    if (key === "auth_error" || (standalone && key === "intent")) continue;
    for (const item of Array.isArray(value) ? value : [value]) query.append(key, item);
  }
  let attempt, invalid = false;
  try { attempt = nativeAttempt(query); } catch { invalid = true; }
  const googleEnabled = Boolean(process.env.BLOT_GOOGLE_WEB_CLIENT_ID && process.env.BLOT_GOOGLE_WEB_CLIENT_SECRET && process.env.BLOT_GOOGLE_WEB_REDIRECT_URI);
  let yandexEnabled = false;
  try { yandexConfiguration(); yandexEnabled = true; } catch {}
  return <LoginPage attempt={attempt || null} query={attemptQuery(attempt)} initialMode={attempt?.intent || (standalone && values.intent === "register" ? "register" : "login")}
    initialError={invalid ? "invalid_app_request" : typeof values.auth_error === "string" ? values.auth_error : ""} googleEnabled={googleEnabled} yandexEnabled={yandexEnabled} />;
}
