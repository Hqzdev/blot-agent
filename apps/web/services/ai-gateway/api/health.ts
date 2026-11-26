export default function handler(): Response {
  return Response.json({ service: 'ai-gateway', status: 'ok' });
}
