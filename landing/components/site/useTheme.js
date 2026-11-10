"use client";

import { useLayoutEffect, useState } from "react";
import { readThemePreference, THEME_STORAGE_KEY } from "@/lib/landing/theme";

export function useTheme() {
  const [theme, setTheme] = useState("system");
  useLayoutEffect(() => {
    const system = window.matchMedia("(prefers-color-scheme: dark)");
    const sync = () => {
      const preference = readThemePreference();
      document.documentElement.dataset.theme = preference === "system" ? system.matches ? "dark" : "light" : preference;
      setTheme(preference);
    };
    const storage = event => { if (event.key === THEME_STORAGE_KEY || event.key === null) sync(); };
    sync();
    system.addEventListener("change", sync);
    window.addEventListener("storage", storage);
    window.addEventListener("blot-theme-change", sync);
    return () => {
      system.removeEventListener("change", sync);
      window.removeEventListener("storage", storage);
      window.removeEventListener("blot-theme-change", sync);
    };
  }, []);

  function changeTheme(value) {
    try { localStorage.setItem(THEME_STORAGE_KEY, value); } catch {}
    document.documentElement.dataset.theme = value === "system" ? window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light" : value;
    setTheme(value);
    window.dispatchEvent(new Event("blot-theme-change"));
  }
  return { theme, changeTheme };
}
