"use client";

import Link from "next/link";
import { Monitor } from "lucide-react";
import { useLocale } from "./LocaleProvider";
import { Logo } from "@/components/landing/Navigation";
import { footerGroups } from "@/lib/landing/content";

export function SiteFooter({ theme, onThemeChange }) {
  const { t } = useLocale();
  return <footer className="blot-footer">
    <div className="blot-footer-top">
      <div className="blot-footer-brand"><Logo /><label className="site-appearance"><Monitor size={16} /><select value={theme} onChange={event => onThemeChange(event.target.value)} aria-label={t("Appearance")}><option value="system">{t("System")}</option><option value="light">{t("Light")}</option><option value="dark">{t("Dark")}</option></select></label></div>
      <div className="blot-footer-links">{footerGroups.map(([name, links]) => <div key={name}><h3>{t(name)}</h3><ul>{links.map(([label, href]) => <li key={label}><Link href={href}>{t(label)}</Link></li>)}</ul></div>)}</div>
    </div>
    <div className="blot-footer-bottom">© 2026 Blot</div>
  </footer>;
}
