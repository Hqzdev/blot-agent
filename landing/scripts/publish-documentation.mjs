import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { documents, architectureDocuments } from "../lib/workspace/documentation.mjs";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const repositoryRoot = fileURLToPath(new URL("../../", import.meta.url));

export async function publishDocumentation() {
  const knownPaths = new Set(documents.map((item) => resolve(repositoryRoot, item.path)));
  const manifest = [];
  for (const document of documents) {
    const sourcePath = resolve(repositoryRoot, document.path);
    const content = await readFile(sourcePath, "utf8");
    if (!content.startsWith("# ") || content.trim().length < 700) throw new Error(`Incomplete document: ${document.path}`);
    if (document.taskId && !content.includes(`Задача: ${document.taskId}.`)) throw new Error(`Missing task identity: ${document.path}`);
    const fenceCount = content.split("\n").filter((line) => line.startsWith("```")).length;
    if (fenceCount % 2) throw new Error(`Unclosed code fence: ${document.path}`);
    for (const match of content.matchAll(/```json\s*\n([\s\S]*?)\n```/g)) JSON.parse(match[1]);
    for (const match of content.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
      const href = match[1].split("#")[0];
      if (!href || /^https?:\/\//.test(href)) continue;
      const linkedPath = resolve(dirname(sourcePath), href);
      if (!knownPaths.has(linkedPath)) throw new Error(`Unknown document link: ${document.path} → ${href}`);
    }
    const destination = resolve(projectRoot, "public", document.downloadUrl.slice(1));
    await mkdir(dirname(destination), { recursive: true });
    await writeFile(destination, content, "utf8");
    manifest.push({ id: document.id, taskId: document.taskId, source: document.path, downloadUrl: document.downloadUrl, sha256: createHash("sha256").update(content).digest("hex"), bytes: Buffer.byteLength(content), taskCompleted: document.completed });
  }
  const overview = await readFile(resolve(repositoryRoot, "docs/archive/acceptance-matrix.md"), "utf8");
  for (let number = 1; number <= 18; number++) if (!overview.includes(`REQ-${String(number).padStart(2, "0")}`)) throw new Error(`Missing requirement REQ-${number}`);
  await writeFile(resolve(projectRoot, "public/project-docs/manifest.json"), `${JSON.stringify({ schemaVersion: 1, architectureDocuments: architectureDocuments.length, completedTasks: architectureDocuments.filter((item) => item.completed).length, documents: manifest }, null, 2)}\n`, "utf8");
  console.log(`Validated and published ${architectureDocuments.length} architecture documents; ${manifest.length} files with SHA-256.`);
}
