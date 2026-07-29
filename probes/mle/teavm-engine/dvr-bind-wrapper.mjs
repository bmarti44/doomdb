import * as engine from 'doom_teavm_engine';
import * as codec from 'doom_dvr_codec';
import oracledb from 'mle-js-oracledb';

const FRAME_BYTES = 64000;
const BATCH_HEADER_BYTES = 12;
const RECORD_HEADER_BYTES = 16;
const CODEC_ID = 'DOOM_DFR1_RLE';
const CODEC_VERSION = 1;

let retainedFrame;
let retainedCompressed;
let batchFrames = [];
let batchFrameIds = [];

export function allocateIwad(length) {
  return engine.allocateIwad(length);
}

export function loadIwadChunk(offset, chunk) {
  return engine.loadIwadChunk(offset, chunk);
}

export function allocateTablePack(length) {
  return engine.allocateTablePack(length);
}

export function loadTablePackChunk(offset, chunk) {
  return engine.loadTablePackChunk(offset, chunk);
}

export function initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map) {
  if (codec.codecId() !== CODEC_ID || codec.codecVersion() !== CODEC_VERSION) {
    throw new Error(
      `DVR codec identity mismatch: ${codec.codecId()}/${codec.codecVersion()}`,
    );
  }
  return engine.initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map);
}

export function stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands) {
  return engine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
}

function renderExact(playerSlot) {
  const frame = engine.renderPlayerFrame(playerSlot);
  if (!(frame instanceof Uint8Array) || frame.byteLength !== FRAME_BYTES) {
    throw new Error(`exact frame length mismatch: ${frame?.byteLength}`);
  }
  retainedFrame = frame;
  return frame;
}

function compressExact(frame) {
  const compressed = codec.compressFrame(frame);
  if (!(compressed instanceof Uint8Array)
      || compressed.byteLength < 12
      || compressed[0] !== 68 || compressed[1] !== 70
      || compressed[2] !== 82 || compressed[3] !== 49) {
    throw new Error('compiled codec returned an invalid DFR1 payload');
  }
  retainedCompressed = compressed;
  return compressed;
}

export function renderRetain(playerSlot) {
  return renderExact(playerSlot).byteLength;
}

export function compressRetained() {
  if (!(retainedFrame instanceof Uint8Array)) {
    throw new Error('no exact frame is retained');
  }
  return compressExact(retainedFrame).byteLength;
}

export function renderCompressAppend(playerSlot, frameId) {
  requireFrameId(frameId);
  const compressed = compressExact(renderExact(playerSlot));
  batchFrames.push(compressed);
  batchFrameIds.push(frameId);
  return compressed.byteLength;
}

export function roundTripRetained() {
  if (!(retainedFrame instanceof Uint8Array)
      || !(retainedCompressed instanceof Uint8Array)) {
    throw new Error('no exact compressed frame is retained');
  }
  const decoded = codec.decompressFrame(retainedCompressed);
  if (!(decoded instanceof Uint8Array)
      || decoded.byteLength !== retainedFrame.byteLength) {
    return 0;
  }
  for (let offset = 0; offset < decoded.byteLength; offset++) {
    if (decoded[offset] !== retainedFrame[offset]) return 0;
  }
  return 1;
}

export function retainedFrameChunk(offset, length) {
  return checkedChunk(retainedFrame, offset, length, 'exact frame');
}

export function retainedCompressedChunk(offset, length) {
  return checkedChunk(retainedCompressed, offset, length, 'compressed frame');
}

export function retainedCompressedLength() {
  if (!(retainedCompressed instanceof Uint8Array)) {
    throw new Error('no compressed frame is retained');
  }
  return retainedCompressed.byteLength;
}

export function resetBatch() {
  batchFrames = [];
  batchFrameIds = [];
  return 0;
}

export function batchCount() {
  return batchFrames.length;
}

function putU32(target, offset, value) {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >>> 8) & 0xff;
  target[offset + 2] = (value >>> 16) & 0xff;
  target[offset + 3] = (value >>> 24) & 0xff;
}

function batchPayload() {
  if (batchFrames.length === 0 || batchFrames.length !== batchFrameIds.length) {
    throw new Error('DVR batch is empty or inconsistent');
  }
  let length = BATCH_HEADER_BYTES;
  for (const frame of batchFrames) {
    length += RECORD_HEADER_BYTES + frame.byteLength;
  }
  const payload = new Uint8Array(length);
  payload.set([68, 70, 66, 49], 0); // DFB1.
  putU32(payload, 4, batchFrames.length);
  putU32(payload, 8, length);
  let offset = BATCH_HEADER_BYTES;
  for (let index = 0; index < batchFrames.length; index++) {
    const frameId = batchFrameIds[index];
    const low = frameId >>> 0;
    const high = Math.floor(frameId / 0x100000000) >>> 0;
    const frame = batchFrames[index];
    putU32(payload, offset, low);
    putU32(payload, offset + 4, high);
    putU32(payload, offset + 8, frame.byteLength);
    putU32(payload, offset + 12, CODEC_VERSION);
    offset += RECORD_HEADER_BYTES;
    payload.set(frame, offset);
    offset += frame.byteLength;
  }
  return payload;
}

function acquirePersistentLocator(
    sinkId, batchId, frameCount, firstFrameId, lastFrameId, codecId) {
  const result = oracledb.defaultConnection().execute(
    `update doom_dvr_frame_sink
        set batch_id=:batchId,
            frame_count=:frameCount,
            first_frame_id=:firstFrameId,
            last_frame_id=:lastFrameId,
            codec_id=:codecId,
            payload=empty_blob()
      where sink_id=:sinkId
     returning payload into :payload`,
    {
      sinkId,
      batchId,
      frameCount,
      firstFrameId,
      lastFrameId,
      codecId,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    });
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1
      || !(result.outBinds.payload[0] instanceof OracleBlob)) {
    throw new Error('persistent DVR locator acquisition failed');
  }
  return result.outBinds.payload[0];
}

function persistWithLocator(
    bytes, sinkId, batchId, frameCount, firstFrameId, lastFrameId, codecId) {
  const payload = acquirePersistentLocator(
    sinkId, batchId, frameCount, firstFrameId, lastFrameId, codecId);
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, bytes);
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the enclosing call rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  return bytes.byteLength;
}

export function persistRetainedRaw(frameId) {
  requireFrameId(frameId);
  if (!(retainedFrame instanceof Uint8Array)) {
    throw new Error('no exact frame is retained');
  }
  return persistWithLocator(
    retainedFrame, 1, frameId, 1, frameId, frameId, 'RAW_INDEXED_V1');
}

export function persistCompressedBatch(batchId) {
  requireFrameId(batchId);
  const payload = batchPayload();
  return persistWithLocator(
    payload,
    2,
    batchId,
    batchFrames.length,
    batchFrameIds[0],
    batchFrameIds[batchFrameIds.length - 1],
    CODEC_ID,
  );
}

function requireFrameId(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`frame id is invalid: ${value}`);
  }
}

function checkedChunk(value, offset, length, label) {
  if (!(value instanceof Uint8Array)) {
    throw new Error(`no ${label} is retained`);
  }
  if (!Number.isInteger(offset) || !Number.isInteger(length)
      || offset < 0 || length < 0
      || offset > value.byteLength || length > value.byteLength - offset) {
    throw new Error(`${label} chunk is out of range: ${offset}/${length}`);
  }
  return value.subarray(offset, offset + length);
}

export function release() {
  engine.release();
  retainedFrame = undefined;
  retainedCompressed = undefined;
  batchFrames = [];
  batchFrameIds = [];
}
