// Custom covers are independent of the publication queue, keyed by immutable
// Drive file ID. Updating a cover cannot overwrite dates or publication history.
export const youtubeThumbnailKey = driveFileId => 'social:youtube-thumbnail:' + driveFileId;

export async function loadYoutubeThumbnail(env, post) {
  if (!post.driveFileId || post.youtubeFormat !== 'video') return null;
  const raw = await env.INSTALLS.get(youtubeThumbnailKey(post.driveFileId));
  if (!raw) return null;
  try {
    const record = JSON.parse(raw);
    if (record.schema !== 1 || record.mimeType !== 'image/png' || typeof record.data !== 'string'
      || record.data.length > 4 * 1024 * 1024 || !/^[a-f0-9]{64}$/.test(record.sha256)) throw Error();
    const bytes = Uint8Array.from(atob(record.data), c => c.charCodeAt(0));
    if (bytes.length < 24 || [137,80,78,71,13,10,26,10].some((v, i) => bytes[i] !== v)) throw Error();
    const sha256 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
      .map(v => v.toString(16).padStart(2, '0')).join('');
    if (sha256 !== record.sha256) throw Error();
    return { bytes, sha256, mimeType: record.mimeType };
  } catch (_) {
    throw new Error('Обложка YouTube повреждена; загрузите PNG заново');
  }
}

// Pauses before the second and third attempt. The video is already uploaded,
// so retrying thumbnails.set can never create a second copy of it.
export const thumbnailRetryDelays = { ms: [2000, 6000] };
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

export async function setYoutubeThumbnail(thumbnail, videoId, getToken) {
  if (!thumbnail) return null;
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) throw new Error('Не удалось определить видео для обложки');
  const delays = thumbnailRetryDelays.ms;
  let failure = null;
  for (let attempt = 0; attempt <= delays.length; attempt++) {
    if (attempt) await wait(delays[attempt - 1]);
    let token;
    try {
      token = await getToken();
    } catch (_) {
      failure = new Error('Не удалось получить доступ к каналу YouTube для обложки. Проверьте подключение Google-аккаунта в настройках автопостинга; повтор продолжит работу с тем же видео');
      continue;
    }
    let response;
    try {
      response = await fetch('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?uploadType=media&videoId=' + encodeURIComponent(videoId), {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { authorization: 'Bearer ' + token, 'content-type': thumbnail.mimeType },
        body: thumbnail.bytes,
      });
    } catch (_) {
      failure = new Error('YouTube не ответил при установке обложки (' + (attempt + 1) + ' попытки). Видео уже загружено; повтор продолжит работу с тем же видео');
      continue;
    }
    const data = await response.json().catch(() => ({}));
    if (response.ok && data.items?.length) return thumbnail.sha256;
    // Temporary provider states are retried; a refusal is final and needs a person.
    if (response.status === 429 || response.status >= 500) {
      failure = new Error('YouTube временно не принял обложку (HTTP ' + response.status + ', ' + (attempt + 1) + ' попытки). Видео уже загружено; повтор продолжит работу с тем же видео');
      continue;
    }
    throw new Error('YouTube не принял обложку (HTTP ' + response.status + '). Проверьте доступ канала к пользовательским значкам');
  }
  throw failure;
}
