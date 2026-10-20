(function () {
  // shortcut: inspected Canvas Classic DOM only; add a verified adapter before supporting other layouts.
  const rootSelector = '.display_question.question';
  const clean = text => String(text ?? '').replace(/\s+/gu, ' ').trim();
  function fail(message) { throw new Error(message); }
  function visibleRect(element, viewport) {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    if (element.hidden || style.display === 'none' || style.visibility !== 'visible' || Number(style.opacity) === 0 ||
        rect.width <= 0 || rect.height <= 0 || rect.left < 0 || rect.top < 0 || rect.right > viewport.width || rect.bottom > viewport.height) {
      fail('문제와 보기 전체가 화면 안에 보이도록 조정하세요.');
    }
    for (let ancestor = element.parentElement; ancestor && ancestor !== document.documentElement; ancestor = ancestor.parentElement) {
      const clip = ancestor.getBoundingClientRect(), css = getComputedStyle(ancestor);
      if ((/(auto|scroll|hidden|clip)/u.test(css.overflowX) && (rect.left < clip.left || rect.right > clip.right)) ||
          (/(auto|scroll|hidden|clip)/u.test(css.overflowY) && (rect.top < clip.top || rect.bottom > clip.bottom))) {
        fail('스크롤 영역에서 문항 일부가 잘려 있습니다.');
      }
    }
    return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
  }
  function locate(hovered, viewport = {width: innerWidth, height: innerHeight}) {
    const root = hovered?.closest?.(rootSelector);
    if (!root || !root.isConnected) fail('본문의 문제 번호나 문항 안에 커서를 두세요.');
    if ([...document.querySelectorAll('.text_only_question, .stimulus_question, [data-stimulus-id]')].some(element => !root.contains(element) && element.getBoundingClientRect().height > 0)) fail('컨테이너 밖 공통 지문이 있는 화면은 아직 지원하지 않습니다.');
    if (!root.classList.contains('multiple_choice_question') || root.querySelector(rootSelector)) fail('단일 정답 문항 하나의 범위를 확인할 수 없습니다.');
    if (root.querySelector('canvas, video, iframe, svg animate, svg animateTransform, svg set')) fail('내용 변경을 추적할 수 없는 동적 그림은 아직 지원하지 않습니다.');
    const stem = root.querySelector('.question_text');
    const rows = [...root.querySelectorAll('.answers .answer')];
    if (!stem || !clean(stem.innerText) || rows.length < 2 || rows.length > 10) fail('본문과 보기 2~10개를 확인할 수 없습니다.');
    const rect = visibleRect(root, viewport);
    const overlays = [...document.querySelectorAll('header, [role="dialog"], [style*="position"]')].filter(element => {
      const css = getComputedStyle(element);
      return !root.contains(element) && ['fixed', 'sticky'].includes(css.position) && css.visibility === 'visible' && css.display !== 'none' && Number(css.opacity) > 0;
    }).map(element => element.getBoundingClientRect());
    const required = [stem, ...rows, ...root.querySelectorAll('img, svg, canvas')];
    for (const element of required) {
      if (element.tagName === 'IMG' && (!element.complete || !element.naturalWidth)) fail('문항 그림이 모두 로드된 뒤 다시 선택하세요.');
      const essential = visibleRect(element, viewport);
      if (essential.x < rect.x || essential.y < rect.y || essential.x + essential.width > rect.x + rect.width || essential.y + essential.height > rect.y + rect.height) fail('문항의 필수 내용이 캡처 범위 밖으로 넘칩니다.');
      const r = element.getBoundingClientRect();
      if (overlays.some(o => o.left < r.right && o.right > r.left && o.top < r.bottom && o.bottom > r.top)) fail('고정된 화면 요소가 문항을 가리고 있습니다.');
      for (const [x, y] of [[0.5, 0.5], [0.01, 0.01], [0.99, 0.01], [0.01, 0.99], [0.99, 0.99]]) {
        const top = document.elementFromPoint(r.left + r.width * x, r.top + r.height * y);
        if (!top || !root.contains(top)) fail('다른 화면 요소가 문항을 가리고 있습니다.');
      }
    }
    const options = rows.map((row, i) => {
      if (row.closest(rootSelector) !== root || row.querySelector('input[type="checkbox"]') || !row.querySelector('input[type="radio"], [role="radio"]')) fail('지원하는 단일 정답 보기 형식이 아닙니다.');
      const text = clean(row.querySelector('.answer_text, .answer_label')?.innerText);
      if (!text) fail('보기 내용을 읽을 수 없습니다.');
      const label = clean(row.querySelector('[data-option-label]')?.innerText) || String(i + 1);
      return {index: i + 1, label, text};
    });
    const sorted = rows.map((row, i) => ({i, r: row.getBoundingClientRect()})).sort((a, b) => a.r.top - b.r.top || a.r.left - b.r.left);
    if (sorted.some((row, i) => row.i !== i)) fail('보기의 화면 순서와 문서 순서가 다릅니다.');
    const roots = [...document.querySelectorAll(rootSelector)];
    const name = clean(root.querySelector('.question_name')?.innerText);
    const question = {
      page_session_id: globalThis.__aiSolverPageSession ??= crypto.randomUUID(),
      question_key: root.id || `question-${roots.indexOf(root)}`,
      question_number: name.match(/\d+/u)?.[0] ?? null,
      stem_text: clean(stem.innerText), options
    };
    if (new TextEncoder().encode(question.stem_text + options.map(o => o.text).join('')).length > 65536) fail('문항 텍스트가 허용 크기를 넘었습니다.');
    const graphics = [...root.querySelectorAll('img, svg')].map(element => [element.outerHTML, element.currentSrc ?? '']);
    return {question, rect, viewport: {...viewport}, scroll: {x: scrollX, y: scrollY}, graphics};
  }
  globalThis.AISolverLocator = {locate};
})();
