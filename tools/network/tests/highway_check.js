const assert = require('node:assert/strict');
const fs = require('node:fs');
const L = require('../editor/layout.js');
const clone = s => JSON.parse(JSON.stringify(s));
const fixtures=[];
function scene(template='highway',lane=0,maneuver='straight'){
 const s={schema:1,id:'highway-test',crop:90,layout:L.template(template,90),question:{maneuver,correct:0,text:{ru:{options:['Да']}}},compliance:{status:'ok'},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[]};
 for(const st of s.layout.streets)st.kind='highway';
 s.layout.player={...(s.layout.player||{}),lane};L.apply(s);return s;
}
assert.equal(L.widthOf({kind:'highway'}),24);
assert.deepEqual(L.laneOffsets({kind:'highway'}),[3.25,6.75,10.25]);
for(const template of ['highway','cross','ring'])for(const lane of [0,1,2])for(const maneuver of template==='highway'?['straight']:['straight','left','right','uturn']){
 const s=scene(template,lane,maneuver),st=L.playerPlan(s).st;
 assert.equal(L.playerPlan(s).laneIndex,lane);
 assert.equal(L.medianOf(st),3);
 const before=JSON.stringify(s);L.apply(s);assert.equal(JSON.stringify(s),before,'generated data remains stable');
 const reloaded=clone(s);L.apply(reloaded);assert.deepEqual(reloaded,s,'save/load remains stable');
 fixtures.push(s);
}
const straight=scene();const st=straight.layout.streets[0];
assert.deepEqual(L.streetProfile(straight.layout,st,90,90),{width:24,median:3,blend:1});
for(const d of [0,24,34,146,156,180])assert.deepEqual(L.streetProfile(straight.layout,st,d,90),{width:14,median:0,blend:0},'four-lane contact plateau');
assert.equal(straight.markings.filter(m=>m.type==='dashed').length,4,'two boundaries per carriageway');
const early=scene('highway',2);early.layout.player.questionAt=65;L.apply(early);fixtures.push(early);
// Gentle curved source, three lanes and the same four-lane boundary.
const curved=scene();curved.layout.streets[0].bend=[18,0];L.apply(curved);fixtures.push(curved);
// An internal highway-to-avenue joint narrows to its neighbour instead of forming a width step.
const joint=scene();joint.layout.nodes.push({id:'join',x:0,z:35});
joint.layout.streets[0].b='join';joint.layout.streets.push({id:'avenue-tail',a:'join',b:'n',kind:'avenue'});
L.apply(joint);assert.equal(L.streetProfile(joint.layout,joint.layout.streets[0],125,90).width,14);fixtures.push(joint);
const manual=scene();manual.layout.streets[0].manualMarks=true;L.apply(manual);
assert.equal(manual.markings.filter(m=>m.type==='solid'||m.type==='dashed').length,0,'manual paint suppresses generated lane dividers');
const ordinary=scene();ordinary.layout.streets[0].kind='avenue';L.apply(ordinary);ordinary.reference=true;fixtures.push(ordinary);
if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(fixtures));
console.log(`Highway: ${fixtures.length} poses/turns/curves/joints, three lanes, taper, persistence/manual marks PASS`);
