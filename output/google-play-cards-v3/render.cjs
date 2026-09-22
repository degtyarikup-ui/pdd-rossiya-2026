const fs=require('fs'),path=require('path');
const {createCanvas,loadImage,GlobalFonts}=require('@napi-rs/canvas');
const sharp=require('sharp');
const spec=require('../google-play-cards/spec.json'),gen=require('./generation.json');
GlobalFonts.registerFromPath(path.resolve('assets/fonts/Onest-Bold.ttf'),'Onest');
async function main(){
 const phone=await loadImage(gen.phone);
 const frame=createCanvas(1080,1920),f=frame.getContext('2d');
 // One whole image transform, no slicing or reconstruction of the body.
 const sx=638/707,sy=1335/1683,tx=221-87*sx,ty=513-47*sy;
 f.drawImage(phone,tx,ty,phone.width*sx,phone.height*sy);
 f.save();f.globalCompositeOperation='destination-out';f.beginPath();f.roundRect(222,514,636,1333,48);f.fill();f.restore();
 fs.writeFileSync(path.join(__dirname,'phone-frame.png'),frame.toBuffer('image/png'));
 fs.copyFileSync(gen.phone,path.join(__dirname,'phone-original.png'));
 const checks=[];
 for(let i=0;i<6;i++){
 const bgPath=path.join(__dirname,'background-0'+(i+1)+'.png');
 await sharp(gen.backgrounds[i]).flatten({background:'#298ef8'}).resize(1080,1920).png().toFile(bgPath);
 const bg=await loadImage(bgPath),c=createCanvas(1080,1920),ctx=c.getContext('2d');
 ctx.drawImage(bg,0,0);
 ctx.font='bold 96px Onest';ctx.textAlign='center';ctx.textBaseline='top';ctx.fillStyle='white';spec.titles[i].split('\n').forEach((t,j)=>ctx.fillText(t,540,150+j*108));
 ctx.save();ctx.shadowColor='rgba(0,20,60,.20)';ctx.shadowBlur=24;ctx.shadowOffsetY=14;ctx.fillStyle='#171b20';ctx.beginPath();ctx.roundRect(187,482,706,1398,70);ctx.fill();ctx.restore();
 const src=await loadImage(spec.paths[i]),screen=createCanvas(638,1335);
 screen.getContext('2d').drawImage(src,0,135,src.width,src.height-135,0,0,638,1335);
 ctx.save();ctx.beginPath();ctx.roundRect(220,512,640,1337,52);ctx.clip();ctx.drawImage(screen,221,513);ctx.restore();
 ctx.drawImage(frame,0,0);
 const a=ctx.getImageData(281,573,518,1215).data,b=screen.getContext('2d').getImageData(60,60,518,1215).data;
 let differences=0;for(let n=0;n<a.length;n++)if(a[n]!==b[n])differences++;
 checks.push({card:i+1,size:[1080,1920],screenshotInteriorChangedChannels:differences,headlineTop:150,screenBounds:[221,513,638,1335]});
 fs.writeFileSync(path.join(__dirname,'card-0'+(i+1)+'.png'),c.toBuffer('image/png'));
 }
 for(const prefix of ['card','background']){
 const thumbs=await Promise.all(Array.from({length:6},(_,i)=>sharp(path.join(__dirname,prefix+'-0'+(i+1)+'.png')).resize(270,480).toBuffer()));
 await sharp({create:{width:810,height:960,channels:3,background:'#fff'}}).composite(thumbs.map((input,i)=>({input,left:i%3*270,top:Math.floor(i/3)*480}))).png().toFile(path.join(__dirname,prefix+'-preview.png'));
 }
 fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(checks,null,2));console.log(checks);
}
main();
