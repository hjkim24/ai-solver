(function () {
  if (globalThis.AISolverCapture) return;
  let selected;
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  function end(id) {
    if (!selected || selected.id !== id) return;
    for (const [name, callback] of selected.events) window.removeEventListener(name, callback, true);
    selected.observer.disconnect(); clearInterval(selected.interval); selected = null;
  }
  function verify(id) {
    if (!selected || selected.id !== id) throw new Error('선택한 문서가 바뀌었습니다.');
    const now = AISolverLocator.locate(selected.root);
    if (!same(now, selected.snapshot)) throw new Error('문항 내용이나 화면 위치가 바뀌었습니다. 다시 선택하세요.');
    return now;
  }
  function begin(id, hovered = [...document.querySelectorAll(':hover')].at(-1)) {
    if (selected) end(selected.id);
    const snapshot = AISolverLocator.locate(hovered);
    const root = hovered.closest('.display_question.question');
    const invalidate = reason => {
      if (selected?.id !== id) return;
      end(id);
      chrome.runtime.sendMessage({type: 'invalidate', request_id: id, reason}).catch(() => {});
    };
    const events = ['scroll', 'resize', 'pagehide'].map(name => [name, () => invalidate('화면이 바뀌었습니다. 문항을 다시 선택하세요.')]);
    const check = () => { try { verify(id); } catch (error) { invalidate(error.message); } };
    const observer = new MutationObserver(check);
    selected = {id, root, snapshot, events, observer, interval: setInterval(check, 200)};
    for (const [name, callback] of events) window.addEventListener(name, callback, true);
    observer.observe(root, {subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['class', 'style', 'src', 'hidden']});
    return snapshot;
  }
  globalThis.AISolverCapture = {begin, verify, end};
})();
