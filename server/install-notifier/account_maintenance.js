import { accountRpc } from './account_state.js';
// Bounded rolling reconciliation uses the public KV index only to discover
// documents; their authoritative values and every mutation live in AccountState.
async function page(env, prefix, cursorKey, operation, select) {
  const cursor = await env.INSTALLS.get(cursorKey) || undefined;
  const batch = await env.INSTALLS.list({ prefix, limit: 25, cursor });
  for (const entry of batch.keys || []) {
    try {
      const raw = await env.INSTALLS.get(entry.name);
      const value = raw ? JSON.parse(raw) : null;
      const job = value && select(value);
      if (!job) continue;
      const response = await accountRpc(env, job.userId, operation, job);
      if (!response?.ok) throw new Error('account reconciliation unavailable');
    } catch { console.error('Account maintenance item deferred'); }
  }
  if (batch.list_complete === false && batch.cursor) await env.INSTALLS.put(cursorKey, batch.cursor);
  else await env.INSTALLS.delete(cursorKey);
}
export async function reconcileAccounts(env) {
  if (!env.ACCOUNTS || !env.INSTALLS) return;
  await page(env, 'pay_order:', 'reconcile:payments:cursor', '/_account/reconcile', order =>
    ['pending', 'confirmed', 'creating'].includes(order.status) && order.userId && Date.now() - Date.parse(order.createdAt || order.confirmedAt) < 180 * 86400000
      ? { userId: order.userId, orderId: order.orderId } : null);
  await page(env, 'user:', 'reconcile:subscriptions:cursor', '/_account/refresh', user =>
    user.id && (user.verifiedPurchase || user.verifiedPurchases) ? { userId: user.id } : null);
}
