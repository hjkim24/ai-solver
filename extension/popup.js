async function request(type) {
  try {
    const response = await chrome.runtime.sendMessage({type});
    document.querySelector('#status').textContent = response.message;
    document.querySelector('#site').textContent = response.allowedOrigin || '아직 등록한 사이트가 없습니다.';
    document.querySelector('#shortcut').textContent = response.shortcut ? `등록된 단축키: ${response.shortcut}` : '단축키가 비어 있습니다. 확장 프로그램의 단축키 설정에서 등록하세요.';
    document.querySelector('#preview').textContent = response.previewNext ? '미리보기 대기 중: 문항 위에서 ⌘⇧Y' : '다음 단축키로 캡처만 미리보기';
  } catch { document.querySelector('#status').textContent = '확장 프로그램을 다시 로드하세요.'; }
}
for (const [id, type] of [['connect', 'connect'], ['site-button', 'use-site'], ['preview', 'preview-next']]) document.getElementById(id).addEventListener('click', () => request(type));
request('status');
