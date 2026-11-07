"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "motion/react";
import { ArrowRight, ArrowUpRight, Check, ChevronDown, Download, Laptop, Minus, Plus, Smartphone } from "lucide-react";
import { siApple } from "simple-icons";
import { enterpriseFeatures, faqs, features, individualPlans, roles, teamFeatures } from "@/lib/landing/content";
import { useLocale } from "@/components/site/LocaleProvider";
import { betaRelease, releaseDownload, releasePlatforms } from "@/lib/releases.mjs";
import { ChatDemo } from "./ChatDemo";
import { Avatar, Pet } from "./Pet";

export function AppleMark() {
  return <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" aria-hidden="true"><path d={siApple.path} /></svg>;
}

export function Reveal({ children, className = "" }) {
  const reduced = useReducedMotion();
  return <motion.div className={className} initial={false} whileInView={reduced ? { opacity: 1, y: 0 } : { opacity: [0, 1], y: [18, 0] }} viewport={{ once: true, amount: 0.1 }} transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}>{children}</motion.div>;
}

export function Hero() {
  const { t } = useLocale();
  return <section id="hero" className="blot-hero">
    <Reveal className="blot-hero-copy"><Link href="/changelog" className="blot-announcement"><span className="blot-announcement-desktop">{t("1.0 Beta is here · See what’s new")}</span><span className="blot-announcement-mobile">{t("1.0 Beta is here")}</span><ArrowUpRight size={13} /></Link>
      <h1>{t("Meet")}<Pet size={60} />{t("Blot")}</h1>
      <p>{t("AI teammates you can give real work to. Bots can sign in to your tools, use them just like you do, and come back with finished work.")}</p>
      <div className="blot-actions"><a className="blot-button" href={releaseDownload("macos")}><AppleMark />{t("Download for macOS")}</a><Link className="blot-button blot-button-soft" href="/contact">{t("Contact sales")}</Link></div>
    </Reveal>
    <Reveal className="blot-hero-demo" ><div id="demo"><ChatDemo /></div></Reveal>
  </section>;
}

export function Statement() {
  const { t } = useLocale();
  return <section id="statement" className="blot-section blot-statement"><Reveal className="blot-statement-card"><div><h2>{t("Message Bots like teammates")}</h2><p>{t("Give tasks to Bots like you would a teammate on desktop or iOS. Your AI teammates take projects from start to end, keep context on how you work and get smarter over time, and come back when your approval is needed.")}</p></div><div className="blot-statement-pet"><Pet size={250} /></div></Reveal></section>;
}

function FeatureVisual({ index, title }) {
  const ref = useRef(null);
  const frame = useRef(null);
  const active = useInView(ref, { margin: "80px" });
  const reduced = useReducedMotion();
  const notify = () => frame.current?.contentWindow?.postMessage({ type: "blot-visual", active: active && !reduced }, window.location.origin);
  useEffect(notify, [active, reduced]);
  return <div className="blot-feature-visual" ref={ref}><iframe ref={frame} src={`/blot/visuals/feature-${index}.html`} title={`${title} illustration`} tabIndex={-1} aria-hidden="true" loading="lazy" onLoad={notify} /></div>;
}

export function Features() {
  const { t } = useLocale();
  return <section id="features" className="blot-section blot-features"><Reveal className="blot-section-intro"><h2>{t("Work with many Bots at once")}</h2><p>{t("Create a Bot, give it a task, and add another when the work grows—one on a project, one on outbound, one on systems. AI teammates work in parallel, collaborate where it makes sense, and keep working 24/7.")}</p></Reveal><div className="blot-feature-grid">{features.map((feature, index) => <Reveal key={feature.title} className="blot-feature"><FeatureVisual index={index} title={t(feature.title)} /><h3>{t(feature.title)}</h3><p>{t(feature.body)}</p></Reveal>)}</div></section>;
}

export function RolePicker() {
  const { t } = useLocale();
  const [selected, setSelected] = useState(0);
  const role = roles[selected];
  return <section id="use-cases" className="blot-section blot-roles"><Reveal><h2>{t("Give each Bot a job")}</h2><div className="blot-role-layout"><div className="blot-role-copy"><div className="blot-role-options" aria-label={t("Choose an agent role")}>{roles.map((item, index) => <button key={item.id} aria-pressed={index === selected} onClick={() => setSelected(index)} style={{ "--role-color": item.color }} className={index === selected ? "is-selected" : ""}><Avatar name={`role-${item.id}`} size={20} /><span>{t(item.name)}</span></button>)}</div><div className="blot-role-description"><AnimatePresence mode="wait" initial={false}><motion.p key={role.id} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.18 }}>{t(role.description)}</motion.p></AnimatePresence></div><Link className="blot-button blot-button-soft" href="/features">{t("Explore more bots")}<ArrowUpRight size={14} /></Link></div><div className="blot-role-phone" style={{ "--role-color": role.color }}><ChatDemo key={role.id} phone role={role} /></div></div></Reveal></section>;
}

function FeatureList({ intro, items }) {
  const { t } = useLocale();
  return <div className="blot-plan-features"><p>{t(intro)}</p><ul>{items.map(item => <li key={item}><Check size={14} /><span>{t(item)}</span></li>)}</ul></div>;
}

export function Pricing() {
  const { t } = useLocale();
  const [teams, setTeams] = useState(false);
  const [seat, setSeat] = useState(0);
  return <section id="pricing" className="blot-section blot-pricing"><Reveal><div className="blot-section-intro"><h2>{t("Pricing")}</h2></div><div className="blot-segmented" aria-label={t("Choose Individual or Teams plans")}>{["Individual", "Teams"].map((name, index) => <button key={name} aria-pressed={teams === Boolean(index)} className={teams === Boolean(index) ? "is-selected" : ""} onClick={() => setTeams(Boolean(index))}>{teams === Boolean(index) && <motion.span layoutId="blot-pricing-pill" className="blot-segmented-indicator" transition={{ type: "spring", bounce: 0.15, duration: 0.4 }} />}<span>{t(name)}</span></button>)}</div>
      <div className={`blot-plans${teams ? " is-teams" : ""}`}>
        {!teams ? individualPlans.map(plan => <article className="blot-plan" key={plan.name}><h3>{plan.name}</h3><div className="blot-plan-price"><strong>${plan.price}</strong><span>{t("/ month")}</span></div><p className="blot-plan-billing">{t("Billed monthly")}</p><Link className="blot-button" href={`/beta?plan=${plan.name.toLowerCase()}`}>{t("Get")} {plan.name}</Link><FeatureList intro={plan.intro} items={plan.features} /></article>) : <>
          <article className="blot-plan"><div className="blot-plan-header"><h3>{t("Teams")}</h3><div className="blot-seat-picker" aria-label={t("Choose a Teams seat")}>{individualPlans.map((plan, index) => <button key={plan.name} aria-pressed={seat === index} className={seat === index ? "is-selected" : ""} onClick={() => setSeat(index)}>{plan.name}</button>)}</div></div><div className="blot-plan-price"><strong>${individualPlans[seat].price}</strong><span>{t("/ user / month")}</span></div><p className="blot-plan-billing">{t("Billed monthly")}</p><Link className="blot-button" href={`/beta?plan=teams&seat=${individualPlans[seat].name.toLowerCase()}`}>{t("Get Teams")}</Link><FeatureList intro="Includes:" items={teamFeatures} /></article>
          <article className="blot-plan"><h3>{t("Enterprise")}</h3><div className="blot-plan-price"><strong>{t("Custom")}</strong></div><p className="blot-plan-billing">{t("Let’s find the right fit")}</p><Link className="blot-button blot-button-soft" href="/contact">{t("Contact sales")}</Link><FeatureList intro="Everything in Teams, plus:" items={enterpriseFeatures} /></article>
        </>}
      </div><p className="blot-pricing-note">{t("Already on an eligible Premium, Super, Ultra, Teams, or Enterprise plan? Blot is included.")}</p></Reveal></section>;
}

export function Downloads() {
  const { t } = useLocale();
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    function close(event) { if (!ref.current?.contains(event.target) || event.key === "Escape") setOpen(false); }
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", close);
    return () => { document.removeEventListener("pointerdown", close); document.removeEventListener("keydown", close); };
  }, []);
  return <section id="download" className="blot-section blot-download"><Reveal className="blot-download-card"><div><h2>{t("Download Blot")}</h2><p>{betaRelease.version} · {t("macOS 26+ on Apple Silicon and iOS 26+. iPhone IPA requires your own signing.")}</p><Link className="site-text-link" href="/beta">{t("Installation guide and model setup")}<ArrowUpRight size={14} /></Link></div><div className="blot-download-actions" ref={ref}><a className="blot-button" href={releaseDownload("macos")}><AppleMark />{t("Download for macOS")}</a><button className="blot-button blot-button-paper" aria-expanded={open} aria-controls="blot-platforms" onClick={() => setOpen(!open)}>{t("More downloads")}<ChevronDown size={15} /></button><AnimatePresence>{open && <motion.div className="blot-platform-menu" id="blot-platforms" initial={{ opacity: 0, y: -5 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -5 }} transition={{ duration: 0.16 }}>{releasePlatforms.map(({ name, id, file }) => { const Icon = ["macos", "windows"].includes(id) ? Laptop : Smartphone; return file ? <a key={id} href={releaseDownload(id)}><Icon size={16} /><span>{name}</span><Download size={14} /></a> : <span className="blot-platform-soon" key={id} aria-disabled="true"><Icon size={16} /><span>{name}</span><small>{t("Soon")}</small></span>; })}</motion.div>}</AnimatePresence></div></Reveal></section>;
}

export function Guides() {
  const { t } = useLocale();
  return <section id="guides" className="blot-section blot-guides"><Reveal className="blot-guide-card"><h2>{t("Blot Guides")}</h2><p>{t("How PMs, designers, and GTM run Blot day to day.")}</p><Link href="/docs" className="blot-button">{t("Read guides")}<ArrowUpRight size={14} /></Link></Reveal></section>;
}

export function FAQ() {
  const { t } = useLocale();
  const [open, setOpen] = useState(0);
  return <section id="faqs" className="blot-section blot-faq"><Reveal className="blot-faq-layout"><h2>{t("FAQs")}</h2><div className="blot-faq-list">{faqs.map(([question, answer], index) => <article className="blot-faq-item" key={question}><h3><button id={`blot-question-${index}`} aria-expanded={open === index} aria-controls={`blot-answer-${index}`} onClick={() => setOpen(open === index ? null : index)}>{t(question)}{open === index ? <Minus size={18} /> : <Plus size={18} />}</button></h3><AnimatePresence initial={false}>{open === index && <motion.div id={`blot-answer-${index}`} role="region" aria-labelledby={`blot-question-${index}`} initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}><p>{t(answer)}</p></motion.div>}</AnimatePresence></article>)}</div></Reveal></section>;
}

export function FinalCTA() {
  const { t } = useLocale();
  return <section className="blot-section blot-final" id="get-started"><Reveal><Pet size={140} /><h2>{t("Meet your first Bot")}</h2><p>{t("An AI teammate you can trust to get work done")}</p><div className="blot-actions"><Link href="/beta" className="blot-button">{t("Get started for free")}<ArrowRight size={15} /></Link><Link href="/contact" className="blot-button blot-button-soft">{t("Contact sales")}</Link></div></Reveal></section>;
}
