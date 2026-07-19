import { decodeBytes } from './codec.js';
export function decodePatch(payload) {
    const bytes = decodeBytes(payload);
    if (bytes.length < 12)
        throw new TypeError('Doom patch is truncated');
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const width = view.getInt16(0, true);
    const height = view.getInt16(2, true);
    const leftOffset = view.getInt16(4, true);
    const topOffset = view.getInt16(6, true);
    if (width < 1 || height < 1 || width > 320 || height > 200 ||
        8 + width * 4 > bytes.length)
        throw new TypeError('Doom patch header is invalid');
    const pixels = new Int16Array(width * height).fill(-1);
    for (let x = 0; x < width; x += 1) {
        let source = view.getUint32(8 + x * 4, true);
        let previousTop = -1;
        let posts = 0;
        for (;;) {
            if (source >= bytes.length || posts++ > height + 1) {
                throw new TypeError('Doom patch column is invalid');
            }
            const rawTop = bytes[source];
            if (rawTop === 255)
                break;
            if (source + 4 > bytes.length)
                throw new TypeError('Doom patch post is truncated');
            const length = bytes[source + 1];
            let top = rawTop;
            if (previousTop >= 0 && rawTop <= previousTop)
                top += previousTop;
            previousTop = top;
            source += 3;
            if (length < 1 || source + length + 1 > bytes.length) {
                throw new TypeError('Doom patch post pixels are invalid');
            }
            for (let y = 0; y < length; y += 1) {
                if (top + y >= 0 && top + y < height)
                    pixels[(top + y) * width + x] = bytes[source + y];
            }
            source += length + 1;
        }
    }
    return { width, height, leftOffset, topOffset, pixels };
}
export function drawPatch(target, patch, x, y) {
    if (target.length !== 320 * 200)
        throw new TypeError('menu target is invalid');
    const originX = x - patch.leftOffset;
    const originY = y - patch.topOffset;
    for (let py = 0; py < patch.height; py += 1) {
        const targetY = originY + py;
        if (targetY < 0 || targetY >= 200)
            continue;
        for (let px = 0; px < patch.width; px += 1) {
            const targetX = originX + px;
            const color = patch.pixels[py * patch.width + px];
            if (color >= 0 && targetX >= 0 && targetX < 320)
                target[targetY * 320 + targetX] = color;
        }
    }
}
