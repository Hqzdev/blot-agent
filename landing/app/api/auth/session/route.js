import { accountRequest, AuthError } from "@/lib/auth/config.mjs";
import { input, json, failure, setSession, currentTokens, clientIP } from "@/lib/auth/route-support.mjs";
import { SESSION_COOKIE, COOKIE_OPTIONS } from "@/lib/auth/browser-session.mjs";

export const runtime = "nodejs";
export async function GET(request) {
  try {
    const tokens = await currentTokens(request);
    const account = await accountRequest("me", { method: "GET", accessToken: tokens.accessToken });
    return setSession(json({ account }), tokens, request);
  } catch (error) {
    if (error instanceof AuthError && error.status === 401) return json({ account: null });
    return failure(error);
  }
}
export async function POST(request) {
  try {
    const value = await input(request);
    const { action, email, name, code, intent } = value;
    if (typeof action !== "string") throw new AuthError("invalid_request");
    switch (action) {
      case "email/request":
        await accountRequest("email/request", { body: { email, name, intent }, clientIP: clientIP(request) });
        return json({ verificationRequired: true });
      case "email/verify": {
        const tokens = await accountRequest("email/verify", { body: { email, code }, clientIP: clientIP(request) });
        return setSession(json({ authenticated: true }), tokens, request);
      }
      case "logout": {
        let response;
        try {
          const tokens = await currentTokens(request);
          await accountRequest("logout", { accessToken: tokens.accessToken });
          response = json({ authenticated: false });
        } catch (error) { response = failure(error); }
        response.cookies.set(SESSION_COOKIE, "", { ...COOKIE_OPTIONS, maxAge: 0 });
        return response;
      }
      default: throw new AuthError("invalid_request");
    }
  } catch (error) { return failure(error); }
}
