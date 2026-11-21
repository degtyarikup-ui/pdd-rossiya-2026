// Fixed host operations for Godot. Arguments remain data: no eval or generated JS.
(() => {
  let reply = '';
  let voiceReply = '';
  window.addEventListener('message', event => {
    if (event.source !== window.parent || event.origin !== window.location.origin) return;
    try {
      const data = JSON.parse(event.data);
      if (data.bridge === 'pdd-godot' && data.kind === 'voice_audio_result') voiceReply = event.data;
    } catch {}
  });
  const onReply = event => {
    if (event.source !== window.parent || event.origin !== window.location.origin) return;
    try {
      const data = JSON.parse(event.data);
      if (data.bridge === 'pdd-godot' && data.kind === 'question_report_result') reply = event.data;
    } catch { /* Other messages do not belong to this bridge. */ }
  };
  window.PddWebBridge = Object.freeze({
    resolve: path => new URL(path, window.location.href).href,
    post(kind, json) {
      if (window.parent !== window) window.parent.postMessage(JSON.stringify({ bridge: 'pdd-godot', kind, json }), window.location.origin);
    },
    share(title, text) {
      if (navigator.share) navigator.share({ title, text }).catch(() => {});
      else if (navigator.clipboard) navigator.clipboard.writeText(text).catch(() => {});
    },
    beginReport() {
      reply = '';
      window.removeEventListener('message', onReply);
      window.addEventListener('message', onReply);
    },
    voiceReply: () => voiceReply,
    reportReply: () => reply,
    endReport() { window.removeEventListener('message', onReply); reply = ''; },
  });
})();
