import nodemailer from "nodemailer";
import { AuthError } from "../auth/errors.mjs";

export class AccountEmailSender {
  #environment;
  constructor(environment = process.env) { this.#environment = environment; }
  async sendCode(email, code, purpose) {
    const env = this.#environment;
    const port = Number(env.BLOT_SMTP_PORT || 587);
    if (!env.BLOT_SMTP_HOST || !env.BLOT_SMTP_USERNAME || !env.BLOT_SMTP_PASSWORD || !env.BLOT_SMTP_FROM
        || !Number.isInteger(port) || port < 1 || port > 65535) throw new AuthError("smtp_unconfigured", 503);
    const transport = nodemailer.createTransport({ host: env.BLOT_SMTP_HOST, port, secure: port === 465,
      requireTLS: true, auth: { user: env.BLOT_SMTP_USERNAME, pass: env.BLOT_SMTP_PASSWORD },
      connectionTimeout: 10_000, greetingTimeout: 10_000, socketTimeout: 15_000 });
    try {
      await transport.sendMail({ from: env.BLOT_SMTP_FROM, to: email,
        subject: purpose === "verify" ? "Blot — подтверждение почты" : "Blot — восстановление доступа",
        text: `Ваш код: ${code}\n\nКод действует 10 минут. Если вы не запрашивали письмо, проигнорируйте его.` });
    } catch { throw new AuthError("email_unavailable", 503); }
    finally { transport.close(); }
  }
}
