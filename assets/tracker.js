/** ПДД — first-touch acquisition, page views and app/store transitions. */
(function () {
  var ENDPOINT = 'https://pdd-install-notifier.sergei-pdd.workers.dev/api/track';
  // Shared with browserAcquisitionFields in the web app on /app/.
  var STORAGE_KEY = 'pdd_acquisition_v2';
  var LEGACY_KEY = 'pdd_attr_v1';
  var SOURCES = ['threads', 'instagram', 'youtube', 'tiktok', 'telegram', 'vk',
    'yandex', 'google', 'bing', 'duckduckgo', 'chatgpt', 'perplexity', 'copilot',
    'gemini', 'claude', 'direct', 'other'];
  var SEARCH_SOURCES = ['google', 'yandex', 'bing', 'duckduckgo'];
  var AI_SOURCES = ['chatgpt', 'perplexity', 'copilot', 'gemini', 'claude'];

  function parseQuery() {
    var params = {};
    try {
      new URLSearchParams(window.location.search).forEach(function (value, key) {
        params[key.toLowerCase()] = value;
      });
    } catch (_) {}
    return params;
  }

  function token(raw) {
    var value = String(raw || '');
    return /^[A-Za-z0-9._-]{1,64}$/.test(value) &&
      !Object.prototype.hasOwnProperty.call(Object.prototype, value) && value !== 'prototype' ? value : '';
  }

  function pathname(raw) {
    var value = String(raw || '').split(/[?#]/, 1)[0];
    return value.length <= 240 && /^\/(?!\/)[A-Za-z0-9._~%/-]*$/.test(value) ? value : '';
  }

  function hostname(raw) {
    var value = String(raw || '').toLowerCase();
    return value.length <= 160 && /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(value) ? value : '';
  }

  function referrerHost() {
    try { return hostname(new URL(document.referrer).hostname); } catch (_) { return ''; }
  }

  function detectReferrerSource(refUrl) {
    if (!refUrl) return 'direct';
    try {
      var host = new URL(refUrl).hostname.toLowerCase();
      var isHost = function (domain) { return host === domain || host.endsWith('.' + domain); };
      // Authentication referrers are never acquisition search results.
      if (['accounts.google.com', 'oauth.yandex.ru', 'id.yandex.ru', 'appleid.apple.com'].indexOf(host) !== -1) return null;
      // Internal navigation is never a new acquisition.
      if (host === window.location.hostname || host === 'pdd-drive.ru' || host === 'app.pdd-drive.ru') return null;
      if (isHost('chatgpt.com') || host === 'chat.openai.com') return 'chatgpt';
      if (isHost('perplexity.ai')) return 'perplexity';
      if (host === 'copilot.microsoft.com') return 'copilot';
      if (host === 'gemini.google.com') return 'gemini';
      if (isHost('claude.ai')) return 'claude';
      if (isHost('bing.com')) return 'bing';
      if (isHost('duckduckgo.com')) return 'duckduckgo';
      if (isHost('threads.net') || isHost('threads.com')) return 'threads';
      if (isHost('youtube.com') || isHost('youtu.be')) return 'youtube';
      if (isHost('tiktok.com')) return 'tiktok';
      if (isHost('instagram.com')) return 'instagram';
      if (isHost('t.me') || isHost('telegram.org')) return 'telegram';
      if (isHost('vk.com') || isHost('vk.ru')) return 'vk';
      if (/^(?:[a-z0-9-]+\.)?yandex\.(?:ru|com|by|kz|uz|com\.tr)$/.test(host) || isHost('ya.ru')) return 'yandex';
      if (/^(?:[a-z0-9-]+\.)?google\.(?:com|ru|by|kz|co\.uk|de|fr|com\.au|co\.in|com\.tr|co\.jp|co\.kr|com\.br|com\.mx|ca|es|it|nl|pl|ua|uz|az|ge|am|ee|lt|lv|fi|se|no|dk|ch|at|be|cz|sk|ro|hu|pt|gr)$/.test(host)) return 'google';
      return 'other';
    } catch (_) { return 'other'; }
  }

  function normalizeSource(raw) {
    var value = String(raw || '').toLowerCase().trim();
    var aliases = { th: 'threads', thread: 'threads', yt: 'youtube', tt: 'tiktok',
      ig: 'instagram', insta: 'instagram', tg: 'telegram', vkontakte: 'vk',
      'chatgpt.com': 'chatgpt', 'chat.openai.com': 'chatgpt', 'perplexity.ai': 'perplexity' };
    if (Object.prototype.hasOwnProperty.call(aliases, value)) value = aliases[value];
    return SOURCES.indexOf(value) === -1 ? '' : value;
  }

  function cleanSaved(raw) {
    if (!raw || typeof raw !== 'object') return null;
    var source = normalizeSource(raw.marketingSource || raw.source);
    if (!source) return null;
    return {
      marketingSource: source,
      marketingCampaign: token(raw.marketingCampaign || (raw.campaign !== 'none' ? raw.campaign : '')),
      marketingMedium: token(raw.marketingMedium || raw.medium),
      marketingContent: token(raw.marketingContent),
      landingPage: pathname(raw.landingPage),
      referrerHost: hostname(raw.referrerHost),
      attributionMethod: raw.attributionMethod === 'web_utm' ? 'web_utm' : 'web_referrer'
    };
  }

  function storeAttribution(attr) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(attr)); } catch (_) {}
    try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(attr)); } catch (_) {}
    return attr;
  }

  function resolveAttribution() {
    var saved;
    try { saved = cleanSaved(JSON.parse(localStorage.getItem(STORAGE_KEY))); } catch (_) {}
    if (!saved) try { saved = cleanSaved(JSON.parse(sessionStorage.getItem(STORAGE_KEY))); } catch (_) {}
    if (!saved) try { saved = cleanSaved(JSON.parse(sessionStorage.getItem(LEGACY_KEY))); } catch (_) {}
    // Every known first source (including a direct visit) is immutable. A later
    // search, campaign or OAuth callback must not relabel an existing visitor.
    if (saved) return storeAttribution(saved);

    var q = parseQuery();
    var parts = String(q.ref || '').split(/[_:-]/);
    var explicit = q.utm_source || (q.ref ? parts[0] : '');
    var detected = detectReferrerSource(document.referrer);
    var source = explicit ? normalizeSource(explicit) || 'other' : detected || 'direct';
    var medium = token(q.utm_medium) || (!explicit && SEARCH_SOURCES.indexOf(source) !== -1 ? 'organic' :
      AI_SOURCES.indexOf(source) !== -1 ? 'ai' : source === 'direct' ? 'direct' :
      ['threads', 'instagram', 'youtube', 'tiktok', 'telegram', 'vk'].indexOf(source) !== -1 ? 'social' : 'referral');
    return storeAttribution({
      marketingSource: source,
      marketingCampaign: token(q.utm_campaign) || (parts.length > 1 ? token(parts.slice(1).join('_')) : ''),
      marketingMedium: medium,
      marketingContent: token(q.utm_content),
      landingPage: pathname(q.landing_page) || pathname(window.location.pathname) || '/',
      referrerHost: hostname(q.referrer_host) || (detected && detected !== 'direct' ? referrerHost() : ''),
      attributionMethod: explicit ? 'web_utm' : 'web_referrer'
    });
  }

  function getPlatform() {
    var ua = navigator.userAgent || '';
    if (/android/i.test(ua)) return 'android';
    if (/iphone|ipad|ipod/i.test(ua)) return 'ios';
    return 'desktop';
  }

  function sendEvent(payload) {
    try {
      var body = JSON.stringify(payload);
      // sendBeacon can reject its queue, in which case keepalive is still needed.
      try {
        if (navigator.sendBeacon && navigator.sendBeacon(ENDPOINT, body) !== false) return;
      } catch (_) { /* A rejected beacon still gets a keepalive attempt. */ }
      fetch(ENDPOINT, {
        method: 'POST',
        // A CORS-safelisted content type avoids a preflight during navigation.
        headers: { 'content-type': 'text/plain;charset=UTF-8' },
        body: body,
        keepalive: true
      }).catch(function () {});
    } catch (_) {}
  }

  var attribution = resolveAttribution();
  var platform = getPlatform();

  function eventFields(type, target) {
    return {
      type: type,
      target: target,
      source: attribution.marketingSource,
      campaign: attribution.marketingCampaign,
      medium: attribution.marketingMedium,
      content: attribution.marketingContent,
      landingPage: attribution.landingPage,
      referrerHost: attribution.referrerHost,
      attributionMethod: attribution.attributionMethod,
      path: pathname(window.location.pathname) || '/',
      platform: platform
    };
  }

  sendEvent(eventFields('view'));

  function toUrl(href) {
    var base = window.location.href || 'https://' + window.location.hostname + (window.location.pathname || '/');
    return new URL(href, base);
  }

  function identifyTarget(href) {
    try {
      var url = toUrl(href);
      if (!/^https?:$/.test(url.protocol)) return null;
      if (url.hostname === 'www.rustore.ru' || url.hostname === 'rustore.ru') return 'rustore';
      if (url.hostname === 'play.google.com') return 'gplay';
      if (url.hostname === 'apps.apple.com') return 'appstore';
      if (url.hostname === 'app.pdd-drive.ru' ||
          (url.hostname === window.location.hostname || url.hostname === 'pdd-drive.ru') && /^\/app(?:\/|$)/.test(url.pathname)) return 'web';
      if (url.hostname === 'youtube.com' || url.hostname === 'www.youtube.com') return 'social_youtube';
      if (url.hostname === 'instagram.com' || url.hostname === 'www.instagram.com') return 'social_instagram';
      if (url.hostname === 'tiktok.com' || url.hostname === 'www.tiktok.com') return 'social_tiktok';
    } catch (_) {}
    return null;
  }

  function attributedHref(href) {
    var destination = toUrl(href);
    var target = identifyTarget(href);
    var tags = new URLSearchParams({ utm_source: attribution.marketingSource,
      utm_medium: attribution.marketingMedium || 'referral' });
    if (attribution.marketingCampaign) tags.set('utm_campaign', attribution.marketingCampaign);
    if (attribution.marketingContent) tags.set('utm_content', attribution.marketingContent);
    if (attribution.landingPage) tags.set('landing_page', attribution.landingPage);
    if (attribution.referrerHost) tags.set('referrer_host', attribution.referrerHost);
    if (target === 'gplay') destination.searchParams.set('referrer', tags.toString());
    if (target === 'rustore') destination.searchParams.set('referrerId', tags.toString());
    // App Store campaign tokens are aggregate reporting, not deferred identity.
    if (target === 'appstore') destination.searchParams.set('ct', attribution.marketingCampaign || attribution.marketingSource);
    if (target === 'web') tags.forEach(function (value, key) { destination.searchParams.set(key, value); });
    return destination.href;
  }

  function prepareLink(link) {
    try {
      var target = identifyTarget(link.href);
      if (target === 'gplay' || target === 'rustore' || target === 'appstore' || target === 'web') link.href = attributedHref(link.href);
    } catch (_) {}
  }

  // Prepare static links for keyboard navigation and the browser context menu.
  // Delegated click/auxclick also handles links inserted by quiz/result screens.
  function prepareLinks() {
    try {
      var links = document.querySelectorAll('a[href]');
      for (var i = 0; i < links.length; i++) prepareLink(links[i]);
    } catch (_) {}
  }
  prepareLinks();
  if (typeof MutationObserver !== 'undefined') {
    new MutationObserver(prepareLinks).observe(document.documentElement, { childList: true, subtree: true });
  }

  function onLinkClick(e) {
    try {
      var target = e.target;
      while (target && target.tagName !== 'A') target = target.parentElement;
      if (!target || !target.href || e.type === 'auxclick' && e.button !== 1) return;
      prepareLink(target);
      var cta = target.getAttribute('data-cta');
      if (cta && typeof window.ym === 'function') {
        window.ym(111960332, 'reachGoal', cta === 'article-practice' ? 'article_practice_click' : 'knowledge_test_click', {
          article: target.getAttribute('data-context') || window.location.pathname,
          source: attribution.marketingSource
        });
      }
      var storeTarget = identifyTarget(target.href);
      if (storeTarget) sendEvent(eventFields('click', storeTarget));
    } catch (_) {}
  }
  document.addEventListener('click', onLinkClick, true);
  document.addEventListener('auxclick', onLinkClick, true);

  // The static /go pages share the same attribution as article and landing CTAs.
  var redirect = {
    '/go/gplay/': 'https://play.google.com/store/apps/details?id=ru.pdd.pdd_app',
    '/go/appstore/': 'https://apps.apple.com/ru/app/id6792369533',
    '/go/rustore/': 'https://www.rustore.ru/catalog/app/ru.pdd.pdd_app',
    '/go/web/': '/app/'
  }[String(window.location.pathname || '').replace(/index\.html$/, '').replace(/\/?$/, '/')];
  if (redirect) {
    sendEvent(eventFields('click', identifyTarget(redirect)));
    window.location.replace(attributedHref(redirect));
    return;
  }

  // 3. Cookie Notice Banner (152-ФЗ)
  function initCookieBanner() {
    try {
      if (localStorage.getItem('pdd_cookie_consent_v1')) return;
      var banner = document.createElement('div');
      banner.className = 'cookie-banner';
      banner.innerHTML = '<span>Мы используем файлы cookie и анонимную аналитику для удобства работы сайта. Продолжая пользоваться сайтом, вы соглашаетесь с <a href="/privacy.html">Политикой конфиденциальности</a> и <a href="/terms.html">Пользовательским соглашением</a>.</span><button id="pdd-accept-cookie">Понятно</button>';
      document.body.appendChild(banner);
      setTimeout(function () { banner.classList.add('show'); }, 400);

      var btn = document.getElementById('pdd-accept-cookie');
      if (btn) {
        btn.addEventListener('click', function () {
          localStorage.setItem('pdd_cookie_consent_v1', 'true');
          banner.classList.remove('show');
          setTimeout(function () { if (banner.parentNode) banner.parentNode.removeChild(banner); }, 300);
        });
      }
    } catch (_) {}
  }

  // 4. Реальные просмотры статей: числа приходят с воркера (/api/views),
  //    до ответа элементы скрыты, чтобы не показывать пустой глаз.
  function pluralViews(num) {
    var n = num % 100, n1 = num % 10;
    if (n >= 11 && n <= 19) return 'просмотров';
    if (n1 === 1) return 'просмотр';
    if (n1 >= 2 && n1 <= 4) return 'просмотра';
    return 'просмотров';
  }
  function fmtShort(num) {
    if (num >= 10000) return Math.round(num / 1000) + 'k';
    if (num >= 1000) return (Math.floor(num / 100) / 10).toFixed(1).replace('.0', '') + 'k';
    return String(num);
  }
  function fmtFull(num) {
    return String(num).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' ' + pluralViews(num);
  }
  function initViewCounter() {
    try {
      var els = document.querySelectorAll('[data-slug] .views-count');
      if (!els.length) return;
      var slugs = {};
      for (var i = 0; i < els.length; i++) slugs[els[i].parentNode.getAttribute('data-slug')] = 1;
      var list = Object.keys(slugs).join(',');
      var m = (window.location.pathname || '').match(/^\/blog\/([a-z0-9-]+)\/?$/);
      var here = m ? m[1] : null;
      fetch(ENDPOINT.replace('/api/track', '/api/views') + '?slugs=' + encodeURIComponent(list))
        .then(function (r) { return r.json(); })
        .then(function (data) {
          for (var j = 0; j < els.length; j++) {
            var wrap = els[j].parentNode;
            var slug = wrap.getAttribute('data-slug');
            var num = data[slug];
            if (typeof num !== 'number') continue;
            if (slug === here && num === 0) num = 1;
            if (num === 0) continue;
            els[j].textContent = wrap.classList.contains('post-views') ? fmtFull(num) : fmtShort(num);
            wrap.hidden = false;
          }
        })
        .catch(function () {});
    } catch (_) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      initCookieBanner();
      initViewCounter();
    });
  } else {
    initCookieBanner();
    initViewCounter();
  }
})();
