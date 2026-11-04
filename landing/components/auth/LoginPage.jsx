"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowUpRight, Check, LoaderCircle, Mail } from "lucide-react";
import { AppHandoff } from "@/lib/auth/app-handoff.mjs";
import "./login.css";

const ERRORS = {
  wrong_credentials: "Почта или пароль не совпадают.", invalid_email: "Проверьте адрес электронной почты.",
  invalid_password: "Пароль должен содержать от 8 до 128 символов.", invalid_name: "Укажите ваше имя.",
  email_unverified: "Сначала подтвердите почту. Можно снова зарегистрироваться с этим адресом, чтобы получить код.",
  code_expired_or_invalid: "Код не подошёл или истёк. Запросите новый код.", rate_limited: "Слишком много попыток. Повторите немного позже.",
  challenge_cooldown: "Письмо уже отправлено. Подождите перед повторной отправкой.",
  auth_service_unconfigured: "Сервис входа ещё не подключён. Попробуйте позже.",
  auth_service_unavailable: "Не удалось связаться с сервисом входа. Проверьте связь и повторите.",
  service_unavailable: "Сервис временно недоступен. Попробуйте позже.", web_session_unconfigured: "Сервис входа ещё не настроен.",
  web_session_expired: "Время входа истекло. Войдите ещё раз.", session_expired: "Войдите ещё раз, чтобы продолжить.",
  google_unconfigured: "Вход через Google ещё не настроен.", google_failed: "Не удалось войти через Google. Попробуйте ещё раз.",
  google_identity_invalid: "Google не подтвердил этот вход. Попробуйте ещё раз.", google_unavailable: "Google временно недоступен. Попробуйте позже.",
  email_unavailable: "Не удалось отправить письмо. Попробуйте позже.", smtp_unconfigured: "Отправка писем ещё не настроена.",
  google_access_denied: "Вы отменили вход через Google.", google_state_invalid: "Ссылка входа истекла. Попробуйте ещё раз.",
  google_link_required: "Аккаунт с этой почтой уже есть. Войдите по почте и паролю.",
  yandex_unconfigured: "Вход через Яндекс ещё не настроен.", yandex_failed: "Не удалось войти через Яндекс. Попробуйте ещё раз.",
  yandex_identity_invalid: "Яндекс не подтвердил этот вход или не предоставил почту. Попробуйте ещё раз.",
  yandex_unavailable: "Яндекс временно недоступен. Попробуйте позже.", yandex_access_denied: "Вы отменили вход через Яндекс.",
  yandex_state_invalid: "Ссылка входа истекла. Попробуйте ещё раз.",
  yandex_link_required: "Аккаунт с этой почтой уже есть. Используйте прежний способ входа.",
  invalid_app_request: "Ссылка из приложения некорректна. Начните вход заново в Blot.",
  browser_authorization_invalid: "Ссылка для приложения истекла. Начните вход заново в Blot.",
};

async function request(path, body) {
  const response = await fetch(path, { method: body === undefined ? "GET" : "POST", cache: "no-store",
    headers: body === undefined ? {} : { "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const value = await response.json();
  if (!response.ok) throw new Error(value.code || "auth_service_unavailable");
  return value;
}

export function LoginPage({ attempt, query, initialMode, initialError, googleEnabled, yandexEnabled }) {
  const [mode, setMode] = useState(initialMode);
  const [account, setAccount] = useState(null);
  const [checking, setChecking] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(initialError);
  const [notice, setNotice] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [platform, setPlatform] = useState("macos");
  const errorRef = useRef(null);
  const autoHandoff = useRef(null);
  const handoff = useRef(null);
  if (!handoff.current) handoff.current = new AppHandoff({
    prepare: query => request("/api/auth/app", { query }),
    navigate: url => window.location.assign(url),
  });

  useEffect(() => {
    let active = true;
    if (/iPhone|iPad|iPod/.test(navigator.userAgent)) setPlatform("ios");
    request("/api/auth/session").then(value => { if (active) setAccount(value.account); })
      .catch(() => {}).finally(() => { if (active) setChecking(false); });
    return () => { active = false; };
  }, []);
  useEffect(() => { if (error) errorRef.current?.focus(); }, [error]);

  const prepareApp = useCallback(async () => {
    setBusy(true); setError("");
    try { await handoff.current.open({ query, platform }); }
    catch (failure) { setError(failure.message); }
    finally { setBusy(false); }
  }, [query, platform]);
  useEffect(() => {
    if (!account || checking || error) return;
    const key = `${account.id}:${query || platform}`;
    if (autoHandoff.current === key) return;
    autoHandoff.current = key;
    void prepareApp();
  }, [account, checking, error, query, platform, prepareApp]);
  async function submit(event) {
    event.preventDefault(); setBusy(true); setError(""); setNotice("");
    try {
      const value = await request("/api/auth/session", { action: mode, email, password, name, code });
      if (value.verificationRequired) { setMode("verify"); setNotice("Отправили код на вашу почту."); }
      if (value.authenticated) {
        setPassword(""); setCode("");
        const current = await request("/api/auth/session"); setAccount(current.account);
      }
      if (value.resetRequested) { setMode("reset"); setNotice("Если адрес зарегистрирован, письмо с кодом восстановления отправлено."); }
      if (value.passwordChanged) { setMode("login"); setPassword(""); setCode(""); setNotice("Пароль изменён. Теперь можно войти."); }
    } catch (failure) { setError(failure.message); }
    finally { setBusy(false); }
  }
  function changeMode(next) { setMode(next); setError(""); setNotice(""); setCode(""); setPassword(""); }
  async function logout() {
    setBusy(true); setError("");
    try { await request("/api/auth/session", { action: "logout" }); setAccount(null); autoHandoff.current = null; }
    catch (failure) { setError(failure.message); }
    finally { setBusy(false); }
  }

  const signingUp = mode === "register";
  const title = account ? "Можно возвращаться к работе." : mode === "verify" ? "Проверьте почту." : mode === "recover" || mode === "reset" ? "Вернём доступ." : signingUp ? "Ваша команда начинается здесь." : "С возвращением.";
  const primary = { login: "Войти", register: "Создать аккаунт", verify: "Подтвердить почту", recover: "Получить код", reset: "Изменить пароль" }[mode];
  const codeInput = mode === "verify" || mode === "reset";

  return <main id="main-content" className="auth-page" lang="ru">
    <section className="auth-story" aria-labelledby="auth-title">
      <span className="auth-eyebrow">Ваше рабочее пространство</span>
      <h1 id="auth-title">{title}</h1>
      <p>{account ? "Вход выполнен. Возвращаемся в Blot…" : "Один аккаунт для ваших чатов, агентов и задач на Mac и iPhone."}</p>
      <div className="auth-pet" aria-hidden="true"><img src="/blot/logo-ink.png" alt="" className="auth-pet-light" /><img src="/blot/logo-paper.png" alt="" className="auth-pet-dark" /></div>
      <Link href="/" className="auth-back">Узнать больше о Blot <ArrowUpRight size={15} /></Link>
    </section>
    <section className="auth-panel" aria-label={account ? "Открыть приложение" : "Вход в аккаунт"} aria-busy={busy || checking}>
      {checking ? <div className="auth-checking" role="status"><LoaderCircle size={20} className="auth-spinner" /> Проверяем вход…</div> : account ? <>
        <div className="auth-account"><span className="auth-check"><Check size={20} /></span><div><strong>{account.name}</strong><span>{account.email}</span></div></div>
        <h2>Возвращаемся в Blot…</h2>
        <p className="auth-description" role="status">{attempt ? `Вход в Blot для ${attempt.clientID === "blot-ios" ? "iPhone" : "Mac"} продолжится автоматически.` : "Открываем приложение на вашем устройстве."}</p>
        {!attempt && <div className="auth-platforms" role="group" aria-label="Устройство"><button type="button" aria-pressed={platform === "macos"} onClick={() => setPlatform("macos")}>Mac</button><button type="button" aria-pressed={platform === "ios"} onClick={() => setPlatform("ios")}>iPhone</button></div>}
        <button className="auth-primary" disabled={busy} onClick={prepareApp}>{busy ? <><LoaderCircle className="auth-spinner" size={18} /> Открываем Blot…</> : <>Открыть ещё раз <ArrowUpRight size={17} /></>}</button>
        <p className="auth-help">Если браузер запросит разрешение открыть Blot, подтвердите его. Повторное открытие нужно только если автоматический переход заблокирован.</p>
        <Link className="auth-download" href="/beta">Скачать Blot</Link>
        <button type="button" className="auth-text-button" disabled={busy} onClick={logout}>Войти в другой аккаунт</button>
      </> : <>
        <div className="auth-heading"><h2>{mode === "verify" ? "Подтверждение почты" : mode === "recover" || mode === "reset" ? "Восстановление доступа" : signingUp ? "Регистрация" : "Войти в Blot"}</h2><p>{codeInput ? `Введите код из письма для ${email}.` : ["recover", "reset"].includes(mode) ? "Восстановите доступ по электронной почте." : googleEnabled || yandexEnabled ? "Выберите способ входа или используйте почту." : "Используйте электронную почту для входа."}</p></div>
        {(googleEnabled || yandexEnabled) && ["login", "register"].includes(mode) && <>
          <div className="auth-providers">
            {googleEnabled && <a className="auth-provider" href={`/auth/google/start${query ? "?" + query : ""}`}><svg viewBox="0 0 24 24" width="19" height="19" aria-hidden="true"><path fill="currentColor" d="M21.6 12.23c0-.71-.06-1.39-.18-2.05H12v3.88h5.38a4.6 4.6 0 0 1-2 3.02v2.51h3.24c1.9-1.75 2.98-4.33 2.98-7.36ZM12 22c2.7 0 4.96-.9 6.62-2.41l-3.24-2.51c-.9.6-2.05.96-3.38.96-2.6 0-4.8-1.76-5.59-4.12H3.07v2.59A10 10 0 0 0 12 22ZM6.41 13.92A6 6 0 0 1 6.1 12c0-.67.11-1.32.31-1.92V7.49H3.07A10 10 0 0 0 2 12c0 1.61.39 3.14 1.07 4.51l3.34-2.59ZM12 5.96c1.47 0 2.79.51 3.83 1.51l2.87-2.87A9.6 9.6 0 0 0 12 2a10 10 0 0 0-8.93 5.49l3.34 2.59C7.2 7.72 9.4 5.96 12 5.96Z" /></svg>Продолжить с Google</a>}
            {yandexEnabled && <a className="auth-provider" href={`/auth/yandex/start${query ? "?" + query : ""}`}><svg viewBox="0 0 24 24" width="19" height="19" aria-hidden="true"><rect width="24" height="24" rx="12" fill="#FC3F1D" /><path d="M13.6912 19.212H16.1982V4.812H12.5516C8.8843 4.812 6.9574 6.6975 6.9574 9.4739C6.9574 11.6909 8.0141 12.9962 9.8995 14.3429L6.6259 19.212H9.3401L12.9867 13.7628L11.7228 12.9133C10.1896 11.8773 9.4437 11.0693 9.4437 9.3288C9.4437 7.5956 10.5211 6.7596 12.5723 6.7596H13.6912V19.212Z" fill="white" /></svg>Войти с Яндекс ID</a>}
          </div>
          <div className="auth-divider"><span>или по почте</span></div>
        </>}
        <form onSubmit={submit}>
          {signingUp && <label>Ваше имя<input name="name" autoComplete="name" required maxLength={200} value={name} onChange={event => setName(event.target.value)} disabled={busy} /></label>}
          <label>Электронная почта<input name="email" type="email" autoComplete="email" required maxLength={254} value={email} onChange={event => setEmail(event.target.value)} disabled={busy} /></label>
          {codeInput && <label>Код из письма<input className="auth-code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" minLength={6} maxLength={6} required value={code} onChange={event => setCode(event.target.value.replace(/\D/g, ""))} disabled={busy} /></label>}
          {["login", "register", "reset"].includes(mode) && <label>{mode === "reset" ? "Новый пароль" : "Пароль"}<input name="password" type="password" autoComplete={mode === "login" ? "current-password" : "new-password"} required minLength={8} maxLength={128} value={password} onChange={event => setPassword(event.target.value)} disabled={busy} />{signingUp && <span className="auth-hint">Не меньше 8 символов.</span>}</label>}
          {mode === "login" && <button type="button" className="auth-forgot" onClick={() => changeMode("recover")}>Не помню пароль</button>}
          <button className="auth-primary" type="submit" disabled={busy}>{busy ? <><LoaderCircle className="auth-spinner" size={18} /> Подождите…</> : <><Mail size={17} />{primary}</>}</button>
        </form>
        {mode === "verify" ? <button type="button" className="auth-text-button" onClick={() => changeMode("register")}>Запросить новый код</button> : <p className="auth-switch">{signingUp ? "Уже есть аккаунт?" : "Ещё нет аккаунта?"} <button type="button" onClick={() => changeMode(signingUp ? "login" : "register")}>{signingUp ? "Войти" : "Создать аккаунт"}</button></p>}
        {["recover", "reset"].includes(mode) && <button className="auth-text-button" type="button" onClick={() => changeMode("login")}>Вернуться ко входу</button>}
        <p className="auth-privacy">Продолжая, вы принимаете <Link href="/privacy">политику конфиденциальности</Link>.</p>
      </>}
      {notice && <p className="auth-notice" role="status">{notice}</p>}
      {error && <p className="auth-error" role="alert" tabIndex={-1} ref={errorRef}>{ERRORS[error] || "Не удалось продолжить. Проверьте данные и повторите."}</p>}
    </section>
  </main>;
}
