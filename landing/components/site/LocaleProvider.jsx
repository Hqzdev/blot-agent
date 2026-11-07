"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { russian } from "@/lib/landing/russian";

const LocaleContext = createContext(null);
const STORAGE_KEY = "blot-language";

export function LocaleProvider({ children }) {
  const [language, setLanguage] = useState("ru");
  useEffect(() => {
    function sync() {
      let saved;
      try { saved = localStorage.getItem(STORAGE_KEY); } catch {}
      setLanguage(["ru", "en"].includes(saved) ? saved : navigator.language.toLowerCase().startsWith("ru") ? "ru" : "en");
    }
    sync();
    const storage = event => { if (event.key === STORAGE_KEY || event.key === null) sync(); };
    window.addEventListener("storage", storage);
    return () => window.removeEventListener("storage", storage);
  }, []);
  useEffect(() => { document.documentElement.lang = language; }, [language]);
  function changeLanguage(value) {
    setLanguage(value);
    try { localStorage.setItem(STORAGE_KEY, value); } catch {}
  }
  const t = text => language === "ru" ? russian[text] ?? text : text;
  return <LocaleContext.Provider value={{ language, changeLanguage, t }}>{children}</LocaleContext.Provider>;
}

export function useLocale() { return useContext(LocaleContext); }

export function LanguageSwitcher() {
  const { language, changeLanguage } = useLocale();
  return <div className="site-language" role="group" aria-label={language === "ru" ? "Язык сайта" : "Website language"}>
    {["ru", "en"].map(value => <button key={value} type="button" lang={value} aria-pressed={language === value} onClick={() => changeLanguage(value)}>{value.toUpperCase()}</button>)}
  </div>;
}

export function SiteText({ children }) {
  const { t } = useLocale();
  return t(children);
}
