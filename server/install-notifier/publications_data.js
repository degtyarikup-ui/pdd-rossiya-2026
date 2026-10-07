// Read-only view of the existing blog, Threads and video queues. The planner
// never writes derived dates or statuses back to those queues.

const PUBLICATION_CHANNELS = ['blog', 'threads', 'instagram', 'youtube'];
const PUBLICATION_STATUSES = ['scheduled', 'queued', 'processing', 'published', 'failed', 'draft', 'dated'];
const MSK_OFFSET = 3 * 60 * 60 * 1000;

function publicationValidDay(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) return false;
  const parsed = new Date(value + 'T00:00:00.000Z');
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

/** A datetime-local value is always Moscow time, independently of the browser. */
export function publicationMskToIso(value) {
  const match = String(value || '').match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?$/);
  if (!match || !publicationValidDay(match[1])) return null;
  if (Number(match[2]) > 23 || Number(match[3]) > 59 || Number(match[4] || 0) > 59) return null;
  const timestamp = Date.parse(match[1] + 'T' + match[2] + ':' + match[3] + ':' + (match[4] || '00') + '.000Z');
  return new Date(timestamp - MSK_OFFSET).toISOString();
}

function publicationTimestamp(value) {
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? value.getTime() : null;
  if (typeof value === 'number') return Number.isFinite(value) && Math.abs(value) <= 8640000000000000 ? value : null;
  const text = String(value || '').trim();
  if (publicationValidDay(text)) return Date.parse(text + 'T00:00:00.000Z') - MSK_OFFSET;
  const local = publicationMskToIso(text);
  if (local) return Date.parse(local);
  const match = text.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/);
  if (!match || !publicationValidDay(match[1]) || Number(match[2]) > 23 || Number(match[3]) > 59 || Number(match[4] || 0) > 59) return null;
  const timestamp = Date.parse(text);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function publicationIso(value) {
  const timestamp = publicationTimestamp(value);
  return timestamp === null ? null : new Date(timestamp).toISOString();
}

export function publicationDay(value) {
  const timestamp = publicationTimestamp(value);
  return timestamp === null ? null : new Date(timestamp + MSK_OFFSET).toISOString().slice(0, 10);
}

export function publicationTime(value) {
  const timestamp = publicationTimestamp(value);
  return timestamp === null ? null : new Date(timestamp + MSK_OFFSET).toISOString().slice(11, 16);
}

function publicationNow(value) {
  const timestamp = publicationTimestamp(value);
  return timestamp === null ? Date.now() : timestamp;
}

function publicationSafeUrl(value) {
  const text = String(value || '').trim();
  if (/^\/(?!\/)/.test(text)) return text;
  try {
    const parsed = new URL(text);
    return ['https:', 'http:'].includes(parsed.protocol) ? parsed.href : null;
  } catch (_) {
    return null;
  }
}

function publicationArray(value) {
  return Array.isArray(value) ? value.filter(item => item && typeof item === 'object' && !Array.isArray(item)) : [];
}

function publicationRecord(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function publicationText(value, fallback = '') {
  return typeof value === 'string' ? value : fallback;
}

function publicationTitle(value, fallback) {
  return publicationText(value).replace(/\s+/g, ' ').trim().slice(0, 180) || fallback;
}

function publicationBase(type, sourceId, index) {
  const id = String(sourceId == null || sourceId === '' ? index : sourceId);
  return {
    id: type + ':' + id, sourceType: type, sourceId: id, channels: [],
    title: '', text: '', date: null, time: null, scheduledAt: null, publishedAt: null,
    status: 'queued', thumbnail: null, previewUrl: null, permalink: null, error: null,
    accountId: null, accountName: null, autoTime: null, scheduleMode: 'none',
    paused: false, channelStatuses: {}, partialPublished: false, overdue: false,
    publicationVerified: true, legacyDate: null, createdAt: null,
  };
}

/**
 * Inputs are the existing API responses, without a second persisted queue.
 * Blog dates describe the catalogue plan; they are not verified site releases.
 * Undated videos remain queued because active account slots can publish them.
 */
export function normalizePublications(sources = {}, options = {}) {
  const input = publicationRecord(sources);
  const now = publicationNow(options.now);
  const today = publicationDay(now);
  const threads = publicationRecord(input.threads);
  const social = publicationRecord(input.social);
  const accounts = new Map(publicationArray(social.accounts).map(account => [String(account.id), account]));
  const blog = publicationArray(Array.isArray(input.blog) ? input.blog : publicationRecord(input.blog).articles);
  const items = [];

  blog.forEach((article, index) => {
    const item = publicationBase('blog', article.slug, index);
    const date = publicationValidDay(article.datePublished) ? article.datePublished : null;
    item.channels = ['blog'];
    item.title = publicationTitle(article.title || article.shortTitle, 'Статья без названия');
    item.text = publicationText(article.description);
    item.date = date;
    item.status = article.published === false ? 'draft' : date ? (date >= today ? 'scheduled' : 'dated') : 'draft';
    item.scheduleMode = date && article.published !== false ? 'date' : 'none';
    item.publicationVerified = false;
    const base = 'https://pdd-drive.ru/blog/' + encodeURIComponent(item.sourceId) + '/';
    const cover = publicationText(article.cover);
    item.thumbnail = publicationSafeUrl(cover)
      || (cover && !/[\\/]/.test(cover) ? base + encodeURIComponent(cover) : null);
    item.permalink = base;
    item.readingMinutes = Number.isFinite(Number(article.readingMinutes)) ? Number(article.readingMinutes) : null;
    items.push(item);
  });

  publicationArray(Array.isArray(input.threads) ? input.threads : threads.posts).forEach((post, index) => {
    const item = publicationBase('threads', post.id, index);
    item.channels = ['threads'];
    item.title = publicationTitle(post.text, 'Пост без текста');
    item.text = publicationText(post.text);
    item.scheduledAt = publicationIso(post.scheduledAt);
    item.publishedAt = publicationIso(post.publishedAt);
    item.createdAt = publicationIso(post.createdAt);
    item.legacyDate = publicationDay(post.scheduledDate);
    item.status = ['published', 'failed', 'processing'].includes(post.status)
      ? post.status : item.scheduledAt ? 'scheduled' : 'queued';
    const effectiveDate = item.status === 'published' ? item.publishedAt || item.scheduledAt : item.scheduledAt;
    item.date = publicationDay(effectiveDate);
    item.time = publicationTime(effectiveDate);
    item.scheduleMode = item.scheduledAt ? 'date' : 'none';
    item.thumbnail = publicationSafeUrl(post.imageUrl);
    item.permalink = publicationSafeUrl(post.permalink);
    item.error = publicationText(post.error) || null;
    item.accountName = publicationText(threads.settings && threads.settings.username) || null;
    item.channelStatuses = { threads: item.status };
    item.overdue = item.status === 'scheduled' && publicationTimestamp(item.scheduledAt) < now;
    items.push(item);
  });

  publicationArray(social.posts).forEach((post, index) => {
    const item = publicationBase('social', post.id, index);
    const account = accounts.get(String(post.accountId));
    const targetSource = Array.isArray(post.targets) && post.targets.length
      ? post.targets : account && Array.isArray(account.targets) ? account.targets : ['instagram', 'youtube'];
    item.channels = [...new Set(targetSource.filter(channel => ['instagram', 'youtube'].includes(channel)))];
    item.title = publicationTitle(post.title || post.fileName, 'Ролик без названия');
    item.text = publicationText(post.caption);
    item.fileName = publicationText(post.fileName);
    item.scheduledAt = publicationIso(post.scheduledAt);
    item.publishedAt = publicationIso(post.publishedAt);
    item.createdAt = publicationIso(post.createdAt);
    item.status = ['published', 'failed', 'processing'].includes(post.status)
      ? post.status : item.scheduledAt ? 'scheduled' : 'queued';
    const effectiveDate = item.status === 'published' ? item.publishedAt || item.scheduledAt : item.scheduledAt;
    item.date = publicationDay(effectiveDate);
    item.time = publicationTime(effectiveDate);
    item.accountId = post.accountId == null ? null : String(post.accountId);
    item.accountName = account ? publicationText(account.name) || null : null;
    item.paused = !account || !account.active;
    item.autoTime = account && /^\d{1,2}:\d{2}$/.test(String(account.postTime || '')) ? String(account.postTime) : '19:00';
    item.scheduleMode = item.scheduledAt ? 'date' : 'automatic';
    const token = publicationText(post.streamToken);
    if (/^[A-Za-z0-9_-]{1,128}$/.test(token)) {
      item.thumbnail = '/s/t/' + token;
      item.previewUrl = '/s/v/' + token;
    }
    item.permalinks = {};
    item.channels.forEach(channel => {
      const key = channel === 'instagram' ? 'instagramStatus' : 'youtubeStatus';
      item.channelStatuses[channel] = ['published', 'processing', 'failed'].includes(post[key])
        ? post[key] : item.status === 'published' ? 'published' : 'queued';
      const link = publicationSafeUrl(post[channel + 'Permalink']);
      if (link) item.permalinks[channel] = link;
    });
    item.permalink = item.permalinks.instagram || item.permalinks.youtube || null;
    item.partialPublished = item.channels.some(channel => item.channelStatuses[channel] === 'published')
      && item.channels.some(channel => item.channelStatuses[channel] !== 'published');
    item.error = publicationText(post.error) || (!account ? 'Аккаунт удалён' : null);
    item.overdue = item.status === 'scheduled' && !item.paused && publicationTimestamp(item.scheduledAt) < now;
    items.push(item);
  });
  return items;
}

/** Filter against the Moscow publication day, never the browser's local day. */
export function filterPublications(items, options = {}) {
  const channel = String(options.channel || 'all');
  const status = String(options.status || 'all');
  const query = String(options.query || '').trim().toLocaleLowerCase('ru');
  const from = publicationValidDay(options.dateFrom) ? options.dateFrom : null;
  const to = publicationValidDay(options.dateTo) ? options.dateTo : null;
  return publicationArray(items).filter(item => {
    if (channel !== 'all' && !(item.channels || []).includes(channel)) return false;
    if (status !== 'all' && item.status !== status) return false;
    if (query && ![item.title, item.text, item.sourceId, item.accountName, item.fileName].filter(Boolean)
      .join(' ').toLocaleLowerCase('ru').includes(query)) return false;
    if (!item.date && (from || to) && options.includeUndated !== true) return false;
    if (item.date && from && item.date < from) return false;
    if (item.date && to && item.date > to) return false;
    return true;
  }).sort((a, b) => {
    if (!a.date && b.date) return 1;
    if (a.date && !b.date) return -1;
    const dates = String(a.date || '').localeCompare(String(b.date || ''));
    if (dates) return dates;
    const times = String(a.time || '').localeCompare(String(b.time || ''));
    return times || String(a.id).localeCompare(String(b.id));
  });
}

/** Content totals count a multi-platform video once; channel totals count destinations. */
export function summarizePublications(items, options = {}) {
  const all = publicationArray(items);
  const now = publicationNow(options.now);
  const today = publicationDay(now);
  const end = publicationDay(now + 6 * 86400000);
  const summary = {
    total: all.length,
    counts: Object.fromEntries(PUBLICATION_STATUSES.map(status => [status, 0])),
    channels: Object.fromEntries(PUBLICATION_CHANNELS.map(channel => [channel, 0])),
    today: 0, next7Days: 0, attention: 0, undated: 0, automatic: 0,
  };
  all.forEach(item => {
    if (Object.hasOwn(summary.counts, item.status)) summary.counts[item.status] += 1;
    [...new Set(item.channels || [])].forEach(channel => {
      if (Object.hasOwn(summary.channels, channel)) summary.channels[channel] += 1;
    });
    if (item.status === 'scheduled' && item.date === today) summary.today += 1;
    if (item.status === 'scheduled' && item.date >= today && item.date <= end) summary.next7Days += 1;
    if (item.status === 'failed' || item.overdue) summary.attention += 1;
    if (!item.date && !['published', 'dated'].includes(item.status)) summary.undated += 1;
    if (item.scheduleMode === 'automatic' && !item.paused && ['queued', 'failed'].includes(item.status)) summary.automatic += 1;
  });
  return summary;
}

// The admin is a single HTML response, so expose the same pure functions there.
export const PUBLICATIONS_DATA_CLIENT_JS = [
  'const PUBLICATION_CHANNELS = ' + JSON.stringify(PUBLICATION_CHANNELS) + ';',
  'const PUBLICATION_STATUSES = ' + JSON.stringify(PUBLICATION_STATUSES) + ';',
  'const MSK_OFFSET = ' + MSK_OFFSET + ';',
  publicationValidDay, publicationMskToIso, publicationTimestamp, publicationIso,
  publicationDay, publicationTime, publicationNow, publicationSafeUrl,
  publicationArray, publicationRecord, publicationText, publicationTitle,
  publicationBase, normalizePublications, filterPublications, summarizePublications,
].map(part => typeof part === 'function' ? part.toString() : part).join('\n');
