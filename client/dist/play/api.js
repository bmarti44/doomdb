const ROOT = '/ords/doom/doom_api/';
let uppercaseProcedures = true;
async function post(path, body) {
    const request = () => fetch(`${ROOT}${uppercaseProcedures ? path.toUpperCase() : path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body)
    });
    let response = await request();
    // ORDS 26.2's generated package endpoints retain catalog case. Keep a
    // one-request fallback for older/local test doubles that expose lowercase.
    if (response.status === 404) {
        uppercaseProcedures = !uppercaseProcedures;
        response = await request();
    }
    if (!response.ok)
        throw new Error(`${path} request failed: ${response.status}`);
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
async function postAsync(path, body) {
    let lastFailure;
    for (let attempt = 0; attempt < 8; attempt += 1) {
        try {
            return await post(path, body);
        }
        catch (cause) {
            lastFailure = cause instanceof Error ? cause : new Error(`${path} request failed`);
            if (attempt === 7)
                break;
            await delay(Math.min(25 * (2 ** attempt), 500));
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
export async function createMatch(displayName, skill = 3, gameMode = 'COOP') {
    const document = await post('create_match', {
        p_game_mode: gameMode, p_skill: skill, p_episode: 1, p_map: 1,
        p_display_name: displayName
    });
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
        workerMode: stringField(document, 'p_worker_mode')
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
export async function pollMatchTransitions(match, playerCapability, afterTic, holdMilliseconds = 500, maxTransitions = 32) {
    const document = await postAsync('poll_match_transitions', {
        p_match: match, p_player_capability: playerCapability,
        p_after_tic: afterTic, p_hold_ms: holdMilliseconds,
        p_max_transitions: maxTransitions
    });
    const ready = numberField(document, 'p_ready');
    if (ready !== 0 && ready !== 1) {
        throw new TypeError('p_ready response field is invalid');
    }
    // Timeout is a valid DMB1 batch with zero records, not a missing payload.
    return { currentTic: numberField(document, 'p_current_tic'),
        payload: stringField(document, 'p_payload'), ready: ready === 1 };
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
