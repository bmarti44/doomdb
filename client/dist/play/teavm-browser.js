const AUTHORITY = {
    url: '/play/doom-mle-authority-a942cd2dcbdc.js',
    sha: 'a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2'
};
const PRESENTATION = {
    url: '/play/doom-mle-presentation-d45863e0c1be.js',
    sha: 'd45863e0c1be8fabdc63086fafc5d9d57193c4ed5758f259cd92af360426b39c'
};
const IWAD = {
    url: '/play/freedoom1-7323bcc168c5.bin',
    sha: '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d'
};
const TABLES = {
    url: '/play/canonical-runtime-v2-058cd0df9444.bin',
    sha: '058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44'
};
const LOAD_CHUNK_BYTES = 1024 * 1024;
function hex(bytes) {
    return Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
}
async function verifiedBytes(url, expectedSha) {
    const response = await fetch(url, { cache: 'force-cache' });
    if (!response.ok)
        throw new Error(`TeaVM asset request failed: ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    const actual = hex(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)));
    if (actual !== expectedSha)
        throw new Error(`TeaVM asset integrity failed: ${url}`);
    return bytes;
}
async function verifiedModule(source) {
    const bytes = await verifiedBytes(source.url, source.sha);
    const objectUrl = URL.createObjectURL(new Blob([bytes], { type: 'text/javascript' }));
    try {
        return await import(objectUrl);
    }
    finally {
        URL.revokeObjectURL(objectUrl);
    }
}
function load(engine, bytes, allocate, write, label) {
    if (allocate.call(engine, bytes.length) !== bytes.length) {
        throw new Error(`${label} allocation failed`);
    }
    for (let offset = 0; offset < bytes.length; offset += LOAD_CHUNK_BYTES) {
        const chunk = bytes.slice(offset, Math.min(bytes.length, offset + LOAD_CHUNK_BYTES));
        if (write.call(engine, offset, chunk) !== offset + chunk.length) {
            throw new Error(`${label} load failed at ${offset}`);
        }
    }
}
function initialize(engine, status, iwad, tables) {
    load(engine, iwad, engine.allocateIwad, engine.loadIwadChunk, 'IWAD');
    load(engine, tables, engine.allocateTablePack, engine.loadTablePackChunk, 'canonical table pack');
    const state = engine.initializeMultiplayerGame(status.maxPlayers, status.mode === 'DEATHMATCH' ? 1 : 0, status.skill, status.episode, status.map);
    if (!state.includes('state=multiplayer-initialized|gametic=0|')) {
        throw new Error(`TeaVM browser initialization failed: ${state}`);
    }
}
/** Load two SHA-verified, independent confirmed-state engine contexts. */
export async function createBrowserAuthorityEngines(status) {
    const [authority, presentation, iwad, tables] = await Promise.all([
        verifiedModule(AUTHORITY), verifiedModule(PRESENTATION),
        verifiedBytes(IWAD.url, IWAD.sha), verifiedBytes(TABLES.url, TABLES.sha)
    ]);
    initialize(authority, status, iwad, tables);
    initialize(presentation, status, iwad, tables);
    return { verifier: authority, presenter: presentation };
}
