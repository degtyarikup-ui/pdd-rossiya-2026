// Two points run along the kerb; the teeth occupy a narrow band on one side.
const BusStopMark = (() => {
  const defaults = {depth:1.2, step:1.5, width:.12, side:1};
  const limits = {length:[2,60,.5], depth:[.4,3,.1], step:[.6,4,.1], width:[.06,.3,.01]};
  const length = m => m.points?.length === 2 ? Math.hypot(m.points[1][0]-m.points[0][0],m.points[1][1]-m.points[0][1]) : 0;
  const count = m => Math.max(1,Math.floor(length(m)/(m.step ?? defaults.step)+.5));
  function label(m) {
    const n=count(m),mod=n%100;
    return `${n} ${mod>=11&&mod<=14 ? 'зубцов' : n%10===1 ? 'зубец' : n%10>=2&&n%10<=4 ? 'зубца' : 'зубцов'}`;
  }
  function line(m) {
    const n = length(m);
    if (n < .001) return [];
    const [a,b] = m.points, dx=(b[0]-a[0])/n, dz=(b[1]-a[1])/n;
    const side=m.side ?? 1, depth=m.depth ?? defaults.depth, teeth=count(m);
    const at = (t,v) => [a[0]+dx*t-dz*v*side,a[1]+dz*t+dx*v*side];
    const out=[at(0,0)];
    for(let i=0;i<teeth;i++) out.push(at((i+.5)*n/teeth,depth),at((i+1)*n/teeth,0));
    return out;
  }
  function polygons(m) {
    const points=line(m);
    if(points.length<2)return [];
    const half=(m.width ?? defaults.width)/2;
    const normals=points.slice(1).map((b,i)=>{const a=points[i],n=Math.hypot(b[0]-a[0],b[1]-a[1]);return [-(b[1]-a[1])/n,(b[0]-a[0])/n];});
    const offsets=points.map((p,i)=>{
      if(i===0)return normals[0].map(v=>v*half);
      if(i===points.length-1)return normals.at(-1).map(v=>v*half);
      const a=normals[i-1],b=normals[i],sum=[a[0]+b[0],a[1]+b[1]],den=sum[0]*b[0]+sum[1]*b[1];
      return sum.map(v=>v*half/den);
    });
    const edge = side => points.map((p,i)=>p.map((v,k)=>v+offsets[i][k]*side));
    return [[...edge(1),...edge(-1).reverse()]];
  }
  function setLength(m,value) {
    const a=m.points[0], b=m.points[1], n=length(m), dx=n>.001 ? (b[0]-a[0])/n : 1, dz=n>.001 ? (b[1]-a[1])/n : 0;
    m.points[1]=[a[0]+dx*value,a[1]+dz*value];
  }
  const inside = (p, ring) => {
    let on=false;
    for(let i=0,j=ring.length-1;i<ring.length;j=i++) {
      const a=ring[i],b=ring[j];
      if((a[1]>p[1])!==(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])on=!on;
    }
    return on;
  };
  function chooseSide(scene,m) {
    const score = side => line({...m,side}).filter((_,i)=>i%2).reduce((sum,p)=>sum+Number((scene.roads || []).some(r=>inside(p,r.outer)&&!(r.holes || []).some(h=>inside(p,h)))),0);
    return score(-1)>score(1) ? -1 : 1;
  }
  function svg() {
    return '<svg class="bus-stop-mark-pic" viewBox="0 0 48 28" aria-hidden="true"><rect width="48" height="28" rx="3" fill="#3a3f47"/><path d="M4 22 9 6 14 22 19 6 24 22 29 6 34 22 39 6 44 22" fill="none" stroke="#f5b025" stroke-width="1.6" stroke-linejoin="miter"/></svg>';
  }
  return {defaults,limits,length,count,label,line,polygons,chooseSide,setLength,svg};
})();
if(typeof module!=='undefined')module.exports=BusStopMark;
