"use client";

import { useState } from "react";
import { MotionConfig } from "motion/react";
import { Navigation } from "@/components/landing/Navigation";
import { SiteFooter } from "./SiteFooter";

export function SiteShell({ children }) {
  const [dark, setDark] = useState(false);
  return <MotionConfig reducedMotion="user">
    <div className="blot-landing" data-theme={dark ? "dark" : "light"}>
      <Navigation />
      {children}
      <SiteFooter dark={dark} onThemeChange={() => setDark(value => !value)} />
    </div>
  </MotionConfig>;
}
