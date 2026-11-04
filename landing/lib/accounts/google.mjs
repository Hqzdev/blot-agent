import { createRemoteJWKSet, jwtVerify } from "jose";
import { AuthError } from "../auth/errors.mjs";
import { emailAddress, equal, validToken } from "./security.mjs";

const keys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"), { timeoutDuration: 10_000 });
export class GoogleAccountIdentity {
  #audience;
  #keys;
  constructor(audience, signingKeys = keys) { this.#audience = audience; this.#keys = signingKeys; }
  async verify(idToken, nonce) {
    if (!this.#audience) throw new AuthError("google_unconfigured", 503);
    if (typeof idToken !== "string" || idToken.length > 16_384 || !validToken(nonce)) throw new AuthError("google_identity_invalid", 401);
    try {
      const { payload } = await jwtVerify(idToken, this.#keys, { audience: this.#audience,
        issuer: ["https://accounts.google.com", "accounts.google.com"], algorithms: ["RS256"], requiredClaims: ["exp", "iat", "sub"] });
      if (payload.email_verified !== true || typeof payload.nonce !== "string" || !equal(payload.nonce, nonce)
          || typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 255) throw new Error();
      const email = emailAddress(payload.email);
      const name = typeof payload.name === "string" && payload.name.trim() ? payload.name.trim().slice(0, 200) : email;
      return { subject: payload.sub, email, name };
    } catch (error) {
      if (error.code === "ERR_JWKS_TIMEOUT" || error instanceof TypeError && error.message === "fetch failed") throw new AuthError("google_unavailable", 503);
      throw new AuthError("google_identity_invalid", 401);
    }
  }
}
