/**
 * ПДД 2026 — Легковесный трекер соцсетей и переходов в магазины (<1 КБ)
 * Отслеживает:
 * 1. Просмотры страниц с разметкой источника (YouTube, TikTok, Instagram, VK, Telegram, Direct)
 * 2. Клики по кнопкам скачивания (RuStore, Google Play, App Store, Веб-версия)
 */
(function () {
  var ENDPOINT = 'https://pdd-install-notifier.sergei-pdd.workers.dev/api/track';
  var STORAGE_KEY = 'pdd_attr_v1';

  function parseQuery() {
    var params = {};
    try {
      var search = window.location.search.substring(1);
      if (!search) return params;
      var pairs = search.split('&');
      for (var i = 0; i < pairs.length; i++) {
        var pair = pairs[i].split('=');
        if (pair.length === 2) {
          params[decodeURIComponent(pair[0]).toLowerCase()] = decodeURIComponent(pair[1]);
        }
      }
    } catch (_) {}
    return params;
  }

  function detectReferrerSource(refUrl) {
    if (!refUrl) return 'direct';
    try {
      var host = new URL(refUrl).hostname.toLowerCase();
      if (host.indexOf('youtube.com') !== -1 || host.indexOf('youtu.be') !== -1) return 'youtube';
      if (host.indexOf('tiktok.com') !== -1) return 'tiktok';
      if (host.indexOf('instagram.com') !== -1) return 'instagram';
      if (host.indexOf('t.me') !== -1 || host.indexOf('telegram.org') !== -1) return 'telegram';
      if (host.indexOf('vk.com') !== -1 || host.indexOf('vk.ru') !== -1) return 'vk';
      if (host.indexOf('yandex.') !== -1 || host.indexOf('ya.ru') !== -1) return 'yandex';
      if (host.indexOf('google.') !== -1) return 'google';
      if (host === window.location.hostname) return null; // внутренний переход
      return 'other';
    } catch (_) {
      return 'other';
    }
  }

  function normalizeSource(raw) {
    if (!raw) return 'direct';
    var s = String(raw).toLowerCase().trim();
    if (s === 'yt' || s === 'youtube') return 'youtube';
    if (s === 'tt' || s === 'tiktok') return 'tiktok';
    if (s === 'ig' || s === 'insta' || s === 'instagram') return 'instagram';
    if (s === 'tg' || s === 'telegram') return 'telegram';
    if (s === 'vk' || s === 'vkontakte') return 'vk';
    return s;
  }

  function resolveAttribution() {
    var q = parseQuery();
    var source = null;
    var campaign = q.utm_campaign || '';
    var medium = q.utm_medium || '';

    if (q.ref) {
      var parts = String(q.ref).split(/[_:-]/);
      source = normalizeSource(parts[0]);
      if (parts.length > 1 && !campaign) {
        campaign = parts.slice(1).join('_');
      }
    } else if (q.utm_source) {
      source = normalizeSource(q.utm_source);
    }

    if (!source) {
      var refSource = detectReferrerSource(document.referrer);
      if (refSource && refSource !== 'direct') {
        source = refSource;
        if (!campaign) campaign = 'referrer';
      }
    }

    // Восстанавливаем из сессии, если текущий переход внутренний
    if (!source) {
      try {
        var saved = sessionStorage.getItem(STORAGE_KEY);
        if (saved) return JSON.parse(saved);
      } catch (_) {}
      source = 'direct';
    }

    var attr = {
      source: source,
      campaign: campaign || 'none',
      medium: medium || ''
    };

    try {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(attr));
    } catch (_) {}

    return attr;
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
      if (navigator.sendBeacon) {
        navigator.sendBeacon(ENDPOINT, body);
      } else {
        fetch(ENDPOINT, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: body,
          keepalive: true
        }).catch(function () {});
      }
    } catch (_) {}
  }

  var attribution = resolveAttribution();
  var platform = getPlatform();

  // 1. Отправляем событие просмотра (view)
  sendEvent({
    type: 'view',
    source: attribution.source,
    campaign: attribution.campaign,
    medium: attribution.medium,
    path: window.location.pathname || '/',
    platform: platform,
    referrer: document.referrer || ''
  });

  // 2. Отслеживаем клики по ссылкам сторов
  function identifyTarget(href) {
    if (!href) return null;
    var h = String(href).toLowerCase();
    if (h.indexOf('rustore.ru') !== -1) return 'rustore';
    if (h.indexOf('play.google.com') !== -1) return 'gplay';
    if (h.indexOf('apps.apple.com') !== -1) return 'appstore';
    if (h.indexOf('app.pdd-drive.ru') !== -1 || h.indexOf('/app/') !== -1) return 'web';
    if (h.indexOf('youtube.com') !== -1) return 'social_youtube';
    if (h.indexOf('instagram.com') !== -1) return 'social_instagram';
    if (h.indexOf('tiktok.com') !== -1) return 'social_tiktok';
    return null;
  }

  document.addEventListener('click', function (e) {
    try {
      var target = e.target;
      while (target && target.tagName !== 'A') {
        target = target.parentElement;
      }
      if (!target || !target.href) return;

      var storeTarget = identifyTarget(target.href);
      if (storeTarget) {
        sendEvent({
          type: 'click',
          target: storeTarget,
          source: attribution.source,
          campaign: attribution.campaign,
          path: window.location.pathname || '/',
          platform: platform
        });
      }
    } catch (_) {}
  }, true);
})();
