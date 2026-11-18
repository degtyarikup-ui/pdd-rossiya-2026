// One strongly consistent ledger for project distributions, independent of the
// legacy KV settings document. A retried request cannot create a second payment.
export class EconomyPayouts {
  constructor(state) { this.storage = state.storage; }

  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (request.method === 'GET') {
      const rows = [];
      let startAfter;
      while (true) {
        const page = await this.storage.list({ prefix: path === '/entries' ? '' : 'pay:', limit: 512, startAfter });
        for (const [key, row] of page) {
          startAfter = key;
          if (!row.deleted) rows.push(row);
        }
        if (page.size < 512) break;
      }
      return Response.json(rows);
    }
    const { action, id, revision, entry } = await request.json();
    const development = path === '/development';
    const key = (development ? 'dev:' : 'pay:') + id;
    const fields = development ? ['partnerId','month','date','amount','title'] : ['partnerId','month','date','amount'];
    const result = await this.storage.transaction(async tx => {
      const old = await tx.get(key);
      const replay = action === 'add' && old?.revision === 1 || action === 'update' && old?.revision === revision + 1;
      if (replay && !old.deleted && fields.every(field => old[field] === entry[field])) {
        return { ok: true, [development ? 'expense' : 'payout']: old };
      }
      if (action !== 'add' && !old) return { error: 'Запись не найдена', status: 404 };
      if (action === 'delete' && old?.deleted && old.revision === revision + 1) return { ok: true, id };
      if (action === 'add' ? old : old.deleted || old.revision !== revision) {
        return { error: 'Запись уже изменилась. Обновите журнал.', status: 409 };
      }
      if (entry && !entry.partnerName) {
        if (entry.partnerId !== old?.partnerId || entry.month !== old.month) return { error: development ? 'Фонд недоступен за этот месяц' : 'Выберите партнёра за указанный месяц', status: 400 };
        entry.partnerName = old.partnerName;
      }
      const next = action === 'delete' ? { deleted: true, revision: revision + 1 }
        : { ...old, ...entry, id, revision: (old?.revision || 0) + 1 };
      await tx.put(key, next);
      return action === 'delete' ? { ok: true, id } : { ok: true, [development ? 'expense' : 'payout']: next };
    });
    return Response.json(result, { status: result.status || 200 });
  }
}

export function payoutLedger(env) {
  const namespace = env.ECONOMY_PAYOUTS;
  return namespace?.get(namespace.idFromName('project'));
}

export function monthlyBalances(shares, entries, month) {
  const rows = new Map(shares.map(share => [share.id, { ...share, paidCents: 0 }]));
  for (const entry of entries) {
    if (entry.month !== month) continue;
    const row = rows.get(entry.partnerId) || { id: entry.partnerId, name: entry.partnerName, percent: 0, payoutUsd: 0, paidCents: 0 };
    row.paidCents += Math.round(entry.amount * 100);
    rows.set(row.id, row);
  }
  return Array.from(rows.values(), ({ paidCents, ...share }) => ({ ...share,
    paidUsd: paidCents / 100, remainingUsd: (Math.round(share.payoutUsd * 100) - paidCents) / 100 }));
}
