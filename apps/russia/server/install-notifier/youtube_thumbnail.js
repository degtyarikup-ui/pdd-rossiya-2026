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

export async function setYoutubeThumbnail(thumbnail, videoId, getToken) {
  if (!thumbnail) return null;
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) throw new Error('Не удалось определить видео для обложки');
  let response;
  try {
    response = await fetch('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?uploadType=media&videoId=' + encodeURIComponent(videoId), {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
      headers: { authorization: 'Bearer ' + await getToken(), 'content-type': thumbnail.mimeType },
      body: thumbnail.bytes,
    });
  } catch (_) {
    throw new Error('Не удалось подтвердить обложку YouTube. Повтор продолжит работу с тем же видео');
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.items?.length) {
    throw new Error('YouTube не принял обложку (HTTP ' + response.status + '). Проверьте доступ канала к пользовательским значкам');
  }
  return thumbnail.sha256;
}
