import { buildIncidentMessage } from './diagnostics.js';
import { incidentCopy, incidentGuide } from './incident_copy.js';

export const INCIDENT_BATCH_WINDOW_MS = 3000;
export const INCIDENT_BATCH_MAX = 8;
const OPERATIONS = new Set(['api.user.sync', 'api.user.progress.sync', 'api.user.progress',
  'api.user.status', 'api.user.premium', 'api.notifications', 'api.support.messages']);

// A temporal bundle is not a claim that separate failures share a root cause.
// Keep different people, devices, causes and payment/authentication events apart.
export function incidentBatchIdentity(event) {
  if (event.origin !== 'server' || event.category !== 'infrastructure' || !event.userId
      || event.payment || !OPERATIONS.has(event.operation) || !Number.isInteger(event.status) || event.status < 500 || event.status > 599) return null;
  return JSON.stringify([event.userId, event.code, event.status, event.platform, event.appVersion,
    event.device, event.country, event.os, event.authProvider, event.provider,
    event.context?.stage, event.context?.errorType, event.context?.retryable, event.context?.overloaded]);
}

const priority = event => incidentCopy(event).title === 'Сбой сервера' ? 0
  : event.operation === 'api.user.sync' ? 1 : event.operation === 'api.user.progress.sync' ? 2 : 3;

export function buildIncidentBatchMessage(entries) {
  const events = entries.map(entry => entry.incident).sort((a, b) => priority(a) - priority(b));
  const headings = [...new Set(events.map(event => incidentGuide(event).emoji + ' <b>' + incidentCopy(event).title + '</b>'))];
  const repeats = entries.reduce((total, entry) => total + (entry.repeats || 0), 0);
  const overflow = entries.reduce((total, entry) => total + (entry.overflow || 0), 0);
  // Shorten source fields before escaping rather than slicing HTML or hiding
  // an operation/diagnostic ID. An oversize result is sent as a separate alert.
  const options = entries.length === 1 ? {} : { headings, relatedEvents: events };
  const full = buildIncidentMessage(events[0], repeats, overflow, options);
  if (full.length <= 4096) return full;
  const primary = { ...events[0], userName: events[0].userName?.slice(0, 40),
    userEmail: events[0].userEmail?.slice(0, 80), device: events[0].device?.slice(0, 40) };
  return buildIncidentMessage(primary, repeats, overflow, options);
}
