(function () {
  function pixelRect(rect, viewport, image) {
    const values = [rect.x, rect.y, rect.width, rect.height, viewport.width, viewport.height, image.width, image.height];
    if (!values.every(Number.isFinite) || rect.x < 0 || rect.y < 0 || values.slice(2).some(v => v <= 0) ||
        rect.x + rect.width > viewport.width || rect.y + rect.height > viewport.height) throw new Error('유효하지 않은 캡처 영역입니다.');
    const x = Math.floor(rect.x * image.width / viewport.width), y = Math.floor(rect.y * image.height / viewport.height);
    const right = Math.ceil((rect.x + rect.width) * image.width / viewport.width), bottom = Math.ceil((rect.y + rect.height) * image.height / viewport.height);
    return {x, y, width: right - x, height: bottom - y};
  }
  async function crop(dataURL, snapshot) {
    const bitmap = await createImageBitmap(await (await fetch(dataURL)).blob());
    try {
      const r = pixelRect(snapshot.rect, snapshot.viewport, bitmap);
      const canvas = new OffscreenCanvas(r.width, r.height);
      canvas.getContext('2d').drawImage(bitmap, r.x, r.y, r.width, r.height, 0, 0, r.width, r.height);
      const blob = await canvas.convertToBlob({type: 'image/png'});
      if (!blob.size || blob.size > 10 * 1024 * 1024) throw new Error('캡처 이미지가 허용 크기를 넘었습니다.');
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let binary = '';
      for (let i = 0; i < bytes.length; i += 32768) binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
      return btoa(binary);
    } finally { bitmap.close(); }
  }
  globalThis.AISolverCrop = {pixelRect, crop};
})();
