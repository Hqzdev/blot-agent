"use client";

import { useState } from "react";
import { Laptop, Smartphone } from "lucide-react";
import { PageLink } from "./PageFrame";

const platforms = [
  { id: "macos", name: "macOS", icon: Laptop, detail: "The desktop workspace for your agents, tools, files, and projects." },
  { id: "ios", name: "iOS", icon: Smartphone, detail: "Follow tasks, talk to your agents, and review requests from your phone." },
  { id: "android", name: "Android", icon: Smartphone, detail: "A mobile companion for agent chats, schedules, and approvals." },
  { id: "windows", name: "Windows", icon: Laptop, detail: "The desktop agent workspace for your Windows computer." },
];

export function PlatformAvailability({ platform, plan }) {
  const [selected, setSelected] = useState(platform);
  const current = platforms.find(item => item.id === selected) || platforms[0];
  return <div className="site-split">
    <div className="site-platform-picker" aria-label="Choose a platform">{platforms.map(({ id, name, icon: Icon }) => <button key={id} onClick={() => setSelected(id)} aria-pressed={selected === id} className={selected === id ? "is-selected" : ""}><Icon size={24} /><span>{name}</span></button>)}</div>
    <section className="site-prose site-availability" aria-live="polite"><span className="site-tag">In development</span><h2>Blot for {current.name}</h2><p>{current.detail}</p><p>Public installers are not available yet. Follow the project workspace for progress.</p>{plan && <p className="site-plan-selection">Selected plan: <strong>{plan}</strong>. Subscriptions are not available for purchase yet.</p>}<PageLink href="/workspace">Follow development</PageLink><PageLink href="https://github.com/Hqzdev/blot-agent">View the repository</PageLink></section>
  </div>;
}
