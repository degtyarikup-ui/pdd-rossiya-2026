// Screen-independent overlay geometry: dimensions and other explanations have
// no answer letter and never serve as a driving route.
const AnnotationLine = (() => {
  const styles = [['line','Линия'],['arrow','Со стрелкой'],['both','Стрелки с двух сторон']];
  const colours = [['#20242b','Чёрная'],['#ffffff','Белая'],['#0574f8','Синяя'],['#e0533d','Красная'],['#e0b33c','Жёлтая']];
  function clean(points) {
    const out=[];
    for(const p of points || []) {
      if(!Array.isArray(p)||p.length!==2||!p.every(Number.isFinite))continue;
      const last=out.at(-1);
      if(!last||Math.hypot(p[0]-last[0],p[1]-last[1])>.0001)out.push([...p]);
    }
    return out;
  }
  const length = points => points.slice(1).reduce((sum,p,i)=>sum+Math.hypot(p[0]-points[i][0],p[1]-points[i][1]),0);
  function trim(points, metres) {
    const out = points.map(p=>[...p]);
    while(out.length>1) {
      const tip=out.at(-1), prev=out.at(-2), n=Math.hypot(tip[0]-prev[0],tip[1]-prev[1]);
      if(n>metres) {out[out.length-1]=tip.map((v,i)=>v+(prev[i]-v)*metres/n);break;}
      metres-=n;out.pop();
    }
    return out;
  }
  function geometry(route, border=0) {
    const points=clean(route.points);if(points.length<2)return [];
    const style=route.style || 'line', both=style==='both', end=style!=='line';
    const width=route.width ?? .16, half=(width+border*2)/2;
    const headLength=Math.min(.8,length(points)*.35), headWidth=Math.max(.26,width*2);
    let line=end?trim(points,headLength):points;
    if(both)line=trim([...line].reverse(),headLength).reverse();
    const out=[];
    const tri=(a,b,c)=>out.push(a,b,c);
    const disk=p=>{for(let i=0;i<16;i++)tri(p,[p[0]+Math.cos(i*Math.PI/8)*half,p[1]+Math.sin(i*Math.PI/8)*half],[p[0]+Math.cos((i+1)*Math.PI/8)*half,p[1]+Math.sin((i+1)*Math.PI/8)*half]);};
    for(let i=1;i<line.length;i++) {
      const a=line[i-1],b=line[i],n=Math.hypot(b[0]-a[0],b[1]-a[1]);if(n<.0001)continue;
      const x=-(b[1]-a[1])/n*half,z=(b[0]-a[0])/n*half;
      const p=[a[0]+x,a[1]+z],q=[a[0]-x,a[1]-z],r=[b[0]+x,b[1]+z],s=[b[0]-x,b[1]-z];
      tri(p,q,r);tri(r,q,s);
    }
    line.forEach((p,i)=>{if(i>0&&i<line.length-1 || i===0&&!both || i===line.length-1&&!end)disk(p);});
    const head=list=>{
      const tip=list.at(-1),base=trim(list,headLength).at(-1),n=Math.hypot(tip[0]-base[0],tip[1]-base[1]);if(n<.0001)return;
      const x=(tip[0]-base[0])/n,z=(tip[1]-base[1])/n,w=headWidth+border;
      tri([tip[0]+x*border*2,tip[1]+z*border*2],[base[0]-z*w-x*border,base[1]+x*w-z*border],[base[0]+z*w-x*border,base[1]-x*w-z*border]);
    };
    if(end)head(points);if(both)head([...points].reverse());
    return out;
  }
  return {styles,colours,clean,length,geometry};
})();
if(typeof module!=='undefined')module.exports=AnnotationLine;
