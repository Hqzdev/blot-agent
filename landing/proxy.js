import { NextResponse } from "next/server";

// The web application is a separate deployment, exposed only through /app.
export function proxy(request) {
  const secret = process.env.BLOT_WEB_PROXY_SECRET;
  const configured = process.env.BLOT_WEB_UPSTREAM_URL;
  if (!secret || !configured) return new NextResponse("Web application unavailable", { status: 503 });
  const upstream = new URL(configured);
  if (upstream.protocol !== "https:" || upstream.pathname !== "/" || upstream.username || upstream.password || upstream.search || upstream.hash)
    return new NextResponse("Web application unavailable", { status: 503 });
  const destination = new URL(request.nextUrl.pathname + request.nextUrl.search, upstream);
  const headers = new Headers(request.headers);
  headers.set("x-blot-proxy-secret", secret);
  return NextResponse.rewrite(destination, { request: { headers } });
}

export const config = { matcher: "/app/:path*" };
