"""Build disposable asymmetric/compact roads for native seam and chassis checks."""
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build

script = r"""
const L=require('./tools/network/editor/layout.js');
const scenes=[];
function make(name,crop,counts,median=0,curve=false,reverse=false,width=3.5){
  const s={schema:1,id:name,crop,sceneFormat:crop===45?'compact':'standard',
    layout:L.template('straight',crop),roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],
    question:{maneuver:'straight',correct:0,text:{ru:{options:['Да']}}},compliance:{status:'ok'}};
  const st=s.layout.streets[0];
  st.edge=true;st.median=median;st.centre='solid';
  if(counts) L.setLaneConfig(st,{a:{left:counts[0],right:counts[1]},b:{left:counts[2],right:counts[3]},width,taper:40});
  if(curve) st.bend=[30,0];
  if(reverse){[st.a,st.b]=[st.b,st.a];s.layout.player.toward=st.b;}
  L.apply(s);
  s.expectedPorts={};
  for(const end of ['a','b']){
    const cfg=counts?L.laneConfig(st)[end]:{left:1,right:1};
    const positive=end==='a'?cfg.right:cfg.left,negative=end==='a'?cfg.left:cfg.right;
    s.expectedPorts[st[end]]={positive,negative,width:counts?(positive+negative)*width+median:8.4,median,
      offset:counts?(negative-positive)*width/2:0,custom:!!counts};
  }
  scenes.push(s);
  return s;
}
make('compact-legacy',45,null);
make('legacy-straight',90,null);
for(const crop of [45,90]) for(const median of [0,3]){
  make(`asymmetric-${crop}-${median}`,crop,[2,3,2,3],median);
  make(`taper-${crop}-${median}`,crop,[3,3,2,2],median);
  make(`swap-${crop}-${median}`,crop,[2,3,3,2],median);
}
make('curved-asymmetric',90,[2,3,2,3],3,true);
make('curved-reverse',90,[2,3,2,3],3,true,true);
make('many-lanes',90,[1,6,1,2],0);
make('opposite-asymmetric',90,[3,2,3,2],3);
make('custom-two-wide',90,[1,1,1,1],0,false,false,4);
const split=make('split-taper',90,[3,3,2,2],3);
L.splitStreet(split.layout,'s1',118,split.crop);L.apply(split);
const short=make('short-border-taper',45,[3,3,2,2]);
short.layout.nodes[0].x=45;short.layout.nodes[0].z=0;
short.layout.nodes[1].x=45;short.layout.nodes[1].z=25;
L.apply(short);short.profileOnly=true;
for(const s of scenes){
  s.profileSamples=[];
  for(const st of s.layout.streets.filter(st=>st.lanes)){
    const total=L.polyLen(L.centreline(s.layout,st));
    for(const distance of [0,Math.min(24,total-12),total/2,Math.max(0,total-24),total]){
      s.profileSamples.push({street:st.id,total,distance,
        borderA:L.nodeKind(s.layout,L.nodeOf(s.layout,st.a),s.crop)==='border',
        borderB:L.nodeKind(s.layout,L.nodeOf(s.layout,st.b),s.crop)==='border',
        expected:L.streetProfile(s.layout,st,distance,s.crop)});
    }
  }
}
process.stdout.write(JSON.stringify(scenes));
"""
scenes = json.loads(subprocess.check_output(["node", "-e", script], cwd=build.ROOT))
for scene in scenes:
    scene["build"] = build.build(scene)
    assert scene["build"]["carriageway"], scene["id"]
path = build.ROOT / "scratch/lane-profile-fixtures.json"
path.parent.mkdir(exist_ok=True)
path.write_text(json.dumps(scenes), encoding="utf-8")
print(f"Lane profiles: {len(scenes)} asymmetric, reversed, tapered and compact native fixtures built at {path}")
