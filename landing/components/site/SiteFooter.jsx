"use client";

import Link from "next/link";
import { Moon, Sun } from "lucide-react";
import { Logo } from "@/components/landing/Navigation";
import { footerGroups } from "@/lib/landing/content";

export function SiteFooter({ dark, onThemeChange }) {
  return <footer className="blot-footer">
    <div className="blot-footer-top">
      <div className="blot-footer-brand"><Logo /><button onClick={onThemeChange} className="blot-theme-toggle" aria-label={dark ? "Switch to light mode" : "Switch to dark mode"}>{dark ? <Sun size={18} /> : <Moon size={18} />}</button></div>
      <div className="blot-footer-links">{footerGroups.map(([name, links]) => <div key={name}><h3>{name}</h3><ul>{links.map(([label, href]) => <li key={label}><Link href={href}>{label}</Link></li>)}</ul></div>)}</div>
    </div>
    <div className="blot-footer-bottom">© 2026 Blot</div>
  </footer>;
}
