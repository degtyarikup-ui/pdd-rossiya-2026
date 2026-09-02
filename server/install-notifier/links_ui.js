// ─────────────────────────────────────────────────────────────────────────────
// Генератор UTM-ссылок: поле «Соцсеть / канал» с возможностью вписать своё.
//
// В исходной разметке это был <select> с пятью вариантами, а новых площадок
// становится больше (Threads, Дзен, рассылки). Здесь список заменяется на поле
// с подсказками: знакомые каналы выбираются из выпадашки, любой другой просто
// вписывается руками.
//
// Разметка админки собрана экранированной строкой внутри worker.js, поэтому
// подмена делается в renderAdminPage(), а не правкой той строки.
// ─────────────────────────────────────────────────────────────────────────────

/** Что ищем в исходной разметке — этот блок заменяем целиком. */
export const LINKS_SOURCE_SELECT_MARKER = '<select id="gen-source" class="sidebar-select">';

export const LINKS_SOURCE_HTML = `<input id="gen-source" class="sidebar-select" list="gen-source-list"
              value="yt" placeholder="напр: threads" autocomplete="off">
            <datalist id="gen-source-list">
              <option value="yt">YouTube (Shorts / Видео)</option>
              <option value="tt">TikTok</option>
              <option value="ig">Instagram (Reels / Bio)</option>
              <option value="threads">Threads</option>
              <option value="tg">Telegram</option>
              <option value="vk">ВКонтакте</option>
              <option value="dzen">Дзен</option>
            </datalist>`;

export const LINKS_CLIENT_JS = `
// ────────────────────── Генератор ссылок: свой источник ──────────────────────

(function () {
  var field = document.getElementById('gen-source');
  if (!field || field.tagName !== 'INPUT') return;

  // Кириллицу переводим в латиницу: метка уезжает в адрес ссылки и в отчёты,
  // а там русские буквы читаются как %D1%82%D1%80…
  var TRANSLIT = {
    'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'e','ж':'zh','з':'z','и':'i','й':'y',
    'к':'k','л':'l','м':'m','н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f',
    'х':'h','ц':'c','ч':'ch','ш':'sh','щ':'sch','ъ':'','ы':'y','ь':'','э':'e','ю':'yu','я':'ya'
  };

  function normalize(value) {
    return String(value || '').toLowerCase().split('').map(function (ch) {
      if (TRANSLIT[ch] !== undefined) return TRANSLIT[ch];
      if (/[a-z0-9_-]/.test(ch)) return ch;
      if (/\\s/.test(ch)) return '_';
      return '';
    }).join('').replace(/_+/g, '_').replace(/^_|_$/g, '');
  }

  function apply() {
    var clean = normalize(field.value);
    if (clean !== field.value) field.value = clean;
    // Пересчёт ссылки живёт в основном скрипте админки.
    if (typeof updateGeneratedLink === 'function') updateGeneratedLink();
  }

  field.addEventListener('input', apply);
  field.addEventListener('change', apply);
  field.addEventListener('blur', apply);
  apply();
})();
`;
