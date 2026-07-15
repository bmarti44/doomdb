export function createDoomCanvas(): HTMLCanvasElement {
  const canvas = document.createElement('canvas');
  canvas.width = 320;
  canvas.height = 200;
  canvas.dataset.doomCanvas = '';
  canvas.setAttribute('aria-label', 'DoomDB game');
  return canvas;
}

export function blit(canvas: HTMLCanvasElement, rgba: Uint8ClampedArray<ArrayBuffer>): void {
  if (rgba.length !== 320 * 200 * 4) throw new TypeError('canvas frame length is invalid');
  const context = canvas.getContext('2d', {willReadFrequently: true});
  if (context === null) throw new Error('canvas context is unavailable');
  context.imageSmoothingEnabled = false;
  context.putImageData(new ImageData(rgba, 320, 200), 0, 0);
}
