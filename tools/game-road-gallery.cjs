// Build output/game-textures/roads/index.html from the captured before/after PNGs.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const ROOT = 'output/game-textures/roads';
const NAMES = { game: 'Игровая камера', curb: 'Тротуар и бордюр', lanes: 'Асфальт и разметка', corner: 'Скруглённый угол',
  centre: 'Центр перекрёстка', seam: 'Стык сегментов', mouth: 'Примыкание', island: 'Островок', flare: 'Въезд на кольцо',
  median: 'Разделитель', transition: 'Грунт → асфальт', driveway: 'Въезд во двор', islands: 'Островки', bend: 'Изгиб',
  deck: 'Настил переезда', ballast: 'Балласт и шпалы', pavement: 'Тротуар у рельсов', shoulder: 'Обочина', junction: 'Угол примыкания', bay: 'Карман' };

(async () => {
  const capture = pass => JSON.parse(fs.readFileSync(path.join(ROOT, pass, 'capture.json'), 'utf8'));
  const after = capture('after'), before = capture('before');
  const have = new Set(before.records.map(r => r.scene + '-' + r.view));
  fs.mkdirSync(path.join(ROOT, 'web'), { recursive: true });
  const jpg = async (pass, name) => {
    const src = path.join(ROOT, pass, name + '.png'), out = path.join('web', pass + '-' + name + '.jpg');
    if (!fs.existsSync(src)) return null;
    await sharp(src).jpeg({ quality: 86, mozjpeg: true }).toFile(path.join(ROOT, out));
    return out;
  };
  const scenes = [];
  for (const r of after.records) {
    let s = scenes.find(x => x.id === r.scene);
    if (!s) scenes.push(s = { id: r.scene, label: r.label, views: [] });
    const name = r.scene + '-' + r.view;
    s.views.push({ view: r.view, after: await jpg('after', name), before: have.has(name) ? await jpg('before', name) : null });
  }
  const bench = fs.existsSync(path.join(ROOT, 'benchmark.json')) ? JSON.parse(fs.readFileSync(path.join(ROOT, 'benchmark.json'))) : null;
  const valid = fs.existsSync(path.join(ROOT, 'validation.json')) ? JSON.parse(fs.readFileSync(path.join(ROOT, 'validation.json'))) : null;
  const esc = t => String(t).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  const figure = (src, cap) => src ? `<figure><a href="${src}"><img loading="lazy" src="${src}" alt="${esc(cap)}"></a><figcaption>${esc(cap)}</figcaption></figure>`
    : `<figure class="none"><div>нет снимка «до»</div><figcaption>${esc(cap)}</figcaption></figure>`;
  const benchRows = bench ? bench.before.map((b, i) => { const a = bench.after[i];
    return `<tr><td>${esc(b.id)}</td><td>${b.calls} → ${a.calls}</td><td>${b.triangles} → ${a.triangles}</td><td>${b.textures} → ${a.textures}</td><td>${b.medianMs} → ${a.medianMs}</td></tr>`; }).join('') : '';
  const html = `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Дорога: до и после</title><style>
:root{--bg:#f4f5f7;--card:#fff;--ink:#1d2228;--muted:#69717c;--line:#dde1e6;--accent:#0574F8}
@media (prefers-color-scheme:dark){:root{--bg:#15181c;--card:#1e2227;--ink:#e8ebef;--muted:#9aa3ad;--line:#2d333a}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,system-ui,Segoe UI,Roboto,sans-serif}
main{max-width:1180px;margin:0 auto;padding:24px 16px 64px}h1{font-size:26px;margin:0 0 6px}h2{font-size:19px;margin:34px 0 10px}
p,li{color:var(--muted);max-width:820px}nav{display:flex;flex-wrap:wrap;gap:6px;margin:16px 0}nav a{padding:4px 10px;border-radius:14px;background:var(--card);color:var(--ink);text-decoration:none;font-size:13px}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:8px 0 18px}.pair h3{grid-column:1/-1;margin:6px 0 0;font-size:14px;color:var(--muted);font-weight:600}
figure{margin:0;background:var(--card);border-radius:10px;overflow:hidden}figure img{display:block;width:100%;height:auto}
.game figure img{max-height:640px;object-fit:contain;background:#dfe3e2}figcaption{padding:6px 10px;font-size:13px;color:var(--muted)}
figure.none div{aspect-ratio:3/4;display:grid;place-items:center;color:var(--muted)}table{border-collapse:collapse;background:var(--card);border-radius:10px;overflow:hidden;font-size:13px}
td,th{padding:6px 10px;border-bottom:1px solid var(--line);text-align:left}
@media (max-width:600px){.pair{gap:6px}figcaption{font-size:12px;padding:4px 6px}}
</style></head><body><main>
<h1>Прогон 2: дорога — до и после</h1>
<p>Снимки реального движка (лаборатория игры, лето, ясно, телефонный кадр 390×844 @2x). Слева — до прогона, справа — после. Крупные планы — ортокамера лаборатории с подписанным центром. Декор вокруг дороги может слегка отличаться: число создаваемых объектов изменилось, а Three.js тратит случайные числа на их идентификаторы.</p>
<nav>${scenes.map(s => `<a href="#${s.id}">${esc(s.label)}</a>`).join('')}</nav>
${scenes.map(s => `<section id="${s.id}"><h2>${esc(s.label)} <small style="color:var(--muted);font-weight:400">${esc(s.id)}</small></h2>
${s.views.map(v => `<div class="pair ${v.view === 'game' ? 'game' : ''}"><h3>${esc(NAMES[v.view] || v.view)}</h3>${figure(v.before, 'До')}${figure(v.after, 'После')}</div>`).join('')}</section>`).join('\n')}
<h2>Проверки и измерения</h2>
${valid ? `<p>tools/game-road-materials-test.cjs: ${Object.keys(valid.coverage).length} сцен без нетекстурированных поверхностей; ${valid.seams.overlaps} перекрытий у стыков с одинаковым текселем; масштаб через стык ${valid.seams.scaleAcrossSeam.toFixed(4)} м на метр; ${valid.rebase.length} перестройки мира (180°, 90°, 30°, −75°) без сдвига рисунка и со стыком нового участка; после перестройки изменилось ${(valid.rebaseFrameChange * 100).toFixed(3)}% пикселей кадра (края сглаживания); ${valid.themePairs} пар светлой/тёмной темы совпадают попиксельно; общих карт ${valid.lifecycle.shared} (${valid.lifecycle.sharedMiB} МиБ с mip-уровнями), рамок текстур не больше ${valid.lifecycle.maxFrames}.</p>` : ''}
${bench ? `<p>${esc(bench.environment)}. Медиана одной отрисовки сцены, сравнивать только столбцы между собой — это не FPS телефона.</p>
<table><tr><th>Сцена</th><th>Вызовы отрисовки</th><th>Треугольники</th><th>GPU-текстуры</th><th>мс</th></tr>${benchRows}</table>` : ''}
</main></body></html>`;
  // Images are embedded so the page also works in viewers that block sibling files.
  const inline = html.replace(/<a href="(web\/[^"]+)"><img loading="lazy" src="\1"/g, (m, f) =>
    `<a href="${f}"><img src="data:image/jpeg;base64,${fs.readFileSync(path.join(ROOT, f)).toString('base64')}"`);
  fs.writeFileSync(path.join(ROOT, 'index.html'), inline);
  console.log(path.join(ROOT, 'index.html'), scenes.length, 'scenes');
})().catch(e => { console.error(e); process.exitCode = 1; });
