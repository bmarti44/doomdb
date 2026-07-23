import { createMatch, getAsset, joinMatch, leaveMatch, matchStatus, matchInputFrontier, pollMatchTransitions, readyMatch, reviseMatchInput } from './api.js';
import { AudioPresenter } from './audio.js';
import { createDoomCanvas, createIndexedBlitter } from './canvas.js';
import { decodeBytes } from './codec.js';
import { bindInput } from './input.js';
import { createPalette } from './palette.js';
import { decodeAuthorityBatch } from './authority-batch.js';
import { ConfirmedAuthorityMirror } from './authority-mirror.js';
import { authorityRootChainSha } from './authority.js';
import { ConfirmedWanPolicy } from './authority-wan.js';
import { createBrowserAuthorityEngines } from './teavm-browser.js';
const MAX_CONFIRMED_PRESENTATION_BACKLOG = 16;
const soloMode = document.body.hasAttribute('data-doom-solo');
const soloStartedAt = soloMode ? performance.now() : 0;
const launchParameters = new URLSearchParams(location.search.length > 1 ? location.search : location.hash.slice(1));
const requestedSkill = Number(launchParameters.get('skill') ?? 3);
const soloSkill = Number.isInteger(requestedSkill) &&
    requestedSkill >= 1 && requestedSkill <= 5 ? requestedSkill : 3;
const requestedMode = launchParameters.get('mode');
const requestedHoldMs = Number(new URLSearchParams(location.search).get('holdMs') ?? 0);
const transitionHoldMs = Number.isInteger(requestedHoldMs) &&
    requestedHoldMs >= 0 && requestedHoldMs <= 500 ? requestedHoldMs : 0;
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
  body[data-doom-solo]{padding:0;overflow:hidden}
  body[data-doom-solo] main{width:100vw;height:100vh;display:block}
  body[data-doom-solo] header,body[data-doom-solo] main>p{display:none}
  body[data-doom-solo] [data-game][data-active]{width:100vw;height:100vh}
  body[data-doom-solo] canvas{width:min(100vw,160vh);max-width:100vw;max-height:100vh}
  @media(max-width:700px){.forms{grid-template-columns:1fr}body{padding:8px}}
`;
document.head.append(style);
const main = document.createElement('main');
main.innerHTML = `
  <header><h1>${soloMode ? 'DoomDB' : 'DoomDB Multiplayer'}</h1><p class="muted">One authoritative Doom world inside Oracle · ${soloMode ? 'confirmed-only MLE presentation' : 'co-op and deathmatch with two database-authored POVs'} · generated AutoREST only</p></header>
  <section class="panel" data-lobby>
    <div class="forms">
      <form data-create><h2>Create match</h2>
        <label>Name <input name="name" maxlength="32" value="Player 1" required></label>
        <label>Mode <select name="mode"><option value="COOP" selected>Co-op</option><option value="DEATHMATCH">Multiplayer deathmatch</option></select></label>
        <label>Skill <select name="skill"><option value="1">I'm too young to die</option><option value="2">Hey, not too rough</option><option value="3" selected>Hurt me plenty</option><option value="4">Ultra-violence</option><option value="5">Nightmare</option></select></label>
        <button>Create two-player match</button>
      </form>
      <form data-join><h2>Join match</h2>
        <label>Name <input name="name" maxlength="32" value="Player 2" required></label>
        <label>Match id <input name="match" maxlength="32" required></label>
        <label>Join capability <input name="join" maxlength="64" type="password" required></label>
        <button>Join match</button>
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
  <p>${soloMode ? '' : '<a href="/play/">Single-player</a> · '}<a href="/">Status dashboard</a></p>`;
document.body.replaceChildren(main);
if (!soloMode && (requestedMode === 'COOP' || requestedMode === 'DEATHMATCH')) {
    const mode = main.querySelector('select[name="mode"]');
    if (mode !== null)
        mode.value = requestedMode;
}
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
const soloPresentationAssets = soloMode ?
    Promise.all([getAsset('PLAYPAL'), getAsset('TITLEPIC')]) : null;
const trace = (name, detail) => {
    window.dispatchEvent(new CustomEvent(`doom:multiplayer-${name}`, {
        detail: { at: performance.now(), ...detail }
    }));
};
const storageKey = (match) => `doomdb.match.${match}`;
const soloCurrentKey = 'doomdb.solo.current';
const saveLocal = (value) => {
    sessionStorage.setItem(storageKey(value.match), JSON.stringify(value));
    if (soloMode)
        sessionStorage.setItem(soloCurrentKey, value.match);
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
const retirePriorSolo = async () => {
    const current = sessionStorage.getItem(soloCurrentKey);
    const matches = new Set();
    if (current !== null)
        matches.add(current);
    // Migration fallback for solo credentials saved before the explicit pointer
    // existed. Multiplayer hosts retain host/join capabilities; the solo host
    // deliberately stores neither, so this cannot retire a co-op lobby.
    for (let index = 0; index < sessionStorage.length; index++) {
        const key = sessionStorage.key(index);
        if (key?.startsWith('doomdb.match.')) {
            const match = key.slice('doomdb.match.'.length);
            const candidate = loadLocal(match);
            if (candidate?.playerSlot === 0 && candidate.hostCapability === undefined &&
                candidate.joinCapability === undefined)
                matches.add(match);
        }
    }
    for (const match of matches) {
        const prior = loadLocal(match);
        try {
            if (prior !== null && prior.playerSlot === 0) {
                await leaveMatch(prior.match, prior.playerCapability);
            }
        }
        catch {
            // Expired/already-finished credentials are already retired. Any real
            // remaining capacity conflict is still rejected by CREATE_MATCH.
        }
        finally {
            sessionStorage.removeItem(storageKey(match));
        }
    }
    sessionStorage.removeItem(soloCurrentKey);
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
const showSoloError = (cause) => {
    hud.className = 'error';
    hud.textContent = `SINGLE PLAYER\n${cause instanceof Error ? cause.message : String(cause)}`;
    setBusy(false);
};
const transientAuthorityFailure = (cause) => cause instanceof Error &&
    /request failed: (?:429|502|503|504)\b/.test(cause.message);
let local = null;
let latestStatus = null;
let ready = false;
let lobbyTimer = 0;
let gameStarted = false;
function scheduleLobbyRefresh() {
    window.clearTimeout(lobbyTimer);
    if (gameStarted || local === null)
        return;
    lobbyTimer = window.setTimeout(() => {
        void refreshLobby()
            .catch(soloMode ? showSoloError : showError)
            .finally(() => scheduleLobbyRefresh());
    }, 500);
}
const joinUrl = (value) => {
    const url = new URL('/play/multiplayer.html', location.origin);
    url.search = location.search;
    url.hash = `join=${value.match}.${value.joinCapability ?? ''}`;
    return url.toString();
};
async function refreshLobby() {
    if (local === null)
        return;
    const capability = local.hostCapability ?? local.playerCapability;
    latestStatus = await matchStatus(local.match, capability);
    if (latestStatus.state === 'READY_TO_START' && ready) {
        await readyMatch(local.match, local.playerCapability, true);
        latestStatus = await matchStatus(local.match, capability);
    }
    const soloProgress = soloMode && latestStatus.state === 'STARTING' ?
        ` · cold MLE authority ${Math.floor((performance.now() - soloStartedAt) / 1000)}s`
            + ' · local Free baseline ~110s' : '';
    roomStatus.textContent = `Match ${local.match} · player ${local.playerSlot + 1}\n${latestStatus.memberCount}/${latestStatus.maxPlayers} joined · ${latestStatus.readyCount} ready · ${latestStatus.state}${soloProgress}`;
    readyButton.textContent = ready ? 'Not ready' : 'Ready';
    readyButton.disabled = latestStatus.memberCount !== latestStatus.maxPlayers;
    if (latestStatus.state === 'ACTIVE' && !gameStarted) {
        gameStarted = true;
        window.clearTimeout(lobbyTimer);
        await startMleGame(local, latestStatus);
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
    scheduleLobbyRefresh();
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
async function startMleGame(value, status) {
    lobby.hidden = true;
    game.dataset.active = '';
    hud.textContent = 'Loading SHA-verified Doom engine and IWAD…';
    const audio = new AudioPresenter();
    const [presentationAssets, initialInputSequence, engines] = await Promise.all([
        soloPresentationAssets ??
            Promise.all([getAsset('PLAYPAL'), getAsset('TITLEPIC')]),
        matchInputFrontier(value.match, value.playerCapability),
        createBrowserAuthorityEngines(status)
    ]);
    const [paletteAsset, titleAsset] = presentationAssets;
    const blitIndexed = createIndexedBlitter(canvas, createPalette(decodeBytes(paletteAsset.payload)));
    blitIndexed(decodeBytes(titleAsset.payload));
    const rootChainSha = await authorityRootChainSha(value.match, status.membershipEpoch);
    const mirror = new ConfirmedAuthorityMirror(engines.verifier, engines.presenter, value.playerSlot, { tic: 0, generation: 1, membershipEpoch: status.membershipEpoch,
        chainSha: rootChainSha });
    const wan = new ConfirmedWanPolicy();
    const presentations = new Map();
    let latest = { seq: 0, turn: 0, forward: 0, strafe: 0, run: 0,
        fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: '' };
    let inputSequence = initialInputSequence;
    const inputQueue = [];
    let inputPosting = false;
    let polling = false;
    let stopped = false;
    let presentedTic = 0;
    let serverTic = status.currentTic;
    let nextPresentationAt = 0;
    let presentationStarted = false;
    const paintedAt = [];
    const buttons = new Map();
    const fail = (cause) => {
        stopped = true;
        hud.className = 'error';
        hud.textContent = cause instanceof Error ? cause.message : String(cause);
    };
    const updateHud = () => {
        const elapsed = paintedAt.length > 1 ? paintedAt.at(-1) - paintedAt[0] : 0;
        const fps = elapsed > 0 ? (paintedAt.length - 1) * 1000 / elapsed : 0;
        const role = soloMode ? 'SINGLE PLAYER' :
            `${status.mode} · PLAYER ${value.playerSlot + 1}`;
        hud.textContent = `${role} · TIC ${presentedTic}`
            + ` · CONFIRMED ${mirror.frontier.tic} · SERVER ${serverTic}`
            + `\n${fps.toFixed(1)} FPS · lead ${wan.inputLeadTics}`
            + ` · playout ${wan.playoutBufferTics} · confirmed-only`;
    };
    bindInput(canvas, buttons, command => {
        latest = command;
        inputSequence += 1;
        inputQueue.push({ sequence: inputSequence, command: { ...latest }, hex: ticcmd(latest) });
        trace('input', { inputSequence, command: latest,
            targetTic: wan.inputTargetTic(mirror.frontier.tic),
            leadTics: wan.inputLeadTics });
    }, () => { }, () => { void audio.enable(); });
    canvas.addEventListener('click', () => {
        if (document.pointerLockElement !== canvas)
            void canvas.requestPointerLock();
    });
    canvas.focus();
    const postInput = () => {
        if (stopped || inputPosting || inputQueue.length === 0)
            return;
        inputPosting = true;
        const input = inputQueue[0];
        const started = performance.now();
        const targetTic = wan.inputTargetTic(Math.max(serverTic, mirror.frontier.tic));
        void reviseMatchInput(value.match, value.playerCapability, input.sequence, input.hex, targetTic).then(result => {
            const finished = performance.now();
            wan.observeRoundTrip(finished - started, finished);
            if (result.accepted !== 1 ||
                result.membershipEpoch !== mirror.frontier.membershipEpoch ||
                result.generation < mirror.frontier.generation) {
                throw new Error('multiplayer input fence changed');
            }
            inputQueue.shift();
            trace('input-effective', { inputSequence: input.sequence,
                effectiveTic: result.effectiveTic, command: input.command,
                targetTic, roundTripMs: finished - started,
                leadTics: wan.inputLeadTics });
        }).catch(cause => {
            if (transientAuthorityFailure(cause)) {
                trace('recovery-wait', { path: 'input', message: String(cause) });
            }
            else {
                fail(cause);
            }
        }).finally(() => { inputPosting = false; });
    };
    const poll = () => {
        if (stopped || polling)
            return;
        polling = true;
        const frontier = mirror.frontier;
        void pollMatchTransitions(value.match, value.playerCapability, frontier.tic, transitionHoldMs, 32).then(async (result) => {
            const batch = await decodeAuthorityBatch(result.payload, frontier);
            serverTic = Math.max(serverTic, result.currentTic, batch.committedFrontierTic);
            for (const transition of batch.transitions) {
                const presentation = await mirror.apply(transition);
                presentations.set(transition.tic, {
                    presentation, audio: transition.audio
                });
                wan.observeConfirmedDelivery(performance.now());
                trace('confirmed', { tic: transition.tic, chainSha: transition.chainSha,
                    generation: transition.generation,
                    membershipEpoch: transition.membershipEpoch });
            }
        }).catch(cause => {
            if (transientAuthorityFailure(cause)) {
                trace('recovery-wait', { path: 'transitions', message: String(cause) });
                hud.textContent = `${soloMode ? 'SINGLE PLAYER' : status.mode}`
                    + ` · TIC ${presentedTic}\nRecovering retained MLE authority…`;
            }
            else {
                fail(cause);
            }
        }).finally(() => {
            polling = false;
            // Free defaults to immediate batches. WAN-qualified deployments select
            // a bounded hold via the page URL; the database enforces both the
            // 500 ms ceiling and one outstanding poll per player.
            if (!stopped)
                window.setTimeout(poll, 20);
        });
    };
    const pump = () => {
        if (stopped)
            return;
        postInput();
        const target = wan.presentationTargetTic(mirror.frontier.tic);
        const now = performance.now();
        // Engine/IWAD verification takes about two seconds on a cold browser while
        // the authority continues at 35 Hz. Once every intervening transition has
        // been verified and applied, begin at the confirmed playout target rather
        // than replaying that cold-load backlog forever at the same 35 Hz rate.
        // This discards presentation snapshots only; it never skips mirror state.
        if (!presentationStarted && target > 0 &&
            serverTic - mirror.frontier.tic <= 2 && presentations.has(target)) {
            for (const tic of presentations.keys())
                if (tic < target)
                    presentations.delete(tic);
            presentedTic = target - 1;
            presentationStarted = true;
            trace('resync', { tic: presentedTic, reason: 'confirmed-startup' });
        }
        if (presentationStarted &&
            target - presentedTic > MAX_CONFIRMED_PRESENTATION_BACKLOG &&
            presentations.has(target)) {
            for (const tic of presentations.keys())
                if (tic < target)
                    presentations.delete(tic);
            presentedTic = target - 1;
            nextPresentationAt = now;
            trace('resync', { tic: presentedTic, reason: 'confirmed-backlog' });
        }
        if (!presentationStarted)
            return;
        const next = presentations.get(presentedTic + 1);
        if (next !== undefined && next.presentation.tic <= target &&
            now >= nextPresentationAt) {
            presentations.delete(next.presentation.tic);
            blitIndexed(next.presentation.frame);
            audio.enqueue(next.audio, fail);
            presentedTic = next.presentation.tic;
            paintedAt.push(now);
            if (paintedAt.length > 60)
                paintedAt.shift();
            nextPresentationAt = Math.max(nextPresentationAt + 1000 / 35, now);
            trace('present', { tic: presentedTic, chainSha: next.presentation.chainSha,
                leadTics: wan.inputLeadTics,
                playoutTics: wan.playoutBufferTics,
                serverTic });
            updateHud();
        }
    };
    updateHud();
    poll();
    window.setInterval(pump, 4);
}
/*
 * Historical DB-frame polling implementation removed from the production
 * module by the approved MLE role swap. Kept temporarily as commented migration
 * context until the Java-removal audit deletes the old REST endpoints.
 *
export async function startGameLegacy(value: LocalMatch, status: MatchStatus): Promise<void> {
  lobby.hidden = true;game.dataset.active = '';
  const audio = new AudioPresenter();
  const [paletteAsset, titleAsset, initial, initialInputSequence] = await Promise.all([
    getAsset('PLAYPAL'), getAsset('TITLEPIC'),
    pollMatchFrame(value.match, value.playerCapability, 0, 1000),
    matchInputFrontier(value.match, value.playerCapability)
  ]);
  const palette = createPalette(decodeBytes(paletteAsset.payload));
  const blitIndexed = createIndexedBlitter(canvas,palette);
  const title = decodeBytes(titleAsset.payload);
  blitIndexed(title);
  if (initial.payload === null) throw new Error('tic-zero POV is unavailable');
  const initialFrame = await decodePayload(initial.payload);
  if (initialFrame.tic !== 0) throw new Error('invalid multiplayer frontier');
  // Asset and tic-zero loading can take seconds on a cold generated-ORDS path
  // while a paced worker is already producing frames. Join the latest durable
  // frontier before presentation instead of replaying that startup backlog.
  if (status.workerMode === 'PACED_INPUT') {
    const refreshed = await matchStatus(value.match,value.playerCapability);
    if (refreshed.state!=='ACTIVE' ||
        refreshed.membershipEpoch!==status.membershipEpoch ||
        refreshed.generation<status.generation)
      throw new Error('multiplayer startup fence changed');
    status=refreshed;
  }

  let latest: Command = {seq: 0, turn: 0, forward: 0, strafe: 0, run: 0,
    fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: ''};
  let inputSequence = initialInputSequence;
  const paced = status.workerMode === 'PACED_INPUT';
  type InputRevision = {sequence: number; command: Command; hex: string};
  const inputQueue: InputRevision[] = [];
  const buttons = new Map<ControlName, HTMLButtonElement>();
  bindInput(canvas, buttons, command => {
    latest = command;inputSequence += 1;
    inputQueue.push({sequence: inputSequence,command: {...command},hex: ticcmd(command)});
    trace('input', {inputSequence,command});
  }, () => {}, () => {
    void audio.enable();
  });
  canvas.addEventListener('click', () => {
    if (document.pointerLockElement !== canvas) void canvas.requestPointerLock();
  });
  canvas.focus();

  let currentTic = status.currentTic;
  if (paced && currentTic>0)
    currentTic-=((currentTic-1)%PACED_KEYFRAME_TICS)+1;
  let serverTic = status.currentTic;
  let submittedTic = currentTic;
  let submitting = false;
  let pendingSubmit: {tic: number; command: Command; hex: string;
    inputs?: InputRevision[]} | null = null;
  const pollingBatches = new Set<number>();
  let pollEpoch = 0;
  let nextPollTic = currentTic + 1;
  const frameBuffer = new Map<number, Frame>();
  const frameBatchState: FrameBatchState = {previousTransport:undefined};
  let nextPresentationAt = 0;
  let presentationStarted = !paced;
  let stopped = false;
  const membershipEpoch = status.membershipEpoch;
  let generation = status.generation;
  let transportFailures = 0;
  let retryAfter = 0;
  const paintedAt: number[] = [];
  const updateHud = (): void => {
    const windowMs = paintedAt.length > 1 ? paintedAt.at(-1)! - paintedAt[0]! : 0;
    const fps = windowMs > 0 ? (paintedAt.length - 1) * 1000 / windowMs : 0;
    hud.textContent = `${status.mode} · PLAYER ${value.playerSlot + 1} · TIC ${currentTic} · LAG ${Math.max(0,serverTic-currentTic)}\n${fps.toFixed(1)} displayed FPS · click game for mouse · F/Ctrl fire · Space use`;
  };
  const fail = (cause: unknown): void => {
    stopped = true;hud.className = 'error';
    hud.textContent = cause instanceof Error ? cause.message : String(cause);
  };
  const recovered = (): void => {
    transportFailures = 0;retryAfter = 0;hud.className = '';
  };
  const retryTransport = (cause: unknown): void => {
    transportFailures += 1;
    if (transportFailures > 60) { fail(cause);return; }
    retryAfter = performance.now() + Math.min(100 * transportFailures, 1000);
    hud.className = 'muted';
    hud.textContent = `${status.mode} · PLAYER ${value.playerSlot + 1} · TIC ${currentTic}\nReconnecting to Oracle…`;
  };
  const pump = (): void => {
    if (stopped || performance.now() < retryAfter) return;
    const nextFrame = frameBuffer.get(currentTic + 1);
    if (!presentationStarted && nextFrame !== undefined &&
        frameBuffer.has(currentTic + 2)) {
      presentationStarted = true;nextPresentationAt = performance.now();
    }
    if (presentationStarted && nextFrame !== undefined &&
        performance.now() >= nextPresentationAt) {
      frameBuffer.delete(nextFrame.tic);
      blitIndexed(nextFrame.indices);
      audio.enqueue(nextFrame.audio, fail);
      currentTic = nextFrame.tic;
      const now = performance.now();
      paintedAt.push(now);
      if (paintedAt.length > 60) paintedAt.shift();
      trace('present', {tic: nextFrame.tic, frameSha: nextFrame.frameSha});
      // A reconnect begins at Oracle's current frontier. Let an older client
      // drain a deep authoritative buffer without skipping frames, then settle
      // onto the worker's exact cadence once only a small jitter reserve remains.
      nextPresentationAt = paced ? (serverTic-currentTic>2 ? now+20 :
        Math.max(nextPresentationAt + 1000 / 35,now + 20)) : now + 20;
      recovered();updateHud();
    }
    if (paced && !submitting && inputQueue.length > 0) {
      submitting = true;
      const input = inputQueue[0]!;
      void reviseMatchInput(value.match,value.playerCapability,input.sequence,input.hex)
        .then(result => {
          if (result.accepted!==1 || result.membershipEpoch!==membershipEpoch ||
              result.generation<generation) throw new Error('multiplayer input fence changed');
          generation=result.generation;inputQueue.shift();
          trace('input-effective',{inputSequence:input.sequence,
            effectiveTic:result.effectiveTic,command:input.command});recovered();
        }).catch(cause => {
          if (transientTransportFailure(cause)) retryTransport(cause);else fail(cause);
        }).finally(()=>{submitting=false;});
    }
    if (!paced && !submitting && submittedTic < currentTic + 6) {
      submitting = true;
      let request=pendingSubmit;
      if (request===null) {
        request={tic:submittedTic+1,command:{...latest},hex:ticcmd(latest)};
        const inputs=inputQueue.splice(0,4);if (inputs.length>0) request.inputs=inputs;
      }
      pendingSubmit = request;
      for (let offset = 0; offset < 4; offset += 1) {
        trace('submit', {tic: request.tic + offset, command: request.command});
      }
      const operation: Promise<{accepted:number;membershipEpoch:number;
        generation:number;inputAccepted?:number;effectiveTic?:number;
        payload?:string}> =
        request.inputs === undefined ?
        submitMatchBatch(value.match,value.playerCapability,request.tic,
          request.tic,request.hex.repeat(4)) :
        submitMatchBatchInput(value.match,value.playerCapability,request.tic,
          request.tic,request.hex.repeat(4),request.inputs[0]!.sequence,
          request.inputs.map(input=>input.hex).join(''));
      void operation.then(async result => {
          if (result.accepted !== 4 || result.generation < generation ||
              result.membershipEpoch !== membershipEpoch) {
            throw new Error('multiplayer submit fence changed');
          }
          if (result.inputAccepted!==undefined) {
            if (request.inputs===undefined ||
                result.inputAccepted!==request.inputs.length ||
                result.effectiveTic===undefined)
              throw new Error('multiplayer input fence changed');
            for (const input of request.inputs) trace('input-effective',{
              inputSequence:input.sequence,effectiveTic:result.effectiveTic,
              command:input.command});
            if (result.payload===undefined)
              throw new Error('multiplayer input frame is unavailable');
            const inputFrames=await decodeFrameBatch(result.payload);
            if (inputFrames.length<1 || inputFrames.at(-1)!.tic!==result.effectiveTic)
              throw new Error('multiplayer input frame frontier changed');
            for (const frame of inputFrames) {
              if (frame.tic>currentTic) frameBuffer.set(frame.tic,frame);
              trace('input-frame',{tic:frame.tic,frameSha:frame.frameSha});
            }
          }
          generation = result.generation;submittedTic = request.tic + 3;
          pendingSubmit = null;recovered();
        }).catch(async cause => {
          if (transientTransportFailure(cause)) { retryTransport(cause);return; }
          const refreshed = await matchStatus(value.match, value.playerCapability);
          if (refreshed.state !== 'ACTIVE' || refreshed.generation < generation ||
              refreshed.membershipEpoch !== membershipEpoch) throw cause;
          generation = refreshed.generation;
          currentTic = Math.max(currentTic, refreshed.currentTic);
          serverTic = Math.max(serverTic, refreshed.currentTic);
          submittedTic = Math.max(submittedTic, refreshed.currentTic);
          nextPollTic = currentTic + 1;frameBuffer.clear();pendingSubmit = null;
          recovered();updateHud();
        }).catch(cause => {
          if (transientTransportFailure(cause)) retryTransport(cause);
          else fail(cause);
        }).finally(() => {submitting = false;});
    }
    const pollSpan=paced?2:4;
    if (pollingBatches.size < (paced?1:2) &&
        (paced ? nextPollTic <= currentTic + 3 : nextPollTic + 3 <= submittedTic)) {
      const firstTic = nextPollTic;
      const requestEpoch = pollEpoch;
      pollingBatches.add(firstTic);nextPollTic += pollSpan;
      for (let offset = 0; offset < pollSpan; offset += 1) trace('poll', {tic: firstTic + offset});
      void pollMatchBatch(value.match, value.playerCapability,firstTic,5000,pollSpan)
        .then(async result => {
          const frames = await decodeFrameBatch(result.payload,
            paced?frameBatchState:undefined);
          if (requestEpoch!==pollEpoch) return;
          if (paced && paintedAt.length<20 && result.currentTic-currentTic>8) {
            // A cold start/reconnect may leave the browser far behind a worker
            // that never stopped. Rejoin a recent committed frontier; this
            // skips stale presentation only and never synthesizes game state.
            currentTic=Math.max(0,result.currentTic-
              ((result.currentTic-1)%PACED_KEYFRAME_TICS)-1);
            serverTic=result.currentTic;
            frameBuffer.clear();nextPollTic=currentTic+1;pollEpoch+=1;
            frameBatchState.previousTransport=undefined;
            presentationStarted=false;nextPresentationAt=0;
            trace('resync',{tic:currentTic});updateHud();return;
          }
          for (const [index, frame] of frames.entries()) {
            const tic = firstTic + index;trace('ready', {tic});
            if (frame.tic !== tic) throw new Error('multiplayer frame frontier changed');
            trace('decoded', {tic, frameSha: frame.frameSha});
            if (tic>currentTic) frameBuffer.set(tic, frame);
          }
          serverTic = Math.max(serverTic, result.currentTic);recovered();
        }).catch(async cause => {
          if (transientTransportFailure(cause)) {
            if (requestEpoch===pollEpoch) nextPollTic=Math.min(nextPollTic,firstTic);
            retryTransport(cause);
            try {
              const refreshed=await matchStatus(value.match,value.playerCapability);
              if (requestEpoch===pollEpoch && refreshed.state==='ACTIVE' &&
                  refreshed.membershipEpoch===membershipEpoch &&
                  refreshed.generation>=generation &&
                  refreshed.currentTic-firstTic>8) {
                generation=refreshed.generation;serverTic=refreshed.currentTic;
                currentTic=Math.max(0,refreshed.currentTic-
                  ((refreshed.currentTic-1)%PACED_KEYFRAME_TICS)-1);
                frameBuffer.clear();frameBatchState.previousTransport=undefined;
                nextPollTic=currentTic+1;pollEpoch+=1;
                presentationStarted=false;nextPresentationAt=0;
                trace('resync',{tic:currentTic});recovered();updateHud();
              }
            } catch (statusFailure) {
              if (!transientTransportFailure(statusFailure)) fail(statusFailure);
            }
          }
          else fail(cause);
        }).finally(() => {pollingBatches.delete(firstTic);});
    }
  };
  updateHud();window.setInterval(pump, 4);
}
*/
const hash = location.hash.slice(1);
if (soloMode) {
    createForm.hidden = true;
    joinForm.hidden = true;
    readyButton.hidden = true;
    shareWrap.hidden = true;
    lobby.hidden = true;
    game.dataset.active = '';
    hud.textContent = 'SINGLE PLAYER\nStarting a new game inside Oracle…';
    void soloPresentationAssets?.then(([paletteAsset, titleAsset]) => {
        const blit = createIndexedBlitter(canvas, createPalette(decodeBytes(paletteAsset.payload)));
        blit(decodeBytes(titleAsset.payload));
    }).catch(showSoloError);
    ready = true;
    setBusy(true);
    void retirePriorSolo().then(() => createMatch('PLAYER 1', soloSkill, 'COOP', 1)).then(async (value) => {
        const credentials = {
            match: value.match, playerCapability: value.playerCapability, playerSlot: 0
        };
        await enterLobby(credentials);
        hud.textContent = 'SINGLE PLAYER\nInitializing the retained MLE authority…';
        await readyMatch(value.match, value.playerCapability, true);
        await refreshLobby();
    }).catch(showSoloError).finally(() => setBusy(false));
}
else if (hash.startsWith('join=')) {
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
