const ROOT = '/ords/doom/doom_api/';
let uppercaseProcedures = false;
async function post(path, body) {
    const request = () => fetch(`${ROOT}${uppercaseProcedures ? path.toUpperCase() : path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body)
    });
    let response = await request();
    // ORDS 26.2's generated package endpoints retain the catalog procedure
    // case even though older/local test doubles accept lowercase routes.
    if (response.status === 404 && !uppercaseProcedures) {
        uppercaseProcedures = true;
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
    const document = await post('step', {
        p_session: session,
        p_commands: JSON.stringify({ v: 1, commands: [command] })
    });
    return stringField(document, 'p_payload');
}
export async function getAsset(name) {
    const document = await post('get_asset', { p_asset_name: name });
    return {
        payload: stringField(document, 'p_payload'),
        mediaType: stringField(document, 'p_media_type')
    };
}
