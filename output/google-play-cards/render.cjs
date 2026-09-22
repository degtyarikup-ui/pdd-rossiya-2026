const fs=require('fs');
const path=require('path');
const {createCanvas,loadImage,GlobalFonts}=require('@napi-rs/canvas');
const sharp=require('sharp');
const spec=require('./spec.json');
GlobalFonts.registerFromPath(path.resolve('assets/fonts/Onest-Bold.ttf'),'Onest');
const W=1080,H=1920;
function rounded(ctx,x,y,w,h,r){ctx.beginPath();ctx.roundRect(x,y,w,h,r);}
function cone(c,x,y){
 c.save();c.translate(x,y);c.rotate(-.12);
 c.fillStyle='#FF8A00';rounded(c,-47,65,94,18,8);c.fill();
 c.beginPath();c.moveTo(-34,68);c.lineTo(-12,0);c.quadraticCurveTo(0,-8,12,0);c.lineTo(34,68);c.closePath();c.fill();
 c.fillStyle='rgba(255,255,255,.87)';c.beginPath();c.moveTo(-21,29);c.lineTo(21,29);c.lineTo(27,47);c.lineTo(-27,47);c.closePath();c.fill();c.restore();
}
function road(c,i){
 const ways=[
 [-140,1860,180,1250,850,1010,1210,410],
 [-210,530,520,810,780,1240,1210,1840],
 [-130,430,260,980,830,1270,1200,1870],
 [-160,1840,230,1410,840,930,1210,690],
 [-120,1500,360,1670,770,790,1190,590],
 [-120,620,330,900,740,1400,1210,1610]];
 const p=ways[i];c.beginPath();c.moveTo(p[0],p[1]);c.bezierCurveTo(...p.slice(2));
 c.strokeStyle='rgba(255,255,255,.055)';c.lineWidth=160;c.stroke();
 c.strokeStyle='rgba(255,255,255,.20)';c.lineWidth=7;c.setLineDash([33,34]);c.stroke();c.setLineDash([]);
}
async function main(){
 const report=[];
 for(let i=0;i<6;i++){
  const c=createCanvas(W,H),ctx=c.getContext('2d');
  const g=ctx.createLinearGradient(0,0,0,H);g.addColorStop(0,'#0A5AF5');g.addColorStop(.6,'#0574F8');g.addColorStop(1,'#278DFA');ctx.fillStyle=g;ctx.fillRect(0,0,W,H);
  road(ctx,i);
  const pos=[[194,1660],[924,413],[890,1650],[156,413],[182,1650],[886,1670]][i];cone(ctx,...pos);
  if(i===4){for(const [x,y,s] of [[135,680,17],[940,1110,13],[142,1410,11]]){
   ctx.fillStyle='rgba(255,255,255,.42)';ctx.beginPath();ctx.moveTo(x,y-s);ctx.quadraticCurveTo(x+3,y-3,x+s,y);ctx.quadraticCurveTo(x+3,y+3,x,y+s);ctx.quadraticCurveTo(x-3,y+3,x-s,y);ctx.quadraticCurveTo(x-3,y-3,x,y-s);ctx.fill();
  }}
  ctx.font='bold 96px Onest';ctx.textAlign='center';ctx.textBaseline='top';ctx.fillStyle='#FFFFFF';
  const lines=spec.titles[i].split('\n');lines.forEach((t,j)=>ctx.fillText(t,540,150+j*108));
  const x=208,y=500,w=664,h=1367;
  ctx.save();ctx.shadowColor='rgba(0,28,92,.24)';ctx.shadowBlur=35;ctx.shadowOffsetY=19;ctx.fillStyle='#151C27';rounded(ctx,x,y,w,h,48);ctx.fill();ctx.restore();
  ctx.strokeStyle='#455165';ctx.lineWidth=2;rounded(ctx,x+1,y+1,w-2,h-2,47);ctx.stroke();
  ctx.fillStyle='#111823';rounded(ctx,x-3,y+190,4,70,2);ctx.fill();rounded(ctx,x+w-1,y+244,4,100,2);ctx.fill();
  const src=await loadImage(spec.paths[i]);
  const crop=135,sw=644,sh=1347,sx=218,sy=510;
  ctx.save();rounded(ctx,sx,sy,sw,sh,38);ctx.clip();
  const prepared=createCanvas(sw,sh);prepared.getContext('2d').drawImage(src,0,crop,src.width,src.height-crop,0,0,sw,sh);ctx.drawImage(prepared,sx,sy);ctx.restore();
  const dest=path.join(__dirname,'card-0'+(i+1)+'.png');fs.writeFileSync(dest,c.toBuffer('image/png'));
  // Compare the unmasked interior with an independently rendered source crop.
  const check=createCanvas(sw,sh);check.getContext('2d').drawImage(src,0,crop,src.width,src.height-crop,0,0,sw,sh);
  const a=ctx.getImageData(sx+40,sy+40,sw-80,sh-80).data;
  const b=check.getContext('2d').getImageData(40,40,sw-80,sh-80).data;
  let diff=0;for(let n=0;n<a.length;n++)if(a[n]!==b[n])diff++;
  report.push({card:i+1,size:[W,H],headlineTop:150,fontSize:96,phone:[x,y,w,h],sourceCropTop:crop,screenshotInteriorDifferentChannels:diff});
 }
 fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(report,null,2));
 const thumbs=await Promise.all(Array.from({length:6},(_,i)=>sharp(path.join(__dirname,'card-0'+(i+1)+'.png')).resize(270,480).toBuffer()));
 await sharp({create:{width:810,height:960,channels:3,background:'#fff'}}).composite(thumbs.map((input,i)=>({input,left:(i%3)*270,top:Math.floor(i/3)*480}))).png().toFile(path.join(__dirname,'contact-sheet.png'));
 console.log(JSON.stringify(report));
}
main();
