import { randomUUID } from "node:crypto";
import { request } from "node:https";
import { rootCertificates } from "node:tls";
import { AuthError } from "../auth/errors.mjs";
import { gigaChatRoot } from "./gigachat-ca.mjs";

const OAUTH = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth";
const COMPLETIONS = "https://api.giga.chat/v1/chat/completions";

// This trust configuration is scoped to the two fixed GigaChat endpoints.
function requestJSON(url, body, headers, timeout) {
  return new Promise((resolve, reject) => {
    const signal = AbortSignal.timeout(timeout);
    const outgoing = request(url, {
      method: "POST", signal, ca: [...rootCertificates, gigaChatRoot],
      headers: { Accept: "application/json", "Content-Length": Buffer.byteLength(body), ...headers },
    }, incoming => {
      let size = 0;
      const chunks = [];
      incoming.on("data", chunk => {
        size += chunk.length;
        if (size > 1_048_576) outgoing.destroy(new Error("GigaChat response exceeded limit"));
        else chunks.push(chunk);
      });
      incoming.on("error", reject);
      incoming.on("end", () => {
        const status = incoming.statusCode;
        if (status < 200 || status >= 300) {
          resolve({ status });
          return;
        }
        try {
          resolve({ status, data: JSON.parse(Buffer.concat(chunks).toString("utf8")) });
        } catch (error) { reject(error); }
      });
    });
    outgoing.on("error", reject);
    outgoing.end(body);
  });
}

export class GigaChat {
  #key;
  #scope;
  #token;
  #pending;
  #request;
  constructor({ key, scope, transport = requestJSON }) {
    this.#key = key;
    this.#scope = scope;
    this.#request = transport;
  }

  async #authorize() {
    const result = await this.#request(OAUTH, new URLSearchParams({ scope: this.#scope }).toString(), {
      Authorization: "Basic " + this.#key,
      RqUID: randomUUID(),
      "Content-Type": "application/x-www-form-urlencoded",
    }, 10_000);
    const { access_token: access, expires_at: expiry } = result.data ?? {};
    if (typeof access !== "string" || !access || !Number.isFinite(expiry) || expiry <= Date.now()) {
      throw new AuthError("cli_model_unavailable", 503);
    }
    this.#token = { access, expiry };
    return access;
  }

  async #access() {
    if (this.#token?.expiry > Date.now() + 30_000) return this.#token.access;
    this.#pending ??= this.#authorize().finally(() => { this.#pending = undefined; });
    return this.#pending;
  }

  async complete(payload) {
    if (!this.#key) throw new AuthError("cli_model_unconfigured", 503);
    const send = access => this.#request(COMPLETIONS, JSON.stringify(payload), {
      Authorization: "Bearer " + access, "Content-Type": "application/json",
    }, 34_000);
    try {
      const access = await this.#access();
      let reply = await send(access);
      if (reply.status === 401) {
        if (this.#token?.access === access) this.#token = undefined;
        reply = await send(await this.#access());
      }
      if (reply.status === 429) throw new AuthError("cli_model_rate_limited", 429);
      if (reply.status === 422 || reply.status === 400) throw new AuthError("cli_model_input_rejected", 422);
      if (!Array.isArray(reply.data?.choices) || !reply.data.choices.length) throw new AuthError("cli_model_unavailable", 502);
      return { choices: reply.data.choices, usage: reply.data.usage };
    } catch (error) {
      if (error instanceof AuthError) throw error;
      throw new AuthError("cli_model_unavailable", 503);
    }
  }
}
