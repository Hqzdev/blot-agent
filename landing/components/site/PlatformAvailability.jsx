"use client";

import { useState } from "react";
import { Laptop, Smartphone } from "lucide-react";
import { PageLink } from "./PageFrame";
import { betaRelease, releaseDownload, releasePlatforms } from "@/lib/releases.mjs";

const platforms = releasePlatforms.map(item => ({ ...item, icon: ["macos", "windows"].includes(item.id) ? Laptop : Smartphone }));

export function PlatformAvailability({ platform, plan }) {
  const [selected, setSelected] = useState(platform);
  const current = platforms.find(item => item.id === selected) || platforms[0];
  return <div className="site-split">
    <div className="site-platform-picker" aria-label="Choose a platform">{platforms.map(({ id, name, file, icon: Icon }) => <button key={id} onClick={() => setSelected(id)} aria-pressed={selected === id} className={selected === id ? "is-selected" : ""}><Icon size={24} /><span>{name}{!file && " · Soon"}</span></button>)}</div>
    <section className="site-prose site-availability" aria-live="polite"><span className="site-tag">{current.file ? betaRelease.version : "Soon"}</span><h2>Blot for {current.name}</h2><p>{current.detail}</p>{current.file ? <><p>{current.requirements}</p><PageLink href={releaseDownload(current.id)}>Download {current.format} on GitHub</PageLink><h3>Installation</h3><p>{current.installation}</p><p>Bring your own model API key: save a compatible API endpoint, model ID, and key in Settings, then select Compatible API for your agent. No shared model key is included.</p><PageLink href={betaRelease.url}>Release notes and SHA-256 checksums</PageLink></> : <p>Coming soon. There is no public installer for this platform yet.</p>}{plan && <p className="site-plan-selection">Selected plan: <strong>{plan}</strong>. Subscriptions are not available for purchase yet.</p>}<PageLink href="/changelog">What’s new in 1.0 Beta</PageLink></section>
  </div>;
}
