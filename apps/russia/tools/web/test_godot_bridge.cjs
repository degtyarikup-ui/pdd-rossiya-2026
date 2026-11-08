const test = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {runInNewContext} = require('node:vm');
const source = readFileSync(new URL('../../game_godot/web_bridge.js', 'file://' + __filename), 'utf8');
function fixture() {
  const listeners = new Set(), posts = [];
  const window = { location: new URL('https://pdd-drive.app/app/godot/index.html?lang=ru'),
    parent: { postMessage: (...args) => posts.push(args) },
    addEventListener: (name, fn) => listeners.add(fn), removeEventListener: (name, fn) => listeners.delete(fn) };
  runInNewContext(source, {window, URL, navigator: {}});
  return {window, posts, bridge:window.PddWebBridge, message:event=>listeners.forEach(fn=>fn(event)), listeners};
}
test('Godot host operations pass strings as data and resolve shared assets without eval', () => {
  const f = fixture(), text = '\"); throw Error("injected"); //';
  f.bridge.post('send', text);
  assert.deepEqual(JSON.parse(f.posts[0][0]), {bridge:'pdd-godot',kind:'send',json:text});
  assert.equal(f.posts[0][1], 'https://pdd-drive.app');
  assert.equal(f.bridge.resolve('../assets/assets/audio/'), 'https://pdd-drive.app/app/assets/assets/audio/');
  assert.equal(f.bridge.resolve('.'), 'https://pdd-drive.app/app/godot/');
});
test('report replies require both the parent window and exact origin, and cleanup removes the listener', () => {
  const f = fixture(), data = JSON.stringify({bridge:'pdd-godot',kind:'question_report_result',request_id:'one',success:true});
  f.bridge.beginReport(); f.bridge.beginReport(); assert.equal(f.listeners.size,1);
  for(const event of [{source:{},origin:'https://pdd-drive.app',data},{source:f.window.parent,origin:'https://evil.test',data}]) {
    f.message(event); assert.equal(f.bridge.reportReply(),'');
  }
  f.message({source:f.window.parent,origin:'https://pdd-drive.app',data});
  assert.equal(f.bridge.reportReply(),data);
  f.bridge.endReport(); assert.equal(f.listeners.size,0); assert.equal(f.bridge.reportReply(),'');
});
