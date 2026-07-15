function base64Bytes(encoded) {
    if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded))
        throw new TypeError('payload base64 is invalid');
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1)
        bytes[index] = binary.charCodeAt(index);
    return bytes;
}
export function decodeBytes(encoded) {
    return base64Bytes(encoded);
}
function audioTuples(value, tic) {
    if (!Array.isArray(value))
        throw new TypeError('payload audio is invalid');
    return value.map((entry, ordinal) => {
        if (!Array.isArray(entry) || entry.length !== 5)
            throw new TypeError('payload audio tuple is invalid');
        const [eventTic, eventOrdinal, asset, volume, separation] = entry;
        if (eventTic !== tic || eventOrdinal !== ordinal || typeof asset !== 'string' ||
            !Number.isInteger(volume) || !Number.isInteger(separation)) {
            throw new TypeError('payload audio tuple is invalid');
        }
        return [eventTic, eventOrdinal, asset, volume, separation];
    });
}
function frameFrom(value) {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        throw new TypeError('payload JSON is invalid');
    }
    const document = value;
    if (document.v !== 1 || document.w !== 320 || document.h !== 200 ||
        !Number.isInteger(document.tic) || typeof document.mode !== 'string' ||
        typeof document.frame_sha !== 'string' || !/^[0-9a-f]{64}$/.test(document.frame_sha) ||
        !Array.isArray(document.cols) || document.cols.length !== 320) {
        throw new TypeError('payload frame envelope is invalid');
    }
    const indices = new Uint8Array(320 * 200);
    for (let x = 0; x < 320; x += 1) {
        const column = document.cols[x];
        if (!Array.isArray(column))
            throw new TypeError('payload column is invalid');
        let y = 0;
        for (const item of column) {
            if (!Array.isArray(item) || item.length !== 3)
                throw new TypeError('payload run is invalid');
            const [y0, length, color] = item;
            if (y0 !== y || !Number.isInteger(length) || !Number.isInteger(color) ||
                length < 1 || y + length > 200 ||
                color < 0 || color > 255) {
                throw new TypeError('payload run value is invalid');
            }
            for (let offset = 0; offset < length; offset += 1) {
                indices[(y + offset) * 320 + x] = color;
            }
            y += length;
        }
        if (y !== 200)
            throw new TypeError('payload column coverage is invalid');
    }
    const tic = document.tic;
    return {
        tic,
        mode: document.mode,
        frameSha: document.frame_sha,
        indices,
        audio: audioTuples(document.audio, tic)
    };
}
export async function decodePayload(encoded) {
    const bytes = base64Bytes(encoded);
    let document;
    try {
        const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
        const text = await new Response(stream).text();
        document = JSON.parse(text);
    }
    catch (cause) {
        throw new TypeError('gzip payload decode failed', { cause });
    }
    return frameFrom(document);
}
