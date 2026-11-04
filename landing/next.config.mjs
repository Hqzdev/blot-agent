import nextEnv from "@next/env";
import { fileURLToPath } from "node:url";

// Server-only values stay out of nextConfig.env and the browser bundle.
const { combinedEnv } = nextEnv.loadEnvConfig(fileURLToPath(new URL("../", import.meta.url)));
// Next reloads the app directory's env later; retain explicitly loaded server settings.
nextEnv.updateInitialEnv(combinedEnv);

/** @type {import('next').NextConfig} */
const nextConfig = {
  devIndicators: false,
  outputFileTracingIncludes: { "/api/auth/**/*": ["./lib/accounts/schema.sql"], "/auth/**/*": ["./lib/accounts/schema.sql"], "/v1/**/*": ["./lib/accounts/schema.sql"] },
  logging: { incomingRequests: { ignore: [/\/(?:auth|api\/auth|v1\/auth|login|register)(?:\/|\?|$)/] } },
};

export default nextConfig;
