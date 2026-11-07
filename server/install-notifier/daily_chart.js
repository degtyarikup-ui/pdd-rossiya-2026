// PNG rendered inside Workers. No third-party chart service or user identifiers.
const FONT = {
  '0':['01110','10001','10011','10101','11001','10001','01110'], '1':['00100','01100','00100','00100','00100','00100','01110'],
  '2':['01110','10001','00001','00010','00100','01000','11111'], '3':['11110','00001','00001','01110','00001','00001','11110'],
  '4':['00010','00110','01010','10010','11111','00010','00010'], '5':['11111','10000','10000','11110','00001','00001','11110'],
  '6':['01110','10000','10000','11110','10001','10001','01110'], '7':['11111','00001','00010','00100','01000','01000','01000'],
  '8':['01110','10001','10001','01110','10001','10001','01110'], '9':['01110','10001','10001','01111','00001','00001','01110'],
  'А':['01110','10001','10001','11111','10001','10001','10001'], 'В':['11110','10001','10001','11110','10001','10001','11110'],
  'Г':['11111','10000','10000','10000','10000','10000','10000'], 'Д':['01110','01010','01010','01010','01010','11111','10001'],
  'Е':['11111','10000','10000','11110','10000','10000','11111'], 'И':['10001','10001','10011','10101','11001','10001','10001'],
  'К':['10001','10010','10100','11000','10100','10010','10001'], 'М':['10001','11011','10101','10101','10001','10001','10001'],
  'Н':['10001','10001','10001','11111','10001','10001','10001'], 'О':['01110','10001','10001','10001','10001','10001','01110'],
  'П':['11111','10001','10001','10001','10001','10001','10001'], 'Р':['11110','10001','10001','11110','10000','10000','10000'],
  'С':['01111','10000','10000','10000','10000','10000','01111'], 'Т':['11111','00100','00100','00100','00100','00100','00100'],
  'У':['10001','10001','10001','01111','00001','00001','01110'], 'Ы':['10001','10001','10001','11101','10011','10011','11101'],
  'Ь':['10000','10000','10000','11110','10001','10001','11110'], 'Ч':['10001','10001','10001','01111','00001','00001','00001'],
  '/':['00001','00010','00010','00100','01000','01000','10000'], '.':['00000','00000','00000','00000','00000','00110','00110'],
  'Х':['10001','10001','01010','00100','01010','10001','10001'],
  'A':['01110','10001','10001','11111','10001','10001','10001'], 'E':['11111','10000','10000','11110','10000','10000','11111'],
  'G':['01110','10001','10000','10111','10001','10001','01110'], 'L':['10000','10000','10000','10000','10000','10000','11111'],
  'O':['01110','10001','10001','10001','10001','10001','01110'], 'P':['11110','10001','10001','11110','10000','10000','10000'],
  'R':['11110','10001','10001','11110','10100','10010','10001'], 'S':['01111','10000','10000','01110','00001','00001','11110'],
  'D':['11110','10001','10001','10001','10001','10001','11110'], 'U':['10001','10001','10001','10001','10001','10001','01110'],
  'T':['11111','00100','00100','00100','00100','00100','00100'], 'Y':['10001','10001','01010','00100','00100','00100','00100'],
  ':':['00000','00110','00110','00000','00110','00110','00000'], '-':['00000','00000','00000','11111','00000','00000','00000'],
};
// Orange matches AppColors.premiumAmber in the app.
const COLORS = [[246,248,252],[27,39,60],[216,223,235],[0,122,255],[39,174,96],[117,128,150],
  [255,165,60],[24,24,26],[142,62,0],[0,80,184]];
const GENERAL_SERIES = [
  { key: 'installs', label: 'УСТАНОВКИ', legendX: 40, offset: 0, width: 32, color: 3 },
  { key: 'registrations', label: 'АККАУНТЫ', legendX: 320, offset: 42, width: 32, color: 4 },
];
const PREMIUM_SERIES = [
  { key: 'web', label: 'PLATEGA', legendX: 40, offset: 0, width: 24, color: 6, valueColor: 8 },
  { key: 'appstore', label: 'APP STORE', legendX: 215, offset: 33, width: 24, color: 7 },
  { key: 'googleplay', label: 'GOOGLE PLAY', legendX: 420, offset: 66, width: 24, color: 3, valueColor: 9 },
];
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) { crc ^= byte; for (let i=0;i<8;i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, bytes) {
  const out = new Uint8Array(bytes.length + 12), view = new DataView(out.buffer);
  view.setUint32(0, bytes.length);
  out.set(new TextEncoder().encode(type), 4); out.set(bytes, 8);
  view.setUint32(out.length-4, crc32(out.subarray(4, out.length-4)));
  return out;
}
export function pngBase64(bytes) {
  let binary = '';
  for (let i=0; i<bytes.length; i+=8192) binary += String.fromCharCode(...bytes.subarray(i,i+8192));
  return btoa(binary);
}
export async function renderDailyChart(points, { premium = false } = {}) {
  if (!Array.isArray(points) || points.length !== 7) throw new Error('expected seven days');
  const w=960,h=520, pixels=new Uint8Array(w*h);
  function rect(x,y,width,height,color) {
    const left=Math.max(0,Math.round(x)),right=Math.min(w,Math.round(x+width));
    for (let row=Math.max(0,Math.round(y));row<Math.min(h,Math.round(y+height));row++) pixels.fill(color,row*w+left,row*w+right);
  }
  function text(value,x,y,color=1,scale=3) {
    for (const letter of String(value)) {
      const glyph=FONT[letter];
      if (glyph) glyph.forEach((row,j)=>[...row].forEach((bit,i)=>{ if(bit==='1') rect(x+i*scale,y+j*scale,scale,scale,color); }));
      x+=6*scale;
    }
  }
  const series = premium ? PREMIUM_SERIES : GENERAL_SERIES;
  text(premium ? 'ПРЕМИУМ / 7 СУТОК' : 'ПДД / 7 СУТОК',40,30,1,4);
  if (premium) text('СУММЫ ПОКУПОК / USD',695,42,5,2);
  for (const { label, legendX, color } of series) {
    rect(legendX,91,20,20,color); text(label,legendX+32,91,1,3);
  }
  text('22:00-22:00 МСК',premium ? 695 : 630,94,5,2);
  const count = v => Number.isFinite(Number(v)) ? Math.max(0,Math.min(1e8,Number(v))) : 0;
  const max=Math.max(5,...points.flatMap(p=>series.map(({ key })=>count(p[key]))));
  const magnitude=10**Math.floor(Math.log10(max/5));
  const step=Math.ceil(max/5/magnitude)*magnitude,top=step*5;
  const base=430,plot=260;
  for(let i=0;i<=5;i++) {
    const y=base-i*plot/5;
    rect(110,y,805,1,2); text(Math.round(i*step),20,y-7,5,2);
  }
  points.forEach((p,i)=>{
    const x=128+i*112;
    const labels = [];
    if(p.available === false) text('Н/Д',x+7,base-30,5,3);
    else for (const { key, offset, width, color, valueColor = color } of series) {
      const value=count(p[key]);
      const bh=value/top*plot;
      rect(x+offset,base-bh,width,bh,color);
      const label = premium ? (p[key] == null ? 'Н/Д' : value ? value.toFixed(2) : '0') : String(value);
      const labelScale = premium && label.length > 3 ? 1.5 : 2;
      const labelWidth = label.length * 6 * labelScale;
      const labelX=premium ? x+offset+(width-labelWidth)/2 : x+offset;
      let labelY=base-bh-20;
      while (premium && labels.some(other => labelX < other.right && labelX+labelWidth > other.left && Math.abs(labelY-other.y)<15)) labelY-=16;
      labels.push({ left: labelX, right: labelX+labelWidth, y: labelY });
      text(label,labelX,labelY,premium && p[key] == null ? 5 : valueColor,labelScale);
    }
    text(String(p.date).slice(8,10)+'.'+String(p.date).slice(5,7),x-4,453,1,3);
  });
  text('Н/Д - НЕТ ДАННЫХ',40,493,5,2);
  const raw=new Uint8Array((w+1)*h);
  for(let y=0;y<h;y++) raw.set(pixels.subarray(y*w,(y+1)*w),y*(w+1)+1);
  const compressed=new Uint8Array(await new Response(new Blob([raw]).stream().pipeThrough(new CompressionStream('deflate'))).arrayBuffer());
  const ihdr=new Uint8Array(13),view=new DataView(ihdr.buffer);
  view.setUint32(0,w);view.setUint32(4,h);ihdr[8]=8;ihdr[9]=3;
  const parts=[new Uint8Array([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('PLTE',new Uint8Array(COLORS.flat())),chunk('IDAT',compressed),chunk('IEND',new Uint8Array())];
  const png=new Uint8Array(parts.reduce((sum,p)=>sum+p.length,0));let offset=0;
  for(const p of parts){png.set(p,offset);offset+=p.length;}
  return png;
}
