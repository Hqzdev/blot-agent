import { readFile } from "node:fs/promises";
import { join } from "node:path";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, ArrowDownToLine, Check } from "lucide-react";
import MarkdownDocument from "@/components/workspace/MarkdownDocument";
import { documents, getDocument } from "@/lib/workspace/documentation.mjs";
import "../../workspace.css";
import "../document.css";

export const dynamicParams = false;
export function generateStaticParams() { return documents.map((document) => ({ id: document.id })); }

export async function generateMetadata({ params }) {
  const { id } = await params;
  const document = getDocument(id);
  return { title: document ? `Blot — ${document.title}` : "Blot — документ" };
}

export default async function DocumentPage({ params }) {
  const { id } = await params;
  const document = getDocument(id);
  if (!document) notFound();
  const content = await readFile(join(process.cwd(), "..", "docs", document.path.slice("docs/".length)), "utf8");
  const title = content.split("\n")[0].replace(/^# /, "");
  return <main className="ws-doc-page" lang="ru" id="main-content" tabIndex={-1}>
    <Link className="ws-doc-back" href={`/workspace#${document.completed ? "completed" : "tasks"}`}><ArrowLeft size={14} />{document.completed ? "К выполненным задачам" : "К рабочей среде"}</Link>
    <header className="ws-doc-header"><div className="ws-doc-meta"><span>{document.taskId || "АРХИТЕКТУРА"}</span><span className={document.completed ? "completed" : ""}>{document.completed && <Check size={12} />}{document.completed ? "Задача выполнена" : "Документ подготовлен"}</span></div><h1>{title}</h1><p>{document.summary}</p><div className="ws-doc-actions"><code>{document.path}</code><a href={document.downloadUrl} download><ArrowDownToLine size={15} /> Скачать MD</a></div></header>
    <MarkdownDocument content={content} sourcePath={document.path} />
  </main>;
}
