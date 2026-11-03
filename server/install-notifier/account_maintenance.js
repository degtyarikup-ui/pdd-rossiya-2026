import { accountRpc } from './account_state.js';

// The caller classifies the original cause. Only these internal stage labels
// are exported to the incident log; KV keys and provider errors stay private.
export class ReconcilePageFailure extends Error {
  constructor(scope, stage, cause) {
    super('Account maintenance page failed', { cause });
    this.stage = scope + '.' + stage;
  }
}

async function page(env, scope, prefix, operation, select) {
  const cursorKey = 'reconcile:' + scope + ':cursor';
  let stage = 'read_cursor';
  try {
    const cursor = await env.INSTALLS.get(cursorKey) || undefined;
    stage = 'list';
    const batch = await env.INSTALLS.list({ prefix, limit: 25, cursor });
    for (const entry of batch.keys || []) {
      let itemStage = 'read_item';
      try {
        const raw = await env.INSTALLS.get(entry.name);
        itemStage = 'decode_item';
        const value = raw ? JSON.parse(raw) : null;
        const job = value && select(value);
        if (!job) continue;
        itemStage = 'account';
        const response = await accountRpc(env, job.userId, operation, job);
        if (!response?.ok) throw new Error('account reconciliation unavailable');
      } catch { console.error('Account maintenance item deferred', scope, itemStage); }
    }
    if (batch.list_complete === false && batch.cursor) {
      stage = 'save_cursor';
      await env.INSTALLS.put(cursorKey, batch.cursor);
    } else {
      stage = 'clear_cursor';
      await env.INSTALLS.delete(cursorKey);
    }
  } catch (cause) {
    throw new ReconcilePageFailure(scope, stage, cause);
  }
}

export async function reconcileAccounts(env) {
  if (!env.ACCOUNTS || !env.INSTALLS) return;
  // KV only discovers candidate keys; authoritative mutations live in AccountState.
  await page(env, 'payments', 'pay_order:', '/_account/reconcile', order =>
    ['pending', 'confirmed', 'creating'].includes(order.status) && order.userId && Date.now() - Date.parse(order.createdAt || order.confirmedAt) < 180 * 86400000
      ? { userId: order.userId, orderId: order.orderId } : null);
  await page(env, 'subscriptions', 'user:', '/_account/refresh', user =>
    user.id && (user.verifiedPurchase || user.verifiedPurchases) ? { userId: user.id } : null);
}
