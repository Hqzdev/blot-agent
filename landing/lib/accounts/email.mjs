import { AccountSmtpTransport } from "./smtp-transport.mjs";
import { AuthError } from "../auth/errors.mjs";

export class AccountEmailSender {
  #environment;
  constructor(environment = process.env) { this.#environment = environment; }
  async sendCode(email, code, purpose) {
    let transport;
    try {
      transport = await new AccountSmtpTransport(this.#environment).create();
      await transport.sendMail({ from: this.#environment.BLOT_SMTP_FROM, to: email,
        subject: purpose === "delete" ? "Blot — удаление аккаунта" : purpose === "signin" ? "Blot — код для входа" : purpose === "verify" ? "Blot — подтверждение почты" : "Blot — восстановление доступа",
        text: `Ваш код: ${code}\n\nКод действует 10 минут. Если вы не запрашивали письмо, проигнорируйте его.` });
    } catch (error) {
      if (error instanceof AuthError) throw error;
      throw new AuthError("email_unavailable", 503);
    }
    finally { transport?.close(); }
  }
}
