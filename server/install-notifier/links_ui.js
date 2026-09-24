// Раздел «Ссылки» админки: создание отслеживаемой ссылки, «Мои ссылки» со
// статистикой по каждой и все источники визитов. Заменяет старый генератор
// из экранированной строки worker.js. Стиль и помощники (anLogo, anNum,
// anDelta, AN_SOURCES…) — общие с analytics_ui.js, он подключается раньше.
//
// Ссылка = страница + ?ref=<канал>_<метка>. Сайт (tracker.js) и страницы
// /go/* раскладывают ref на источник и кампанию — по метке и считаем.
//
// Клиентский код — String.raw без обратных кавычек и ${ внутри.

export const LINKS_VIEW_HTML = String.raw`
    <!-- 2. LINKS GENERATOR VIEW -->
    <div id="links-view" style="display:none;">
      <style>
        #links-view .an-title { display:flex; align-items:center; justify-content:space-between; gap:16px; }
        .ln-field { margin-bottom:24px; }
        .ln-field .an-label { margin-bottom:8px; }
        .ln-chips { display:flex; flex-wrap:wrap; gap:8px; }
        .ln-chip { display:inline-flex; align-items:center; gap:8px; border:none; background:#EFF0F4; color:#121212; border-radius:12px; padding:8px 14px 8px 8px; font:inherit; font-size:15px; font-weight:700; cursor:pointer; }
        .ln-chip.text { padding:8px 14px; }
        .ln-chip .an-logo, .ln-chip .an-mono { width:24px; height:24px; border-radius:8px; background:#fff; }
        .ln-chip .an-mono { font-size:13px; }
        .ln-chip.active { background:#0574F8; color:#fff; }
        .ln-input { width:100%; max-width:420px; box-sizing:border-box; background:#EFF0F4; border:none; border-radius:12px; padding:12px 14px; font:inherit; font-size:15px; font-weight:600; color:#121212; outline:none; }
        .ln-result { display:flex; align-items:center; gap:8px; flex-wrap:wrap; background:#F8F8FA; border-radius:12px; padding:8px 8px 8px 16px; }
        .ln-url { flex:1 1 280px; min-width:0; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:15px; font-weight:700; color:#0574F8; overflow-wrap:anywhere; }
        .ln-btn { border:none; border-radius:12px; padding:10px 16px; font:inherit; font-size:15px; font-weight:700; cursor:pointer; background:#EFF0F4; color:#121212; white-space:nowrap; }
        .ln-btn.primary { background:#0574F8; color:#fff; }
        .ln-btn:disabled { opacity:1; background:#EFF0F4; color:#A1A6B7; cursor:not-allowed; }
        .ln-seg { display:inline-flex; background:#EFF0F4; border-radius:12px; padding:4px; gap:2px; }
        .ln-seg button { border:none; background:transparent; border-radius:8px; padding:6px 12px; font:inherit; font-size:13px; font-weight:700; color:#7C8190; cursor:pointer; }
        .ln-seg button.active { background:#fff; color:#121212; }
        #links-view .ln-table { width:100%; border-collapse:collapse; }
        #links-view .ln-table th { background:none; text-transform:none; letter-spacing:0; border:none; font-size:13px; font-weight:600; color:#A1A6B7; text-align:right; padding:0 0 12px 16px; white-space:nowrap; }
        #links-view .ln-table th:first-child { text-align:left; padding-left:0; }
        #links-view .ln-table td { background:none; padding:12px 0 12px 16px; text-align:right; border-top:1px solid #EFF0F4; font-size:15px; font-weight:800; color:#121212; font-variant-numeric:tabular-nums; vertical-align:middle; white-space:nowrap; }
        #links-view .ln-table td:first-child { text-align:left; padding-left:0; white-space:normal; }
        #links-view .ln-table td .an-delta { margin:0; }
        .ln-who { display:flex; align-items:center; gap:12px; min-width:0; }
        .ln-name { font-size:15px; font-weight:700; color:#121212; line-height:20px; }
        .ln-sub { font-size:13px; font-weight:600; color:#A1A6B7; line-height:18px; overflow-wrap:anywhere; }
        #links-view .ln-sub-row td { border-top:none; padding-top:0; font-size:13px; font-weight:700; color:#7C8190; }
        #links-view .ln-sub-row td:first-child { padding-left:44px; }
        .ln-actions { display:inline-flex; gap:4px; }
        .ln-icon { border:none; background:transparent; width:32px; height:32px; border-radius:8px; cursor:pointer; color:#A1A6B7; display:inline-flex; align-items:center; justify-content:center; }
        .ln-icon:hover { background:#EFF0F4; color:#121212; }
        .ln-icon.danger:hover { color:#ED4621; }
        .ln-conv { color:#0574F8; }
        .ln-error { font-size:13px; font-weight:700; color:#ED4621; margin-top:8px; min-height:18px; }
        #ln-links, #ln-all { overflow-x:auto; }
        @media (max-width:640px) { .ln-hide-sm { display:none; } #links-view .ln-table td, #links-view .ln-table th { padding-left:10px; } }
      </style>

      <div class="an-card">
        <div class="an-title">Новая ссылка</div>
        <div class="ln-field">
          <div class="an-label">Где разместите</div>
          <div class="ln-chips" id="ln-sources"></div>
          <input class="ln-input" id="ln-source-custom" placeholder="Свой канал латиницей, например mailing" style="display:none;margin-top:8px">
        </div>
        <div class="ln-field">
          <div class="an-label">Куда ведёт</div>
          <div class="ln-chips" id="ln-pages"></div>
        </div>
        <div class="ln-field">
          <div class="an-label">Метка — чтобы отличать ссылки одного канала</div>
          <input class="ln-input" id="ln-campaign" placeholder="например bio или reels_12" autocomplete="off">
        </div>
        <div class="ln-result">
          <div class="ln-url" id="ln-url"></div>
          <button class="ln-btn" id="ln-copy">Скопировать</button>
          <button class="ln-btn primary" id="ln-save">Сохранить</button>
        </div>
        <div class="ln-error" id="ln-error"></div>
      </div>

      <div class="an-card">
        <div class="an-title"><span>Мои ссылки</span>
          <div class="ln-seg" id="ln-period"><button data-days="7">7 дней</button><button data-days="30" class="active">30 дней</button><button data-days="90">90 дней</button></div>
        </div>
        <div id="ln-links"></div>
      </div>

      <div class="an-card">
        <div class="an-title">Все источники визитов</div>
        <div id="ln-all"></div>
      </div>
    </div>
`;

export const LINKS_CLIENT_JS = String.raw`
// ────────────────────── Links (links_ui.js) ──────────────────────
var LN_SOURCES = [
  ['yt', 'youtube'], ['ig', 'instagram'], ['tt', 'tiktok'], ['tg', 'telegram'],
  ['vk', 'vk'], ['threads', 'threads'], ['dzen', 'dzen']
];
var LN_PAGES = [
  ['https://pdd-drive.ru/links/', 'Все кнопки'],
  ['https://pdd-drive.ru/', 'Сайт'],
  ['https://pdd-drive.ru/go/gplay/', 'Google Play'],
  ['https://pdd-drive.ru/go/rustore/', 'RuStore'],
  ['https://pdd-drive.ru/go/appstore/', 'App Store'],
  ['https://pdd-drive.ru/go/rs-gplay/', 'Сербия · Google Play']
];
var LN_PAGE_NAMES = {}; LN_PAGES.forEach(function (p) { LN_PAGE_NAMES[p[0]] = p[1]; });
var lnState = { source: 'ig', custom: '', page: LN_PAGES[0][0], campaign: '', days: 30, links: [], stats: null, loaded: false };

var LN_TRANSLIT = { 'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'e','ж':'zh','з':'z','и':'i','й':'y','к':'k','л':'l','м':'m','н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f','х':'h','ц':'c','ч':'ch','ш':'sh','щ':'sch','ъ':'','ы':'y','ь':'','э':'e','ю':'yu','я':'ya' };
// Метка уезжает в адрес и в отчёты: только латиница, цифры, _ и -.
function lnClean(value, allowUnderscore) {
  return String(value || '').toLowerCase().split('').map(function (ch) {
    if (LN_TRANSLIT[ch] !== undefined) return LN_TRANSLIT[ch];
    if (/[a-z0-9-]/.test(ch)) return ch;
    if (allowUnderscore && /[\s_]/.test(ch)) return '_';
    return '';
  }).join('').replace(/_+/g, '_').replace(/^_/, '').slice(0, allowUnderscore ? 48 : 32);
}
function lnSourceCode() { return lnState.source === 'custom' ? lnClean(lnState.custom) : lnState.source; }
function lnUrl() {
  var src = lnSourceCode();
  var camp = lnState.campaign.replace(/_$/, '');
  return lnState.page + '?ref=' + (src || 'канал') + (camp ? '_' + camp : '');
}
function lnSourceConf(code) { return AN_SOURCES[anSourceKey(code)] || AN_SOURCES.other; }
function lnIconBtn(kind, attrs, title) {
  var icon = kind === 'copy'
    ? '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="12" height="12" rx="3"/><path d="M5 15V6a3 3 0 0 1 3-3h9"/></svg>'
    : '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/></svg>';
  return '<button class="ln-icon' + (kind === 'delete' ? ' danger' : '') + '" ' + attrs + ' title="' + title + '">' + icon + '</button>';
}

function lnRenderForm() {
  document.getElementById('ln-sources').innerHTML = LN_SOURCES.map(function (s) {
    var conf = AN_SOURCES[s[1]];
    return '<button class="ln-chip' + (lnState.source === s[0] ? ' active' : '') + '" data-src="' + s[0] + '">' + anLogo(conf) + conf.name + '</button>';
  }).join('') + '<button class="ln-chip text' + (lnState.source === 'custom' ? ' active' : '') + '" data-src="custom">Другое</button>';
  document.getElementById('ln-source-custom').style.display = lnState.source === 'custom' ? '' : 'none';
  document.getElementById('ln-pages').innerHTML = LN_PAGES.map(function (p) {
    return '<button class="ln-chip text' + (lnState.page === p[0] ? ' active' : '') + '" data-page="' + p[0] + '">' + p[1] + '</button>';
  }).join('');
  lnRenderUrl();
}
function lnRenderUrl() {
  document.getElementById('ln-url').textContent = lnUrl();
  var ready = lnSourceCode() && lnState.campaign.replace(/_$/, '');
  document.getElementById('ln-save').disabled = !ready;
  document.getElementById('ln-copy').disabled = !lnSourceCode();
}

async function lnLoad() {
  try {
    var res = await Promise.all([
      adminFetchJson('/api/admin/links'),
      adminFetchJson('/api/admin/stats?days=' + lnState.days + '&app=all')
    ]);
    lnState.links = res[0].links || [];
    lnState.stats = res[1];
    lnRenderStats();
  } catch (err) {
    document.getElementById('ln-links').innerHTML = '<div class="an-empty">Не загрузилось: ' + anEsc(err.message) + '</div>';
  }
}

function lnRenderStats() {
  var st = lnState.stats || {}, prev = (st.previous || {}).campaigns || {};
  var camps = {};
  (st.campaigns || []).forEach(function (c) { camps[c.name] = c; });
  // Мои ссылки
  var box = document.getElementById('ln-links');
  if (!lnState.links.length) {
    box.innerHTML = '<div class="an-empty">Сохраните первую ссылку — здесь будет видно, сколько людей по ней пришло</div>';
  } else {
    var rows = lnState.links.map(function (l) { var c = camps[l.campaign] || {}; return { l: l, views: c.views || 0, clicks: c.clicks || 0 }; })
      .sort(function (a, b) { return b.views - a.views || b.clicks - a.clicks; });
    box.innerHTML = '<table class="ln-table"><thead><tr><th>Ссылка</th><th>Визиты</th><th>В магазин</th><th class="ln-hide-sm">Конверсия</th><th></th></tr></thead><tbody>'
      + rows.map(function (r) {
        var conf = lnSourceConf(r.l.source), p = prev[r.l.campaign] || {};
        var conv = r.views ? Math.round(r.clicks / r.views * 100) + '%' : '—';
        return '<tr><td><div class="ln-who">' + anLogo(conf) + '<div style="min-width:0"><div class="ln-name">' + anEsc(conf.name === 'Другие сайты' ? r.l.source : conf.name) + ' · ' + anEsc(r.l.campaign) + '</div>'
          + '<div class="ln-sub">' + anEsc(LN_PAGE_NAMES[r.l.page] || r.l.page) + '</div></div></div></td>'
          + '<td>' + anNum(r.views) + anDelta(r.views, p.views) + '</td>'
          + '<td>' + anNum(r.clicks) + anDelta(r.clicks, p.clicks) + '</td>'
          + '<td class="ln-hide-sm ln-conv">' + conv + '</td>'
          + '<td><span class="ln-actions">' + lnIconBtn('copy', 'data-copy="' + anEsc(r.l.page + '?ref=' + r.l.source + '_' + r.l.campaign) + '"', 'Скопировать ссылку')
          + lnIconBtn('delete', 'data-del="' + anEsc(r.l.id) + '"', 'Удалить из списка') + '</span></td></tr>';
      }).join('') + '</tbody></table>';
  }

  // Все источники: визиты и переходы, внутри — метки, которых нет в «Моих ссылках».
  var saved = {}; lnState.links.forEach(function (l) { saved[l.campaign] = 1; });
  var src = {};
  (st.sources || []).forEach(function (s) {
    if (!s.views && !s.clicks) return;
    var key = anSourceKey(s.name);
    if (!src[key]) src[key] = { views: 0, clicks: 0, camps: [] };
    src[key].views += s.views || 0; src[key].clicks += s.clicks || 0;
  });
  (st.campaigns || []).forEach(function (c) {
    if (saved[c.name] || c.name === 'referrer' || c.name === 'none') return;
    var key = anSourceKey(c.source);
    if (src[key]) src[key].camps.push(c);
  });
  var keys = Object.keys(src).sort(function (a, b) { return src[b].views - src[a].views; });
  var prevSrc = {};
  Object.keys((st.previous || {}).sources || {}).forEach(function (n) { var k = anSourceKey(n), v = st.previous.sources[n]; prevSrc[k] = (prevSrc[k] || 0) + (v.views || 0); });
  document.getElementById('ln-all').innerHTML = keys.length
    ? '<table class="ln-table"><thead><tr><th>Источник</th><th>Визиты</th><th>В магазин</th><th class="ln-hide-sm">Конверсия</th></tr></thead><tbody>'
      + keys.map(function (k) {
        var s = src[k], conf = AN_SOURCES[k];
        var row = '<tr><td><div class="ln-who">' + anLogo(conf) + '<div class="ln-name">' + conf.name + '</div></div></td>'
          + '<td>' + anNum(s.views) + anDelta(s.views, prevSrc[k]) + '</td><td>' + anNum(s.clicks) + '</td>'
          + '<td class="ln-hide-sm ln-conv">' + (s.views ? Math.round(s.clicks / s.views * 100) + '%' : '—') + '</td></tr>';
        return row + s.camps.sort(function (a, b) { return b.views - a.views; }).slice(0, 5).map(function (c) {
          return '<tr class="ln-sub-row"><td>метка «' + anEsc(c.name) + '»</td><td>' + anNum(c.views) + '</td><td>' + anNum(c.clicks) + '</td><td class="ln-hide-sm"></td></tr>';
        }).join('');
      }).join('') + '</tbody></table>'
    : '<div class="an-empty">Визитов за период нет</div>';
}

async function lnCopy(text, btn) {
  try { await navigator.clipboard.writeText(text); } catch (_) { prompt('Скопируйте ссылку:', text); return; }
  if (!btn) return;
  var old = btn.innerHTML;
  btn.innerHTML = btn.classList.contains('ln-icon') ? '✓' : 'Скопировано';
  setTimeout(function () { btn.innerHTML = old; }, 1500);
}

// Старый скрипт зовёт updateGeneratedLink при входе в раздел — это наша загрузка.
function updateGeneratedLink() {
  if (!lnState.loaded) { lnState.loaded = true; lnRenderForm(); }
  lnLoad();
}

(function () {
  var view = document.getElementById('links-view');
  if (!view) return;
  view.addEventListener('click', async function (e) {
    var t = e.target;
    var src = t.closest('[data-src]');
    if (src) { lnState.source = src.dataset.src; lnRenderForm(); if (lnState.source === 'custom') document.getElementById('ln-source-custom').focus(); return; }
    var page = t.closest('[data-page]');
    if (page) { lnState.page = page.dataset.page; lnRenderForm(); return; }
    var per = t.closest('#ln-period button');
    if (per) {
      lnState.days = parseInt(per.dataset.days, 10);
      document.querySelectorAll('#ln-period button').forEach(function (b) { b.classList.toggle('active', b === per); });
      lnLoad(); return;
    }
    var copy = t.closest('[data-copy]');
    if (copy) { lnCopy(copy.dataset.copy, copy); return; }
    var del = t.closest('[data-del]');
    if (del) {
      if (!confirm('Убрать ссылку из списка? Сама ссылка продолжит работать.')) return;
      try {
        var r = await adminFetchJson('/api/admin/links', { method: 'DELETE', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ id: del.dataset.del }) });
        lnState.links = r.links; lnRenderStats();
      } catch (err) { adminToast(err.message, true); }
      return;
    }
    if (t.closest('#ln-copy')) { lnCopy(lnUrl(), t.closest('#ln-copy')); return; }
    if (t.closest('#ln-save')) {
      var btn = t.closest('#ln-save'), err = document.getElementById('ln-error');
      btn.disabled = true; err.textContent = '';
      try {
        var res = await adminFetchJson('/api/admin/links', { method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ source: lnSourceCode(), campaign: lnState.campaign.replace(/_$/, ''), page: lnState.page }) });
        lnState.links = res.links;
        lnCopy(lnUrl(), document.getElementById('ln-copy'));
        lnState.campaign = ''; document.getElementById('ln-campaign').value = '';
        lnRenderUrl(); lnRenderStats();
      } catch (e2) { err.textContent = e2.message; lnRenderUrl(); }
    }
  });
  view.addEventListener('input', function (e) {
    if (e.target.id === 'ln-campaign') {
      var v = lnClean(e.target.value, true);
      if (v !== e.target.value) e.target.value = v;
      lnState.campaign = v; document.getElementById('ln-error').textContent = ''; lnRenderUrl();
    } else if (e.target.id === 'ln-source-custom') {
      var c = lnClean(e.target.value);
      if (c !== e.target.value) e.target.value = c;
      lnState.custom = c; lnRenderUrl();
    }
  });
})();
`;
