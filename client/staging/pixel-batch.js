const MAGIC = 0x44504232; // DPB2
const SHARED_MAGIC = 0x44504431; // DPD1
const FRAME_BYTES = 64_000;
const ENTRY_BYTES = 8 + FRAME_BYTES;
export function nextDatabaseFrameTic(tic) {
    if (!Number.isSafeInteger(tic) || tic < -1)
        throw new TypeError('database frame tic is invalid');
    return tic + 1;
}
/** Decide whether a self-contained confirmed-frame stream must resynchronize. */
export function databasePixelBatchDisposition(currentGeneration, transportTic, incomingGeneration, firstTic) {
    if (!Number.isSafeInteger(currentGeneration) || currentGeneration < 1
        || !Number.isSafeInteger(incomingGeneration) || incomingGeneration < 1
        || !Number.isSafeInteger(transportTic) || transportTic < -1
        || firstTic !== null && (!Number.isSafeInteger(firstTic) || firstTic < 0)) {
        throw new TypeError('pixel batch frontier is invalid');
    }
    if (incomingGeneration < currentGeneration)
        throw new TypeError('pixel batch generation regressed');
    if (incomingGeneration > currentGeneration)
        return 'RESET_GENERATION';
    if (firstTic !== null && transportTic >= 0
        && firstTic !== nextDatabaseFrameTic(transportTic))
        return 'RESET_GAP';
    return 'CONTINUE';
}
/** Decode a generation-fenced batch of complete database framebuffers. */
export function decodeDatabasePixelBatch(payload, playerSlot = 0) {
    if (payload.byteLength < 8)
        throw new TypeError('pixel batch is truncated');
    const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    const magic = view.getUint32(0);
    if (magic === SHARED_MAGIC) {
        if (!Number.isInteger(playerSlot) || playerSlot < 0 || playerSlot > 1
            || payload.byteLength < 16)
            throw new TypeError('shared pixel viewpoint is invalid');
        const tic = view.getUint32(4);
        const playerMask = view.getUint8(8);
        const palette0 = view.getUint8(9);
        const palette1 = view.getUint8(10);
        if ((playerMask !== 1 && playerMask !== 3)
            || (playerMask & (1 << playerSlot)) === 0
            || palette0 > 13 || (playerMask === 3 && palette1 > 13)
            || view.getUint8(11) !== 0 || view.getUint32(12) !== 0
            || payload.byteLength !== 16 +
                (playerMask === 1 ? FRAME_BYTES : 2 * FRAME_BYTES)) {
            throw new TypeError('shared pixel dimensions are invalid');
        }
        const offset = 16 + (playerSlot === 1 ? FRAME_BYTES : 0);
        return [{
                tic,
                paletteIndex: playerSlot === 0 ? palette0 : palette1,
                indices: payload.subarray(offset, offset + FRAME_BYTES)
            }];
    }
    if (magic !== MAGIC) {
        throw new TypeError('pixel batch magic is invalid');
    }
    const count = view.getUint32(4);
    if (count < 1 || count > 8 ||
        payload.byteLength !== 8 + count * ENTRY_BYTES) {
        throw new TypeError('pixel batch dimensions are invalid');
    }
    const frames = [];
    let offset = 8;
    let priorTic = -1;
    for (let index = 0; index < count; index += 1) {
        const tic = view.getUint32(offset);
        offset += 4;
        const paletteIndex = view.getUint8(offset);
        if (paletteIndex > 13 || view.getUint8(offset + 1) !== 0
            || view.getUint8(offset + 2) !== 0 || view.getUint8(offset + 3) !== 0)
            throw new TypeError('pixel batch palette field is invalid');
        offset += 4;
        if (tic <= priorTic
            || index > 0 && tic !== nextDatabaseFrameTic(priorTic))
            throw new TypeError('pixel batch tics are not consecutive');
        // Retain a zero-copy view into the decoded batch. The backing response
        // stays alive until the final queued frame is presented, avoiding eight
        // additional 64 KiB allocations and copies on every successful poll.
        const indices = payload.subarray(offset, offset + FRAME_BYTES);
        offset += FRAME_BYTES;
        frames.push({ tic, paletteIndex, indices });
        priorTic = tic;
    }
    return frames;
}
/**
 * Decode the versioned database-native transport envelope.
 *
 * Oracle UTL_COMPRESS emits an RFC-1952 gzip member. The uncompressed bytes
 * remain the self-fencing DPB2/DPD1 payload, so compression changes neither
 * framebuffer authorship nor the canonical tic/palette/length checks.
 */
export async function decodeDatabasePixelTransport(payload, playerSlot = 0) {
    if (payload.byteLength >= 4 && payload[0] === 0x1f && payload[1] === 0x8b
        && payload[2] === 0x08 && payload[3] === 0x00) {
        const stream = new Blob([payload]).stream()
            .pipeThrough(new DecompressionStream('gzip'));
        const restored = new Uint8Array(await new Response(stream).arrayBuffer());
        if (restored.byteLength > 8 + 8 * ENTRY_BYTES)
            throw new TypeError('pixel transport expansion is invalid');
        return decodeDatabasePixelBatch(restored, playerSlot);
    }
    // Retain exact raw decoding for an incarnation-fenced rollback deployment.
    return decodeDatabasePixelBatch(payload, playerSlot);
}
