import test from 'node:test';
import assert from 'node:assert/strict';
import { acquisitionPurchaseEvidence, acquisitionSnapshot } from './acquisition_analytics.js';
import { usersSnapshot } from './analytics_data.js';
import { ANALYTICS_CLIENT_JS } from './analytics_ui.js';
import { USERS_CLIENT_JS } from './users_ui.js';

const now = Date.parse('2026-10-25T12:00:00Z');
const day = date => date.toISOString().slice(0, 10);
const base = { provider: 'google', app: 'ru', createdAt: '2026-10-25T02:00:00Z' };
const production = { evidenceVersion: 1, store: 'appstore', environment: 'Production', paid: true, refunded: false };
const webPayment = { awarded: true, amount: 99, at: '2026-10-25T10:00:00Z' };

test('buyer evidence excludes grants, test/sandbox, free trials and refunds; retains expired paid users', () => {
  const evidence = acquisitionPurchaseEvidence;
  assert.deepEqual(evidence({ isPremium: true, premiumSource: 'admin_grant' }), { hasPaidPurchase: false, purchaseEvidenceKnown: true });
  assert.equal(evidence({ isPremium: false, verifiedPurchase: production }).hasPaidPurchase, true);
  assert.equal(evidence({ verifiedPurchase: { ...production, environment: 'Sandbox' } }).hasPaidPurchase, false);
  assert.equal(evidence({ verifiedPurchase: { ...production, isTest: true } }).hasPaidPurchase, false);
  assert.equal(evidence({ verifiedPurchase: { ...production, paid: false } }).hasPaidPurchase, false);
  assert.equal(evidence({ verifiedPurchase: { ...production, refunded: true } }).hasPaidPurchase, false);
  assert.deepEqual(evidence({ verifiedPurchase: { ...production, store: 'googleplay', refunded: null } }), { hasPaidPurchase: false, purchaseEvidenceKnown: false });
  assert.equal(evidence({ verifiedPurchase: { ...production, revocationDate: now } }).hasPaidPurchase, false);
  assert.equal(evidence({ email: 'mojomaker.play@gmail.com', verifiedPurchase: production }).hasPaidPurchase, false);
  assert.deepEqual(evidence({ purchasedAt: base.createdAt, premiumSource: 'appstore' }), { hasPaidPurchase: false, purchaseEvidenceKnown: false });
  assert.equal(evidence({ verifiedPurchase: { store: 'appstore', transactionId: '123' } }).purchaseEvidenceKnown, false);
  assert.equal(evidence({ verifiedPurchase: { ...production, paid: null } }).purchaseEvidenceKnown, false);
  assert.equal(evidence({ verifiedPurchases: { appstore: { ...production, paid: null }, googleplay: { ...production, store: 'googleplay' } } }).hasPaidPurchase, true);
});

test('web buyers require unreversed positive confirmed payment; known test and chargeback stay excluded', () => {
  assert.equal(acquisitionPurchaseEvidence({ webPayments: { one: webPayment } }).hasPaidPurchase, true);
  for (const patch of [{ reversed: '2026-10-26' }, { isTest: true }, { test: true }, { amount: 0 }, { awarded: false }, { at: 'invalid' }]) {
    assert.equal(acquisitionPurchaseEvidence({ webPayments: { one: { ...webPayment, ...patch } } }).hasPaidPurchase, false, JSON.stringify(patch));
  }
  assert.equal(acquisitionPurchaseEvidence({ premiumSource: 'web', purchasedAt: base.createdAt }).purchaseEvidenceKnown, false);
  assert.equal(acquisitionPurchaseEvidence({ webPayments: { one: { ...webPayment, reversed: '2026-10-26' }, two: webPayment } }).hasPaidPurchase, true);
});

test('acquisition report uses registration cohorts, first source and confirmed account buyers, not active access', () => {
  const users = [
    { ...base, id: 'one', marketingSource: 'threads', marketingMedium: 'social', marketingCampaign: 'reel_1', landingPage: '/blog/first/', verifiedPurchase: production },
    { ...base, id: 'two', marketingSource: 'threads', marketingMedium: 'social', marketingCampaign: 'reel_1', landingPage: '/blog/first/', premiumSource: 'admin_grant', isPremium: true },
    { ...base, id: 'three', marketingSource: 'yandex', marketingMedium: 'organic', landingPage: '/blog/search/', webPayments: { one: webPayment, two: webPayment } },
    { ...base, id: 'four', installStore: 'App Store', purchasedAt: base.createdAt },
    { ...base, id: 'five', marketingSource: 'direct' },
    { ...base, id: 'six', marketingSource: 'google', marketingMedium: 'cpc', createdAt: '2026-09-01', verifiedPurchase: production },
    { ...base, id: 'seven', marketingSource: 'threads', suspect: true, verifiedPurchase: production },
    { ...base, id: 'eight', marketingSource: 'threads', provider: 'guest', verifiedPurchase: production },
    { ...base, id: 'nine', marketingSource: 'threads', pending: true, verifiedPurchase: production },
    { ...base, id: 'ten', marketingSource: 'threads', app: 'rs', verifiedPurchase: production },
  ];
  const result = usersSnapshot(users, 1, 'ru', day, now);
  assert.equal(result.acquisition.cohort.accounts, 5);
  assert.equal(result.acquisition.cohort.buyers, 2);
  assert.equal(result.acquisition.cohort.purchaseUnknown, 1);
  assert.equal(result.acquisition.allTime.accounts, 6);
  assert.equal(result.acquisition.allTime.buyers, 3);
  const threads = result.acquisition.cohort.rows.find(row => row.source === 'threads');
  assert.equal(threads.accounts, 2); assert.equal(threads.buyers, 1); assert.equal(threads.conversion, 0.5);
  assert.equal(result.acquisition.cohort.rows.find(row => row.source === 'unknown').accounts, 1);
  assert.equal(result.acquisition.cohort.rows.find(row => row.source === 'direct').accounts, 1);
  assert.deepEqual(result.acquisition.cohort.campaigns[0], { source: 'threads', medium: 'social', campaign: 'reel_1', accounts: 2, buyers: 1, purchaseUnknown: 0, conversion: 0.5 });
  assert.equal(result.acquisition.cohort.articles.find(row => row.landingPage === '/blog/search/').buyers, 1);
  assert.equal(result.cohort.paid, 2);
});

test('report bounds high-cardinality campaigns/articles, rejects malformed paths and never guesses store search', () => {
  const users = Array.from({ length: 80 }, (_, index) => ({ ...base, marketingSource: index % 2 ? 'google' : 'yandex', marketingCampaign: 'c' + index, landingPage: '/blog/a' + index + '/' }));
  users.push({ ...base, marketingSource: '__proto__', marketingCampaign: 'constructor', landingPage: '//foreign.test/' });
  users.push({ ...base, marketingSource: 'unknown', installStore: 'Google Play', landingPage: '/blog/article/?email=private' });
  const result = acquisitionSnapshot(users, ['2026-10-25'], day, now).cohort;
  assert.equal(result.accounts, 82); assert.equal(result.knownSources, 80);
  assert.equal(result.campaigns.length, 50); assert.equal(result.campaignsOmitted, 30);
  assert.equal(result.articles.length, 50); assert.equal(result.articlesOmitted, 30);
  assert.equal(result.rows.find(row => row.source === 'unknown').accounts, 2);
  assert.ok(!result.rows.some(row => row.source === 'google_play_organic'));
  assert.equal({}.accounts, undefined);
});

test('server summary proof survives as booleans and account/admin clients compile', () => {
  assert.deepEqual(acquisitionPurchaseEvidence({ hasPaidPurchase: true, purchaseEvidenceKnown: true }), { hasPaidPurchase: true, purchaseEvidenceKnown: true });
  assert.deepEqual(acquisitionPurchaseEvidence({ hasPaidPurchase: false, purchaseEvidenceKnown: false }), { hasPaidPurchase: false, purchaseEvidenceKnown: false });
  assert.doesNotThrow(() => new Function(ANALYTICS_CLIENT_JS));
  assert.doesNotThrow(() => new Function(USERS_CLIENT_JS));
});
