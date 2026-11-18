import { EconomyPayouts } from './economy_payouts.js';
import { MemoryStorage } from './fixture-account.mjs';

export function payoutBinding() {
  const ledger = new EconomyPayouts({ storage: new MemoryStorage() });
  return { idFromName: name => name, get: () => ({ fetch: (url, options) => ledger.fetch(new Request(url, options)) }) };
}
