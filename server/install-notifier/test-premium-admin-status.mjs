import { test } from 'node:test';
import assert from 'node:assert/strict';
import { googleEntitlement } from './store_verification.js';
import { userSummary, listUserSummaries } from './user_store.js';
import { USERS_CLIENT_JS } from './users_ui.js';

test('Google auto renewal preserves true, false and unknown independently of active access', () => {
  for (const value of [true, false, null]) {
    const result = googleEntitlement({ subscriptionState: 'SUBSCRIPTION_STATE_CANCELED',
      lineItems: [{ productId: 'p', expiryTime: '2030-01-01', autoRenewingPlan: { autoRenewEnabled: value } }] }, 'p', 0);
    assert.equal(result.active, true);
    assert.equal(result.autoRenewEnabled, value);
  }
});
test('older metadata is enriched with verified renewal without querying stores', async () => {
  const record = { id: 'u', premiumSource: 'googleplay', autoRenewEnabled: false, storeVerifiedAt: 123 };
  let saved;
  const env = { INSTALLS: {
    list: async () => ({ keys: [{ name: 'user:u', metadata: { id: 'u', v: 3 } }], list_complete: true }),
    get: async () => JSON.stringify(record), put: async (_, __, options) => { saved = options.metadata; },
  } };
  const result = await listUserSummaries(env);
  assert.equal(result[0].autoRenewEnabled, false);
  assert.equal(saved.v, 4);
  assert.equal(userSummary(record).storeVerifiedAt, 123);
});
test('admin client parses; labels distinguish source and unknown renewal', () => {
  new Function(USERS_CLIENT_JS);
  const start = USERS_CLIENT_JS.indexOf('function uvPremiumDetails(u)');
  const end = USERS_CLIENT_JS.indexOf('function uvPremiumCard(u)', start);
  const details = new Function('UV_SOURCES', 'uvEsc', 'uvDate', USERS_CLIENT_JS.slice(start, end) + '; return uvPremiumDetails;')(
    { googleplay: 'Google Play', appstore: 'App Store' }, String, String);
  assert.match(details({ premiumSource: 'admin_grant', autoRenewEnabled: true }), /Выдан вручную.*не применяется/s);
  assert.match(details({ premiumSource: 'appstore', autoRenewEnabled: false }), /Куплен · App Store.*выключено/s);
  assert.match(details({ premiumSource: 'googleplay' }), /неизвестно/);
});
