import { marketingSource, campaignToken } from './attribution.js';

const STORES = new Set(['appstore', 'googleplay', 'rustore']);
const testRecord = value => value?.isTest === true || value?.test === true
  || String(value?.environment || '').toLowerCase() === 'sandbox';
const testAccount = user => testRecord(user)
  || String(user.email || '').trim().toLowerCase() === 'mojomaker.play@gmail.com';

// Calculated while projecting a full profile. Only bounded booleans enter KV
// metadata: neither transaction references nor payment tokens go to the list API.
export function acquisitionPurchaseEvidence(user = {}) {
  if (testAccount(user)) return { hasPaidPurchase: false, purchaseEvidenceKnown: true };
  // Already calculated by the server for a profile summary.
  if (typeof user.hasPaidPurchase === 'boolean' && typeof user.purchaseEvidenceKnown === 'boolean') {
    return { hasPaidPurchase: user.hasPaidPurchase, purchaseEvidenceKnown: user.purchaseEvidenceKnown };
  }
  let hasPaidPurchase = false, incomplete = false;
  for (const payment of Object.values(user.webPayments || {})) {
    if (!payment || testRecord(payment) || payment.reversed || payment.refunded) continue;
    if (payment.awarded !== false && Number(payment.amount) > 0 && Number.isFinite(Date.parse(payment.at || ''))) hasPaidPurchase = true;
    else incomplete = true;
  }
  const references = Object.values(user.verifiedPurchases || {});
  if (user.verifiedPurchase) references.push(user.verifiedPurchase);
  for (const reference of references) {
    if (!reference || !STORES.has(reference.store)) continue;
    if (testRecord(reference) || reference.refunded || reference.revokedAt || reference.revocationDate) continue;
    if (reference.refunded === null) { incomplete = true; continue; }
    if (reference.evidenceVersion === 1 && String(reference.environment).toLowerCase() === 'production'
        && typeof reference.paid === 'boolean') {
      if (reference.paid) hasPaidPurchase = true;
    } else incomplete = true;
  }
  // Old purchasedAt/effective Premium source cannot distinguish a production
  // payment, a sandbox transaction or a grant. Leave that evidence incomplete.
  const legacyPurchase = user.purchasedAt || (STORES.has(user.premiumSource) && !references.length)
    || (user.premiumSource === 'web' && !Object.keys(user.webPayments || {}).length);
  if (legacyPurchase && !references.length && !Object.keys(user.webPayments || {}).length) incomplete = true;
  return { hasPaidPurchase, purchaseEvidenceKnown: hasPaidPurchase || !incomplete };
}

function mediumToken(value) {
  const token = String(value || '').trim().toLowerCase();
  return /^[a-z0-9._-]{1,40}$/.test(token) ? token : '';
}
function landingPath(value) {
  const path = String(value || '');
  return path.startsWith('/') && !path.startsWith('//') && !/[?#<>\s\\]/.test(path) ? path.slice(0, 240) : '';
}
function rowFor(map, key, fields) {
  if (!map.has(key)) map.set(key, { ...fields, accounts: 0, buyers: 0, purchaseUnknown: 0 });
  return map.get(key);
}
function add(row, evidence) {
  row.accounts++;
  if (evidence.hasPaidPurchase) row.buyers++;
  if (!evidence.purchaseEvidenceKnown) row.purchaseUnknown++;
}
function finish(map, limit) {
  const rows = [...map.values()].sort((a, b) => b.accounts - a.accounts || b.buyers - a.buyers);
  return { rows: rows.slice(0, limit).map(row => ({ ...row,
    conversion: row.accounts ? row.buyers / row.accounts : 0,
  })), omitted: Math.max(0, rows.length - limit) };
}
function summarize(users) {
  const sources = new Map(), campaigns = new Map(), articles = new Map();
  let buyers = 0, purchaseUnknown = 0, knownSources = 0, articleAccounts = 0;
  for (const user of users) {
    const source = marketingSource(user.marketingSource), medium = mediumToken(user.marketingMedium);
    const campaign = campaignToken(user.marketingCampaign), article = landingPath(user.landingPage);
    const evidence = acquisitionPurchaseEvidence(user);
    if (evidence.hasPaidPurchase) buyers++;
    if (!evidence.purchaseEvidenceKnown) purchaseUnknown++;
    if (source !== 'unknown') knownSources++;
    add(rowFor(sources, JSON.stringify([source, medium]), { source, medium }), evidence);
    if (campaign) add(rowFor(campaigns, JSON.stringify([source, medium, campaign]), { source, medium, campaign }), evidence);
    if (article.startsWith('/blog/') && article !== '/blog/') {
      add(rowFor(articles, article, { landingPage: article }), evidence);
      articleAccounts++;
    }
  }
  const sourceRows = finish(sources, 100), campaignRows = finish(campaigns, 50), articleRows = finish(articles, 50);
  return { accounts: users.length, buyers, purchaseUnknown, knownSources, articleAccounts,
    rows: sourceRows.rows, sourcesOmitted: sourceRows.omitted,
    campaigns: campaignRows.rows, campaignsOmitted: campaignRows.omitted,
    articles: articleRows.rows, articlesOmitted: articleRows.omitted };
}

// The cohort is selected by registration date. A buyer is counted once per
// account, regardless of renewal count, current access or the date of payment.
export function acquisitionSnapshot(users, periodKeys, dayKey, now = Date.now()) {
  const selected = new Set(periodKeys);
  const cohort = users.filter(user => {
    const created = Date.parse(user.createdAt || '');
    return Number.isFinite(created) && created <= now && selected.has(dayKey(new Date(created)));
  });
  return { cohort: summarize(cohort), allTime: summarize(users) };
}
