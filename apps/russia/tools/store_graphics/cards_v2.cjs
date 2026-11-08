// Store posters assembled from actual current game captures and Flutter screens.
// NODE_PATH=<bundled node_modules> node tools/store_graphics/cards_v2.cjs
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const sharp = require('sharp');
const {createCanvas, loadImage, GlobalFonts} = require('@napi-rs/canvas');
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'store_assets/release-2026-10-18/cards-v2');
GlobalFonts.registerFromPath(path.join(root, 'assets/fonts/Onest-Bold.ttf'), 'Onest');
const B = '#0574F8', G = '#34A853', O = '#EB8214';
const cards = [
  {id:'01-city', badge:'ЖИВОЙ ГОРОД', title:['Учи ПДД', 'за рулём'], color:B, source:'output/store-cards-2026-10-18/city-alt.png', capture:'Godot 4.7.2 Compatibility, current sources; real ticket 5/14; 1080×1920', alt:'Живой город: автомобиль и трамвай на перекрёстке, вопрос по билету 5'},
  {id:'02-regulator', badge:'РЕГУЛИРОВЩИК', title:['Разбирайся', 'в сигналах'], color:G, source:'output/store-cards-2026-10-18/regulator.png', capture:'Godot 4.7.2 Compatibility, current sources; 1080×1920', alt:'Игра Регулировщик: инспектор показывает сигнал, внизу варианты разрешённых направлений'},
  {id:'03-crossroads', badge:'РАЗРУЛИ ПЕРЕКРЁСТОК', title:['Кто проедет', 'первым?'], color:B, source:'output/store-cards-2026-10-18/crossroads.png', capture:'Godot 4.7.2 Compatibility, current sources; 1080×1920', alt:'Три автомобиля с направлениями движения на перекрёстке — определите очерёдность проезда'},
  {id:'04-tickets', badge:'КАТЕГОРИИ A/B И C/D', title:['Билеты', 'с объяснениями'], color:B, source:'store_assets/release-2026-10-18/raw/13-ticket-image.png', crop:true, capture:'Actual Flutter web release capture, ticket 1/2; unchanged visible region', alt:'Вопрос билета с фотографией дорожной ситуации и вариантами ответа'},
  {id:'05-exam', badge:'20 ВОПРОСОВ · 20 МИНУТ', title:['Проверь себя', 'как в ГИБДД'], color:G, source:'output/release-audit-2026-10-18/screenshots/20-exam.png', crop:true, capture:'Actual Flutter web release capture; unchanged visible region', alt:'Экзамен ПДД: таймер 20 минут, номера вопросов и варианты ответа'},
  {id:'06-signs', badge:'СПРАВОЧНИКИ ОФЛАЙН', title:['Знаки и ПДД', 'под рукой'], color:O, source:'output/release-audit-2026-10-18/screenshots/10-signs.png', crop:true, capture:'Actual Flutter web release capture; unchanged visible region', alt:'Справочник дорожных знаков: предупреждающие знаки, знаки приоритета и запрещающие'},
  {id:'07-feed', badge:'ЛЕНТА С ОЗВУЧКОЙ', title:['Листай вопросы', 'слушай ответы'], color:B, source:'output/store-cards-2026-10-18/feed.png', capture:'Current Flutter FeedCard rendered with bundled ticket 27/13, light theme, Onest; 1080×1920', alt:'Лента ПДД: вопрос с изображением регулировщика и трамвая, кнопка озвучки и варианты ответа'},
  {id:'08-progress', badge:'ПРОГРЕСС · ОШИБКИ · ИЗБРАННОЕ', title:['Следи за', 'подготовкой'], color:G, source:'store_assets/release-2026-10-18/raw/01-home.png', capture:'Actual Flutter web release capture; initial local progress, unchanged visible region', alt:'Экран подготовки: шкала готовности, статистика, экзамен, темы, билеты, ошибки и избранное'},
];
const digest = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function round(ctx, x, y, w, h, r) {ctx.beginPath();ctx.roundRect(x,y,w,h,r);}
async function render(card, store) {
  const w=1080, h=1920, canvas=createCanvas(w,h), ctx=canvas.getContext('2d');
  ctx.fillStyle=card.color;ctx.fillRect(0,0,w,h);
  ctx.textAlign='center';ctx.textBaseline='middle';ctx.font='700 27px Onest';
  const badgeW=ctx.measureText(card.badge).width+58;
  if(badgeW>948)throw Error('Badge overflows: '+card.id);
  ctx.fillStyle='#fff';round(ctx,(w-badgeW)/2,58,badgeW,50,25);ctx.fill();
  ctx.fillStyle=card.color;ctx.fillText(card.badge,w/2,82);
  let font=102;
  do{ctx.font=`700 ${font}px Onest`;if(Math.max(...card.title.map(t=>ctx.measureText(t).width))<=948)break;font--;}while(font>88);
  if(font<88)throw Error('Title too long: '+card.id);
  ctx.fillStyle='#fff';ctx.textBaseline='top';
  card.title.forEach((line,i)=>ctx.fillText(line,w/2,140+i*108));
  const input=path.join(out,'raw',card.id+'.png');
  const meta=await sharp(input).metadata();
  const cropHeight=card.crop?Math.min(meta.height,Math.floor(meta.width*16/9)):meta.height;
  const bytes=await sharp(input).extract({left:0,top:0,width:meta.width,height:cropHeight}).png().toBuffer();
  const img=await loadImage(bytes);
  const ih=1470,iw=ih*img.width/img.height,x=(w-iw)/2,y=370;
  if(iw>864||iw>meta.width||ih>cropHeight)throw Error('Image geometry/upscale error: '+card.id);
  ctx.save();round(ctx,x,y,iw,ih,36);ctx.clip();ctx.drawImage(img,x,y,iw,ih);ctx.restore();
  const file=path.join(out,store,card.id+(store==='rustore'?'.jpg':'.png'));
  const output=sharp(canvas.toBuffer('image/png')).removeAlpha().toColourspace('srgb');
  if(store==='rustore')await output.jpeg({quality:95,mozjpeg:true}).toFile(file);
  else await output.png({compressionLevel:9}).toFile(file);
  const result=await sharp(file).metadata(),size=fs.statSync(file).size;
  if(result.width!==w||result.height!==h||result.hasAlpha||size>3*1024*1024)throw Error('Invalid export '+file);
  return {store,file:path.relative(out,file),width:w,height:h,bytes:size,sha256:digest(file),headlineFont:font,sourceCrop:{x:0,y:0,width:meta.width,height:cropHeight},screenshotRect:{x,y,width:iw,height:ih},alt:card.alt};
}
async function feature(){
  const c=createCanvas(1024,500),ctx=c.getContext('2d');ctx.fillStyle=B;ctx.fillRect(0,0,1024,500);
  const buffer=await sharp(path.join(out,'raw/01-city.png')).extract({left:0,top:220,width:1080,height:1055}).resize(512,500,{fit:'cover'}).png().toBuffer();
  const img=await loadImage(buffer);ctx.drawImage(img,512,0,512,500);
  ctx.fillStyle='#fff';ctx.textAlign='left';ctx.textBaseline='top';
  ctx.font='700 22px Onest';ctx.fillText('ПДД РОССИЯ',50,48);
  ctx.font='700 60px Onest';ctx.fillText('ПДД оживают',50,124);ctx.fillText('в игре',50,194);
  ctx.font='700 25px Onest';ctx.fillText('Живой город',50,316);
  ctx.font='700 19px Onest';ctx.fillText('Регулировщик · Перекрёстки',50,362);
  const file=path.join(out,'google-play/feature-1024x500.png');
  await sharp(c.toBuffer('image/png')).removeAlpha().png().toFile(file);
  return {file:path.relative(out,file),width:1024,height:500,sha256:digest(file),alt:'ПДД оживают в игре: городской перекрёсток с автомобилем и трамваем'};
}
async function main(){
  fs.mkdirSync(path.join(out,'raw'),{recursive:true});
  for(const card of cards){const src=path.join(root,card.source),dest=path.join(out,'raw',card.id+'.png');if(fs.existsSync(src))fs.copyFileSync(src,dest);else if(!fs.existsSync(dest))throw Error('Missing capture '+src);card.sourceSha256=digest(dest);}
  const files=[];
  for(const store of ['google-play','rustore']){fs.mkdirSync(path.join(out,store),{recursive:true});for(const card of cards)files.push(await render(card,store));}
  const banner=await feature();
  for(const [name,cols,rows] of [['preview',4,2],['games-preview',3,1]]){
    const subset=name==='preview'?cards:cards.slice(0,3),tw=324,th=576,gap=16;
    const parts=await Promise.all(subset.map(card=>sharp(path.join(out,'google-play',card.id+'.png')).resize(tw,th).toBuffer()));
    await sharp({create:{width:cols*tw+(cols-1)*gap,height:rows*th+(rows-1)*gap,channels:3,background:'#e9edf4'}}).composite(parts.map((input,i)=>({input,left:(i%cols)*(tw+gap),top:Math.floor(i/cols)*(th+gap)}))).png().toFile(path.join(out,name+'.png'));
  }
  const manifest={date:'2026-10-18',sourceCommit:execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),order:cards.map(c=>c.id),cards,files,featureGraphic:banner,method:'Actual Godot captures, actual Flutter screenshots/component rendering, deterministic Onest composition. No generated or retouched gameplay.',nativeAndroidScreenshots:false,status:'design-review; not submitted',specs:{google:'https://support.google.com/googleplay/android-developer/answer/9866151',rustore:'https://www.rustore.ru/help/developers/publishing-and-verifying-apps/app-publication'}};
  fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  fs.writeFileSync(path.join(out,'SHA256SUMS.txt'),[...files,banner].map(f=>`${f.sha256}  ${f.file}`).join('\n')+'\n');
  fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>ПДД — карточки для сторов</title><style>*{box-sizing:border-box}body{font:16px system-ui;color:#14233c;background:#f4f6fa;margin:0}main{max-width:1440px;margin:auto;padding:36px 24px}h1{font-size:42px;letter-spacing:-1.5px;margin:0 0 14px}p{line-height:1.6;max-width:960px}.links a{margin-right:24px}a{color:#0574F8}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:18px;margin-top:30px}article{background:white;border-radius:18px;padding:12px}article img{display:block;width:100%;border-radius:10px}h2{font-size:19px;margin:14px 0 8px}small{color:#687386}.banner{max-width:1024px;width:100%;display:block;border-radius:14px;margin-top:20px}@media(max-width:1000px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:520px){.grid{grid-template-columns:1fr}h1{font-size:32px}}</style><main><h1>Сначала игры. Затем вся подготовка.</h1><p>Живой город → регулировщик → перекрёсток. Дальше — билеты, экзамен, справочники, лента с озвучкой и прогресс. Восемь карточек в одном порядке для Google Play и RuStore.</p><p class="links"><a href="publishing-kit.zip">Скачать комплект</a><a href="manifest.json">Источники и размеры</a><a href="games-preview.png">Первые три крупно</a></p>${fs.existsSync(path.join(out,'app-store/index.html'))?'<p><a href="app-store/index.html">App Store: iPhone и iPad</a></p>':''}<div class="grid">${cards.map((c,i)=>`<article><a href="google-play/${c.id}.png"><img src="google-play/${c.id}.png" alt="${c.alt}"></a><h2>${i+1}. ${c.badge}</h2><a href="google-play/${c.id}.png">Google Play · PNG</a> · <a href="rustore/${c.id}.jpg">RuStore · JPG</a></article>`).join('')}</div><h2>Обложка Google Play</h2><a href="google-play/feature-1024x500.png"><img class="banner" src="google-play/feature-1024x500.png" alt="${banner.alt}"></a><p><small>Игры сняты из текущих исходников Godot. Экраны обучения — реальные Flutter-кадры; лента отрендерена текущим компонентом с вопросом из контента. Настольный рендер не заменяет проверку финальной Android-сборки. Готово к обсуждению, на модерацию не отправлено.</small></p></main></html>`);
  const zip=path.join(out,'publishing-kit.zip');if(fs.existsSync(zip))fs.unlinkSync(zip);
  execFileSync('/usr/bin/zip',['-q','-r','publishing-kit.zip','google-play','rustore','manifest.json','SHA256SUMS.txt'],{cwd:out});
  console.log(JSON.stringify({posters:files.length,feature:banner.file,maxFileBytes:Math.max(...files.map(f=>f.bytes)),out}));
}
main().catch(e=>{console.error(e);process.exitCode=1});
