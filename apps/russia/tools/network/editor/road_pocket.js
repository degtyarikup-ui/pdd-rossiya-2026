// A freely placed road widening. The same cubic outline is built by pocket_geometry.py.
const RoadPocket = (() => {
  const defaults = {length:16, width:3, entryLength:8, exitLength:8, side:'right', walk:true, edge:true};
  const limits = {length:[1,200],width:[.5,30],entryLength:[1,150],exitLength:[1,150]};
  const number = (value, fallback) => value !== null && value !== undefined && String(value).trim() !== "" && Number.isFinite(Number(value)) ? Number(value) : fallback;
  function normalized(p = {}) {
    const out = {...defaults,...p};
    for (const [key,[min,max]] of Object.entries(limits)) out[key] = Math.max(min,Math.min(max,number(p[key],defaults[key])));
    out.pos = [number(p.pos?.[0],0),number(p.pos?.[1],0)]; out.yaw = number(p.yaw,0);
    out.side = p.side === 'left' || p.side === -1 ? 'left' : 'right';
    return out;
  }
  function at(p, along, across) {
    const a=p.yaw || 0, sign=p.side === 'left' || p.side === -1 ? -1 : 1;
    return [p.pos[0]+Math.sin(a)*along-Math.cos(a)*across*sign,
      p.pos[1]+Math.cos(a)*along+Math.sin(a)*across*sign];
  }
  function outline(value) {
    const p=normalized(value), points=[], half=p.length/2;
    const smooth=t=>t*t*(3-2*t);
    const entry=Math.max(8,Math.ceil(p.entryLength/.5)), exit=Math.max(8,Math.ceil(p.exitLength/.5));
    for(let i=0;i<=entry;i++) points.push(at(p,-half-p.entryLength+p.entryLength*i/entry,p.width*smooth(i/entry)));
    points.push(at(p,half,p.width));
    for(let i=1;i<=exit;i++) points.push(at(p,half+p.exitLength*i/exit,p.width*(1-smooth(i/exit))));
    return points;
  }
  // Use the authored/generated asphalt edge, including roads without an editable street plan.
  function placement(scene, position, yaw=null, free=false) {
    let best=null;
    if (!free && yaw === null) for(const road of scene.roads || []) {
      if (road.surface === "pavement") continue;
      const ring=road.outer || [];
      const area=ring.reduce((sum,p,i)=>{const q=ring[(i+1)%ring.length];return sum+p[0]*q[1]-q[0]*p[1];},0);
      for(let i=0;i<ring.length;i++) {
        const a=ring[i],b=ring[(i+1)%ring.length],dx=b[0]-a[0],dz=b[1]-a[1],length2=dx*dx+dz*dz;
        if(length2<.01)continue;
        const t=Math.max(0,Math.min(1,((position[0]-a[0])*dx+(position[1]-a[1])*dz)/length2));
        const pos=[a[0]+t*dx,a[1]+t*dz],distance=Math.hypot(pos[0]-position[0],pos[1]-position[1]);
        if(distance<=5 && (!best || distance<best.distance)) best={distance,pos,yaw:Math.atan2(dx,dz),side:area>0?'left':'right'};
      }
    }
    return {...defaults,pos:best?.pos || [...position],yaw:best?.yaw ?? yaw ?? 0,side:best?.side || defaults.side};
  }
  function picture() {
    return '<svg viewBox="0 0 88 52" aria-hidden="true"><rect x="4" y="26" width="80" height="18" rx="2" fill="#596367"/><path d="M5 26C19 26 17 8 31 8H57C71 8 69 26 83 26" fill="#596367" stroke="#d7ddd6" stroke-width="3"/><path d="M5 35h78" stroke="#eeeede" stroke-dasharray="7 5"/></svg>';
  }
  return {defaults,limits,normalized,at,outline,placement,picture};
})();
if(typeof module !== 'undefined')module.exports=RoadPocket;
