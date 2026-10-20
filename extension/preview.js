chrome.runtime.sendMessage({type: 'get-preview'}).then(({image}) => {
  if (image) document.querySelector('#image').src = image;
  else document.querySelector('#status').textContent = '미리보기가 만료되었습니다. 확장 메뉴에서 다시 선택하세요.';
});
