"use client";

import Link from "next/link";
import { useState } from "react";
import { ArrowUpRight, Search } from "lucide-react";
import { documents, currentProductDocuments } from "@/lib/workspace/documentation.mjs";

const currentIds = new Set(currentProductDocuments.map(document => document.id));

export function DocumentationIndex() {
  const [query, setQuery] = useState("");
  const matches = documents.filter(document => `${document.title} ${document.summary}`.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
  return <div className="site-docs">
    <label className="site-search"><Search size={18} /><input type="search" aria-label="Search documentation" placeholder="Search documentation…" value={query} onChange={event => setQuery(event.target.value)} /></label>
    <p className="site-result-count" role="status">{matches.length} {matches.length === 1 ? "document" : "documents"}</p>
    {!matches.length && <p className="site-empty">No matching documents. Try a different search.</p>}
    {[["Product plan & specifications", matches.filter(document => currentIds.has(document.id))], ["Architecture & implementation", matches.filter(document => !currentIds.has(document.id))]].map(([title, items]) => items.length > 0 && <section className="site-doc-group" key={title}><h2>{title}</h2><div className="site-document-list">{items.map(document => <Link href={document.href} key={document.id} lang="ru"><div><h3>{document.title}</h3><p>{document.summary}</p></div><ArrowUpRight size={18} /></Link>)}</div></section>)}
  </div>;
}
