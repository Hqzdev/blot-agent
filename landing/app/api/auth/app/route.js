import { accountRequest, AuthError } from "@/lib/auth/config.mjs";
import { input, json, failure, currentTokens, setSession } from "@/lib/auth/route-support.mjs";
import { nativeAttempt, appCallback } from "@/lib/auth/browser-session.mjs";

export const runtime = "nodejs";
export async function POST(request) {
  try {
    const body = await input(request);
    if (typeof body.query !== "string" || body.query.length > 2048) throw new AuthError("invalid_app_request");
    const attempt = nativeAttempt(new URLSearchParams(body.query));
    if (!attempt) throw new AuthError("invalid_app_request");
    const tokens = await currentTokens(request);
    const issued = await accountRequest("browser/code", { accessToken: tokens.accessToken,
      body: { clientID: attempt.clientID, redirectURI: attempt.redirectURI, codeChallenge: attempt.codeChallenge } });
    return setSession(json({ callbackURL: appCallback(attempt, issued.code), expiresAt: issued.expiresAt }), tokens, request);
  } catch (error) { return failure(error); }
}
