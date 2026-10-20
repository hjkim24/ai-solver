const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {webcrypto} = require('node:crypto');

async function main() {
  let portMessage, command, runtimeMessage, tabChanged;
  const sent = [], captures = [], badges = [];
  let locationFails = false;
  let holdCapture, releaseCapture;
  let nativeCurrent, nativeReason;
  const snapshot = {question: {question_key: 'q-1'}, rect: {x: 1, y: 2, width: 20, height: 30}, viewport: {width: 100, height: 100}};
  const chrome = {
    action: {setBadgeText: async value => badges.push(value.text), setBadgeBackgroundColor: async () => {}},
    storage: {local: {get: async () => ({allowedOrigin: 'https://canvas.skku.edu'}), set: async () => {}}},
    scripting: {executeScript: async input => {
      if (input.files) return [];
      if (input.func.toString().includes('.begin(') && locationFails) throw new Error('범위 실패');
      return [{result: snapshot}];
    }},
    tabs: {
      query: async () => [{id: 1, windowId: 7, url: 'https://canvas.skku.edu/courses/1/quizzes/1/take'}],
      captureVisibleTab: async () => { captures.push(true); if (holdCapture) await new Promise(resolve => { releaseCapture = resolve; }); return 'data:image/png;base64,full-tab'; },
      onActivated: {addListener: callback => { tabChanged = callback; }}, onUpdated: {addListener() {}}, onRemoved: {addListener() {}}, create: async () => ({})
    },
    commands: {onCommand: {addListener: callback => { command = callback; }}, getAll: async () => [{name: 'solve-question', shortcut: '⌘⇧Y'}]},
    runtime: {id: 'test-extension', getURL: value => value,
      onMessage: {addListener: callback => { runtimeMessage = callback; }},
      connectNative: () => ({onMessage: {addListener: callback => { portMessage = callback; }}, onDisconnect: {addListener() {}},
        postMessage(message) {
          sent.push(message);
          if (message.type === 'cancel' && message.request_id === nativeCurrent) nativeReason = message.reason;
          if (message.type === 'begin') { nativeCurrent = message.request_id; queueMicrotask(() => {
          if (sent.filter(x => x.type === 'begin').length === 1) portMessage({version: 1, request_id: null, state: 'ready', message: '연결 준비'});
          portMessage({version: 1, request_id: message.request_id, state: 'locating', message: '수락'});
        }); } }})
    }
  };
  const context = vm.createContext({chrome, crypto: webcrypto, performance, URL, setTimeout, clearTimeout, queueMicrotask,
    importScripts() {}, AISolverCrop: {crop: async () => 'cropped-only'}});
  vm.runInContext(fs.readFileSync('extension/background.js', 'utf8'), context);
  await command('solve-question');
  assert.equal(sent.filter(x => x.type === 'solve').length, 1);
  assert.equal(sent.find(x => x.type === 'solve').png_base64, 'cropped-only');
  assert.ok(sent.find(x => x.type === 'solve').remaining_ms <= 45000);
  const oldID = sent.find(x => x.type === 'begin').request_id;
  locationFails = true;
  await command('solve-question');
  assert.equal(sent.filter(x => x.type === 'solve').length, 1, 'failed location sent another image');
  assert.ok(sent.some(x => x.type === 'cancel' && x.request_id === oldID), 'old answer not invalidated');
  assert.equal(sent.at(-1).reason, '범위 실패', 'native menu did not receive the current failure reason');
  assert.equal(nativeReason, '범위 실패', 'native host ignored cancellation for an unregistered failed selection');
  locationFails = false; holdCapture = true;
  const pending = command('solve-question');
  while (!releaseCapture) await new Promise(resolve => setTimeout(resolve, 1));
  tabChanged({tabId: 2, windowId: 7});
  releaseCapture(); await pending;
  assert.equal(sent.filter(x => x.type === 'solve').length, 1, 'context changed but crop was sent');
  portMessage({version: 1, request_id: oldID, state: 'answered', message: 'stale'});
  assert.notEqual(badges.at(-1), '1', 'stale response changed UI');
  assert.equal(captures.length, 2);
  assert.ok(runtimeMessage);
  const state = await new Promise(resolve => {
    const handled = runtimeMessage({type: 'status'}, {id: 'test-extension', url: 'popup.html', tab: {id: 22}}, resolve);
    if (handled !== true) resolve({});
  });
  assert.equal(state.shortcut, '⌘⇧Y', 'actual registered shortcut not shown');
  console.log('Extension workflow self-checks passed: 5');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
