import nextEnv from "@next/env";
import { fileURLToPath } from "node:url";
import nodemailer from "nodemailer";

nextEnv.loadEnvConfig(fileURLToPath(new URL("../../", import.meta.url)));
const env = process.env;
const port = Number(env.BLOT_SMTP_PORT || 587);
if (!env.BLOT_SMTP_HOST || !env.BLOT_SMTP_USERNAME || !env.BLOT_SMTP_PASSWORD || !env.BLOT_SMTP_FROM) {
  console.error("SMTP configuration is incomplete");
  process.exitCode = 1;
} else {
  const transport = nodemailer.createTransport({ host: env.BLOT_SMTP_HOST, port, secure: port === 465,
    requireTLS: true, auth: { user: env.BLOT_SMTP_USERNAME, pass: env.BLOT_SMTP_PASSWORD },
    connectionTimeout: 7000, greetingTimeout: 7000, socketTimeout: 10_000 });
  try {
    await transport.verify();
    console.log("SMTP TLS and authentication verified; no email sent");
  } catch (error) {
    console.error("SMTP verification failed:", error.code || "unknown");
    process.exitCode = 1;
  } finally { transport.close(); }
}
