"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { ArrowDown, ArrowUpRight, ChevronDown, Menu, X } from "lucide-react";
import { LanguageSwitcher, useLocale } from "@/components/site/LocaleProvider";
import { menuGroups } from "@/lib/landing/content";

export function Logo({ onNavigate }) {
  const { t } = useLocale();
  return <Link href="/" onClick={onNavigate} className="blot-logo" aria-label={t("Blot home")}><img src="/blot/logo-ink.png" width="126" height="24" alt="Blot Agent" className="blot-logo-ink" /><img src="/blot/logo-paper.png" width="126" height="24" alt="" className="blot-logo-paper" /></Link>;
}

export function Navigation() {
  const { t } = useLocale();
  const [open, setOpen] = useState(null);
  const [mobile, setMobile] = useState(false);
  const ref = useRef(null);
  const menuRef = useRef(null);

  useEffect(() => {
    if (!mobile) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    menuRef.current?.querySelector("button, a")?.focus();
    return () => { document.body.style.overflow = previous; };
  }, [mobile]);

  useEffect(() => {
    const close = (event) => { if (!ref.current?.contains(event.target)) setOpen(null); };
    const keyboard = (event) => {
      if (event.key === "Escape") { setOpen(null); setMobile(false); ref.current?.querySelector(".blot-mobile-toggle")?.focus(); }
      if (event.key !== "Tab" || !mobile) return;
      const nodes = [...menuRef.current.querySelectorAll("a, button")].filter((el) => el.getClientRects().length);
      const first = nodes[0], last = nodes.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", keyboard);
    return () => { document.removeEventListener("pointerdown", close); document.removeEventListener("keydown", keyboard); };
  }, [mobile]);

  const closeMenus = () => { setMobile(false); setOpen(null); };

  return (
    <header className="blot-header" ref={ref}>
      <div className="blot-header-inner">
        <Logo />
        <nav className="blot-desktop-nav" aria-label={t("Main navigation")}>
          {Object.entries(menuGroups).map(([name, links]) => <div className="blot-nav-group" key={name} onMouseEnter={() => setOpen(name)} onMouseLeave={() => setOpen(null)}>
            <button aria-expanded={open === name} aria-controls={`blot-menu-${name}`} onClick={() => setOpen(name)}>{t(name)}<ChevronDown size={12} /></button>
            <AnimatePresence>{open === name && <motion.div id={`blot-menu-${name}`} className="blot-nav-popover" initial={{ opacity: 0, y: -5 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -5 }} transition={{ duration: 0.16 }}>
              {links.map(([label, href]) => <Link href={href} key={label} onClick={closeMenus}>{t(label)}<ArrowUpRight size={14} /></Link>)}
            </motion.div>}</AnimatePresence>
          </div>)}
          <Link href="/#pricing">{t("Pricing")}</Link><Link href="/changelog">{t("News")}</Link>
        </nav>
        <LanguageSwitcher /><div className="blot-header-actions"><Link className="blot-button blot-button-small blot-button-soft" href="/login">{t("Sign in")}</Link><Link className="blot-button blot-button-small" href="/#download">{t("Download")}<ArrowDown size={14} /></Link></div>
        <button className="blot-mobile-toggle" aria-label={t("Open menu")} aria-expanded={mobile} aria-controls="blot-mobile-menu" onClick={() => setMobile(true)}><Menu size={22} /></button>
      </div>
      <AnimatePresence>{mobile && <motion.div className="blot-mobile-menu" id="blot-mobile-menu" role="dialog" aria-modal="true" aria-label={t("Navigation menu")} ref={menuRef} initial={{ opacity: 0, y: -12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -12 }} transition={{ duration: 0.24 }}>
        <div className="blot-mobile-bar"><Logo onNavigate={closeMenus} /><LanguageSwitcher /><button aria-label={t("Close menu")} onClick={closeMenus}><X size={22} /></button></div>
        <nav aria-label={t("Mobile navigation")}>
          {Object.entries(menuGroups).map(([name, links]) => <div key={name} className="blot-mobile-group"><button onClick={() => setOpen(open === name ? null : name)} aria-expanded={open === name}>{t(name)}<ChevronDown size={18} /></button>
            {open === name && <div className="blot-mobile-submenu">{links.map(([label, href]) => <Link key={label} href={href} onClick={closeMenus}>{t(label)}</Link>)}</div>}
          </div>)}
          <Link href="/#pricing" onClick={closeMenus}>{t("Pricing")}</Link><Link href="/changelog" onClick={closeMenus}>{t("News")}</Link><Link href="/login" onClick={closeMenus}>{t("Sign in")}</Link>
        </nav>
        <div className="blot-mobile-bottom"><Link className="blot-button" href="/#download" onClick={closeMenus}>{t("Download")}</Link><div><Link href="/contact">{t("Contact")}</Link><Link href="/privacy">{t("Privacy")}</Link><Link href="/changelog">{t("News")}</Link></div></div>
      </motion.div>}</AnimatePresence>
    </header>
  );
}
