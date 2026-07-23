import {base64AuthorityBytes, commitAuthorityTransition,
  decodeAuthorityTransitionBytes, type AuthorityStreamState,
  type AuthorityTransition} from './authority.js';

export type AuthorityBatch = {
  generation: number;
  membershipEpoch: number;
  requestedAfterTic: number;
  committedFrontierTic: number;
  holdElapsedMs: number;
  timedOut: boolean;
  moreAvailable: boolean;
  transitions: AuthorityTransition[];
};

const HEADER_BYTES = 32;
const FLAG_TIMED_OUT = 1;
const FLAG_MORE_AVAILABLE = 2;
const MAX_TRANSITIONS = 64;
// The requested DBMS_ALERT hold is capped at 500 ms. The owning session can
// resume later under Oracle Resource Manager, so the diagnostic elapsed field
// is bounded separately from the requested hold.
const MAX_RESPONSE_ELAPSED_MS = 60_000;

function ascii(bytes: Uint8Array<ArrayBuffer>, start: number, length: number): string {
  return new TextDecoder('ascii', {fatal: true}).decode(bytes.subarray(start, start + length));
}

/**
 * Decode one database snapshot of consecutive committed DMD1 transitions.
 *
 * Decoding never mutates the caller's frontier. Each transition still has to
 * be applied and committed by ConfirmedAuthorityMirror in order.
 */
export async function decodeAuthorityBatch(
  encoded: string, state: Readonly<AuthorityStreamState>
): Promise<AuthorityBatch> {
  const bytes = base64AuthorityBytes(encoded);
  if (bytes.length < HEADER_BYTES || ascii(bytes, 0, 4) !== 'DMB1') {
    throw new TypeError('authority batch is invalid');
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const version = view.getUint16(4, false);
  const flags = view.getUint16(6, false);
  const count = view.getUint16(8, false);
  const reserved = view.getUint16(10, false);
  const generation = view.getUint32(12, false);
  const membershipEpoch = view.getUint32(16, false);
  const requestedAfterTic = view.getUint32(20, false);
  const committedFrontierTic = view.getUint32(24, false);
  const holdElapsedMs = view.getUint32(28, false);
  const timedOut = (flags & FLAG_TIMED_OUT) !== 0;
  const moreAvailable = (flags & FLAG_MORE_AVAILABLE) !== 0;
  if (version !== 1 || (flags & ~3) !== 0 || count > MAX_TRANSITIONS ||
      reserved !== 0 || generation < state.generation ||
      membershipEpoch !== state.membershipEpoch ||
      requestedAfterTic !== state.tic || committedFrontierTic < requestedAfterTic ||
      holdElapsedMs > MAX_RESPONSE_ELAPSED_MS || timedOut !== (count === 0)) {
    throw new TypeError(`authority batch fence changed (version=${version}`
      + ` flags=${flags} count=${count} generation=${generation}/${state.generation}`
      + ` epoch=${membershipEpoch}/${state.membershipEpoch}`
      + ` after=${requestedAfterTic}/${state.tic} frontier=${committedFrontierTic}`
      + ` elapsed=${holdElapsedMs} timedOut=${timedOut})`);
  }

  const cursor: AuthorityStreamState = {...state};
  const transitions: AuthorityTransition[] = [];
  let offset = HEADER_BYTES;
  for (let index = 0; index < count; index += 1) {
    if (offset > bytes.length - 4) throw new TypeError('authority batch is truncated');
    const length = view.getUint32(offset, false);offset += 4;
    if (length < 150 || length > 32767 || offset > bytes.length - length) {
      throw new TypeError('authority batch record length is invalid');
    }
    const transition = await decodeAuthorityTransitionBytes(
      bytes.slice(offset, offset + length), cursor);
    if (transition.generation > generation) {
      throw new TypeError('authority batch generation changed');
    }
    transitions.push(transition);commitAuthorityTransition(cursor, transition);
    offset += length;
  }
  if (offset !== bytes.length || cursor.tic > committedFrontierTic ||
      moreAvailable !== (cursor.tic < committedFrontierTic)) {
    throw new TypeError('authority batch frontier is invalid');
  }
  return {generation, membershipEpoch, requestedAfterTic,
    committedFrontierTic, holdElapsedMs, timedOut, moreAvailable, transitions};
}
