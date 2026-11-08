import { beginSocialWrite, completeSocialWrite, socialGuard } from './social_guard.js';

function youtubeUploadPending() {
  return Object.assign(new Error('YouTube продолжает загрузку; сохранённая сессия будет проверена автоматически'), { code: 'ERR_YT_PROCESSING' });
}
function youtubeUploadUnconfirmed() {
  return Object.assign(new Error('Результат прежней загрузки YouTube не подтверждён. Новая загрузка остановлена до проверки'), { code: 'ERR_YT_PUBLICATION_UNCONFIRMED' });
}
const youtubeUploadResult = id => ({ videoId: id, permalink: 'https://youtube.com/shorts/' + id });
const youtubeUploadChecksum = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
  .map(v => v.toString(16).padStart(2, '0')).join('');

// Persist the session BEFORE sending bytes. A timeout is recovered using the
// provider's status probe, never a second videos.insert. The URL stays in the DO.
export async function resumableYoutubeUpload(env, post, getToken, loadBytes, initialize) {
  let write = await beginSocialWrite(env, post, 'youtube', false, true);
  if (write.result?.state === 'done') return youtubeUploadResult(write.result.id);
  let session = write.result?.session, offset = 0, bytes;
  if (write.result?.state === 'pending' && !session) throw youtubeUploadUnconfirmed();
  if (!session && post.youtubeNeedsReview) throw youtubeUploadUnconfirmed();
  const token = await getToken();
  const request = async (url, options) => {
    try {
      return await fetch(url, { ...options, redirect: 'manual', signal: AbortSignal.timeout(20000),
        headers: { authorization: 'Bearer ' + token, ...options.headers } });
    } catch (_) { throw env.SOCIAL_PUBLISHER ? youtubeUploadPending() : youtubeUploadUnconfirmed(); }
  };
  const completed = async response => {
    let data;
    try { data = await response.json(); } catch (_) { throw youtubeUploadPending(); }
    if (!response.ok || !/^[A-Za-z0-9_-]{1,100}$/.test(data?.id || '')) {
      if (response.status === 429 || response.status >= 500) throw youtubeUploadPending();
      throw youtubeUploadUnconfirmed();
    }
    await completeSocialWrite(env, post, write, data.id);
    return youtubeUploadResult(data.id);
  };

  if (session) {
    const response = await request(session.url, { method: 'PUT', body: '',
      headers: { 'content-range': 'bytes */' + session.total } });
    if (response.status !== 308) return completed(response);
    const range = response.headers.get('range');
    const match = range?.match(/^bytes=0-(\d+)$/);
    if (range && !match) throw youtubeUploadUnconfirmed();
    offset = match ? Number(match[1]) + 1 : 0;
    if (!Number.isSafeInteger(offset) || offset < 0 || offset >= session.total) throw youtubeUploadPending();
    bytes = await loadBytes();
    if (bytes.byteLength !== session.total || await youtubeUploadChecksum(bytes) !== session.sha256) throw youtubeUploadUnconfirmed();
  } else {
    bytes = await loadBytes();
    const url = await initialize(token, bytes.byteLength);
    write = await beginSocialWrite(env, post, 'youtube');
    if (write.result?.state === 'done') return youtubeUploadResult(write.result.id);
    session = { url, total: bytes.byteLength, sha256: await youtubeUploadChecksum(bytes) };
    await socialGuard(env, post.accountId, '/session', { key: write.key, owner: env.__SOCIAL_OWNER, session });
  }

  const response = await request(session.url, { method: 'PUT',
    headers: { 'content-type': 'video/mp4', 'content-range': `bytes ${offset}-${session.total - 1}/${session.total}` },
    body: offset ? bytes.slice(offset) : bytes });
  if (response.status === 308) throw youtubeUploadPending();
  return completed(response);
}
