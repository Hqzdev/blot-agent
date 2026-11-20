import nextEnv from "@next/env";
import { fileURLToPath } from "node:url";

// Server-only values stay out of nextConfig.env and the browser bundle.
const { combinedEnv } = nextEnv.loadEnvConfig(fileURLToPath(new URL("../", import.meta.url)));
// Next reloads the app directory's env later; retain explicitly loaded server settings.
nextEnv.updateInitialEnv(combinedEnv);

/** @type {import('next').NextConfig} */
const nextConfig = {
  turbopack: { root: fileURLToPath(new URL("../", import.meta.url)) },
  outputFileTracingRoot: fileURLToPath(new URL("../", import.meta.url)),
  devIndicators: false,
  // Older web deployments use a separate origin and have no /app base path.
  async redirects() {
    const legacy = process.env.BLOT_WEB_APP_URL === "https://blot-web-ha1zyys-projects.vercel.app";
    return legacy ? [{ source: "/app/pricing", destination: process.env.BLOT_WEB_APP_URL + "/pricing", permanent: false }] : [];
  },
  async rewrites() {
    const upstream = "https://blot-web-ha1zyys-projects.vercel.app";
    if (process.env.BLOT_WEB_APP_URL !== upstream) return [];
    return ["/api/billing/:path*", "/api/model/chat", "/api/yookassa-webhook"].map(path => ({
      source: "/app" + path, destination: upstream + path,
    }));
  },
  outputFileTracingIncludes: { "/api/auth/**/*": ["./lib/accounts/schema.sql"], "/auth/**/*": ["./lib/accounts/schema.sql"], "/v1/**/*": ["./lib/accounts/schema.sql"] },
  logging: { incomingRequests: { ignore: [/\/(?:auth|api\/auth|v1\/auth|login|register)(?:\/|\?|$)/] } },
};

export default nextConfig;
