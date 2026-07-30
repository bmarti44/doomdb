const ROOT = '/ords/doom/doom_api/';
let uppercaseProcedures = true;
export class MatchCapacityError extends Error {
    constructor() {
        super('Oracle match capacity is temporarily occupied.');
        this.name = 'MatchCapacityError';
    }
}
export class MatchUnavailableError extends Error {
    constructor() {
        super('This Oracle match has ended. Start a new game to continue.');
        this.name = 'MatchUnavailableError';
    }
}
async function post(path, body, signal) {
    const request = () => fetch(`${ROOT}${uppercaseProcedures ? path.toUpperCase() : path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
        ...(signal === undefined ? {} : { signal })
    });
    let response = await request();
    // ORDS 26.2's generated package endpoints retain catalog case. Keep a
    // one-request fallback for older/local test doubles that expose lowercase.
    if (response.status === 404) {
        uppercaseProcedures = !uppercaseProcedures;
        response = await request();
    }
    if (!response.ok) {
        let oracleCode = '';
        let oracleClass = '';
        if (response.status === 555) {
            const detail = await response.text();
            oracleCode = detail.match(/\bORA-[0-9]{5}\b/)?.[0] ?? '';
            if (detail.includes('DMB1 committed transition gap') ||
                detail.includes('DMB1 frontier changed')) {
                oracleClass = ' DMB1_RESYNC_REQUIRED';
            }
            if (detail.includes('ORA-20713'))
                throw new MatchUnavailableError();
            if (path.toLowerCase() === 'create_match' ||
                detail.includes('ORA-20702'))
                throw new MatchCapacityError();
        }
        throw new Error(`${path} request failed: ${response.status}${oracleCode.length > 0 ? ` ${oracleCode}` : ''}${oracleClass}`);
    }
    const value = await response.json();
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        throw new TypeError(`${path} response is invalid`);
    }
    return value;
}
const delay = (milliseconds) => new Promise(resolve => window.setTimeout(resolve, milliseconds));
async function postStep(body) {
    let lastFailure;
    for (let attempt = 0; attempt < 4; attempt += 1) {
        try {
            return await post('step', body);
        }
        catch (cause) {
            lastFailure = cause instanceof Error ? cause : new Error('step request failed');
            if (attempt === 3)
                break;
            await delay(25 * (attempt + 1));
        }
    }
    throw lastFailure ?? new Error('step request failed');
}
async function postAsync(path, body, signal) {
    let lastFailure;
    const aborted = () => signal !== undefined && signal.aborted;
    for (let attempt = 0; attempt < 8; attempt += 1) {
        if (aborted())
            throw signal?.reason;
        try {
            return await post(path, body, signal);
        }
        catch (cause) {
            if (aborted() || cause instanceof DOMException &&
                cause.name === 'AbortError')
                throw cause;
            if (cause instanceof MatchUnavailableError)
                throw cause;
            lastFailure = cause instanceof Error ? cause : new Error(`${path} request failed`);
            if (path === 'poll_match_transitions' &&
                lastFailure.message.includes('DMB1_RESYNC_REQUIRED')) {
                throw lastFailure;
            }
            if (attempt === 7)
                break;
            const retryDelayMs = Math.min(25 * (2 ** attempt), 500);
            const message = lastFailure.message;
            window.dispatchEvent(new CustomEvent('doom:api-retry', { detail: {
                    at: performance.now(), operation: path,
                    status: Number(message.match(/request failed: ([0-9]+)/)?.[1] ?? 0),
                    oracleCode: message.match(/\bORA-[0-9]{5}\b/)?.[0] ?? '',
                    attempt: attempt + 1, retryDelayMs
                } }));
            await delay(retryDelayMs);
        }
    }
    throw lastFailure ?? new Error(`${path} request failed`);
}
function stringField(document, name) {
    const value = document[name];
    if (typeof value !== 'string' || value.length === 0) {
        throw new TypeError(`${name} response field is invalid`);
    }
    return value;
}
export async function newGame(skill = 3) {
    const document = await post('new_game', { p_skill: skill });
    const session = stringField(document, 'p_session');
    if (!/^[0-9a-f]{32}$/.test(session))
        throw new TypeError('session response is invalid');
    return { session, payload: stringField(document, 'p_payload') };
}
export async function step(session, command) {
    // The command sequence is the idempotency key. A retry after an ORDS/AQ
    // timeout returns the immutable committed response instead of applying twice.
    const document = await postStep({
        p_session: session,
        p_commands: JSON.stringify({ v: 2, commands: [command] })
    });
    return stringField(document, 'p_payload');
}
export async function submitStep(session, command) {
    const document = await postAsync('submit_step', {
        p_session: session,
        p_commands: JSON.stringify({ v: 2, commands: [command] })
    });
    const request = stringField(document, 'p_request');
    if (!/^[0-9a-f]{32}$/.test(request))
        throw new TypeError('request response is invalid');
    return request;
}
export async function pollFrame(session, sequence, waitMilliseconds = 1000) {
    const document = await postAsync('poll_frame', {
        p_session: session, p_seq: sequence, p_wait_ms: waitMilliseconds
    });
    const ready = document.p_ready;
    if (ready !== 0 && ready !== 1)
        throw new TypeError('p_ready response field is invalid');
    return ready === 1 ? stringField(document, 'p_payload') : null;
}
export async function getAsset(name) {
    const document = await post('get_asset', { p_asset_name: name });
    return {
        payload: stringField(document, 'p_payload'),
        mediaType: stringField(document, 'p_media_type')
    };
}
function numberField(document, name) {
    const value = document[name];
    if (typeof value !== 'number' || !Number.isSafeInteger(value)) {
        throw new TypeError(`${name} response field is invalid`);
    }
    return value;
}
function capabilityField(document, name) {
    const value = stringField(document, name);
    if (!/^[0-9a-f]{64}$/.test(value)) {
        throw new TypeError(`${name} response field is invalid`);
    }
    return value;
}
export async function createMatch(displayName, skill = 3, gameMode = 'COOP', maxPlayers = 2, signal) {
    const document = await post('create_match', {
        p_game_mode: gameMode, p_skill: skill, p_episode: 1, p_map: 1,
        p_display_name: displayName, p_max_players: maxPlayers
    }, signal);
    const match = stringField(document, 'p_match');
    if (!/^[0-9a-f]{32}$/.test(match))
        throw new TypeError('match response is invalid');
    return {
        match,
        hostCapability: capabilityField(document, 'p_host_capability'),
        joinCapability: capabilityField(document, 'p_join_capability'),
        playerCapability: capabilityField(document, 'p_player_capability')
    };
}
export async function joinMatch(match, joinCapability, displayName, playerCapability = null) {
    const document = await post('join_match', {
        p_match: match, p_join_capability: joinCapability,
        p_display_name: displayName, p_player_capability: playerCapability
    });
    return {
        playerCapability: capabilityField(document, 'p_player_capability'),
        playerSlot: numberField(document, 'p_player_slot')
    };
}
export async function readyMatch(match, playerCapability, ready) {
    const document = await post('ready_match', {
        p_match: match, p_player_capability: playerCapability,
        p_ready: ready ? 1 : 0
    });
    return stringField(document, 'p_match_state');
}
export async function leaveMatch(match, playerCapability) {
    const document = await post('leave_match', {
        p_match: match, p_player_capability: playerCapability
    });
    return stringField(document, 'p_match_state');
}
/**
 * Best-effort unload cleanup. The server-side lease/janitor remains the
 * authority because browsers may terminate without dispatching pagehide.
 */
export function leaveMatchOnUnload(match, playerCapability) {
    const body = JSON.stringify({
        p_match: match, p_player_capability: playerCapability
    });
    const url = `${ROOT}LEAVE_MATCH`;
    const payload = new Blob([body], { type: 'application/json' });
    if (navigator.sendBeacon(url, payload))
        return;
    void fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body,
        keepalive: true
    }).catch(() => {
        // Unload delivery cannot be guaranteed. The database lease and lifecycle
        // reconciler are the fail-safe reclamation path.
    });
}
export async function matchStatus(match, capability) {
    const document = await post('match_status', {
        p_match: match, p_capability: capability
    });
    return {
        state: stringField(document, 'p_match_state'),
        mode: stringField(document, 'p_game_mode'),
        skill: numberField(document, 'p_skill'),
        episode: numberField(document, 'p_episode'),
        map: numberField(document, 'p_map'),
        maxPlayers: numberField(document, 'p_max_players'),
        memberCount: numberField(document, 'p_member_count'),
        readyCount: numberField(document, 'p_ready_count'),
        requesterSlot: numberField(document, 'p_requester_slot'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation'),
        currentTic: numberField(document, 'p_current_tic'),
        workerMode: stringField(document, 'p_worker_mode'),
        recoveryStatus: stringField(document, 'p_recovery_status')
    };
}
export async function submitMatchStep(match, playerCapability, tic, sequence, ticcmdHex) {
    // A rejected late command is a normal lockstep resynchronization signal, not
    // a transient transport failure. The client retries only after refreshing
    // the authoritative frontier.
    const document = await post('submit_match_step', {
        p_match: match, p_player_capability: playerCapability, p_tic: tic,
        p_command_seq: sequence, p_ticcmd_hex: ticcmdHex
    });
    return {
        accepted: numberField(document, 'p_accepted'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation')
    };
}
export async function submitMatchBatch(match, playerCapability, firstTic, firstSequence, ticcmdHex) {
    const document = await post('submit_match_batch', {
        p_match: match, p_player_capability: playerCapability,
        p_first_tic: firstTic, p_first_command_seq: firstSequence,
        p_ticcmd_hex: ticcmdHex
    });
    return {
        accepted: numberField(document, 'p_accepted'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation')
    };
}
export async function submitMatchBatchInput(match, playerCapability, firstTic, firstSequence, ticcmdHex, inputSequence, inputTiccmdHex) {
    const document = await postAsync('submit_match_batch_input', {
        p_match: match, p_player_capability: playerCapability,
        p_first_tic: firstTic, p_first_command_seq: firstSequence,
        p_ticcmd_hex: ticcmdHex, p_input_seq: inputSequence,
        p_input_ticcmd_hex: inputTiccmdHex
    });
    return { accepted: numberField(document, 'p_accepted'),
        inputAccepted: numberField(document, 'p_input_accepted'),
        effectiveTic: numberField(document, 'p_effective_tic'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation'),
        payload: stringField(document, 'p_payload') };
}
export async function reviseMatchInput(match, playerCapability, inputSequence, ticcmdHex, targetTic) {
    const document = await postAsync('revise_match_input', {
        p_match: match, p_player_capability: playerCapability,
        p_input_seq: inputSequence, p_ticcmd_hex: ticcmdHex,
        p_target_tic: targetTic
    });
    return { accepted: numberField(document, 'p_accepted'),
        effectiveTic: numberField(document, 'p_effective_tic'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation') };
}
export async function touchMatchPresence(match, playerCapability) {
    const document = await postAsync('touch_match_presence', {
        p_match: match, p_player_capability: playerCapability
    });
    return {
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation')
    };
}
export async function matchInputFrontier(match, playerCapability) {
    const document = await post('match_input_frontier', {
        p_match: match, p_player_capability: playerCapability
    });
    return numberField(document, 'p_input_seq');
}
export async function exchangeMatchBatch(match, playerCapability, firstTic, firstFrameTic, firstSequence, ticcmdHex, waitMilliseconds = 1000) {
    const document = await postAsync('exchange_match_batch', {
        p_match: match, p_player_capability: playerCapability,
        p_first_tic: firstTic, p_first_frame_tic: firstFrameTic,
        p_first_command_seq: firstSequence,
        p_ticcmd_hex: ticcmdHex, p_wait_ms: waitMilliseconds
    });
    return {
        accepted: numberField(document, 'p_accepted'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation'),
        currentTic: numberField(document, 'p_current_tic'),
        payload: stringField(document, 'p_payload')
    };
}
export async function pollMatchBatch(match, playerCapability, firstTic, waitMilliseconds = 5000, frameCount = 4) {
    const document = await postAsync('poll_match_batch', {
        p_match: match, p_player_capability: playerCapability,
        p_first_tic: firstTic, p_wait_ms: waitMilliseconds,
        p_frame_count: frameCount
    });
    return { currentTic: numberField(document, 'p_current_tic'),
        payload: stringField(document, 'p_payload') };
}
export async function pollMatchTransitions(match, playerCapability, afterTic, holdMilliseconds = 500, maxTransitions = 32, signal) {
    const document = await postAsync('poll_match_transitions', {
        p_match: match, p_player_capability: playerCapability,
        p_after_tic: afterTic, p_hold_ms: holdMilliseconds,
        p_max_transitions: maxTransitions
    }, signal);
    const ready = numberField(document, 'p_ready');
    if (ready !== 0 && ready !== 1) {
        throw new TypeError('p_ready response field is invalid');
    }
    // Timeout is a valid DMB1 batch with zero records, not a missing payload.
    return { currentTic: numberField(document, 'p_current_tic'),
        payload: stringField(document, 'p_payload'), ready: ready === 1 };
}
export async function matchCheckpoint(match, playerCapability, afterTic) {
    const document = await postAsync('match_checkpoint', {
        p_match: match, p_player_capability: playerCapability,
        p_after_tic: afterTic
    });
    const ready = numberField(document, 'p_ready');
    if (ready !== 0 && ready !== 1) {
        throw new TypeError('p_ready response field is invalid');
    }
    const optionalString = (name) => {
        const value = document[name];
        return typeof value === 'string' ? value : '';
    };
    return {
        ready: ready === 1,
        currentTic: numberField(document, 'p_current_tic'),
        checkpointTic: numberField(document, 'p_checkpoint_tic'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation'),
        chainSha: optionalString('p_chain_sha'),
        checkpointSha: optionalString('p_checkpoint_sha'),
        payload: ready === 1 ? stringField(document, 'p_payload') : null
    };
}
export async function pollMatchFrame(match, playerCapability, tic, waitMilliseconds = 1000) {
    const document = await postAsync('poll_match_frame', {
        p_match: match, p_player_capability: playerCapability,
        p_tic: tic, p_wait_ms: waitMilliseconds
    });
    const ready = numberField(document, 'p_ready');
    if (ready !== 0 && ready !== 1)
        throw new TypeError('p_ready response field is invalid');
    return {
        currentTic: numberField(document, 'p_current_tic'),
        payload: ready === 1 ? stringField(document, 'p_payload') : null
    };
}
export async function pollMatchPixels(match, playerCapability, afterTic) {
    const document = await postAsync('poll_match_pixels', {
        p_match: match,
        p_player_capability: playerCapability,
        p_after_tic: afterTic
    });
    const ready = numberField(document, 'p_ready');
    if (ready !== 0 && ready !== 1) {
        throw new TypeError('p_ready response field is invalid');
    }
    return {
        ready: ready === 1,
        currentTic: numberField(document, 'p_current_tic'),
        frameTic: ready === 1 ? numberField(document, 'p_frame_tic') : null,
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation'),
        payload: ready === 1 ? stringField(document, 'p_payload') : null
    };
}
export async function pollMatchPixelBatch(match, playerCapability, afterTic, maximumFrames = 8) {
    const document = await postAsync('poll_match_pixel_batch', {
        p_match: match,
        p_player_capability: playerCapability,
        p_after_tic: afterTic,
        p_max_frames: maximumFrames
    });
    const frameCount = numberField(document, 'p_frame_count');
    if (frameCount < 0 || frameCount > maximumFrames) {
        throw new TypeError('pixel batch count is invalid');
    }
    return {
        frameCount,
        firstTic: frameCount > 0 ? numberField(document, 'p_first_tic') : null,
        lastTic: frameCount > 0 ? numberField(document, 'p_last_tic') : null,
        currentTic: numberField(document, 'p_current_tic'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation'),
        payload: frameCount > 0 ? stringField(document, 'p_payload') : null
    };
}
export async function exchangeMatchPixelBatch(match, playerCapability, afterTic, maximumFrames, inputSequence, ticcmdHex, targetTic) {
    if ((inputSequence === undefined) !== (ticcmdHex === undefined)) {
        throw new TypeError('pixel exchange input is incomplete');
    }
    // Managed ORDS occasionally strands one otherwise read-only request for
    // seconds while the peer browser continues normally. Keep the ordinary
    // path at one request, but issue one idempotent tail hedge after 120 ms.
    // The first valid response wins and both fetches are then aborted. This
    // protects the finite confirmed-frame ring without doubling steady-state
    // request pressure on the Always Free execution lane.
    const hedgeDelayMs = 120;
    const primary = new AbortController();
    const hedge = new AbortController();
    const timeout = window.setTimeout(() => {
        primary.abort();
        hedge.abort();
    }, 20_000);
    let hedgeTimer = 0;
    let document;
    const body = {
        p_match: match,
        p_player_capability: playerCapability,
        p_after_tic: afterTic,
        p_max_frames: maximumFrames,
        p_input_seq: inputSequence,
        p_ticcmd_hex: ticcmdHex,
        p_target_tic: targetTic
    };
    try {
        const primaryRequest = postAsync('exchange_match_pixel_batch', body, primary.signal);
        const hedgeRequest = new Promise((resolve, reject) => {
            hedgeTimer = window.setTimeout(() => {
                void postAsync('exchange_match_pixel_batch', body, hedge.signal)
                    .then(resolve, reject);
            }, hedgeDelayMs);
        });
        document = await Promise.any([primaryRequest, hedgeRequest]);
    }
    catch (cause) {
        if (primary.signal.aborted && hedge.signal.aborted) {
            throw new Error('exchange_match_pixel_batch request failed: 504');
        }
        throw cause;
    }
    finally {
        window.clearTimeout(timeout);
        window.clearTimeout(hedgeTimer);
        primary.abort();
        hedge.abort();
    }
    const frameCount = numberField(document, 'p_frame_count');
    if (frameCount < 0 || frameCount > maximumFrames) {
        throw new TypeError('pixel exchange batch count is invalid');
    }
    const inputAccepted = numberField(document, 'p_input_accepted');
    if (inputAccepted !== 0 && inputAccepted !== 1) {
        throw new TypeError('pixel exchange input result is invalid');
    }
    return {
        inputAccepted,
        effectiveTic: inputAccepted === 1
            ? numberField(document, 'p_effective_tic') : null,
        frameCount,
        firstTic: frameCount > 0 ? numberField(document, 'p_first_tic') : null,
        lastTic: frameCount > 0 ? numberField(document, 'p_last_tic') : null,
        currentTic: numberField(document, 'p_current_tic'),
        membershipEpoch: numberField(document, 'p_membership_epoch'),
        generation: numberField(document, 'p_generation'),
        payload: frameCount > 0 ? stringField(document, 'p_payload') : null
    };
}
