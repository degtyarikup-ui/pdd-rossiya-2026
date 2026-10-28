// Vehicle-local +X is the driver's left. The same dimensions are used by DriverSignal in Godot.
const DriverSignal = (() => {
  const supports = type => ['car','truck','bus','van','tanker','special'].includes(type);
  const poses = [['none','Нет'],['raised','Рука вверх'],['extended','Рука влево']];
  function points(pose, width, height) {
    const shoulder=[width-.16,height*.69,.35],elbow=[width+.32,height*.7,.35];
    const wrist=pose==='extended'?[width+.8,height*.7,.35]:[width+.32,height*.7+.48,.35];
    return [shoulder,elbow,wrist];
  }
  function make(pose,width,height) {
    const root=new THREE.Group();root.name='driver_signal';
    if(!poses.some(([key])=>key===pose)||pose==='none')return root;
    const skin=new THREE.MeshLambertMaterial({color:0xe8b18d}),sleeve=new THREE.MeshLambertMaterial({color:0x42648a});
    const p=points(pose,width,height).map(v=>new THREE.Vector3(...v));
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
  return {supports,poses,points,make};
})();
if(typeof module!=='undefined')module.exports=DriverSignal;
