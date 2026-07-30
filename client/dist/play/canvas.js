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
/**
 * Blit the database renderer's native Doom screen layout. Mocha's retained
 * framebuffer is column-major (`x * 200 + y`); ImageData is row-major. Keep
 * this conversion in the dumb framebuffer client rather than adding another
 * interpreted pass to the database's hot render path.
 */
export function createColumnMajorIndexedBlitter(canvas, palette) {
    if (palette.length !== 256 * 3)
        throw new TypeError('palette byte length is invalid');
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (context === null)
        throw new Error('canvas context is unavailable');
    context.imageSmoothingEnabled = false;
    const image = context.createImageData(320, 200);
    const rgbaWords = new Uint32Array(image.data.buffer, image.data.byteOffset, image.data.byteLength / 4);
    const littleEndian = new Uint8Array(new Uint32Array([0x01020304]).buffer)[0]
        === 0x04;
    const paletteWords = new Uint32Array(256);
    for (let index = 0; index < 256; index += 1) {
        const source = index * 3;
        const red = palette[source];
        const green = palette[source + 1];
        const blue = palette[source + 2];
        paletteWords[index] = littleEndian
            ? red | (green << 8) | (blue << 16) | 0xff000000
            : (red << 24) | (green << 16) | (blue << 8) | 0xff;
    }
    return indices => {
        if (indices.length !== 320 * 200)
            throw new TypeError('database framebuffer dimensions are invalid');
        for (let x = 0; x < 320; x += 1) {
            const sourceColumn = x * 200;
            for (let y = 0; y < 200; y += 1) {
                rgbaWords[y * 320 + x] = paletteWords[indices[sourceColumn + y]];
            }
        }
        context.putImageData(image, 0, 0);
    };
}
/** Expand a database-selected PLAYPAL variant while preserving canvas-only clients. */
export function createColumnMajorIndexedPaletteBlitter(canvas, palettes) {
    if (palettes.length !== 14 * 256 * 3)
        throw new TypeError('PLAYPAL set byte length is invalid');
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (context === null)
        throw new Error('canvas context is unavailable');
    context.imageSmoothingEnabled = false;
    const image = context.createImageData(320, 200);
    const rgbaWords = new Uint32Array(image.data.buffer, image.data.byteOffset, image.data.byteLength / 4);
    const littleEndian = new Uint8Array(new Uint32Array([0x01020304]).buffer)[0]
        === 0x04;
    const paletteWords = new Uint32Array(14 * 256);
    for (let index = 0; index < 14 * 256; index += 1) {
        const source = index * 3;
        const red = palettes[source], green = palettes[source + 1], blue = palettes[source + 2];
        paletteWords[index] = littleEndian
            ? red | (green << 8) | (blue << 16) | 0xff000000
            : (red << 24) | (green << 16) | (blue << 8) | 0xff;
    }
    return (indices, paletteIndex) => {
        if (indices.length !== 320 * 200)
            throw new TypeError('database framebuffer dimensions are invalid');
        if (!Number.isInteger(paletteIndex) || paletteIndex < 0 || paletteIndex > 13)
            throw new TypeError('database palette index is invalid');
        const paletteBase = paletteIndex * 256;
        for (let x = 0; x < 320; x += 1) {
            const sourceColumn = x * 200;
            for (let y = 0; y < 200; y += 1)
                rgbaWords[y * 320 + x] =
                    paletteWords[paletteBase + indices[sourceColumn + y]];
        }
        context.putImageData(image, 0, 0);
    };
}
/** Paint either retained framebuffer layout without moving pixels in MLE. */
export function createDatabaseIndexedPaletteBlitter(canvas, palettes) {
    if (palettes.length !== 14 * 256 * 3)
        throw new TypeError('PLAYPAL set byte length is invalid');
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (context === null)
        throw new Error('canvas context is unavailable');
    context.imageSmoothingEnabled = false;
    const image = context.createImageData(320, 200);
    const rgbaWords = new Uint32Array(image.data.buffer, image.data.byteOffset, image.data.byteLength / 4);
    const littleEndian = new Uint8Array(new Uint32Array([0x01020304]).buffer)[0]
        === 0x04;
    const paletteWords = new Uint32Array(14 * 256);
    for (let index = 0; index < 14 * 256; index += 1) {
        const source = index * 3;
        const red = palettes[source], green = palettes[source + 1], blue = palettes[source + 2];
        paletteWords[index] = littleEndian
            ? red | (green << 8) | (blue << 16) | 0xff000000
            : (red << 24) | (green << 16) | (blue << 8) | 0xff;
    }
    return (indices, paletteIndex, layout) => {
        if (indices.length !== 320 * 200)
            throw new TypeError('database framebuffer dimensions are invalid');
        if (!Number.isInteger(paletteIndex) || paletteIndex < 0 || paletteIndex > 13)
            throw new TypeError('database palette index is invalid');
        const paletteBase = paletteIndex * 256;
        if (layout === 'ROW_MAJOR') {
            for (let index = 0; index < indices.length; index += 1)
                rgbaWords[index] = paletteWords[paletteBase + indices[index]];
        }
        else if (layout === 'COLUMN_MAJOR') {
            for (let x = 0; x < 320; x += 1) {
                const sourceColumn = x * 200;
                for (let y = 0; y < 200; y += 1)
                    rgbaWords[y * 320 + x] =
                        paletteWords[paletteBase + indices[sourceColumn + y]];
            }
        }
        else {
            throw new TypeError('database framebuffer layout is invalid');
        }
        context.putImageData(image, 0, 0);
    };
}
