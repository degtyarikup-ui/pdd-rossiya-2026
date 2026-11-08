// Publish exports retain the captured screenshot exactly; ImageGen concepts are
// saved separately in generated/. Run with the bundled NODE_PATH from Codex.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const {execFileSync} = require('node:child_process');
const {createCanvas, loadImage, GlobalFonts} = require('@napi-rs/canvas');
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'store_assets/release-2026-10-18');
GlobalFonts.registerFromPath(path.join(root,'assets/fonts/Onest-Bold.ttf'),'Onest');
const cards = [
 {id:'01-city',source:'game-city-question.png',badge:'ЖИВОЙ ГОРОД',title:['ПДД оживают','в 3D-городе'],color:'#0574F8',capture:'Godot desktop Compatibility; captured PNG 586×1266, no upscale'},
 {id:'02-crossroads',source:'game-crossroads.png',badge:'ИГРЫ ПО ПДД',title:['Разрули','перекрёсток'],color:'#0574F8',capture:'Godot desktop Compatibility; captured PNG 586×1266, no upscale'},
 {id:'03-regulator',source:'game-regulator.png',badge:'РЕГУЛИРОВЩИК',title:['Понимай','сигналы'],color:'#34A853',capture:'Godot desktop Compatibility; captured PNG 586×1266, no upscale'},
 {id:'04-signs',source:'03-sign-game.png',badge:'ЭТО ЗНАК',title:['Узнавай знаки','в игре'],color:'#EB8214',capture:'Local Flutter web release; Chrome 390×844 @3x'},
 {id:'05-tickets',source:'13-ticket-image.png',badge:'БИЛЕТЫ A/B И C/D',title:['Тренируйся','по билетам'],color:'#0574F8',capture:'Local Flutter web release; Chrome 390×844 @3x'},
 {id:'06-progress',source:'01-home.png',badge:'ТВОЯ ПОДГОТОВКА',title:['Следи за','прогрессом'],color:'#34A853',capture:'Local Flutter web release; Chrome 390×844 @3x'},
];
const sizes = {'google-play':[1080,1920],rustore:[1080,1920],'app-store':[1260,2736]};
function rounded(ctx,x,y,w,h,r){ctx.beginPath();ctx.roundRect(x,y,w,h,r);}
async function render(card,store,w,h){
 const canvas=createCanvas(w,h),ctx=canvas.getContext('2d');
 const scale=w/1080;
 ctx.fillStyle=card.color;ctx.fillRect(0,0,w,h);
 const badgeY=70*scale,badgeH=52*scale;
 ctx.font=`700 ${28*scale}px Onest`;
 const badgeW=ctx.measureText(card.badge).width+64*scale;
 ctx.fillStyle='#fff';rounded(ctx,(w-badgeW)/2,badgeY,badgeW,badgeH,badgeH/2);ctx.fill();
 ctx.fillStyle=card.color;ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(card.badge,w/2,badgeY+badgeH/2);
 let titleSize=92*scale;
 do {ctx.font=`700 ${titleSize}px Onest`;if(Math.max(...card.title.map(t=>ctx.measureText(t).width))<=w-100*scale)break;titleSize-=1;} while(titleSize>40);
 ctx.fillStyle='#fff';ctx.textBaseline='top';
 const titleY=158*scale;
 card.title.forEach((t,i)=>ctx.fillText(t,w/2,titleY+i*106*scale));
 const img=await loadImage(path.join(out,'raw',card.source));
 const top=(store==='app-store'?510:420)*scale;
 const bottom=70*scale;
 const ih=h-top-bottom, iw=ih*img.width/img.height;
 if(iw>w-100*scale)throw Error('Screenshot does not fit: '+card.id);
 const x=(w-iw)/2;
 ctx.save();rounded(ctx,x,top,iw,ih,40*scale);ctx.clip();
 ctx.drawImage(img,x,top,iw,ih);ctx.restore();
 const dest=path.join(out,store,card.id+(store==='rustore'?'.jpg':'.png'));
 const png=canvas.toBuffer('image/png');
 const writer=sharp(png).removeAlpha().toColourspace('srgb');
 if(store==='rustore')await writer.jpeg({quality:94,mozjpeg:true}).toFile(dest);
 else await writer.png({compressionLevel:9}).toFile(dest);
 const meta=await sharp(dest).metadata();
 if(meta.hasAlpha||meta.width!==w||meta.height!==h)throw Error('Invalid export');
 const bytes=fs.statSync(dest).size;
 if(store==='rustore'&&bytes>3*1024*1024)throw Error('RuStore 3MiB limit');
 return {store,file:path.relative(out,dest),width:w,height:h,bytes,hasAlpha:meta.hasAlpha,screenshotRect:{x,y:top,width:iw,height:ih},titleFontSize:titleSize};
}
async function main(){
 fs.mkdirSync(path.join(out,'raw'),{recursive:true});
 for(const c of cards)fs.copyFileSync(path.join(root,'output/release-audit-2026-10-18/screenshots',c.source),path.join(out,'raw',c.source));
 const files=[];
 for(const [store,[w,h]] of Object.entries(sizes)){
  fs.mkdirSync(path.join(out,store),{recursive:true});
  for(const card of cards)files.push(await render(card,store,w,h));
 }
 const thumbs=await Promise.all(cards.map(c=>sharp(path.join(out,'google-play',c.id+'.png')).resize(270,480).toBuffer()));
 await sharp({create:{width:810,height:960,channels:3,background:'#fff'}}).composite(thumbs.map((input,i)=>({input,left:i%3*270,top:Math.floor(i/3)*480}))).png().toFile(path.join(out,'preview.png'));
 fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({date:'2026-10-18',cards,files,method:'ImageGen campaign concepts + deterministic Onest layout with unaltered real UI captures',nativeDeviceVerification:false,sourceNotes:'Raw Godot screenshots are desktop renders; Flutter screenshots are local web release. Verify against final signed phone builds before submission.',specs:{google:'https://support.google.com/googleplay/android-developer/answer/9866151',apple:'https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/',rustore:'https://www.rustore.ru/help/developers/advertising-and-promotion/custom-pages'}},null,2));
 fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Карточки ПДД · 18.10.2026</title><style>body{font:16px system-ui;background:#f5f7fb;color:#14233c;max-width:1200px;margin:40px auto;padding:0 24px}h1{font-size:40px;letter-spacing:-1px}p{line-height:1.6;max-width:900px}a{color:#0574F8}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:24px}article{background:white;border-radius:20px;padding:16px}img{width:100%;border-radius:12px}article p{font-size:14px}small{color:#53627a}</style><h1>ПДД оживают в игре</h1><p>Шесть карточек: четыре про игры, билеты и прогресс. Короткие заголовки, реальные кадры, исходные изображения сохранены. Генератор изображений создал три концепта в <a href="generated/">generated/</a>; экспорт для публикации сохраняет исходный интерфейс без перерисовки.</p><p><strong>Перед загрузкой:</strong> сравнить с финальной подписанной версией на Android и iPhone. Godot снят на desktop, Flutter — в локальной web release. Геометрия файлов проверена; прохождение модерации и точное совпадение с финальным native UI этим не подтверждены.</p><p><a href="publishing-kit.zip">Скачать все 18 файлов · ZIP</a> · <a href="manifest.json">Манифест и размеры</a> · <a href="raw/">Исходные кадры</a> · <a href="generated/prompts.json">Промпты ImageGen</a></p><div class="grid">${cards.map(c=>`<article><img src="google-play/${c.id}.png" alt="${c.title.join(' ')}"><p><strong>${c.title.join(' ')}</strong></p><p><a href="google-play/${c.id}.png">Google Play · PNG</a><br><a href="rustore/${c.id}.jpg">RuStore · JPG</a><br><a href="app-store/${c.id}.png">App Store · PNG</a></p><small>${c.capture}</small></article>`).join('')}</div></html>`);
 execFileSync('/usr/bin/zip',['-q','-r','publishing-kit.zip','google-play','rustore','app-store','manifest.json'],{cwd:out});
 console.log(JSON.stringify({exports:files.length,raw:cards.length,maxBytes:Math.max(...files.map(f=>f.bytes))}));
}
main().catch(e=>{console.error(e);process.exitCode=1});
