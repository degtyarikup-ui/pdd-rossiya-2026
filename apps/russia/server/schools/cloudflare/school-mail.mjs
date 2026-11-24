import { env } from 'cloudflare:workers';

export async function sendMail(envelope) {
  await env.EMAIL.send(JSON.parse(envelope));
}
