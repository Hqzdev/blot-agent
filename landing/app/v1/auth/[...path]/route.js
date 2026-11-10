import { accountRequest, AuthError } from "@/lib/auth/config.mjs";
import { json, failure, clientIP } from "@/lib/auth/route-support.mjs";

export const runtime = "nodejs";
const POSTS = new Set(["account/delete/request", "account/delete", "register", "verify", "login", "refresh", "password/request", "password/reset", "logout", "revoke-sessions", "device-challenge", "device-bind", "browser/token"]);
async function forward(request, context) {
  try {
    const { path: parts } = await context.params;
    const path = parts.join("/");
    if (!(request.method === "GET" ? path === "me" : POSTS.has(path))) throw new AuthError("not_found", 404);
    let body;
    if (request.method === "POST") {
      if (!request.headers.get("content-type")?.startsWith("application/json") && !["logout", "revoke-sessions", "device-challenge", "account/delete/request"].includes(path)) throw new AuthError("invalid_request");
      const reader = request.body?.getReader(); const chunks = []; let size = 0;
      if (reader) try {
        while (true) { const { value, done } = await reader.read(); if (done) break; size += value.length;
          if (size > 16_384) throw new AuthError("invalid_request", 413); chunks.push(Buffer.from(value)); }
      } finally { await reader.cancel(); }
      if (size) { try { body = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { throw new AuthError("invalid_request"); } }
    }
    const auth = request.headers.get("authorization");
    if (auth && !/^Bearer [A-Za-z0-9_-]{43}$/.test(auth)) throw new AuthError("session_required", 401);
    const result = await accountRequest(path, { body, method: request.method, accessToken: auth?.slice(7), clientIP: clientIP(request) });
    return json(result);
  } catch (error) { return failure(error); }
}
export const GET = forward;
export const POST = forward;
