import { env } from 'cloudflare:workers';

export async function redeemSchoolGrant(endpoint, body) {
  const response = await env.PDD_IDENTITY.fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
    redirect: 'manual',
    signal: AbortSignal.timeout(8000),
  });
  if (response.status === 400) return null;
  if (response.status !== 200) throw new Error('School sign-in unavailable');
  return response.text();
}
