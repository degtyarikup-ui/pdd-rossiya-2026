// Language of the 3D game's own texts. Russian is the source in the game files; kk and en come
// from i18n-ui.js (labels) and i18n-situations.js (exam situations). Flutter sets the language
// with configure({ language }); until then the game shows Russian, as before.
(function () {
  window.PDD_LANG = 'ru';

  window.PDD_T = function (text) {
    const lang = window.PDD_LANG;
    if (lang === 'ru' || typeof text !== 'string') return text;
    const table = (window.PDD_UI_I18N || {})[lang];
    return (table && table[text]) || text;
  };

  // A copy of an exam situation in the current language; the original keeps the Russian
  // text, which the engine uses for its own logic.
  window.PDD_LOCALIZE_SITUATION = function (situation) {
    const lang = window.PDD_LANG;
    if (!situation || lang === 'ru') return situation;
    const translated = ((window.PDD_SITUATION_I18N || {})[situation.id] || {})[lang];
    if (!translated) return situation;
    // The time to answer follows the Russian text, so every language gets the same time.
    const sourceTextLength = situation.title.length +
      situation.options.reduce((sum, option) => sum + option.length, 0);
    return Object.assign({}, situation, {
      ticket: translated.ticket,
      title: translated.title,
      options: translated.options.slice(),
      explanation: translated.explanation,
      pddRule: translated.pddRule || situation.pddRule,
      legend: (situation.legend || []).map(item => Object.assign({}, item, { label: window.PDD_T(item.label) })),
      sourceTextLength,
    });
  };
})();
