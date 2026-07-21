export function createDoomCanvas() {
    const canvas = document.createElement('canvas');
    canvas.width = 320;
    canvas.height = 200;
    canvas.dataset.doomCanvas = '';
    canvas.tabIndex = 0;
    canvas.setAttribute('aria-label', 'DoomDB game');
    canvas.addEventListener('pointerdown', () => {
        canvas.focus({ preventScroll: true });
    });
    return canvas;
}
export function blit(canvas, rgba) {
    if (rgba.length !== 320 * 200 * 4)
        throw new TypeError('canvas frame length is invalid');
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (context === null)
        throw new Error('canvas context is unavailable');
    context.imageSmoothingEnabled = false;
    context.putImageData(new ImageData(rgba, 320, 200), 0, 0);
}
/** Reuse one browser-owned RGBA surface for a stream of indexed Doom frames. */
export function createIndexedBlitter(canvas, palette) {
    if (palette.length !== 256 * 3)
        throw new TypeError('palette byte length is invalid');
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (context === null)
        throw new Error('canvas context is unavailable');
    context.imageSmoothingEnabled = false;
    const image = context.createImageData(320, 200);
    return indices => {
        if (indices.length !== 320 * 200)
            throw new TypeError('palette input dimensions are invalid');
        const rgba = image.data;
        for (let index = 0; index < indices.length; index += 1) {
            const source = indices[index] * 3;
            const target = index * 4;
            rgba[target] = palette[source];
            rgba[target + 1] = palette[source + 1];
            rgba[target + 2] = palette[source + 2];
            rgba[target + 3] = 255;
        }
        context.putImageData(image, 0, 0);
    };
}
