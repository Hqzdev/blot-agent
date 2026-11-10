import nextEnv from "@next/env";
import { randomBytes } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

nextEnv.loadEnvConfig(fileURLToPath(new URL("../../", import.meta.url)));
const root = fileURLToPath(new URL("../", import.meta.url));
const directory = new URL("../.build/", import.meta.url);
const secretPath = new URL("auth-secret", directory);
await mkdir(directory, { recursive: true });
try { await writeFile(secretPath, randomBytes(32).toString("hex"), { flag: "wx", mode: 0o600 }); }
catch (error) { if (error.code !== "EEXIST") throw error; }
const secret = (await readFile(secretPath, "utf8")).trim();
if (!/^[a-f0-9]{64}$/.test(secret)) throw new Error("Invalid local account secret");
const child = spawn(process.execPath, ["node_modules/next/dist/bin/next", "dev", "--hostname", "127.0.0.1"], {
  cwd: root, stdio: "inherit", env: { ...process.env, BLOT_LOCAL_ACCOUNTS: "1",
    BLOT_WEB_SESSION_SECRET: secret, BLOT_AUTH_CHALLENGE_SECRET: secret,
    BLOT_GOOGLE_WEB_REDIRECT_URI: "http://127.0.0.1:3000/auth/google/callback" },
});
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
child.on("exit", code => { process.exitCode = code ?? 0; });
