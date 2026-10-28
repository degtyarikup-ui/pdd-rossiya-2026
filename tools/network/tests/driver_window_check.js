// Read the actual vehicle GLBs: the anchor must be inside the front side pane.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const THREE=require('../editor/vendor/three.min.js');
const context=vm.createContext({THREE,TextDecoder,console,setTimeout,clearTimeout,URL});
vm.runInContext(fs.readFileSync(require.resolve('../editor/vendor/GLTFLoader.js'),'utf8'),context);
vm.runInContext(fs.readFileSync(require.resolve('../editor/driver_signal.js'),'utf8'),context);
const Driver=vm.runInContext('DriverSignal',context),root=path.resolve(__dirname,'../../..');
async function main(){
  const fixtures=[];
  for(const asset of ['vehicles/hatch','vehicles/sedan','vehicles/coupe','vehicles/wagon','vehicles/suv','vehicles/pickup','road/truck','road/tanker','road/bus','road/van']){
    const bytes=fs.readFileSync(path.join(root,'game_godot/models',asset+'.glb'));
    const gltf=await new Promise((resolve,reject)=>new THREE.GLTFLoader().parse(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),'',resolve,reject));
    const anchor=Driver.windowAnchor(gltf.scene);assert(anchor,asset+': a real driver window was found');
    const points=Driver.points('raised',1,1.5,anchor);
    assert(points[0][0]<anchor[0]&&points[1][0]>anchor[0],asset+': shoulder starts inside the window');
    assert(points.every(p=>Math.abs(p[2]-anchor[2])<1e-6),asset+': arm stays aligned with the window');
    if(asset==='vehicles/sedan'){
      assert(anchor[1]>.98&&anchor[1]<1.12,'Arm emerges through the glass above the door sill');
      assert(anchor[0]>.72&&anchor[0]<.83&&anchor[2]<.35,'Driver pane, clear of the mirror at z=.909');
    }
    fixtures.push({asset,anchor});
  }
  if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(fixtures));
  console.log('Driver window anchor: 6 cars and 4 cab models, real glazing and interior shoulder PASS');
}
main().catch(error=>{console.error(error);process.exit(1)});
