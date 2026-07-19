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
