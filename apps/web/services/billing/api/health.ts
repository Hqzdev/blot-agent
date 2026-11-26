export default function handler(): Response {
  return Response.json({ service: 'billing', status: 'ok' });
}
