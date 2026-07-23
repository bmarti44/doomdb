export type AuthorityAudioTuple = readonly [number, number, string, number, number];

export type AuthorityTransition = {
  tic: number;
  generation: number;
  membershipEpoch: number;
  membershipBitmap: number;
  activePlayers: number;
  complete: 0 | 1;
  previousChainSha: string;
  chainSha: string;
  canonicalStateSha: string | undefined;
  commands: Uint8Array<ArrayBuffer>;
  audio: AuthorityAudioTuple[];
};

export type AuthorityStreamState = {
  tic: number;
  generation: number;
  membershipEpoch: number;
  chainSha: string;
};

const HEADER_BYTES = 150;
const COMMAND_BYTES = 32;
const FLAG_CANONICAL_STATE = 1;
const FLAG_COMPLETE = 2;

function ascii(bytes: Uint8Array<ArrayBuffer>, start: number, length: number): string {
  return new TextDecoder('ascii', {fatal: true}).decode(bytes.subarray(start, start + length));
}

function hex(bytes: Uint8Array<ArrayBuffer>): string {
  return Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
}

export function base64AuthorityBytes(encoded: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) {
    throw new TypeError('authority payload base64 is invalid');
  }
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function audioTuples(value: unknown, tic: number): AuthorityAudioTuple[] {
  if (!Array.isArray(value)) throw new TypeError('authority audio is invalid');
  return value.map((entry, ordinal) => {
    if (!Array.isArray(entry) || entry.length !== 5) {
      throw new TypeError('authority audio tuple is invalid');
    }
    const [eventTic, eventOrdinal, asset, volume, separation] = entry as unknown[];
    if (eventTic !== tic || eventOrdinal !== ordinal || typeof asset !== 'string' ||
        !/^(?:DS|D_)[A-Z0-9_]+$/.test(asset) || !Number.isInteger(volume) ||
        !Number.isInteger(separation) || (volume as number) < 0 ||
        (volume as number) > 255 || (separation as number) < 0 ||
        (separation as number) > 255) {
      throw new TypeError('authority audio tuple is invalid');
    }
    return [eventTic, eventOrdinal, asset, volume, separation] as AuthorityAudioTuple;
  });
}

async function chainDigest(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  // chain_sha occupies bytes 52..83 and is excluded from its own digest.
  const material = new Uint8Array(bytes.length - 32);
  material.set(bytes.subarray(0, 52));
  material.set(bytes.subarray(84), 52);
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', material)));
}

/** Domain-separated predecessor for tic 1, identical to Oracle STANDARD_HASH. */
export async function authorityRootChainSha(
  match: string, membershipEpoch: number
): Promise<string> {
  if (!/^[0-9a-f]{32}$/.test(match) || !Number.isSafeInteger(membershipEpoch) ||
      membershipEpoch < 1) {
    throw new TypeError('authority root fence is invalid');
  }
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256',
    new TextEncoder().encode(`DMD1_ROOT|${match}|${membershipEpoch}`))));
}

/**
 * Decode one database-committed DMD1 transition.
 *
 * The browser may apply this transition to a render-only TeaVM mirror only
 * after every fence and the authority chain have validated. It must never
 * advance the mirror from locally predicted input.
 */
export async function decodeAuthorityTransition(
  encoded: string, state?: Readonly<AuthorityStreamState>
): Promise<AuthorityTransition> {
  return decodeAuthorityTransitionBytes(base64AuthorityBytes(encoded), state);
}

/** Decode an already framed DMD1 record, used by the consecutive DMB1 batch. */
export async function decodeAuthorityTransitionBytes(
  bytes: Uint8Array<ArrayBuffer>, state?: Readonly<AuthorityStreamState>
): Promise<AuthorityTransition> {
  if (bytes.length < HEADER_BYTES || ascii(bytes, 0, 4) !== 'DMD1') {
    throw new TypeError('authority envelope is invalid');
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tic = view.getUint32(4, false);
  const generation = view.getUint32(8, false);
  const membershipEpoch = view.getUint32(12, false);
  const membershipBitmap = bytes[16] as number;
  const activePlayers = bytes[17] as number;
  const flags = view.getUint16(18, false);
  const audioLength = view.getUint16(148, false);
  if (tic < 1 || generation < 1 || membershipEpoch < 1 ||
      activePlayers < 2 || activePlayers > 4 || membershipBitmap < 1 ||
      (membershipBitmap & ~0x0f) !== 0 || (flags & ~3) !== 0 ||
      bytes.length !== HEADER_BYTES + audioLength) {
    throw new TypeError('authority envelope is invalid');
  }
  const previousChainSha = hex(bytes.subarray(20, 52));
  const chainSha = hex(bytes.subarray(52, 84));
  const canonicalBytes = bytes.subarray(84, 116);
  const hasCanonicalState = (flags & FLAG_CANONICAL_STATE) !== 0;
  const canonicalStateSha = hasCanonicalState ? hex(canonicalBytes) : undefined;
  if (!hasCanonicalState && canonicalBytes.some(value => value !== 0)) {
    throw new TypeError('authority canonical-state marker is invalid');
  }
  if (chainSha !== await chainDigest(bytes)) {
    throw new TypeError('authority chain hash is invalid');
  }
  if (state !== undefined) {
    if (tic !== state.tic + 1 || generation < state.generation ||
        membershipEpoch !== state.membershipEpoch ||
        previousChainSha !== state.chainSha) {
      throw new TypeError('authority stream fence changed');
    }
  }
  let audio: unknown;
  try {
    audio = JSON.parse(new TextDecoder('utf-8', {fatal: true})
      .decode(bytes.subarray(HEADER_BYTES)));
  } catch (cause) {
    throw new TypeError('authority audio is invalid', {cause});
  }
  const transition: AuthorityTransition = {
    tic,
    generation,
    membershipEpoch,
    membershipBitmap,
    activePlayers,
    complete: (flags & FLAG_COMPLETE) === 0 ? 0 : 1,
    previousChainSha,
    chainSha,
    canonicalStateSha,
    commands: bytes.slice(116, 116 + COMMAND_BYTES),
    audio: audioTuples(audio, tic)
  };
  return transition;
}

/** Advance the transport frontier only after the confirmed mirror applied. */
export function commitAuthorityTransition(
  state: AuthorityStreamState, transition: AuthorityTransition
): void {
  if (transition.tic !== state.tic + 1 ||
      transition.generation < state.generation ||
      transition.membershipEpoch !== state.membershipEpoch ||
      transition.previousChainSha !== state.chainSha) {
    throw new TypeError('authority stream fence changed');
  }
  state.tic = transition.tic;
  state.generation = transition.generation;
  state.membershipEpoch = transition.membershipEpoch;
  state.chainSha = transition.chainSha;
}
