import nextEnv from "@next/env";
import { fileURLToPath } from "node:url";
import { AccountSmtpTransport } from "../lib/accounts/smtp-transport.mjs";

nextEnv.loadEnvConfig(fileURLToPath(new URL("../../", import.meta.url)));
let transport;
try {
  transport = await new AccountSmtpTransport().create();
  await transport.verify();
  console.log("SMTP TLS and authentication verified; no email sent");
} catch (error) {
  console.error("SMTP verification failed:", error.code || "unknown");
  process.exitCode = 1;
} finally { transport?.close(); }
