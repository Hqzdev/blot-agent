"use client";

import { useLayoutEffect, useRef, useState } from "react";
import { readThemePreference, THEME_STORAGE_KEY } from "@/lib/landing/theme";

export function useTheme() {
  const [dark, setDark] = useState(false);
  const preference = useRef(null);

  useLayoutEffect(() => {
    const systemTheme = window.matchMedia("(prefers-color-scheme: dark)");
    const syncTheme = () => {
      const theme = preference.current ?? (systemTheme.matches ? "dark" : "light");
      document.documentElement.dataset.theme = theme;
      setDark(theme === "dark");
    };
    const syncStorage = event => {
      if (event.key !== THEME_STORAGE_KEY && event.key !== null) return;
      preference.current = readThemePreference();
      syncTheme();
    };

    preference.current = readThemePreference();
    syncTheme();
    systemTheme.addEventListener("change", syncTheme);
    window.addEventListener("storage", syncStorage);
    return () => {
      systemTheme.removeEventListener("change", syncTheme);
      window.removeEventListener("storage", syncStorage);
    };
  }, []);

  function toggleTheme() {
    const theme = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    preference.current = theme;
    document.documentElement.dataset.theme = theme;
    setDark(theme === "dark");
    try { localStorage.setItem(THEME_STORAGE_KEY, theme); } catch {}
  }

  return { dark, toggleTheme };
}
