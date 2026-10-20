const {spawn} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {pathToFileURL} = require('node:url');

async function main() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-solver-browser-check-'));
  const log = fs.openSync('build/browser-check.log', 'w');
  const browser = spawn(process.env.TEST_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ['--headless', '--disable-gpu', '--disable-accelerated-2d-canvas', '--use-mock-keychain', '--disable-background-networking', '--disable-component-update', '--no-first-run', '--no-default-browser-check', `--user-data-dir=${profile}`, '--window-size=1200,2200', '--remote-debugging-pipe'],
    {stdio: ['ignore', 'ignore', log, 'pipe', 'pipe']});
  const pending = new Map(); let sequence = 0, buffer = '', loaded;
  const fail = error => { for (const entry of pending.values()) entry.reject(error); pending.clear(); };
  browser.on('error', fail); browser.on('exit', () => fail(new Error('Test browser exited')));
  browser.stdio[4].on('data', data => {
    buffer += data.toString();
    let end;
    while ((end = buffer.indexOf('\0')) >= 0) {
      const message = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
      if (message.method === 'Page.loadEventFired') loaded?.();
      const entry = pending.get(message.id);
      if (entry) { pending.delete(message.id); message.error ? entry.reject(new Error(message.error.message)) : entry.resolve(message.result); }
    }
  });
  function call(method, params = {}, sessionId) {
    return new Promise((resolve, reject) => {
      const id = ++sequence; pending.set(id, {resolve, reject});
      browser.stdio[3].write(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}) + '\0');
    });
  }
  const watchdog = setTimeout(() => { fail(new Error('Browser check timeout')); browser.kill(); }, 30000);
  try {
    const {targetId} = await call('Target.createTarget', {url: 'about:blank'});
    const {sessionId} = await call('Target.attachToTarget', {targetId, flatten: true});
    await call('Page.enable', {}, sessionId);
    const load = new Promise(resolve => { loaded = resolve; });
    await call('Page.navigate', {url: pathToFileURL(path.resolve('extension/tests/selfcheck.html')).href}, sessionId);
    await load;
    const result = await call('Runtime.evaluate', {expression: `new Promise(resolve => {
      const timer = setInterval(() => {
        const result = document.querySelector('#result')?.textContent;
        if (result && result !== 'RUNNING') { clearInterval(timer); resolve(JSON.parse(result)); }
      }, 30);
    })`, awaitPromise: true, returnByValue: true}, sessionId);
    if (result.exceptionDetails || !result.result.value) throw new Error('Browser fixture failed before reporting');
    const report = result.result.value;
    fs.writeFileSync('build/browser-check.json', JSON.stringify(report, null, 2));
    console.log(`Browser DOM/crop self-checks passed: ${report.passed}; failed: ${report.failed.length}`);
    if (report.failed.length) throw new Error(JSON.stringify(report.failed));
  } finally {
    clearTimeout(watchdog);
    browser.kill(); await new Promise(resolve => browser.once('close', resolve));
    fs.closeSync(log); fs.rmSync(profile, {recursive: true, force: true});
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
