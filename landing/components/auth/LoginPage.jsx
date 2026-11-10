"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowLeft, ArrowUpRight, Check, LoaderCircle } from "lucide-react";
import { AppHandoff } from "@/lib/auth/app-handoff.mjs";
import { loginCopy, loginErrors } from "@/lib/auth/login-copy";
import { useLocale } from "@/components/site/LocaleProvider";
import { AuthProviders } from "./AuthProviders";
import "./login.css";

async function request(path, body) {
  const response = await fetch(path, { method: body === undefined ? "GET" : "POST", cache: "no-store",
    headers: body === undefined ? {} : { "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const value = await response.json();
  if (!response.ok) throw new Error(value.code || "auth_service_unavailable");
  return value;
}

export function LoginPage({ attempt, query, initialMode, initialError, googleEnabled, yandexEnabled }) {
  const { language } = useLocale();
  const copy = loginCopy[language];
  const [intent, setIntent] = useState(initialMode);
  const [step, setStep] = useState("providers");
  const [account, setAccount] = useState(null);
  const [checking, setChecking] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(initialError);
  const [notice, setNotice] = useState("");
  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [retryAt, setRetryAt] = useState(0);
  const [remaining, setRemaining] = useState(0);
  const [platform, setPlatform] = useState("macos");
  const errorRef = useRef(null);
  const inputRef = useRef(null);
  const autoHandoff = useRef(null);
  const handoff = useRef(null);
  if (!handoff.current) handoff.current = new AppHandoff({ prepare: query => request("/api/auth/app", { query }), navigate: url => window.location.assign(url) });

  useEffect(() => {
    let active = true;
    if (/iPhone|iPad|iPod/.test(navigator.userAgent)) setPlatform("ios");
    request("/api/auth/session").then(value => { if (active) setAccount(value.account); })
      .catch(() => {}).finally(() => { if (active) setChecking(false); });
    return () => { active = false; };
  }, []);
  useEffect(() => { if (error) errorRef.current?.focus(); }, [error]);
  useEffect(() => { inputRef.current?.focus(); }, [step]);
  useEffect(() => {
    if (!retryAt) return;
    const update = () => setRemaining(Math.max(0, Math.ceil((retryAt - Date.now()) / 1000)));
    update();
    const timer = setInterval(update, 1000);
    return () => clearInterval(timer);
  }, [retryAt]);

  const prepareApp = useCallback(async () => {
    setBusy(true); setError("");
    try { await handoff.current.open({ query, platform }); }
    catch (failure) { setError(failure.message); }
    finally { setBusy(false); }
  }, [query, platform]);
  useEffect(() => {
    if (!attempt || !account || checking || error) return;
    const key = `${account.id}:${query}`;
    if (autoHandoff.current === key) return;
    autoHandoff.current = key;
    void prepareApp();
  }, [account, attempt, checking, error, query, prepareApp]);

  async function sendCode() {
    await request("/api/auth/session", { action: "email/request", intent, email: email.trim(), name });
    setStep("code"); setCode(""); setNotice(intent === "register" ? "registrationSent" : "codeSent"); setRetryAt(Date.now() + 60_000);
  }
  async function submit(event) {
    event.preventDefault(); setBusy(true); setError(""); setNotice("");
    try {
      if (step === "email") await sendCode();
      else {
        await request("/api/auth/session", { action: "email/verify", email: email.trim(), code });
        const current = await request("/api/auth/session"); setAccount(current.account); setCode("");
      }
    } catch (failure) { setError(failure.message); }
    finally { setBusy(false); }
  }
  async function resend() {
    setBusy(true); setError(""); setNotice("");
    try { await sendCode(); } catch (failure) { setError(failure.message); }
    finally { setBusy(false); }
  }
  function changeStep(next) { setStep(next); setError(""); setNotice(""); setCode(""); }
  function changeIntent() { setIntent(intent === "register" ? "login" : "register"); changeStep("providers"); }
  async function logout() {
    setBusy(true); setError("");
    try { await request("/api/auth/session", { action: "logout" }); setAccount(null); autoHandoff.current = null; changeStep("providers"); }
    catch (failure) { setError(failure.message); }
    finally { setBusy(false); }
  }
  const registering = intent === "register";
  const title = account ? copy.signedIn : step === "code" ? copy.verify : registering ? copy.register : copy.login;
  return <main id="main-content" className="auth-page" lang={language}>
    <section className="auth-panel" aria-labelledby="auth-title" aria-busy={busy || checking}>
      {checking ? <div className="auth-checking" role="status"><LoaderCircle size={20} className="auth-spinner" />{copy.checking}</div> : <>
        <div className="auth-heading"><h1 id="auth-title">{title}</h1><p>{account ? attempt ? copy.nativeDescription : copy.accountDescription : step === "code" ? <>{copy.codeDescription} <strong>{email.trim()}</strong>. {copy.codeHint}</> : step === "providers" ? copy.choose : null}</p></div>
        {account ? <>
          <div className="auth-account"><span className="auth-check"><Check size={20} /></span><div><strong>{account.name}</strong><span>{account.email}</span></div></div>
          {!attempt && <div className="auth-platforms" role="group" aria-label={copy.device}><button type="button" aria-pressed={platform === "macos"} onClick={() => setPlatform("macos")}>Mac</button><button type="button" aria-pressed={platform === "ios"} onClick={() => setPlatform("ios")}>iPhone</button></div>}
          <button className="auth-primary" disabled={busy} onClick={prepareApp}>{busy ? <><LoaderCircle className="auth-spinner" size={18} />{copy.opening}</> : <>{attempt ? copy.again : copy.open}<ArrowUpRight size={17} /></>}</button>
          <p className="auth-help">{copy.openHelp}</p><Link className="auth-download" href="/beta">{copy.download}</Link>
          <button type="button" className="auth-text-button" disabled={busy} onClick={logout}>{copy.other}</button>
        </> : <>
          {step === "providers" ? <AuthProviders copy={copy} query={query} registering={registering} googleEnabled={googleEnabled} yandexEnabled={yandexEnabled} onEmail={() => changeStep("email")} onUnavailable={setError} /> : <>
            <form onSubmit={submit}>
              {step === "email" ? <>
                {registering && <label>{copy.name}<input ref={inputRef} name="name" autoComplete="name" required maxLength={200} value={name} onChange={event => setName(event.target.value)} disabled={busy} /></label>}
                <label>{copy.email}<input ref={registering ? null : inputRef} name="email" type="email" autoComplete="email" autoCapitalize="none" spellCheck={false} required maxLength={254} value={email} onChange={event => setEmail(event.target.value)} disabled={busy} /></label>
              </> : <label>{copy.code}<input ref={inputRef} className="auth-code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" minLength={6} maxLength={6} required value={code} onChange={event => setCode(event.target.value.replace(/\D/g, ""))} disabled={busy} /></label>}
              <button className="auth-primary" type="submit" disabled={busy}>{busy ? <><LoaderCircle className="auth-spinner" size={18} />{copy.wait}</> : step === "code" ? copy.confirm : copy.send}</button>
            </form>
            {step === "code" && <button type="button" className="auth-text-button" disabled={busy || remaining > 0} onClick={resend}>{remaining > 0 ? `${copy.resendIn} ${remaining} ${copy.seconds}` : copy.resend}</button>}
            <button type="button" className="auth-back" disabled={busy} onClick={() => changeStep(step === "code" ? "email" : "providers")}><ArrowLeft size={14} />{step === "code" ? copy.changeEmail : copy.back}</button>
          </>}
          {step !== "code" && <p className="auth-switch">{registering ? copy.hasAccount : copy.noAccount} <button type="button" disabled={busy} onClick={changeIntent}>{registering ? copy.signIn : copy.signUp}</button></p>}
          <p className="auth-privacy">{copy.privacy} <Link href="/privacy">{copy.privacyLink}</Link>.</p>
        </>}
      </>}
      {notice && <p className="auth-notice" role="status">{copy[notice]}</p>}
      {error && <p className="auth-error" role="alert" tabIndex={-1} ref={errorRef}>{loginErrors[error]?.[language === "ru" ? 0 : 1] || copy.unknown}</p>}
    </section>
  </main>;
}
