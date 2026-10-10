const fs=require('fs'),path=require('path'),sharp=require('sharp');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
async function main(){
 const assets={};
 for(const name of ['steering-wheel','ai-spark']){
  const {data,info}=await sharp(path.join(__dirname,name+'.png')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let minX=info.width,minY=info.height,maxX=0,maxY=0;
  for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++)if(data[(y*info.width+x)*4+3]>24){minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);}
  const buffer=await sharp(path.join(__dirname,name+'.png')).extract({left:Math.max(0,minX-2),top:Math.max(0,minY-2),width:Math.min(info.width-minX,maxX-minX+5),height:Math.min(info.height-minY,maxY-minY+5)}).png().toBuffer();
  assets[name]=await loadImage(buffer);
 }
 for(let i=1;i<=6;i++){
  const src=path.join(__dirname,'../google-play-cards-v4/card-0'+i+'.png'),dest=path.join(__dirname,'card-0'+i+'.png');
  if(i!==1&&i!==5){fs.copyFileSync(src,dest);continue;}
  const canvas=createCanvas(1080,1920),ctx=canvas.getContext('2d');ctx.drawImage(await loadImage(src),0,0);
  const name=i===1?'steering-wheel':'ai-spark',img=assets[name];
  const width=i===1?490:146,x=i===1?814:902,y=i===1?1575:354;
  const height=width*img.height/img.width;
  ctx.save();ctx.shadowColor='rgba(0,20,65,.19)';ctx.shadowBlur=i===1?18:10;ctx.shadowOffsetY=8;ctx.drawImage(img,x,y,width,height);ctx.restore();
  fs.writeFileSync(dest,canvas.toBuffer('image/png'));
 }
 const thumbs=await Promise.all(Array.from({length:6},(_,i)=>sharp(path.join(__dirname,'card-0'+(i+1)+'.png')).resize(270,480).toBuffer()));
 await sharp({create:{width:810,height:960,channels:3,background:'#fff'}}).composite(thumbs.map((input,i)=>({input,left:i%3*270,top:Math.floor(i/3)*480}))).png().toFile(path.join(__dirname,'preview.png'));
}
main();
