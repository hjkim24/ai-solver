importScripts('crop.js');

let port, current, previewNext = false, previewImage;
let status = {state: 'disabled', message: '메뉴 앱에 연결하세요.'};
const waiting = new Map();
function show(state, message) {
  status = {state, message};
  const text = ['locating', 'capturing', 'searching', 'solving'].includes(state) ? '…' : state === 'error' ? '!' : state === 'deferred' ? '?' : '';
  chrome.action.setBadgeText({text}).catch(() => {});
}
function send(message) { if (!port) throw new Error('메뉴 앱 연결을 확인하세요.'); port.postMessage({version: 1, ...message}); }
function stop(reason, state = 'deferred') {
  const old = current; current = null;
  if (!old) return;
  clearTimeout(old.timer);
  const waiter = waiting.get(old.id); waiting.delete(old.id); waiter?.reject(new Error(reason));
  try { send({type: 'cancel', request_id: old.id, reason}); } catch {}
  if (old.tabId) chrome.scripting.executeScript({target: {tabId: old.tabId}, func: id => globalThis.AISolverCapture?.end(id), args: [old.id]}).catch(() => {});
  show(state, reason);
}
function connect() {
  if (port) return port;
  const connected = chrome.runtime.connectNative('com.hjkim24.canvas_rag_solver');
  let greeted = false;
  port = connected;
  connected.onMessage.addListener(message => {
    if (port !== connected || message.version !== 1 || typeof message.message !== 'string') return;
    if (message.request_id == null) {
      if (!greeted && message.state === 'ready') {
        greeted = true;
        if (current) return;
      }
      if (current) stop('메뉴 앱의 설정 또는 사용 상태가 바뀌었습니다.', 'ready');
      show(message.state, message.message); return;
    }
    if (message.request_id !== current?.id) return;
    if (performance.now() >= current.expires) { stop('처리 제한 시간을 넘었습니다.', 'error'); return; }
    const waiter = waiting.get(message.request_id);
    if (waiter) {
      waiting.delete(message.request_id);
      if (message.state === 'locating') waiter.resolve();
      else waiter.reject(new Error(message.message));
    }
    show(message.state, message.message);
    if (['answered', 'deferred', 'error', 'disabled'].includes(message.state)) clearTimeout(current.timer);
  });
  connected.onDisconnect.addListener(() => {
    if (port !== connected) return;
    port = null; stop('메뉴 앱 연결이 종료되었습니다.', 'disabled');
    show('error', chrome.runtime.lastError ? 'Native host 등록과 확장 ID를 확인하세요.' : '메뉴 앱 연결이 종료되었습니다.');
  });
  return connected;
}
async function capture() {
  stop('새 문항을 선택했습니다.', 'ready');
  const id = crypto.randomUUID();
  const job = {id, expires: performance.now() + 45000}; current = job;
  job.timer = setTimeout(() => { if (current === job) stop('45초 처리 제한 시간을 넘었습니다.', 'error'); }, 45000);
  const valid = () => { if (current !== job || performance.now() >= job.expires) throw new Error('현재 요청이 취소되었습니다.'); };
  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true}); valid();
    const {allowedOrigin} = await chrome.storage.local.get('allowedOrigin'); valid();
    if (!tab?.url || !allowedOrigin || new URL(tab.url).origin !== allowedOrigin) throw new Error('허용 사이트에서 확장 메뉴의 사이트 등록을 먼저 선택하세요.');
    job.tabId = tab.id; job.windowId = tab.windowId; job.origin = allowedOrigin;
    await chrome.scripting.executeScript({target: {tabId: tab.id}, files: ['question-locator.js', 'capture-page.js']}); valid();
    const [{result: snapshot}] = await chrome.scripting.executeScript({target: {tabId: tab.id}, func: value => AISolverCapture.begin(value), args: [id]}); valid();
    // Snapshot precedes native startup; moving the cursor during startup never retargets the question.
    connect();
    const accepted = new Promise((resolve, reject) => {
      waiting.set(id, {resolve, reject});
      try { send({type: 'begin', request_id: id}); job.begun = true; }
      catch (error) { waiting.delete(id); reject(error); }
    });
    await accepted; valid();
    show('capturing', '선택 문항 캡처 중');
    const verify = async () => {
      const [active] = await chrome.tabs.query({active: true, currentWindow: true}); valid();
      if (active?.id !== tab.id || active.windowId !== tab.windowId) throw new Error('활성 탭이 바뀌었습니다.');
      await chrome.scripting.executeScript({target: {tabId: tab.id}, func: value => AISolverCapture.verify(value), args: [id]}); valid();
    };
    await verify();
    const full = await chrome.tabs.captureVisibleTab(tab.windowId, {format: 'png'}); valid();
    await verify();
    const png = await AISolverCrop.crop(full, snapshot); valid();
    await verify();
    if (previewNext) {
      previewNext = false; previewImage = `data:image/png;base64,${png}`;
      setTimeout(() => { previewImage = null; }, 120000);
      stop('캡처 미리보기 완료. API에는 전송하지 않았습니다.', 'ready');
      await chrome.tabs.create({url: chrome.runtime.getURL('preview.html')}); return;
    }
    send({type: 'solve', request_id: id, remaining_ms: Math.max(1, Math.floor(job.expires - performance.now())), question: snapshot.question, png_base64: png});
  } catch (error) {
    if (current !== job) return;
    const reason = error.message || '문항을 캡처할 수 없습니다.';
    if (job.tabId && !job.begun) {
      try { connect(); send({type: 'begin', request_id: id}); } catch {}
    }
    stop(reason, /화면|문항|보기|범위|본문|커서/u.test(reason) ? 'deferred' : 'error');
  }
}
chrome.commands.onCommand.addListener(command => { if (command === 'solve-question') return capture(); });
chrome.tabs.onActivated.addListener(info => { if (current && info.windowId === current.windowId && info.tabId !== current.tabId) stop('다른 탭으로 이동했습니다.', 'ready'); });
chrome.tabs.onUpdated.addListener((id, change) => { if (id === current?.tabId && (change.url || change.status === 'loading')) stop('문서가 바뀌었습니다.', 'ready'); });
chrome.tabs.onRemoved.addListener(id => { if (id === current?.tabId) stop('문서를 닫았습니다.', 'ready'); });
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id) return;
  if (message.type === 'invalidate') {
    if (current && sender.tab?.id === current.tabId && sender.frameId === 0 && sender.origin === current.origin && message.request_id === current.id) stop(message.reason, 'ready');
    return;
  }
  if (![chrome.runtime.getURL('popup.html'), chrome.runtime.getURL('preview.html')].includes(sender.url)) return;
  (async () => {
    if (message.type === 'connect') connect();
    if (message.type === 'preview-next') previewNext = true;
    if (message.type === 'get-preview') { const image = previewImage; previewImage = null; return {image}; }
    if (message.type === 'use-site') {
      const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
      const url = new URL(tab.url);
      if (url.protocol !== 'https:') throw new Error('HTTPS 학습 사이트에서 등록하세요.');
      stop('허용 사이트를 변경했습니다.', 'ready');
      await chrome.storage.local.set({allowedOrigin: url.origin});
      show('ready', `사이트 등록: ${url.origin}`);
    }
    const shortcut = (await chrome.commands.getAll()).find(command => command.name === 'solve-question')?.shortcut || '';
    return {...status, previewNext, shortcut, ...(await chrome.storage.local.get('allowedOrigin'))};
  })().then(reply, error => reply({state: 'error', message: error.message}));
  return true;
});
