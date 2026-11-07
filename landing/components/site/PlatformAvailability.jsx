"use client";

import { useLocale } from "./LocaleProvider";
import { useState } from "react";
import { Laptop, Smartphone } from "lucide-react";
import { PageLink } from "./PageFrame";
import { betaRelease, releaseDownload, releasePlatforms } from "@/lib/releases.mjs";

const platforms = releasePlatforms.map(item => ({ ...item, icon: ["macos", "windows"].includes(item.id) ? Laptop : Smartphone }));

export function PlatformAvailability({ platform, plan }) {
  const { t } = useLocale();
  const [selected, setSelected] = useState(platform);
  const current = platforms.find(item => item.id === selected) || platforms[0];
  return <div className="site-split">
    <div className="site-platform-picker" aria-label={t("Choose a platform")}>{platforms.map(({ id, name, file, icon: Icon }) => <button key={id} onClick={() => setSelected(id)} aria-pressed={selected === id} className={selected === id ? "is-selected" : ""}><Icon size={24} /><span>{name}{!file && ` · ${t("Soon")}`}</span></button>)}</div>
    <section className="site-prose site-availability" aria-live="polite"><span className="site-tag">{current.file ? betaRelease.version : t("Soon")}</span><h2>{t("Blot for")} {current.name}</h2><p>{t(current.detail)}</p>{current.file ? <><p>{t(current.requirements)}</p><PageLink href={releaseDownload(current.id)}>{t("Download")} {current.format} {t("on GitHub")}</PageLink><h3>{t("Installation")}</h3><p>{t(current.installation)}</p><p>{t("Bring your own model API key: save a compatible API endpoint, model ID, and key in Settings, then select Compatible API for your agent. No shared model key is included.")}</p><PageLink href={betaRelease.url}>{t("Release notes and SHA-256 checksums")}</PageLink></> : <p>{t("Coming soon. There is no public installer for this platform yet.")}</p>}{plan && <p className="site-plan-selection">{t("Selected plan:")} <strong>{plan}</strong>. {t("Subscriptions are not available for purchase yet.")}</p>}<PageLink href="/changelog">{t("What\u2019s new in 1.0 Beta")}</PageLink></section>
  </div>;
}
