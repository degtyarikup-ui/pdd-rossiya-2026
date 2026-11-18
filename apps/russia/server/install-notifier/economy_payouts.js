// One strongly consistent ledger for project distributions, independent of the
// legacy KV settings document. A retried request cannot create a second payment.
export class EconomyPayouts {
  constructor(state) { this.storage = state.storage; }

  async fetch(request) {
    if (request.method === 'GET') {
      const rows = [];
      let startAfter;
      while (true) {
        const page = await this.storage.list({ prefix: 'pay:', limit: 512, startAfter });
        for (const [key, row] of page) {
          startAfter = key;
          if (!row.deleted) rows.push(row);
        }
        if (page.size < 512) break;
      }
      return Response.json(rows);
    }
    const { action, id, revision, entry } = await request.json();
    const key = 'pay:' + id;
    const result = await this.storage.transaction(async tx => {
      const old = await tx.get(key);
      if (action === 'add' && old && !old.deleted && old.revision === 1 &&
          ['partnerId','month','date','amount'].every(field => old[field] === entry[field])) {
        return { ok: true, payout: old };
      }
      if (action !== 'add' && !old) return { error: 'Выплата не найдена', status: 404 };
      if (action === 'delete' && old?.deleted && old.revision === revision + 1) return { ok: true, id };
      if (action === 'add' ? old : old.deleted || old.revision !== revision) {
        return { error: 'Запись уже изменилась. Обновите журнал.', status: 409 };
      }
      if (entry && !entry.partnerName) {
        if (entry.partnerId !== old?.partnerId || entry.month !== old.month) return { error: 'Выберите партнёра за указанный месяц', status: 400 };
        entry.partnerName = old.partnerName;
      }
      const next = action === 'delete' ? { deleted: true, revision: revision + 1 }
        : { ...entry, id, revision: (old?.revision || 0) + 1 };
      await tx.put(key, next);
      return action === 'delete' ? { ok: true, id } : { ok: true, payout: next };
    });
    return Response.json(result, { status: result.status || 200 });
  }
}

export function payoutLedger(env) {
  const namespace = env.ECONOMY_PAYOUTS;
  return namespace?.get(namespace.idFromName('project'));
}

export function monthlyBalances(shares, payouts, month) {
  const rows = new Map(shares.map(share => [share.id, { ...share, paidCents: 0 }]));
  for (const payout of payouts) {
    if (payout.month !== month) continue;
    const row = rows.get(payout.partnerId) || { id: payout.partnerId, name: payout.partnerName, percent: 0, payoutUsd: 0, paidCents: 0 };
    row.paidCents += Math.round(payout.amount * 100);
    rows.set(row.id, row);
  }
  return Array.from(rows.values(), ({ paidCents, ...share }) => ({ ...share,
    paidUsd: paidCents / 100, remainingUsd: (Math.round(share.payoutUsd * 100) - paidCents) / 100 }));
}
