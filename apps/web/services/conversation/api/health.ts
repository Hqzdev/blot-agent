export default function handler(): Response {
  return Response.json({ service: 'conversation', status: 'ok' });
}
