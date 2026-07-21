import { createMatch, getAsset, joinMatch, matchStatus, pollMatchBatch, pollMatchFrame, readyMatch, submitMatchBatch } from './api.js';
import { AudioPresenter } from './audio.js';
import { createDoomCanvas, blit } from './canvas.js';
import { decodeBytes, decodeFrameBatch, decodePayload } from './codec.js';
import { bindInput } from './input.js';
import { applyPalette, createPalette } from './palette.js';
const style = document.createElement('style');
style.textContent = `
  :root{color-scheme:dark;background:#080806;color:#eee;font:15px/1.4 system-ui}
  *{box-sizing:border-box}html,body{margin:0;min-height:100%;background:#080806}
  body{display:grid;place-items:center;padding:18px}
  main{width:min(100%,900px);display:grid;gap:14px}
  h1{margin:0;color:#d94932;font:900 42px/1 Impact,sans-serif;letter-spacing:.04em}
  p{margin:.4em 0}.panel{border:1px solid #474238;background:#151511;padding:16px}
  .forms{display:grid;grid-template-columns:1fr 1fr;gap:12px}
  label{display:grid;gap:4px;margin:8px 0;color:#bbb}input,select,button{font:inherit}
  input,select{width:100%;padding:9px;background:#080806;color:#fff;border:1px solid #555}
  button{padding:10px 13px;color:#fff;background:#541b14;border:1px solid #b44434;cursor:pointer}
  button:disabled{opacity:.45;cursor:wait}.share{display:flex;gap:6px}.share input{font-size:12px}
  [data-game]{position:relative;display:none;background:#000}
  [data-game][data-active]{display:grid;place-items:center}
  canvas{display:block;width:min(100%,calc(100vh * 1.6 - 50px));height:auto;image-rendering:pixelated;outline:0}
  [data-hud]{position:absolute;left:10px;top:10px;padding:7px 9px;background:#000c;border:1px solid #7778;white-space:pre-line;font:12px/1.35 ui-monospace,monospace;pointer-events:none}
  .muted{color:#aaa}.error{color:#ff8a7a}
  @media(max-width:700px){.forms{grid-template-columns:1fr}body{padding:8px}}
`;
document.head.append(style);
const main = document.createElement('main');
main.innerHTML = `
  <header><h1>DoomDB Co-op</h1><p class="muted">One authoritative Doom world inside Oracle · two database-authored POVs · generated AutoREST only</p></header>
  <section class="panel" data-lobby>
    <div class="forms">
      <form data-create><h2>Create match</h2>
        <label>Name <input name="name" maxlength="32" value="Player 1" required></label>
        <label>Mode <select name="mode"><option value="COOP" selected>Co-op</option><option value="DEATHMATCH">Deathmatch</option></select></label>
        <label>Skill <select name="skill"><option value="1">I'm too young to die</option><option value="2">Hey, not too rough</option><option value="3" selected>Hurt me plenty</option><option value="4">Ultra-violence</option><option value="5">Nightmare</option></select></label>
        <button>Create two-player match</button>
      </form>
      <form data-join><h2>Join match</h2>
        <label>Name <input name="name" maxlength="32" value="Player 2" required></label>
        <label>Match id <input name="match" maxlength="32" required></label>
        <label>Join capability <input name="join" maxlength="64" type="password" required></label>
        <button>Join co-op</button>
      </form>
    </div>
    <div data-room hidden>
      <h2>Lobby</h2><p data-room-status></p>
      <p class="share" data-share-wrap hidden><input data-share readonly aria-label="Private join link"><button data-copy type="button">Copy private join link</button></p>
      <button data-ready type="button">Ready</button>
    </div>
    <p data-message class="muted">Create a match, or open a private join link from the host.</p>
  </section>
  <section data-game><div data-hud>Waiting for match…</div></section>
  <p><a href="/play/">Single-player</a> · <a href="/">Status dashboard</a></p>`;
document.body.replaceChildren(main);
const lobby = main.querySelector('[data-lobby]');
const createForm = main.querySelector('[data-create]');
const joinForm = main.querySelector('[data-join]');
const room = main.querySelector('[data-room]');
const roomStatus = main.querySelector('[data-room-status]');
const message = main.querySelector('[data-message]');
const readyButton = main.querySelector('[data-ready]');
const shareWrap = main.querySelector('[data-share-wrap]');
const shareInput = main.querySelector('[data-share]');
const copyButton = main.querySelector('[data-copy]');
const game = main.querySelector('[data-game]');
const hud = main.querySelector('[data-hud]');
const canvas = createDoomCanvas();
game.prepend(canvas);
const trace = (name, detail) => {
    window.dispatchEvent(new CustomEvent(`doom:multiplayer-${name}`, {
        detail: { at: performance.now(), ...detail }
    }));
};
const storageKey = (match) => `doomdb.match.${match}`;
const saveLocal = (value) => {
    sessionStorage.setItem(storageKey(value.match), JSON.stringify(value));
};
const loadLocal = (match) => {
    try {
        const value = JSON.parse(sessionStorage.getItem(storageKey(match)) ?? 'null');
        if (typeof value !== 'object' || value === null)
            return null;
        const candidate = value;
        if (candidate.match !== match || !/^[0-9a-f]{64}$/.test(candidate.playerCapability ?? '') ||
            (candidate.playerSlot !== 0 && candidate.playerSlot !== 1))
            return null;
        return candidate;
    }
    catch {
        return null;
    }
};
const setBusy = (busy) => {
    for (const button of createForm.querySelectorAll('button'))
        button.disabled = busy;
    for (const button of joinForm.querySelectorAll('button'))
        button.disabled = busy;
    copyButton.disabled = busy;
    readyButton.disabled = busy || latestStatus === null ||
        latestStatus.memberCount !== latestStatus.maxPlayers;
};
const showError = (cause) => {
    message.className = 'error';
    message.textContent = cause instanceof Error ? cause.message : String(cause);
    setBusy(false);
};
let local = null;
let latestStatus = null;
let ready = false;
let lobbyTimer = 0;
let gameStarted = false;
const joinUrl = (value) => {
    const url = new URL('/play/multiplayer.html', location.origin);
    url.hash = `join=${value.match}.${value.joinCapability ?? ''}`;
    return url.toString();
};
async function refreshLobby() {
    if (local === null)
        return;
    const capability = local.hostCapability ?? local.playerCapability;
    latestStatus = await matchStatus(local.match, capability);
    roomStatus.textContent = `Match ${local.match} · player ${local.playerSlot + 1}\n${latestStatus.memberCount}/${latestStatus.maxPlayers} joined · ${latestStatus.readyCount} ready · ${latestStatus.state}`;
    readyButton.textContent = ready ? 'Not ready' : 'Ready';
    readyButton.disabled = latestStatus.memberCount !== latestStatus.maxPlayers;
    if (latestStatus.state === 'ACTIVE' && !gameStarted) {
        gameStarted = true;
        window.clearInterval(lobbyTimer);
        await startGame(local, latestStatus);
    }
}
async function enterLobby(value) {
    local = value;
    saveLocal(value);
    history.replaceState(null, '', `#resume=${value.match}`);
    createForm.hidden = true;
    joinForm.hidden = true;
    room.hidden = false;
    message.textContent = 'Capabilities remain only in this browser session.';
    if (value.joinCapability !== undefined) {
        shareInput.value = joinUrl(value);
        shareWrap.hidden = false;
    }
    await refreshLobby();
    lobbyTimer = window.setInterval(() => {
        void refreshLobby().catch(showError);
    }, 500);
}
createForm.addEventListener('submit', event => {
    event.preventDefault();
    setBusy(true);
    const data = new FormData(createForm);
    const mode = data.get('mode') === 'DEATHMATCH' ? 'DEATHMATCH' : 'COOP';
    void createMatch(String(data.get('name')), Number(data.get('skill')), mode)
        .then(value => enterLobby({ ...value, playerSlot: 0 }))
        .catch(showError).finally(() => setBusy(false));
});
joinForm.addEventListener('submit', event => {
    event.preventDefault();
    setBusy(true);
    const data = new FormData(joinForm);
    const match = String(data.get('match')).toLowerCase();
    const prior = loadLocal(match);
    void joinMatch(match, String(data.get('join')).toLowerCase(), String(data.get('name')), prior?.playerCapability ?? null)
        .then(value => enterLobby({ match, ...value }))
        .catch(showError).finally(() => setBusy(false));
});
readyButton.addEventListener('click', () => {
    if (local === null)
        return;
    setBusy(true);
    ready = !ready;
    void readyMatch(local.match, local.playerCapability, ready)
        .then(() => refreshLobby()).catch(cause => { ready = !ready; showError(cause); })
        .finally(() => setBusy(false));
});
copyButton.addEventListener('click', () => {
    void navigator.clipboard.writeText(shareInput.value).then(() => {
        copyButton.textContent = 'Copied';
        window.setTimeout(() => { copyButton.textContent = 'Copy private join link'; }, 1200);
    }).catch(showError);
});
function signedByte(value) {
    return Math.max(-127, Math.min(127, Math.trunc(value)));
}
function transientTransportFailure(cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    return /request failed: 5\d\d|failed to fetch|networkerror|load failed/i.test(message);
}
function ticcmd(command) {
    const bytes = new Uint8Array(8);
    bytes[0] = signedByte(Math.abs(command.forward) > 1 ? command.forward : command.forward * (command.run ? 50 : 25));
    bytes[1] = signedByte(Math.abs(command.strafe) > 1 ? command.strafe : command.strafe * (command.run ? 40 : 24));
    const turn = command.turn === 0 ? 0 : -Math.sign(command.turn) *
        (Math.abs(command.turn) > 1 ? Math.abs(command.turn) * 256 : (command.run ? 1280 : 320));
    new DataView(bytes.buffer).setInt16(2, turn, false);
    let buttons = (command.fire ? 1 : 0) | (command.use ? 2 : 0);
    if (command.weapon > 0)
        buttons |= 4 | ((command.weapon - 1) << 3);
    bytes[7] = buttons;
    return Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
}
async function startGame(value, status) {
    lobby.hidden = true;
    game.dataset.active = '';
    const audio = new AudioPresenter();
    const [paletteAsset, titleAsset, initial] = await Promise.all([
        getAsset('PLAYPAL'), getAsset('TITLEPIC'),
        pollMatchFrame(value.match, value.playerCapability, 0, 1000)
    ]);
    const palette = createPalette(decodeBytes(paletteAsset.payload));
    const title = decodeBytes(titleAsset.payload);
    blit(canvas, applyPalette(title, palette));
    if (initial.payload === null)
        throw new Error('tic-zero POV is unavailable');
    const initialFrame = await decodePayload(initial.payload);
    if (initialFrame.tic !== 0)
        throw new Error('invalid multiplayer frontier');
    let latest = { seq: 0, turn: 0, forward: 0, strafe: 0, run: 0,
        fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: '' };
    const buttons = new Map();
    bindInput(canvas, buttons, command => { latest = command; trace('input', { command }); }, () => { }, () => {
        void audio.enable();
    });
    canvas.addEventListener('click', () => {
        if (document.pointerLockElement !== canvas)
            void canvas.requestPointerLock();
    });
    canvas.focus();
    let currentTic = status.currentTic;
    let serverTic = status.currentTic;
    let submittedTic = currentTic;
    let submitting = false;
    const pollingBatches = new Set();
    let nextPollTic = currentTic + 1;
    let pendingSubmit = null;
    const frameBuffer = new Map();
    let nextPresentationAt = 0;
    let stopped = false;
    const membershipEpoch = status.membershipEpoch;
    let generation = status.generation;
    let transportFailures = 0;
    let retryAfter = 0;
    const paintedAt = [];
    const updateHud = () => {
        const windowMs = paintedAt.length > 1 ? paintedAt.at(-1) - paintedAt[0] : 0;
        const fps = windowMs > 0 ? (paintedAt.length - 1) * 1000 / windowMs : 0;
        hud.textContent = `${status.mode} · PLAYER ${value.playerSlot + 1} · TIC ${currentTic}\n${fps.toFixed(1)} displayed FPS · click game for mouse · F/Ctrl fire · Space use`;
    };
    const fail = (cause) => {
        stopped = true;
        hud.className = 'error';
        hud.textContent = cause instanceof Error ? cause.message : String(cause);
    };
    const recovered = () => {
        transportFailures = 0;
        retryAfter = 0;
        hud.className = '';
    };
    const retryTransport = (cause) => {
        transportFailures += 1;
        if (transportFailures > 60) {
            fail(cause);
            return;
        }
        retryAfter = performance.now() + Math.min(100 * transportFailures, 1000);
        hud.className = 'muted';
        hud.textContent = `${status.mode} · PLAYER ${value.playerSlot + 1} · TIC ${currentTic}\nReconnecting to Oracle…`;
    };
    const pump = () => {
        if (stopped || performance.now() < retryAfter)
            return;
        const nextFrame = frameBuffer.get(currentTic + 1);
        if (nextFrame !== undefined && performance.now() >= nextPresentationAt) {
            frameBuffer.delete(nextFrame.tic);
            blit(canvas, applyPalette(nextFrame.indices, palette));
            audio.enqueue(nextFrame.audio, fail);
            currentTic = nextFrame.tic;
            const now = performance.now();
            paintedAt.push(now);
            if (paintedAt.length > 60)
                paintedAt.shift();
            trace('present', { tic: nextFrame.tic, frameSha: nextFrame.frameSha });
            nextPresentationAt = now + 28;
            recovered();
            updateHud();
        }
        if (!submitting && submittedTic < serverTic + 8) {
            submitting = true;
            const request = pendingSubmit ?? {
                tic: submittedTic + 1, command: { ...latest }, hex: ticcmd(latest)
            };
            pendingSubmit = request;
            for (let offset = 0; offset < 4; offset += 1) {
                trace('submit', { tic: request.tic + offset, command: request.command });
            }
            void submitMatchBatch(value.match, value.playerCapability, request.tic, request.tic, request.hex.repeat(4)).then(result => {
                if (result.accepted !== 4 || result.generation < generation ||
                    result.membershipEpoch !== membershipEpoch) {
                    throw new Error('multiplayer submit fence changed');
                }
                generation = result.generation;
                submittedTic = request.tic + 3;
                pendingSubmit = null;
                recovered();
            }).catch(async (cause) => {
                if (transientTransportFailure(cause)) {
                    retryTransport(cause);
                    return;
                }
                // The worker may have durably supplied this slot's neutral command
                // while a tab was suspended or reconnecting. Refresh instead of
                // treating that expected late-submit rejection as a fatal error.
                const refreshed = await matchStatus(value.match, value.playerCapability);
                if (refreshed.state !== 'ACTIVE' ||
                    refreshed.generation < generation ||
                    refreshed.membershipEpoch !== membershipEpoch)
                    throw cause;
                generation = refreshed.generation;
                // A deadline-neutralized batch can be older than the bounded frame
                // ring. Resume at the durable frontier; ordinary transport retries
                // remain exact and never enter this authoritative rejection path.
                currentTic = Math.max(currentTic, refreshed.currentTic);
                serverTic = Math.max(serverTic, refreshed.currentTic);
                submittedTic = Math.max(submittedTic, refreshed.currentTic);
                nextPollTic = currentTic + 1;
                frameBuffer.clear();
                pendingSubmit = null;
                recovered();
                updateHud();
            }).catch(cause => {
                if (transientTransportFailure(cause))
                    retryTransport(cause);
                else
                    fail(cause);
            }).finally(() => { submitting = false; });
        }
        if (pollingBatches.size < 2 && nextPollTic + 3 <= submittedTic) {
            const firstTic = nextPollTic;
            pollingBatches.add(firstTic);
            nextPollTic += 4;
            for (let offset = 0; offset < 4; offset += 1) {
                trace('poll', { tic: firstTic + offset });
            }
            void pollMatchBatch(value.match, value.playerCapability, firstTic)
                .then(async (result) => {
                const frames = await decodeFrameBatch(result.payload);
                for (const [index, frame] of frames.entries()) {
                    const tic = firstTic + index;
                    trace('ready', { tic });
                    if (frame.tic !== tic)
                        throw new Error('multiplayer frame frontier changed');
                    trace('decoded', { tic, frameSha: frame.frameSha });
                    frameBuffer.set(tic, frame);
                }
                serverTic = Math.max(serverTic, result.currentTic);
                recovered();
            }).catch(cause => {
                if (transientTransportFailure(cause))
                    retryTransport(cause);
                else
                    fail(cause);
            }).finally(() => { pollingBatches.delete(firstTic); });
        }
    };
    updateHud();
    window.setInterval(pump, 4);
}
const hash = location.hash.slice(1);
if (hash.startsWith('join=')) {
    const [match = '', join = ''] = hash.slice(5).split('.');
    if (/^[0-9a-f]{32}$/.test(match) && /^[0-9a-f]{64}$/.test(join)) {
        joinForm.elements.namedItem('match').value = match;
        joinForm.elements.namedItem('join').value = join;
    }
}
else if (hash.startsWith('resume=')) {
    const match = hash.slice(7);
    const saved = loadLocal(match);
    if (saved !== null)
        void enterLobby(saved).catch(showError);
}
