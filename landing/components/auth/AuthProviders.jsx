import { Mail } from "lucide-react";

export function AuthProviders({ copy, query, onEmail, onUnavailable, googleEnabled, yandexEnabled, registering }) {
  function providerClick(event, enabled, provider) {
    if (!enabled) { event.preventDefault(); onUnavailable(`${provider}_unconfigured`); }
  }
  return <div className="auth-providers">
    <a className="auth-provider" href={`/auth/google/start${query ? "?" + query : ""}`} onClick={event => providerClick(event, googleEnabled, "google")}>
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M21.6 12.23c0-.71-.06-1.39-.18-2.05H12v3.88h5.38a4.6 4.6 0 0 1-2 3.02v2.51h3.24c1.9-1.75 2.98-4.33 2.98-7.36ZM12 22c2.7 0 4.96-.9 6.62-2.41l-3.24-2.51c-.9.6-2.05.96-3.38.96-2.6 0-4.8-1.76-5.59-4.12H3.07v2.59A10 10 0 0 0 12 22ZM6.41 13.92A6 6 0 0 1 6.1 12c0-.67.11-1.32.31-1.92V7.49H3.07A10 10 0 0 0 2 12c0 1.61.39 3.14 1.07 4.51l3.34-2.59ZM12 5.96c1.47 0 2.79.51 3.83 1.51l2.87-2.87A9.6 9.6 0 0 0 12 2a10 10 0 0 0-8.93 5.49l3.34 2.59C7.2 7.72 9.4 5.96 12 5.96Z" /></svg>{copy.google}
    </a>
    <a className="auth-provider" href={`/auth/yandex/start${query ? "?" + query : ""}`} onClick={event => providerClick(event, yandexEnabled, "yandex")}>
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><rect width="24" height="24" rx="12" fill="#FC3F1D" /><path d="M13.6912 19.212H16.1982V4.812H12.5516C8.8843 4.812 6.9574 6.6975 6.9574 9.4739C6.9574 11.6909 8.0141 12.9962 9.8995 14.3429L6.6259 19.212H9.3401L12.9867 13.7628L11.7228 12.9133C10.1896 11.8773 9.4437 11.0693 9.4437 9.3288C9.4437 7.5956 10.5211 6.7596 12.5723 6.7596H13.6912V19.212Z" fill="white" /></svg>{copy.yandex}
    </a>
    <button className="auth-primary" type="button" onClick={onEmail}><Mail size={19} />{registering ? copy.registerEmail : copy.emailButton}</button>
  </div>;
}
