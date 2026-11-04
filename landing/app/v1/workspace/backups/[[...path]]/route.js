import { AuthError } from "@/lib/auth/errors.mjs";
import { json, failure } from "@/lib/auth/route-support.mjs";
import { accountDatabase } from "@/lib/accounts/database.mjs";
import { localAccountService } from "@/lib/accounts/service.mjs";
import { WorkspaceBackups } from "@/lib/accounts/workspace-backups.mjs";

export const runtime = "nodejs";
export const maxDuration = 60;

async function readBody(request) {
  if (!request.headers.get("content-type")?.startsWith("application/json")) throw new AuthError("invalid_request");
  const reader = request.body?.getReader();
  if (!reader) throw new AuthError("invalid_request");
  let size = 0; const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length;
      if (size > 720_000) throw new AuthError("invalid_request", 413);
      chunks.push(Buffer.from(value));
    }
  } finally { await reader.cancel(); }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value;
  } catch { throw new AuthError("invalid_request"); }
}

async function handle(request, context) {
  try {
    const auth = request.headers.get("authorization");
    if (!auth?.startsWith("Bearer ")) throw new AuthError("session_required", 401);
    const account = await localAccountService().authenticate(auth.slice(7));
    const backups = new WorkspaceBackups(accountDatabase());
    const { path = [] } = await context.params;
    if (!path.length) return json(request.method === "GET" ? await backups.list(account) : await backups.begin(account, await readBody(request)));
    if (path.length === 2 && path[1] === "commit" && request.method === "POST") return json(await backups.commit(account, path[0]));
    if (path.length === 3 && path[1] === "parts" && /^(0|[1-9][0-9]?)$/.test(path[2])) {
      const part = Number(path[2]);
      return json(request.method === "GET" ? await backups.part(account, path[0], part)
        : await backups.putPart(account, path[0], part, await readBody(request)));
    }
    throw new AuthError("not_found", 404);
  } catch (error) { return failure(error); }
}
export const GET = handle;
export const POST = handle;
