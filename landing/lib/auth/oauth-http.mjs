import { AuthError } from "./errors.mjs";

export class OAuthHTTPClient {
  #fetch;
  constructor(fetcher = fetch) { this.#fetch = fetcher; }

  async json(url, options, errorCode) {
    try {
      const response = await this.#fetch(url, { ...options, redirect: "error", cache: "no-store", signal: AbortSignal.timeout(15_000) });
      if (!response.ok || Number(response.headers.get("content-length")) > 65_536 || !response.body) throw new Error();
      const reader = response.body.getReader(), chunks = [];
      let size = 0;
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          size += value.length;
          if (size > 65_536) throw new Error();
          chunks.push(Buffer.from(value));
        }
      } finally { await reader.cancel(); }
      const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
      return value;
    } catch { throw new AuthError(errorCode, 502); }
  }
}
