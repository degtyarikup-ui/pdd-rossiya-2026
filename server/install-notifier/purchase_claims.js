import { isBackupRequest, handleBackupExport } from './durable_backup.js';
// Strongly consistent ownership: two accounts cannot claim the same receipt
// concurrently (Workers KV is eventually consistent and is not a lock).
export class PurchaseClaims {
  constructor(state, env) { this.state = state; this.env = env; }
  async fetch(request) {
    if (isBackupRequest(request)) return handleBackupExport(request, { state: this.state, env: this.env, className: 'PurchaseClaims' });
    if (request.method === 'GET') return Response.json({ userId: await this.state.storage.get('owner') || null });
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    const { userId } = await request.json();
    if (typeof userId !== 'string' || !userId) return new Response(null, { status: 400 });
    const allowed = await this.state.storage.transaction(async txn => {
      const owner = await txn.get('owner');
      if (owner && owner !== userId) return false;
      await txn.put('owner', userId);
      return true;
    });
    return new Response(null, { status: allowed ? 204 : 403 });
  }
}
