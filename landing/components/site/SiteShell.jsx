"use client";

import { MotionConfig } from "motion/react";
import { usePathname } from "next/navigation";
import { Navigation } from "@/components/landing/Navigation";
import { SiteFooter } from "./SiteFooter";
import { LocaleProvider, SiteText } from "./LocaleProvider";
import { useTheme } from "./useTheme";

export function SiteShell({ children }) {
  const { theme, changeTheme } = useTheme();
  const pathname = usePathname();
  const isAuth = pathname === "/login" || pathname === "/register";
  return <LocaleProvider><MotionConfig reducedMotion="user">
    <div className="blot-landing">
      <a className="skip-link" href="#main-content"><SiteText>Skip to content</SiteText></a>
      {!isAuth && <Navigation />}
      {children}
      {!isAuth && <SiteFooter theme={theme} onThemeChange={changeTheme} />}
    </div>
  </MotionConfig></LocaleProvider>;
}
