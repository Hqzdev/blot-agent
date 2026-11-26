export default function handler(): Response {
  return Response.json({ service: 'identity', status: 'ok' });
}
