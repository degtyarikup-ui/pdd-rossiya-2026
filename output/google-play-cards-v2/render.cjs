const fs=require('fs'),path=require('path');
const {createCanvas,loadImage,GlobalFonts}=require('@napi-rs/canvas');
const sharp=require('sharp');
const spec=require('../google-play-cards/spec.json');
GlobalFonts.registerFromPath(path.resolve('assets/fonts/Onest-Bold.ttf'),'Onest');
async function main(){
 const bg=await loadImage(path.join(__dirname,'background-generated.png'));
 const phone=await loadImage(path.join(__dirname,'phone-generated.png'));
 const frame=createCanvas(1080,1920),f=frame.getContext('2d');
 const xs=[94,142,799,848],ys=[47,89,1543,1620];
 const xd=[201,221,859,879],yd=[493,513,1848,1890];
 for(let y=0;y<3;y++)for(let x=0;x<3;x++)f.drawImage(phone,xs[x],ys[y],xs[x+1]-xs[x],ys[y+1]-ys[y],xd[x],yd[y],xd[x+1]-xd[x],yd[y+1]-yd[y]);
 f.save();f.globalCompositeOperation='destination-out';f.beginPath();f.roundRect(222,514,636,1333,34);f.fill();f.restore();
 fs.writeFileSync(path.join(__dirname,'phone-frame.png'),frame.toBuffer('image/png'));
 await sharp(path.join(__dirname,'background-generated.png')).resize(1080,1920).png().toFile(path.join(__dirname,'background.png'));
 const checks=[];
 for(let i=0;i<6;i++){
 const c=createCanvas(1080,1920),ctx=c.getContext('2d');
 ctx.save();if(i===2||i===5){ctx.translate(1080,0);ctx.scale(-1,1)}ctx.drawImage(bg,0,0,1080,1920);ctx.restore();
 ctx.font='bold 96px Onest';ctx.textAlign='center';ctx.textBaseline='top';ctx.fillStyle='white';spec.titles[i].split('\n').forEach((t,j)=>ctx.fillText(t,540,150+j*108));
 const src=await loadImage(spec.paths[i]),screen=createCanvas(638,1335);
 screen.getContext('2d').drawImage(src,0,135,src.width,src.height-135,0,0,638,1335);
 ctx.save();ctx.beginPath();ctx.roundRect(220,512,640,1337,35);ctx.clip();ctx.drawImage(screen,221,513);ctx.restore();
 ctx.drawImage(frame,0,0);
 const a=ctx.getImageData(265,557,550,1247).data,b=screen.getContext('2d').getImageData(44,44,550,1247).data;
 let differences=0;for(let n=0;n<a.length;n++)if(a[n]!==b[n])differences++;
 checks.push({card:i+1,size:[1080,1920],screenshotInteriorChangedChannels:differences});
 fs.writeFileSync(path.join(__dirname,'card-0'+(i+1)+'.png'),c.toBuffer('image/png'));
 }
 const thumbs=await Promise.all(Array.from({length:6},(_,i)=>sharp(path.join(__dirname,'card-0'+(i+1)+'.png')).resize(270,480).toBuffer()));
 await sharp({create:{width:810,height:960,channels:3,background:'#fff'}}).composite(thumbs.map((input,i)=>({input,left:i%3*270,top:Math.floor(i/3)*480}))).png().toFile(path.join(__dirname,'contact-sheet.png'));
 fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(checks,null,2));console.log(checks);
}
main();
