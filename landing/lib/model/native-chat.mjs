const gateway = "https://blot-web-ha1zyys-projects.vercel.app/api/model/chat";
const privateHeaders = { "Cache-Control": "no-store" };

export async function forwardNativeChat(request, send = fetch) {
  const authorization = request.headers.get("authorization");
  if (!/^Bearer [A-Za-z0-9_-]{43}$/.test(authorization ?? "")) {
    return new Response(null, { status: 401, headers: privateHeaders });
  }
  if (!request.body || !/^application\/json(?:;|$)/i.test(request.headers.get("content-type") ?? "")) {
    return new Response(null, { status: 400, headers: privateHeaders });
  }

  let upstream;
  try {
    upstream = await send(gateway, {
      method: "POST",
      headers: { Authorization: authorization, "Content-Type": "application/json", Accept: "text/event-stream" },
      body: request.body,
      duplex: "half",
      cache: "no-store",
      redirect: "error",
      signal: request.signal,
    });
  } catch {
    return new Response(null, { status: 502, headers: privateHeaders });
  }

  const headers = new Headers(privateHeaders);
  for (const name of ["content-type", "retry-after", "x-blot-quota-reset"]) {
    const value = upstream.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  return new Response(upstream.body, { status: upstream.status, headers });
}
