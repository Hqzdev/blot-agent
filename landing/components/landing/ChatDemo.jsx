"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "motion/react";
import { ArrowUp, Check, ChevronLeft, Clock3, Monitor, Pause, Play, Plus, Search, X } from "lucide-react";
import { useLocale } from "@/components/site/LocaleProvider";
import { chats, roles } from "@/lib/landing/content";
import { Avatar } from "./Pet";

function TrafficLights() {
  return <span className="blot-traffic" aria-hidden="true"><i /><i /><i /></span>;
}

function Message({ children, user = false, delay = 0 }) {
  return <motion.div className={`blot-message-row${user ? " is-user" : ""}`} initial={{ opacity: 0, y: 8, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ duration: 0.3, delay }}><div className="blot-message">{children}</div></motion.div>;
}

function Computer({ close, compact = false }) {
  const { t } = useLocale();
  return <div className={`blot-computer${compact ? " is-compact" : ""}`}>
    <div className="blot-computer-toolbar"><span>{t("Computer")}</span>{close && <button onClick={close} aria-label={t("Close computer")}><X size={14} /></button>}<span className="blot-computer-status"><i />{t("Working")}</span></div>
    <div className="blot-computer-screen">
      <div className="blot-crm"><div className="blot-crm-toolbar"><span>{t("Salesforce")}</span><span>{t("Accounts")}</span></div><div className="blot-crm-content"><strong>{t("Outreach queue")}</strong><table><thead><tr><th>{t("Contact")}</th><th>{t("Status")}</th></tr></thead><tbody>{["Priya Natarajan", "Marcus Webb", "Elena Sørensen", "Daniel Alvarez"].map(name => <tr key={name}><td>{name}</td><td><span>{t("Draft")}</span></td></tr>)}</tbody></table><div className="blot-crm-total">{t("36 drafts queued")}<span>{t("0 sent")}</span></div></div></div>
      <motion.div className="blot-demo-cursor" aria-hidden="true" animate={{ x: [0, 80, 25, 0], y: [0, 40, 100, 0] }} transition={{ duration: 8, repeat: Infinity, ease: "easeInOut" }}><ArrowUp size={14} fill="currentColor" /></motion.div>
    </div>
  </div>;
}

function Transcript({ role, phase, customMessages }) {
  const { t } = useLocale();
  const ref = useRef(null);
  const reduced = useReducedMotion();
  const outbound = role.id === "sales-outbound";
  const checklist = outbound
    ? ["Accounts researched · 52 accounts", "Lookalike segments pulled", "Recently contacted profiles skipped", "36 drafts queued · 0 sent"]
    : ["Relevant sources gathered", "Workspace context reviewed", "Draft prepared", "Ready for your review"];
  useEffect(() => {
    ref.current?.scrollTo({ top: ref.current.scrollHeight, behavior: reduced ? "instant" : "smooth" });
  }, [phase, customMessages, reduced]);

  return <div className="blot-transcript" ref={ref} tabIndex={0} aria-label={`${t(role.name)} demo conversation`}>
    <div className="blot-transcript-inner">
      <span className="blot-chat-time">{t("8:13 PM")}</span>
      <Message>{t("Hey, good to meet you. What do you want me around for? Anything concrete, or more of a general sidekick?")}</Message>
      {phase >= 1 && <Message user>{t(role.task)}</Message>}
      {phase >= 2 && <div className="blot-chat-event">{t("Renamed to")} {t(role.name)}</div>}
      {phase >= 3 && <Message>{t("Checking what’s connected. Your workspace and email are already signed in. I’m pulling the context together.")}</Message>}
      {phase >= 4 && outbound && <motion.div className="blot-chat-attachment" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}><Computer compact /></motion.div>}
      {phase >= 5 && <Message><div className="blot-chat-checklist">{checklist.map(item => <span key={item}><Check size={13} />{t(item)}</span>)}</div></Message>}
      {phase >= 6 && <><div className="blot-chat-event blot-collaboration">{t("Messages from")} <Avatar name="chat-account-manager" size={15} />{t("Account Manager")} {t("and")} <Avatar name="chat-chief-of-staff" size={15} />{t("Chief")}</div><Message><span className="blot-inline-agent"><Avatar name="chat-account-manager" size={16} />{t("Account Manager")}</span> {t("sent over the latest context and")} <span className="blot-inline-agent"><Avatar name="chat-chief-of-staff" size={16} />{t("Chief")}</span> {t("flagged the priorities. Both are folded into the list.")}</Message></>}
      {phase >= 7 && <Message>{t(role.result)}</Message>}
      {phase >= 8 && <Message user>{t("The top 10 look good. Run this every week.")}</Message>}
      {phase >= 9 && <div className="blot-chat-event">{t("Created routine")}<Clock3 size={13} />{t("Overnight workflow")}</div>}
      {phase >= 10 && <Message>{t("Done.")}</Message>}
      {customMessages.map((text, index) => <Message key={index} user={index % 2 === 0}>{text}</Message>)}
      {phase < 10 && <div className="blot-typing" aria-label={t("Agent is typing")}><i /><i /><i /></div>}
    </div>
  </div>;
}

export function ChatDemo({ phone = false, role: externalRole }) {
  const { t } = useLocale();
  const root = useRef(null);
  const visible = useInView(root, { amount: 0.15 });
  const reduced = useReducedMotion();
  const [selected, setSelected] = useState("sales");
  const [search, setSearch] = useState("");
  const [phase, setPhase] = useState(7);
  const [paused, setPaused] = useState(false);
  const [computer, setComputer] = useState(false);
  const [newAgent, setNewAgent] = useState(false);
  const [draft, setDraft] = useState("");
  const [customMessages, setCustomMessages] = useState([]);
  const selectedChat = chats.find(chat => chat.id === selected) || chats[1];
  const profile = roles.find(item => item.id === selectedChat.role);
  const role = externalRole || { ...profile, name: selectedChat.name };

  useEffect(() => {
    if (!visible || reduced || paused || customMessages.length) return;
    const timer = setTimeout(() => setPhase(value => value >= 10 ? 0 : value + 1), phase >= 10 ? 6500 : 2400);
    return () => clearTimeout(timer);
  }, [phase, visible, reduced, paused, customMessages.length]);

  function selectChat(id) {
    setSelected(id);
    setPhase(0);
    setPaused(false);
    setCustomMessages([]);
    setComputer(false);
  }

  function submit(event) {
    event.preventDefault();
    const text = draft.trim();
    if (!text) return;
    setPhase(10);
    setPaused(true);
    setCustomMessages(previous => [...previous, text, t("Got it. I’ll add that to the review list and keep you posted before any action needs approval.")]);
    setDraft("");
  }

  return <div className={`blot-chat-demo${phone ? " is-phone" : ""}${computer ? " with-computer" : ""}`} ref={root}>
    {!phone && <aside className="blot-chat-sidebar" aria-label={t("Demo agents")}>
      <div className="blot-sidebar-toolbar"><TrafficLights /><button aria-label={t("Add an agent")} aria-expanded={newAgent} onClick={() => setNewAgent(!newAgent)}><Plus size={16} /></button></div>
      <label className="blot-chat-search"><Search size={14} /><input type="search" placeholder={t("Search")} aria-label={t("Search agents")} value={search} onChange={event => setSearch(event.target.value)} /></label>
      <div className="blot-chat-list">{chats.filter(chat => t(chat.name).toLocaleLowerCase().includes(search.toLocaleLowerCase())).map(chat => <button key={chat.id} className={`blot-chat-contact${selected === chat.id ? " is-selected" : ""}`} aria-pressed={selected === chat.id} title={t(chat.name)} onClick={() => selectChat(chat.id)}><Avatar name={chat.avatar} size={44} /><span><span className="blot-chat-contact-title">{t(chat.name)}<time>{chat.time}</time></span><span className="blot-chat-preview">{chat.id === selected && phase < 10 ? t("Typing…") : t(chat.preview)}</span></span></button>)}
        {!search && <button className="blot-chat-contact" onClick={() => selectChat("chief")} title="Offsite crew"><span className="blot-group-avatar"><Avatar name="chat-chief-of-staff" size={27} /><Avatar name="chat-account-manager" size={27} /><Avatar name="chat-talent-scout" size={27} /></span><span><span className="blot-chat-contact-title">{t("Offsite crew")}<time>{t("2:13 PM")}</time></span><span className="blot-chat-preview">{t("that leaves the pipeline. I’d spin up a Bot.")}</span></span></button>}
        {search && !chats.some(chat => t(chat.name).toLocaleLowerCase().includes(search.toLocaleLowerCase())) && <p className="blot-chat-empty">{t("No matching agents")}</p>}
      </div>
      <div className="blot-chat-profile"><span>{t("AS")}</span><span>{t("Armand Segall")}</span></div>
    </aside>}
    <div className="blot-chat-main">
      <div className="blot-chat-titlebar">{phone && <ChevronLeft size={17} />}<Avatar name={phone ? `role-${role.id}` : selectedChat.avatar} size={22} /><span>{t(role.name)}</span><button aria-label={computer ? t("Hide agent computer") : t("Show agent computer")} aria-pressed={computer} onClick={() => setComputer(!computer)}><Monitor size={15} /></button></div>
      <Transcript key={role.id} role={role} phase={phase} customMessages={customMessages} />
      <form className="blot-chat-composer" onSubmit={submit}><Plus size={15} /><input value={draft} onChange={event => setDraft(event.target.value)} aria-label={`${t("Message")} ${t(role.name)}`} placeholder={`${t("Message")} ${t(role.name)}`} maxLength={500} /><button type="submit" aria-label={t("Send demo message")} disabled={!draft.trim()}><ArrowUp size={14} /></button></form>
      <button className="blot-demo-pause" aria-label={paused ? t("Resume chat animation") : t("Pause chat animation")} onClick={() => setPaused(!paused)}>{paused ? <Play size={12} /> : <Pause size={12} />}</button>
    </div>
    <AnimatePresence>{computer && <motion.div className="blot-live-computer" initial={{ opacity: 0, x: 15 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 15 }}><Computer close={() => setComputer(false)} /></motion.div>}</AnimatePresence>
    <AnimatePresence>{newAgent && <motion.div className="blot-add-agent" initial={{ opacity: 0, y: -5 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -5 }}><div><strong>{t("Give a Bot a job")}</strong><button aria-label={t("Close agent picker")} onClick={() => setNewAgent(false)}><X size={16} /></button></div>{chats.map(chat => <button key={chat.id} onClick={() => { selectChat(chat.id); setNewAgent(false); }}><Avatar name={chat.avatar} size={28} />{t(chat.name)}<Plus size={14} /></button>)}</motion.div>}</AnimatePresence>
  </div>;
}
