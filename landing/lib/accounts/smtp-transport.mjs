import { lookup } from "node:dns/promises";
import nodemailer from "nodemailer";
import { AuthError } from "../auth/errors.mjs";

export class AccountSmtpTransport {
  #environment;
  constructor(environment = process.env) { this.#environment = environment; }
  async create() {
    const env = this.#environment;
    const port = Number(env.BLOT_SMTP_PORT || 587);
    if (!env.BLOT_SMTP_HOST || !env.BLOT_SMTP_USERNAME || !env.BLOT_SMTP_PASSWORD || !env.BLOT_SMTP_FROM
        || !Number.isInteger(port) || port < 1 || port > 65535) throw new AuthError("smtp_unconfigured", 503);
    // Use the OS resolver so local VPN and DNS settings apply. TLS still verifies the configured hostname.
    const { address } = await lookup(env.BLOT_SMTP_HOST);
    return nodemailer.createTransport({ host: address, port, secure: port === 465,
      requireTLS: true, tls: { servername: env.BLOT_SMTP_HOST },
      auth: { user: env.BLOT_SMTP_USERNAME, pass: env.BLOT_SMTP_PASSWORD },
      connectionTimeout: 10_000, greetingTimeout: 10_000, socketTimeout: 15_000 });
  }
}
