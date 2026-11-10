const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

test('voice replies remain independent of reports and reject other frames', () => {
  const listeners = new Set();
  const parent = {};
  const window = {
    parent, location: {origin: 'https://example.test', href: 'https://example.test/app/godot/'},
    addEventListener: (_, listener) => listeners.add(listener),
    removeEventListener: (_, listener) => listeners.delete(listener),
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../game_godot/web_bridge.js'), 'utf8'), {window, URL});
  const bridge = window.PddWebBridge;
  const send = (kind, id, source = parent, origin = window.location.origin) => {
    const data = JSON.stringify({bridge: 'pdd-godot', kind, request_id: id, data: {ok: true}});
    for (const listener of listeners) listener({source, origin, data});
  };
  bridge.beginReport();
  send('question_report_result', 'report-1');
  send('voice_audio_result', 'voice-1');
  assert.equal(JSON.parse(bridge.reportReply()).request_id, 'report-1');
  assert.equal(JSON.parse(bridge.voiceReply()).request_id, 'voice-1');
  bridge.endReport();
  send('voice_audio_result', 'voice-2');
  assert.equal(JSON.parse(bridge.voiceReply()).request_id, 'voice-2');
  send('voice_audio_result', 'foreign-frame', {});
  send('voice_audio_result', 'foreign-site', parent, 'https://other.test');
  assert.equal(JSON.parse(bridge.voiceReply()).request_id, 'voice-2');
});
