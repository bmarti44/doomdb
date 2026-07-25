import * as engine from 'doom_teavm_engine';
import oracledb from 'mle-js-oracledb';

let retainedFrame;

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
  return engine.initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map);
}

export function stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands) {
  return engine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
}

function exactFrame(playerSlot) {
  // The presentation artifact's existing render export already returns the
  // Uint8Array shape accepted by MLE's BLOB bind. Keep transport adaptation in
  // JavaScript so adding presentation-only @JSExport roots cannot reshape the
  // separately pinned authority module.
  const frame = engine.renderPlayerFrame(playerSlot);
  if (!(frame instanceof Uint8Array) || frame.byteLength !== 64000) {
    throw new Error(`exact frame length mismatch: ${frame?.byteLength}`);
  }
  retainedFrame = frame;
  return retainedFrame;
}

export function renderPlayerFrameLength(playerSlot) {
  return exactFrame(playerSlot).byteLength;
}

export function renderPlayerFrameChunk(offset, length) {
  if (!(retainedFrame instanceof Uint8Array)) {
    throw new Error('no exact frame is retained');
  }
  if (!Number.isInteger(offset) || !Number.isInteger(length)
      || offset < 0 || length < 0
      || offset > retainedFrame.byteLength
      || length > retainedFrame.byteLength - offset) {
    throw new Error(`exact frame chunk is out of range: ${offset}/${length}`);
  }
  return retainedFrame.subarray(offset, offset + length);
}

function directBlobBindMode() {
  return oracledb.DB_TYPE_BLOB === undefined
    ? 'implicit_target_blob'
    : 'explicit_db_type_blob';
}

function persistDirect(frame, frameId) {
  const payload = {
    dir: oracledb.BIND_IN,
    val: frame,
  };
  // DB_TYPE_BLOB is a node-oracledb-style capability probe, not a documented
  // MLE constant. Oracle 26ai's published MLE mapping includes
  // Uint8Array -> BLOB, so the standards-based arm lets the target BLOB
  // column supply the SQL type when the explicit constant is absent.
  if (oracledb.DB_TYPE_BLOB !== undefined) {
    payload.type = oracledb.DB_TYPE_BLOB;
  }
  const result = oracledb.defaultConnection().execute(
    `insert into doom_teavm_frame_sink(frame_id,payload)
     values(:frameId,:payload)`,
    {
      frameId,
      payload,
    });
  if (result.rowsAffected !== 1) {
    throw new Error(`frame sink insert affected ${result.rowsAffected} rows`);
  }
}

function acquirePersistentLocator(frameId) {
  const result = oracledb.defaultConnection().execute(
    `update doom_teavm_frame_sink
        set frame_id=:frameId
      where sink_id=1
     returning payload into :payload`,
    {
      frameId,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
  });
  if (result.rowsAffected !== 1) {
    throw new Error(
      `persistent frame locator affected ${result.rowsAffected} rows`,
    );
  }
  if (!Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1) {
    throw new Error('RETURNING payload did not produce exactly one locator');
  }
  const payload = result.outBinds.payload[0];
  if (!(payload instanceof OracleBlob)) {
    throw new Error('RETURNING payload did not produce OracleBlob');
  }
  return payload;
}

function persistReturningLocator(frame, frameId) {
  // A persistent LOB locator cannot span transactions. Reuse the same
  // persistent BLOB row, but acquire its locator through UPDATE RETURNING in
  // the current frame transaction and close it before the caller may commit.
  // No temporary LOB is created.
  const payload = acquirePersistentLocator(frameId);
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    // Every exact frame has the same 64,000-byte length, so position-one
    // overwrite reuses the persistent database LOB without trim/temporary LOBs.
    payload.write(1, frame);
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the enclosing SQL call rolls back.
      }
    }
    throw failure;
  }
  payload.close();
}

export function probeDirectBlobBind() {
  // Exercise the real 64 KB shape so a RAW-sized implicit bind cannot produce
  // a false-positive capability result.
  persistDirect(new Uint8Array(64000), -1);
  return 64000;
}

export function directBlobBindCapability() {
  return directBlobBindMode();
}

export function renderPlayerFramePersistDirect(playerSlot, frameId) {
  const frame = exactFrame(playerSlot);
  persistDirect(frame, frameId);
  return frame.byteLength;
}

export function renderPlayerFramePersistLocator(playerSlot, frameId) {
  const frame = exactFrame(playerSlot);
  persistReturningLocator(frame, frameId);
  return frame.byteLength;
}

export function release() {
  engine.release();
  retainedFrame = undefined;
}
