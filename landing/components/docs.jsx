"use client";

import { useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Search, Copy, Check, Info, TriangleAlert, ArrowRight } from "lucide-react";
import { Label, Badge } from "./ui";
import { play } from "@/lib/sound";
import { useClipboard } from "@/lib/useClipboard";
import { currentProductDocuments } from "@/lib/workspace/documentation.mjs";
import FormFeedback from "./FormFeedback";

/* ---------- shared bits for long-form pages ---------- */
export function Code({ lang = "bash", children }) {
  const { state, copy } = useClipboard(children.trim());
  const ok = state === "copied";
  return (
    <div className="code-block dark">
      <div className="cb-head">
        <span className="mono">{lang}</span>
        <button type="button" onClick={copy} disabled={state === "copying"} className="cb-copy" aria-label={ok ? "Copied to clipboard" : "Copy code"}>
          <AnimatePresence mode="wait" initial={false}>
            <motion.span key={String(ok)} initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -4 }} transition={{ duration: 0.12 }}>
              {ok ? <><Check size={13} />Copied</> : <><Copy size={13} />{state === "copying" ? "Copying…" : "Copy"}</>}
            </motion.span>
          </AnimatePresence>
        </button>
      </div>
      <pre>{children.trim()}</pre>
      <FormFeedback error={state === "error"}>{state === "error" ? "Could not copy. Select the code and copy it manually." : ok ? "Code copied to clipboard." : ""}</FormFeedback>
    </div>
  );
}

export const Note = ({ warn, children }) => (
  <div className={`note ${warn ? "warn" : ""}`}>
    {warn ? <TriangleAlert size={16} /> : <Info size={16} />}
    <div>{children}</div>
  </div>
);

export const Kbd = ({ children }) => <kbd className="kbd">{children}</kbd>;

/* Scroll-spy: returns the id of the section nearest the top of the viewport */
export function useScrollSpy(ids) {
  const [active, setActive] = useState(ids[0]);
  useEffect(() => {
    const onScroll = () => {
      let cur = ids[0];
      for (const id of ids) {
        const el = document.getElementById(id);
        if (el && el.getBoundingClientRect().top < 180) cur = id;
      }
      if (innerHeight + scrollY >= document.documentElement.scrollHeight - 4) cur = ids[ids.length - 1];
      setActive(cur);
    };
    onScroll();
    addEventListener("scroll", onScroll, { passive: true });
    return () => removeEventListener("scroll", onScroll);
  }, [ids]);
  return active;
}

export function jump(id) {
  const el = document.getElementById(id);
  if (!el) return;
  play("tick");
  const zoom = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--scale")) || 1;
  scrollTo({ top: scrollY + el.getBoundingClientRect().top * (zoom === 1 ? 1 : 1) - 110, behavior: "smooth" });
}

export function Toc({ items, active, layoutId = "toc" }) {
  return (
    <nav className="toc">
      <span className="label" style={{ marginBottom: 8 }}>On this page</span>
      {items.map(([id, t]) => (
        <a key={id} href={`#${id}`} className={active === id ? "on" : ""} onClick={(e) => { e.preventDefault(); jump(id); }}>
          {active === id && <motion.i layoutId={layoutId} className="toc-bar" transition={{ type: "spring", stiffness: 420, damping: 34 }} />}
          {t}
        </a>
      ))}
    </nav>
  );
}

export function Reveal({ children, id, className = "" }) {
  return (
    <motion.section
      id={id}
      className={className}
      initial={{ opacity: 0, y: 16 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.15 }}
      transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.section>
  );
}

/* ---------- Docs ---------- */
const NAV = [
  ["Product requirements", [["product-plan", "Four-platform specification"]]],
  ["Getting started", [["install", "Install"], ["first-task", "Your first task"], ["projects", "Projects & worktrees"]]],
  ["The agent", [["approvals", "Sandbox & approvals"], ["allow-list", "Allow list"], ["models", "Models & keys"]]],
  ["Extend", [["automations", "Automations"], ["skills", "Skills"]]],
  ["Reference", [["shortcuts", "Keyboard shortcuts"]]],
];
const ALL = NAV.flatMap(([, items]) => items);

export function DocsPage() {
  const ids = useMemo(() => ALL.map(([id]) => id), []);
  const active = useScrollSpy(ids);
  const [q, setQ] = useState("");
  const filtered = NAV.map(([g, items]) => [g, items.filter(([, t]) => t.toLowerCase().includes(q.toLowerCase()))]).filter(([, i]) => i.length);

  useEffect(() => {
    const onKey = (e) => { if (e.key === "/" && document.activeElement?.tagName !== "INPUT") { e.preventDefault(); document.getElementById("docs-q")?.focus(); } };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="docs">
      <aside className="docs-nav">
        <label className="docs-search">
          <Search size={14} color="var(--text-3)" />
          <input id="docs-q" type="search" aria-label="Search documentation" placeholder="Search docs" value={q} onChange={(e) => setQ(e.target.value)} />
          <Kbd>/</Kbd>
        </label>
        {filtered.map(([g, items]) => (
          <div key={g} className="dn-group">
            <span className="dn-title">{g}</span>
            {items.map(([id, t]) => (
              <a key={id} href={`#${id}`} className={active === id ? "on" : ""} onClick={(e) => { e.preventDefault(); jump(id); }}>
                {active === id && <motion.span layoutId="dn-pill" className="dn-pill" transition={{ type: "spring", stiffness: 420, damping: 34 }} />}
                <span>{t}</span>
              </a>
            ))}
          </div>
        ))}
        {filtered.length === 0 && <p className="muted" style={{ fontSize: 13, padding: "8px 10px" }}>Nothing for “{q}”.</p>}
      </aside>

      <article className="prose">
        <header className="prose-head">
          <Label dot="var(--ember)">Product requirements · November 2026</Label>
          <h1>Blot documentation</h1>
          <p className="lead">The current product plan, technical specification and MCP integration contract for Blot.</p>
        </header>

        <Reveal id="product-plan">
          <h2>Four-platform specification</h2>
          <p>The November requirements cover macOS, iOS, Android and Windows, with CEO coordination, local computer execution and mobile control.</p>
          <ul>{currentProductDocuments.map((document) => <li key={document.id}><a href={document.href}>{document.title}</a></li>)}</ul>
          <Note>These documents describe the target product. The earlier interface examples below are historical drafts and do not confirm available commands, installation methods or implemented features.</Note>
        </Reveal>

        <Reveal id="install">
          <h2>Install</h2>
          <p>Blot runs on Apple silicon Macs with macOS 14 Sonoma or newer. Download the beta, drag Blot to Applications, open it and sign in.</p>
          <Code lang="bash">{`brew install --cask blot`}</Code>
          <Note>Blot keeps everything it needs in <code>~/Library/Blot</code>. Uninstalling the app and deleting that folder removes all local history.</Note>
        </Reveal>

        <Reveal id="first-task">
          <h2>Your first task</h2>
          <ol>
            <li>Press <Kbd>⌘</Kbd><Kbd>N</Kbd> and pick a project folder.</li>
            <li>Describe the job the way you would to a teammate: <em>“PnL drifts by a cent on 7 lots — find out why and fix it.”</em></li>
            <li>Blot reads the repo, writes a plan and starts working. You can reply at any point to steer it.</li>
            <li>When it&apos;s done, open <strong>Review</strong>, read the diff, then commit or open a PR.</li>
          </ol>
          <Note>Blot never merges on its own. Every task ends as a diff that waits for you.</Note>
        </Reveal>

        <Reveal id="projects">
          <h2>Projects &amp; worktrees</h2>
          <p>A project is any folder with a git repository. Each task runs in its own git worktree, so up to three tasks can work in parallel without touching your working copy or each other.</p>
          <Code lang="bash">{`# where Blot keeps task worktrees
~/Library/Blot/worktrees/<project>/<task-id>`}</Code>
        </Reveal>

        <Reveal id="approvals">
          <h2>Sandbox &amp; approvals</h2>
          <p>Commands run in an isolated shell. The sandbox mode decides what Blot may change without asking:</p>
          <div className="table">
            <div className="tr th"><span>Mode</span><span>Edits files</span><span>Network</span><span>Outside the project</span></div>
            <div className="tr"><span><Badge>Read-only</Badge></span><span>Asks</span><span>Asks</span><span>Never</span></div>
            <div className="tr"><span><Badge tone="success">Workspace</Badge></span><span>Yes</span><span>Asks</span><span>Asks</span></div>
            <div className="tr"><span><Badge tone="danger">Full access</Badge></span><span>Yes</span><span>Yes</span><span>Yes</span></div>
          </div>
          <Note warn>Full access is meant for throwaway VMs and containers. On your main Mac, stay on Workspace.</Note>
        </Reveal>

        <Reveal id="allow-list">
          <h2>Allow list</h2>
          <p>Commands on the allow list run without a prompt. Click <strong>Always allow</strong> on any approval, or edit the list directly:</p>
          <Code lang="toml">{`# ~/.blot/config.toml
[approvals]
mode = "workspace"
network = "ask"

[[approvals.allow]]
command = "npm test"

[[approvals.allow]]
command = "git status"`}</Code>
        </Reveal>

        <Reveal id="models">
          <h2>Models &amp; keys</h2>
          <p>Blot 1 is the default and is included in the beta. You can switch the model per task or bring your own key for Anthropic, OpenAI, Google or a local Ollama model. Keys live in the macOS Keychain.</p>
          <Code lang="bash">{`blot models add anthropic   # prompts for the key, stores it in Keychain
blot models default blot-1 --effort high`}</Code>
        </Reveal>

        <Reveal id="automations">
          <h2>Automations</h2>
          <p>Automations are tasks that start on a schedule or on an event — a new issue, a failing CI run, an opened pull request. They run in the background, in a fresh worktree, with their own approval limits.</p>
          <Code lang="yaml">{`name: Triage new issues
project: tradr
on:
  schedule: "0 9 * * 1-5"
approvals: labels-and-comments
prompt: |
  Label new GitHub issues as bug, feature or question,
  link duplicates and post a one-line summary in #tradr-dev.`}</Code>
        </Reveal>

        <Reveal id="skills">
          <h2>Skills</h2>
          <p>A skill is a folder with a <code>SKILL.md</code> file. Blot loads it when a task matches its description, so your conventions travel with every task.</p>
          <Code lang="markdown">{`---
name: release-notes
description: Draft the weekly changelog from merged PRs
---
1. Run git log since the last tag.
2. Group changes into NEW / IMPROVED / FIXED.
3. Lead with the one change users will feel.`}</Code>
        </Reveal>

        <Reveal id="shortcuts">
          <h2>Keyboard shortcuts</h2>
          <div className="table">
            {[["New task", ["⌘", "N"]], ["Command palette", ["⌘", "K"]], ["Stop the agent", ["Esc"]], ["Open review", ["⌘", "R"]], ["Commit & push", ["⌘", "⇧", "↵"]], ["Toggle sidebar", ["⌘", "\\"]]].map(([t, keys]) => (
              <div key={t} className="tr two"><span>{t}</span><span>{keys.map((k) => <Kbd key={k}>{k}</Kbd>)}</span></div>
            ))}
          </div>
          <a className="next-link" href="/beta"><span><small>Next</small>Get access to the beta</span><ArrowRight size={18} /></a>
        </Reveal>
      </article>

      <Toc items={ALL} active={active} />
    </div>
  );
}
