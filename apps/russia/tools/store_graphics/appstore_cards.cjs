// Recompose cards from original captures for accepted iPhone screenshot sizes.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require('sharp');
const {execFileSync}=require('node:child_process');
const {createCanvas,loadImage,GlobalFonts}=require('@napi-rs/canvas');
const root=path.resolve(__dirname,'../..'),base=path.join(root,'store_assets/release-2026-10-18/cards-v2');
const out=path.join(base,'app-store'),manifest=JSON.parse(fs.readFileSync(path.join(base,'manifest.json')));
GlobalFonts.registerFromPath(path.join(root,'assets/fonts/Onest-Bold.ttf'),'Onest');
async function main(){
 const exports=[];
 for(const [size,w,h] of [['iphone-faceid-large',1242,2688],['iphone-dynamic-medium',1179,2556],['ipad-13',2048,2732]]){
  const dir=path.join(out,size);fs.mkdirSync(dir,{recursive:true});
  for(const card of (size==='ipad-13'?manifest.cards.slice(0,3):manifest.cards)){
   const c=createCanvas(w,h),ctx=c.getContext('2d'),s=size==='ipad-13'?1.5:w/1080;
   ctx.fillStyle=card.color;ctx.fillRect(0,0,w,h);ctx.textAlign='center';ctx.textBaseline='middle';ctx.font=`700 ${27*s}px Onest`;
   const bw=ctx.measureText(card.badge).width+58*s;ctx.fillStyle='#fff';ctx.beginPath();ctx.roundRect((w-bw)/2,96*s,bw,50*s,25*s);ctx.fill();ctx.fillStyle=card.color;ctx.fillText(card.badge,w/2,120*s);
   let font=102*s;while(font>80*s){ctx.font=`700 ${font}px Onest`;if(Math.max(...card.title.map(t=>ctx.measureText(t).width))<w-100*s)break;font--;}
   ctx.fillStyle='#fff';ctx.textBaseline='top';card.title.forEach((t,i)=>ctx.fillText(t,w/2,(202+i*108)*s));
   let input=path.join(base,'raw',card.id+'.png');
   if(size==='ipad-13'){
    const raw=path.join(out,'raw');fs.mkdirSync(raw,{recursive:true});
    input=path.join(raw,card.id+'.png');const src=path.join(root,'output/store-cards-2026-10-18/ipad-'+card.id.substring(3)+'.png');
    if(fs.existsSync(src))fs.copyFileSync(src,input);else if(!fs.existsSync(input))throw Error('Missing iPad capture');
   }
   const m=await sharp(input).metadata();
   const ch=card.crop?Math.min(m.height,Math.floor(m.width*16/9)):m.height;
   const img=await loadImage(await sharp(input).extract({left:0,top:0,width:m.width,height:ch}).png().toBuffer());
   const y=size==='ipad-13'?680:540*s;
   const ih=size==='ipad-13'?1900:Math.min(ch,h-y-90*s),iw=ih*img.width/img.height,x=(w-iw)/2;
   if(iw>w-100*s||iw>m.width||ih>ch)throw Error('Invalid screenshot geometry');
   ctx.save();ctx.beginPath();ctx.roundRect(x,y,iw,ih,36*s);ctx.clip();ctx.drawImage(img,x,y,iw,ih);ctx.restore();
   const file=path.join(dir,card.id+'.png');await sharp(c.toBuffer('image/png')).removeAlpha().png({compressionLevel:9}).toFile(file);
   const meta=await sharp(file).metadata();if(meta.hasAlpha||meta.width!==w||meta.height!==h)throw Error('Invalid export');
   exports.push({file:path.relative(out,file),width:w,height:h,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),source:path.relative(out,input),screenshotRect:{x,y,width:iw,height:ih}});
  }
 }
 fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({source:'../manifest.json',method:'Actual source captures recomposed without screenshot upscaling; verify against signed iOS build before review',exports},null,2)+'\n');
 fs.writeFileSync(path.join(out,'SHA256SUMS.txt'),exports.map(f=>f.sha256+'  '+f.file).join('\n')+'\n');
 const images=(folder,list)=>list.map(c=>`<article><a href="${folder}/${c.id}.png"><img src="${folder}/${c.id}.png" alt="${c.alt}"></a><p>${c.badge}</p></article>`).join('');
 fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>ПДД — App Store 2.2.4</title><style>body{font:16px system-ui;background:#f4f6fa;color:#14233c;max-width:1440px;margin:32px auto;padding:0 24px}h1{font-size:40px}a{color:#0574f8}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:18px}article img{width:100%;border-radius:12px}article p{font-size:13px}@media(max-width:900px){.grid{grid-template-columns:repeat(2,1fr)}}@media(max-width:520px){.grid{grid-template-columns:1fr}}</style><h1>App Store · ПДД 2.2.4</h1><p>Живой город → регулировщик → перекрёсток → остальные возможности.</p><p><a href="publishing-kit.zip">Скачать набор</a> · <a href="manifest.json">Источники и размеры</a> · <a href="../">Google Play и RuStore</a></p><h2>iPhone</h2><div class="grid">${images('iphone-dynamic-medium',manifest.cards)}</div><h2>iPad</h2><div class="grid">${images('ipad-13',manifest.cards.slice(0,3))}</div></html>`);
 const kit=path.join(out,'publishing-kit.zip');if(fs.existsSync(kit))fs.unlinkSync(kit);
 execFileSync('/usr/bin/zip',['-q','-r','publishing-kit.zip','iphone-dynamic-medium','iphone-faceid-large','ipad-13','manifest.json','SHA256SUMS.txt','index.html'],{cwd:out});
 const index=path.join(base,'index.html');let html=fs.readFileSync(index,'utf8');if(!html.includes('app-store/index.html')){html=html.replace('<div class="grid">','<p><a href="app-store/index.html">App Store: iPhone и iPad</a></p><div class="grid">');fs.writeFileSync(index,html);}
 console.log(JSON.stringify({exports:exports.length,out}));
}
main().catch(e=>{console.error(e);process.exitCode=1});
