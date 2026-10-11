// Translations of the 3D game: every exam situation has kk and en texts, answer order is kept,
// and the runtime returns Russian for ru and the translation for kk/en.
// node tools/game_tests/game-i18n-test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../..');
const assets = path.join(root, 'assets/game');
const read = name => fs.readFileSync(path.join(assets, name), 'utf8');

const windowObject = {};
const context = vm.createContext({ window: windowObject, console });
for (const name of ['i18n-ui.js', 'i18n-situations.js', 'i18n.js']) {
  vm.runInContext(read(name), context, { filename: name });
}

const translations = windowObject.PDD_SITUATION_I18N;
const ui = windowObject.PDD_UI_I18N;
const localize = windowObject.PDD_LOCALIZE_SITUATION;
const cyrillic = /[А-Яа-яЁё]/;
// Marker letters of the pictures stay Cyrillic in every language (А, Б, В, Г).
const markers = /[АБВГ]/g;

// Ids of every situation shipped in the game files.
const ids = new Set();
for (const [name, pattern] of [
  ['game.js', /"id":\s*"(ticket_\d+_\d+)"/g],
  ['junction-situations.js', /"id":\s*"(ticket_\d+_\d+)"/g],
  ['road-situations.js', /"id":\s*"(road_\d+_\d+)"/g],
]) {
  for (const match of read(name).matchAll(pattern)) ids.add(match[1]);
}

assert.ok(ids.size >= 150, `expected the full situation set, found ${ids.size}`);
for (const id of ids) {
  assert.ok(translations[id], `${id}: no translation entry`);
  for (const lang of ['kk', 'en']) {
    const tr = translations[id][lang];
    assert.ok(tr, `${id}: no ${lang} text`);
    assert.ok(tr.title && tr.explanation && tr.ticket, `${id}/${lang}: empty field`);
    assert.ok(tr.options.length >= 2 && tr.options.every(o => o.trim()), `${id}/${lang}: options`);
  }
}

// English has no Russian words; Kazakh may keep only the picture markers as Cyrillic letters.
for (const id of ids) {
  for (const field of [translations[id].en.title, translations[id].en.explanation, ...translations[id].en.options]) {
    assert.equal(cyrillic.test(field.replace(markers, '')), false, `${id}/en keeps Russian: ${field.slice(0, 60)}`);
  }
}

// Legend labels: every Russian label used in a legend has a kk and en text.
for (const lang of ['kk', 'en']) {
  for (const label of ['Вы', 'Вы прямо', 'Вы налево', 'Вы направо', 'Вы на разворот', 'Автомобиль', 'Грузовик',
    'Мотоцикл', 'Трамвай', 'Автобус', 'Встречный', 'Трактор', 'Пешеход', 'Велосипедист', 'Фургон', 'Повозка']) {
    assert.ok(ui[lang][label], `${lang}: no legend label for "${label}"`);
  }
}

// Every Cyrillic label or name the game files can show (legends, badges, signs, actors) has kk and en
// texts. Single marker letters (А, Б, В) stay as they are in every language.
const labelSource = /"(?:label|name)"\s*:\s*"([^"]+)"|\b(?:label|name)\s*:\s*'([^']+)'/g;
for (const name of ['game.js', 'road-situations.js', 'junction-situations.js', 'scenario-routes.js']) {
  for (const match of read(name).matchAll(labelSource)) {
    const label = match[1] || match[2];
    if (!cyrillic.test(label) || /^[АБВ]$/.test(label)) continue;
    for (const lang of ['kk', 'en']) {
      assert.ok(ui[lang][label], `${name}: no ${lang} text for "${label}"`);
    }
  }
}

// Runtime: ru is untouched, kk/en swap the texts but keep the answer order and the correct index.
const sample = { id: 'ticket_1_9', ticket: 'Билет 1 · Вопрос 9', title: 'x', explanation: 'x',
  pddRule: 'п. 1', options: ['a', 'b', 'c'], correctAnswerIndex: 1,
  legend: [{ label: 'Вы прямо', color: '#ED4621' }, { label: 'Грузовик', color: '#FFA53C' }] };

windowObject.PDD_LANG = 'ru';
assert.equal(localize(sample), sample, 'ru returns the same object');

for (const lang of ['kk', 'en']) {
  windowObject.PDD_LANG = lang;
  const out = localize(sample);
  assert.equal(out.title, translations.ticket_1_9[lang].title);
  assert.equal(out.options.length, sample.options.length);
  assert.equal(out.correctAnswerIndex, sample.correctAnswerIndex);
  // Time to answer follows the Russian source: its title and options length.
  assert.equal(out.sourceTextLength, sample.title.length + sample.options.join('').length);
  assert.equal(out.legend[0].label, ui[lang]['Вы прямо']);
  assert.equal(out.legend[1].label, ui[lang]['Грузовик']);
  assert.equal(sample.title, 'x', 'the original situation keeps its Russian text');
}

// An unknown situation falls back to the Russian original.
windowObject.PDD_LANG = 'kk';
const unknown = { id: 'road_99_99', title: 'Русский', options: ['a'], legend: [] };
assert.equal(localize(unknown), unknown);

console.log(`${ids.size} situations: kk and en texts present, answer order kept, runtime checks passed.`);
