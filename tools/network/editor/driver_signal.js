// Vehicle-local +X is the driver's left. The same dimensions are used by DriverSignal in Godot.
const DriverSignal = (() => {
  const supports = type => ['car','truck','bus','van','tanker','special'].includes(type);
  const poses = [['none','Нет'],['raised','Рука вверх'],['extended','Рука влево']];
  const glass=c=>c[0]>=.125&&c[0]<=.265&&c[1]>=.205&&c[1]<=.365&&c[2]>=.275&&c[2]<=.455;
  // Shared vehicle glazing has a blue vertex gradient. Find connected side panes,
  // then use the front pane (+Z), excluding the windscreen, pillars and mirrors.
  function windowAnchor(root) {
    const faces=[];root.updateMatrixWorld(true);const inverse=root.matrixWorld.clone().invert();
    root.traverse(node=>{
      if(!node.isMesh)return;
      const g=node.geometry,p=g.getAttribute('position'),c=g.getAttribute('color');if(!p||!c)return;
      const transform=inverse.clone().multiply(node.matrixWorld),indices=g.index;
      for(let i=0;i<(indices?indices.count:p.count);i+=3) {
        const ids=[0,1,2].map(j=>indices?indices.getX(i+j):i+j);
        if(!ids.every(j=>glass([c.getX(j),c.getY(j),c.getZ(j)])))continue;
        const v=ids.map(j=>new THREE.Vector3(p.getX(j),p.getY(j),p.getZ(j)).applyMatrix4(transform));
        const normal=v[1].clone().sub(v[0]).cross(v[2].clone().sub(v[0])).normalize();
        if(v.every(q=>q.x>0)&&Math.abs(normal.x)>.7&&Math.abs(normal.z)<.35)faces.push(v);
      }
    });
    if(!faces.length)return null;
    faces.sort((a,b)=>b.reduce((s,p)=>s+p.z,0)-a.reduce((s,p)=>s+p.z,0));
    const pane=faces.shift();let joined=true;
    while(joined){joined=false;for(let i=faces.length-1;i>=0;i--)if(faces[i].some(p=>pane.some(q=>p.distanceToSquared(q)<1e-8))){pane.push(...faces.splice(i,1)[0]);joined=true;}}
    const unique=pane.filter((p,i)=>pane.findIndex(q=>p.distanceToSquared(q)<1e-8)===i).sort((a,b)=>a.y-b.y);
    if(unique.length!==4)return null;
    const low=unique.slice(0,2).sort((a,b)=>a.z-b.z),high=unique.slice(2).sort((a,b)=>a.z-b.z);
    return low[0].clone().lerp(low[1],.35).lerp(high[0].clone().lerp(high[1],.35),.45).toArray();
  }
  function points(pose, width, height, window=null) {
    const [x,y,z]=window||[width-.28,height*.78,.12];
    const shoulder=[x-.14,y,z],elbow=[x+.38,y-.035,z];
    const wrist=pose==='extended'?[x+.86,y-.035,z]:[x+.38,y+.445,z];
    return [shoulder,elbow,wrist];
  }
  function make(pose,width,height,window=null) {
    const root=new THREE.Group();root.name='driver_signal';
    if(!poses.some(([key])=>key===pose)||pose==='none')return root;
    const skin=new THREE.MeshLambertMaterial({color:0xe8b18d}),sleeve=new THREE.MeshLambertMaterial({color:0x42648a});
    const p=points(pose,width,height,window).map(v=>new THREE.Vector3(...v));
    const segment=(a,b,r,material)=>{
      const d=b.clone().sub(a),mesh=new THREE.Mesh(new THREE.CylinderGeometry(r,r,d.length(),10),material);
      mesh.position.copy(a).add(b).multiplyScalar(.5);mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),d.normalize());root.add(mesh);
    };
    segment(p[0],p[0].clone().lerp(p[1],.42),.075,sleeve);segment(p[0].clone().lerp(p[1],.4),p[1],.06,skin);segment(p[1],p[2],.05,skin);
    const direction=p[2].clone().sub(p[1]).normalize(),across=new THREE.Vector3(0,0,1),tip=p[2].clone().addScaledVector(direction,.13);
    segment(p[2],tip,.062,skin);
    for(let i=0;i<4;i++) {const start=tip.clone().addScaledVector(across,(i-1.5)*.029);segment(start,start.clone().addScaledVector(direction,.11-Math.abs(i-1.5)*.017),.014,skin);}
    const thumb=p[2].clone().addScaledVector(direction,.05);segment(thumb,thumb.clone().addScaledVector(across,.1).addScaledVector(direction,.04),.022,skin);
    return root;
  }
  return {supports,poses,windowAnchor,points,make};
})();
if(typeof module!=='undefined')module.exports=DriverSignal;
