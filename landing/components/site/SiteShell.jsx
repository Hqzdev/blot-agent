"use client";

import { MotionConfig } from "motion/react";
import { Navigation } from "@/components/landing/Navigation";
import { SiteFooter } from "./SiteFooter";
import { useTheme } from "./useTheme";

export function SiteShell({ children }) {
  const { dark, toggleTheme } = useTheme();
  return <MotionConfig reducedMotion="user">
    <div className="blot-landing">
      <Navigation />
      {children}
      <SiteFooter dark={dark} onThemeChange={toggleTheme} />
    </div>
  </MotionConfig>;
}
