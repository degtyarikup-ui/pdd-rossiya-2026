// Shared walker UV2 tags identify arms without a skeleton. Pose only the chosen
// arm; its walk tag is cleared so the gesture stays fixed while the legs move.
const ActorAppearance = (() => {
  const poses=[['stand','Обычная'],['hail','Останавливает машину'],['forward','Рука вперёд'],['raised','Рука вверх']];
  const isArm=amp=>Math.abs(amp)>.1&&Math.abs(amp)<.21;
  function vertex(point,normal,amp,pivotY,pivotX,pose,arm='right') {
    const side=amp>0?-1:1,wanted=arm==='left'?1:-1;
    if(pose==='stand'||!isArm(amp)||side!==wanted)return {point:[...point],normal:[...normal],amp};
    const angle=pose==='forward'?-Math.PI/2:side*(pose==='raised'?Math.PI:Math.PI/2);
    const c=Math.cos(angle),s=Math.sin(angle);
    const rotate=v=>pose==='forward'?[v[0],v[1]*c-v[2]*s,v[1]*s+v[2]*c]:[v[0]*c-v[1]*s,v[0]*s+v[1]*c,v[2]];
    const p=rotate([point[0]-pivotX,point[1]-pivotY,point[2]]);
    return {point:[p[0]+pivotX,p[1]+pivotY,p[2]],normal:rotate(normal),amp:0};
  }
  function pedestrian(root,pose,arm) {
    root.traverse(mesh=>{
      if(!mesh.isMesh)return;
      const geometry=mesh.geometry.clone(),p=geometry.getAttribute('position'),n=geometry.getAttribute('normal'),uv=geometry.getAttribute('uv2');
      if(!uv)return;
      const extents={left:[Infinity,-Infinity],right:[Infinity,-Infinity]};
      for(let i=0;i<p.count;i++)if(isArm(uv.getX(i))) {
        const box=extents[uv.getX(i)>0?'right':'left'];box[0]=Math.min(box[0],p.getX(i));box[1]=Math.max(box[1],p.getX(i));
      }
      for(let i=0;i<p.count;i++)if(isArm(uv.getX(i))) {
        const box=extents[uv.getX(i)>0?'right':'left'];
        const result=vertex([p.getX(i),p.getY(i),p.getZ(i)],[n.getX(i),n.getY(i),n.getZ(i)],uv.getX(i),uv.getY(i),(box[0]+box[1])/2,pose,arm);
        p.setXYZ(i,...result.point);n.setXYZ(i,...result.normal);uv.setX(i,result.amp);
      }
      geometry.computeBoundingBox();geometry.computeBoundingSphere();mesh.geometry=geometry;mesh.userData.own=true;
    });
  }
  function paint(root,colour) {
    const tint=new THREE.Color(colour);
    root.traverse(mesh=>{
      if(!mesh.isMesh)return;
      const geometry=mesh.userData.own?mesh.geometry:mesh.geometry.clone(),colors=geometry.getAttribute('color');
      if(colors&&colors.itemSize===4) {
        const rgb=[];
        for(let i=0;i<colors.count;i++) {
          const paint=colors.getW(i)>.5;
          rgb.push(colors.getX(i)*(paint?tint.r:1),colors.getY(i)*(paint?tint.g:1),colors.getZ(i)*(paint?tint.b:1));
        }
        // Alpha is a paint mask in these GLBs, never transparency. Strip it
        // after tinting so dark parts remain visible on transparent thumbnails.
        geometry.setAttribute('color',new THREE.Float32BufferAttribute(rgb,3));
      }
      mesh.geometry=geometry;mesh.userData.own=true;
      mesh.material=new THREE.MeshLambertMaterial({vertexColors:true});
    });
  }
  const sidecar=(actor,catalog)=>typeof actor.sidecar==='boolean'?actor.sidecar:!!(catalog?.actorAppearances?.[actor.asset]?.sidecar ?? catalog?.actorTypes?.motorcycle?.sidecar);
  const bounds=(hasSidecar,scale=[1,1,1])=>({halfWidth:(hasSidecar ? .957 : .34)*Math.abs(scale[0]),halfLength:1.075*Math.abs(scale[2])});
  return {poses,isArm,vertex,pedestrian,paint,sidecar,bounds};
})();
if(typeof module!=='undefined')module.exports=ActorAppearance;
