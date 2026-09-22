// Strongly consistent ownership: two accounts cannot claim the same receipt
// concurrently (Workers KV is eventually consistent and is not a lock).
export class PurchaseClaims {
  constructor(state) { this.state = state; }
  async fetch(request) {
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
