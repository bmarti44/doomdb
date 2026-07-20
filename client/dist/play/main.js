import { newGame, pollFrame, step, submitStep } from './api.js';
import { AudioPresenter } from './audio.js';
import { createDoomCanvas, blit } from './canvas.js';
import { decodeBytes, decodePayload } from './codec.js';
import { bindInput } from './input.js';
import { applyPalette, createPalette } from './palette.js';
import { decodePatch, drawPatch } from './patch.js';
import { PresentationState } from './presentation-state.js';
import { getAsset } from './api.js';
const controlNames = [
    'forward', 'backward', 'turn-left', 'turn-right', 'fire',
    'use', 'automap', 'menu', 'pause', 'audio'
];
function stylesheet() {
    const style = document.createElement('style');
    style.textContent = `
    :root{touch-action:none;background:#000;color-scheme:dark}
    *{box-sizing:border-box}
    html,body{width:100%;height:100%;margin:0;overflow:hidden;background:#000}
    body{display:grid;place-items:center}
    [data-doom-shell]{position:relative;width:100vw;height:100vh;display:grid;place-items:center;background:#000}
    canvas[data-doom-canvas]{display:block;width:min(100vw,160vh);height:auto;max-width:100vw;max-height:100vh;image-rendering:pixelated;image-rendering:crisp-edges;background:#000;outline:0}
    canvas[data-doom-canvas]:focus-visible{outline:2px solid #d7b84b;outline-offset:2px}
    [data-doom-controls]{display:none}
    [data-doom-menu]{position:absolute;z-index:3;left:50%;top:55%;width:min(92vw,430px);transform:translate(-50%,-50%);padding:18px 22px;opacity:0;pointer-events:none;font:700 18px/1.2 ui-monospace,monospace;text-align:center}
    [data-doom-menu][hidden]{display:none}
    [data-doom-menu] h2{margin:0 0 14px;color:#cf3b28;font:900 24px/1 ui-monospace,monospace;text-shadow:2px 2px #3d0905}
    [data-doom-menu] button{display:block;width:100%;padding:7px 10px;border:0;background:transparent;color:#b9b9b9;font:inherit;text-align:left;cursor:pointer}
    [data-doom-menu] button[data-selected]::before{content:'▶';display:inline-block;width:24px;color:#e33b22}
    [data-doom-menu] button:not([data-selected])::before{content:'';display:inline-block;width:24px}
    [data-doom-menu] button[data-selected]{color:#fff1cf;text-shadow:1px 1px #5b140d}
    [data-doom-status]{position:fixed;left:12px;top:12px;z-index:4;padding:8px 10px;border:1px solid #7778;border-radius:6px;background:#000c;color:#eee;font:13px/1.35 system-ui;white-space:pre-line;pointer-events:none}
    [data-doom-fullscreen]{position:fixed;right:12px;top:12px;z-index:5;padding:8px 10px;border:1px solid #7778;border-radius:6px;background:#000c;color:#eee;font:13px/1.2 system-ui;cursor:pointer}
    [data-doom-coop]{position:fixed;right:12px;top:54px;z-index:5;padding:8px 10px;border:1px solid #7778;border-radius:6px;background:#000c;color:#eee;font:13px/1.2 system-ui;text-decoration:none}
    [data-doom-coop]:hover,[data-doom-coop]:focus-visible{border-color:#d7b84b;color:#fff}
    [data-doom-fullscreen]:hover,[data-doom-fullscreen]:focus-visible{border-color:#d7b84b;color:#fff}
    [data-doom-control]{position:relative;min-width:40px;min-height:40px;padding:0;border:1px solid #aaa;background:#171717;color:#fff;border-radius:7px;touch-action:none}
    [data-doom-control]::before{content:attr(data-icon);font:700 21px/1 system-ui}
    @media(max-width:900px){
      [data-doom-shell]{grid-template-rows:minmax(0,1fr) 92px;gap:4px;padding:4px}
      canvas[data-doom-canvas]{width:min(calc(100vw - 8px),calc((100vh - 104px)*1.6));max-height:calc(100vh - 104px)}
      [data-doom-controls]{display:grid;grid-template-columns:repeat(5,minmax(40px,52px));grid-template-rows:repeat(2,42px);gap:4px;align-self:end}
    }
    @media(max-width:900px) and (orientation:landscape){
      [data-doom-shell]{grid-template-columns:minmax(0,1fr) 136px;grid-template-rows:1fr;gap:4px}
      canvas[data-doom-canvas]{width:min(calc(100vw - 148px),calc((100vh - 8px)*1.6));max-height:calc(100vh - 8px)}
      [data-doom-controls]{grid-template-columns:repeat(2,64px);grid-template-rows:repeat(5,minmax(40px,1fr));align-self:center}
    }`;
    return style;
}
function controls() {
    const element = document.createElement('section');
    element.dataset.doomControls = '';
    element.setAttribute('aria-label', 'Touch controls');
    const buttons = new Map();
    const icons = ['▲', '▼', '↶', '↷', '●', '◆', '⌖', '☰', 'Ⅱ', '♪'];
    controlNames.forEach((name, index) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.doomControl = name;
        button.dataset.icon = icons[index];
        button.setAttribute('aria-label', name.replace('-', ' '));
        element.append(button);
        buttons.set(name, button);
    });
    return { element, buttons };
}
const state = new PresentationState();
const canvas = createDoomCanvas();
const fireLabel = 'F/Ctrl/left-click fire';
// macOS Dictation owns rapid double-Control presses outside fullscreen
// Keyboard Lock, so tell macOS players where the clean Ctrl capture lives.
const captureHint = navigator.platform.startsWith('Mac') ?
    ' · Fullscreen button: Ctrl capture' : '';
const shell = document.createElement('div');
shell.dataset.doomShell = '';
const touch = controls();
const menu = document.createElement('section');
menu.dataset.doomMenu = '';
menu.hidden = true;
menu.setAttribute('aria-live', 'polite');
const status = document.createElement('div');
status.dataset.doomStatus = '';
status.textContent = 'Starting a new game inside Oracle…\nThe first frame currently takes about 10 seconds.';
const fullscreen = document.createElement('button');
fullscreen.type = 'button';
fullscreen.dataset.doomFullscreen = '';
fullscreen.textContent = '⛶ Fullscreen';
fullscreen.setAttribute('aria-label', 'Enter fullscreen');
fullscreen.setAttribute('aria-pressed', 'false');
fullscreen.hidden = !document.fullscreenEnabled;
const coop = document.createElement('a');
coop.dataset.doomCoop = '';
coop.href = '/play/multiplayer';
coop.textContent = '2-player co-op';
shell.append(canvas, menu, touch.element, status, fullscreen, coop);
document.head.append(stylesheet());
document.body.replaceChildren(shell);
let pointerCapturePending = false;
const capturePointer = async () => {
    if (state.loading || !menu.hidden || pointerCapturePending ||
        document.pointerLockElement === canvas)
        return;
    pointerCapturePending = true;
    delete shell.dataset.pointerError;
    try {
        // Standard relative motion is portable across Chrome, Safari, and
        // Firefox. Requesting optional raw input first can consume the one trusted
        // activation when a browser or OS declines that mode, preventing fallback.
        await canvas.requestPointerLock();
    }
    catch (cause) {
        shell.dataset.pointerError = cause instanceof Error ? `${cause.name}: ${cause.message}` : String(cause);
        console.warn('game mouse capture was declined', cause);
    }
    finally {
        pointerCapturePending = false;
    }
};
// Run after createDoomCanvas's pointerdown focus handler. Requesting lock from
// the ancestor capture phase can produce WrongDocumentError because the canvas
// is not yet the active click target.
canvas.addEventListener('click', event => {
    if (!event.isTrusted || (event instanceof PointerEvent && event.pointerType !== 'mouse'))
        return;
    void capturePointer();
});
const keyboard = navigator.keyboard;
let keyboardCapturePending = false;
const enterFullscreen = async () => {
    if (!document.fullscreenEnabled || keyboardCapturePending ||
        document.fullscreenElement === shell)
        return;
    keyboardCapturePending = true;
    try {
        await shell.requestFullscreen({ navigationUI: 'hide' });
        if (keyboard !== undefined) {
            await keyboard.lock([
                'KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyF', 'ArrowUp', 'ArrowDown',
                'ArrowLeft', 'ArrowRight', 'ControlLeft', 'ControlRight', 'Space',
                // Escape deliberately remains browser-owned so one press releases
                // pointer lock or fullscreen. Tab is Doom's in-game menu key.
                'Tab', 'KeyM', 'KeyP', 'KeyV', 'Enter'
            ]);
            shell.dataset.keyboardCaptured = '';
        }
    }
    catch (cause) {
        console.warn('fullscreen keyboard capture was declined', cause);
    }
    finally {
        keyboardCapturePending = false;
    }
};
fullscreen.addEventListener('click', event => {
    event.preventDefault();
    if (document.fullscreenElement === shell)
        void document.exitFullscreen();
    else
        void enterFullscreen();
});
// Keep Escape a browser-level release key at every presentation stage,
// including before bindInput starts after the first game has loaded.
window.addEventListener('keydown', event => {
    if (event.code !== 'Escape' || event.repeat)
        return;
    if (document.pointerLockElement !== null)
        document.exitPointerLock();
    if (document.fullscreenElement !== null)
        void document.exitFullscreen().catch(() => { });
}, { capture: true });
document.addEventListener('fullscreenchange', () => {
    const active = document.fullscreenElement === shell;
    fullscreen.textContent = active ? 'Exit fullscreen' : '⛶ Fullscreen';
    fullscreen.setAttribute('aria-label', active ? 'Exit fullscreen' : 'Enter fullscreen');
    fullscreen.setAttribute('aria-pressed', String(active));
    if (!active) {
        keyboard?.unlock();
        delete shell.dataset.keyboardCaptured;
    }
});
document.addEventListener('pointerlockchange', () => {
    const captured = document.pointerLockElement === canvas;
    if (captured)
        shell.dataset.pointerCaptured = '';
    else
        delete shell.dataset.pointerCaptured;
    if (state.loading || !menu.hidden || restartReady)
        return;
    status.style.opacity = '1';
    status.textContent = `W/S move · A/D turn · ${fireLabel} · Space use · Tab menu · M map\n${captured ? 'Mouse captured · Esc releases' : 'Click game to capture mouse'}${captureHint}`;
    window.setTimeout(() => { if (!restartReady)
        status.style.opacity = '0.35'; }, 1800);
});
let restartReady = false;
const armRestart = (message) => {
    restartReady = true;
    status.style.opacity = '1';
    status.style.pointerEvents = 'auto';
    status.style.cursor = 'pointer';
    status.textContent = `${message}\nPress R or click this message to restart.`;
};
window.addEventListener('keydown', event => {
    if (!restartReady || (event.code !== 'KeyR' && event.code !== 'Enter'))
        return;
    event.preventDefault();
    window.location.reload();
});
status.addEventListener('click', () => {
    if (restartReady)
        window.location.reload();
});
const trace = (name, detail) => {
    window.dispatchEvent(new CustomEvent(`doom:${name}`, {
        detail: { at: performance.now(), ...detail }
    }));
};
function awaitStart(audio) {
    return new Promise(resolve => {
        const finish = (event) => {
            if (event instanceof KeyboardEvent && event.code !== 'Enter')
                return;
            event.preventDefault();
            window.removeEventListener('keydown', finish, { capture: true });
            canvas.removeEventListener('pointerdown', finish);
            // The same trusted gesture unlocks audio. Startup remains valid when a
            // browser declines audio permission; rendering must never wait on it.
            void audio.enable().catch(cause => console.error('audio enable failed', cause));
            resolve();
        };
        window.addEventListener('keydown', finish, { capture: true });
        canvas.addEventListener('pointerdown', finish);
    });
}
function chooseMenu(heading, choices, initial, allowBack, rowY, render) {
    return new Promise(resolve => {
        let selected = initial;
        let skull = 0;
        const title = document.createElement('h2');
        title.textContent = heading;
        const buttons = choices.map((choice, index) => {
            const button = document.createElement('button');
            button.type = 'button';
            button.textContent = choice.label;
            button.addEventListener('pointerenter', () => { selected = index; paint(); });
            button.addEventListener('click', event => {
                event.preventDefault();
                if (choice.value !== null)
                    finish(choice.value);
            });
            return button;
        });
        const paint = () => {
            buttons.forEach((button, index) => {
                if (index === selected)
                    button.dataset.selected = '';
                else
                    delete button.dataset.selected;
                button.setAttribute('aria-current', index === selected ? 'true' : 'false');
            });
            render(selected, skull);
        };
        const keydown = (event) => {
            if (event.code === 'ArrowUp' || event.code === 'KeyW') {
                event.preventDefault();
                selected = (selected + choices.length - 1) % choices.length;
                paint();
            }
            else if (event.code === 'ArrowDown' || event.code === 'KeyS') {
                event.preventDefault();
                selected = (selected + 1) % choices.length;
                paint();
            }
            else if (event.code === 'Enter' || event.code === 'Space') {
                event.preventDefault();
                const value = choices[selected].value;
                if (value !== null)
                    finish(value);
            }
            else if (allowBack && event.code === 'Escape') {
                event.preventDefault();
                finish(null);
            }
        };
        const pointerIndex = (event) => {
            const bounds = canvas.getBoundingClientRect();
            const logicalY = (event.clientY - bounds.top) * 200 / bounds.height;
            const relative = logicalY - rowY;
            const index = Math.floor(relative / 16);
            return relative >= 0 && relative % 16 < 15 && index >= 0 && index < choices.length ? index : -1;
        };
        const pointermove = (event) => {
            const index = pointerIndex(event);
            if (index >= 0 && index !== selected) {
                selected = index;
                paint();
            }
        };
        const pointerdown = (event) => {
            const index = pointerIndex(event);
            if (index < 0)
                return;
            event.preventDefault();
            selected = index;
            paint();
            const value = choices[selected].value;
            if (value !== null)
                finish(value);
        };
        const finish = (value) => {
            window.removeEventListener('keydown', keydown, { capture: true });
            canvas.removeEventListener('pointermove', pointermove);
            canvas.removeEventListener('pointerdown', pointerdown);
            window.clearInterval(skullTimer);
            menu.hidden = true;
            menu.replaceChildren();
            resolve(value);
        };
        menu.replaceChildren(title, ...buttons);
        menu.hidden = false;
        paint();
        const skullTimer = window.setInterval(() => { skull ^= 1; render(selected, skull); }, 230);
        window.addEventListener('keydown', keydown, { capture: true });
        canvas.addEventListener('pointermove', pointermove);
        canvas.addEventListener('pointerdown', pointerdown);
    });
}
const menuPatchNames = [
    'M_DOOM', 'M_NGAME', 'M_OPTION', 'M_LOADG', 'M_SAVEG', 'M_RDTHIS',
    'M_QUITG', 'M_NEWG', 'M_SKILL', 'M_JKILL', 'M_ROUGH', 'M_HURT',
    'M_ULTRA', 'M_NMARE', 'M_SKULL1', 'M_SKULL2'
];
async function loadMenuPatches() {
    const entries = await Promise.all(menuPatchNames.map(async (name) => {
        const asset = await getAsset(name);
        if (asset.mediaType !== 'application/x-doom-patch') {
            throw new TypeError(`menu patch ${name} has an invalid media type`);
        }
        return [name, decodePatch(asset.payload)];
    }));
    return new Map(entries);
}
function menuPatch(patches, name) {
    const patch = patches.get(name);
    if (patch === undefined)
        throw new Error(`menu patch ${name} is unavailable`);
    return patch;
}
function paintNativeMenu(base, palette, patches, placements) {
    const frame = new Uint8Array(base);
    for (const [name, x, y] of placements)
        drawPatch(frame, menuPatch(patches, name), x, y);
    blit(canvas, applyPalette(frame, palette));
}
async function chooseSkill(base, palette, patches, onSkillMenu) {
    const mainItems = [
        { label: 'NEW GAME', value: 'NEW_GAME' },
        { label: 'OPTIONS', value: null },
        { label: 'LOAD GAME', value: null },
        { label: 'SAVE GAME', value: null },
        { label: 'READ THIS', value: null },
        { label: 'QUIT GAME', value: null }
    ];
    const mainNames = [
        'M_NGAME', 'M_OPTION', 'M_LOADG', 'M_SAVEG', 'M_RDTHIS', 'M_QUITG'
    ];
    const skillChoices = [
        { label: "I'M TOO YOUNG TO DIE", value: 1 },
        { label: 'HEY, NOT TOO ROUGH', value: 2 },
        { label: 'HURT ME PLENTY', value: 3 },
        { label: 'ULTRA-VIOLENCE', value: 4 },
        { label: 'NIGHTMARE!', value: 5 }
    ];
    const skillNames = [
        'M_JKILL', 'M_ROUGH', 'M_HURT', 'M_ULTRA', 'M_NMARE'
    ];
    const renderMain = (selected, skull) => {
        const placements = [['M_DOOM', 94, 2]];
        mainNames.forEach((name, index) => placements.push([name, 97, 64 + index * 16]));
        placements.push([skull === 0 ? 'M_SKULL1' : 'M_SKULL2', 65, 59 + selected * 16]);
        paintNativeMenu(base, palette, patches, placements);
    };
    const renderSkill = (selected, skull) => {
        const placements = [['M_NEWG', 96, 14], ['M_SKILL', 54, 38]];
        skillNames.forEach((name, index) => placements.push([name, 48, 63 + index * 16]));
        placements.push([skull === 0 ? 'M_SKULL1' : 'M_SKULL2', 16, 58 + selected * 16]);
        paintNativeMenu(base, palette, patches, placements);
    };
    for (;;) {
        status.textContent = 'MAIN MENU\nArrow keys + Enter · click to select';
        const action = await chooseMenu('MAIN MENU', mainItems, 0, false, 64, renderMain);
        if (action !== 'NEW_GAME')
            continue;
        status.textContent = 'NEW GAME\nChoose a skill level · Escape goes back';
        // Selecting NEW GAME is the explicit intent signal: overlap the ~10 s
        // engine construction with the player's time on the skill menu. A title
        // or main-menu lurker still allocates nothing.
        onSkillMenu();
        const skill = await chooseMenu('CHOOSE SKILL LEVEL', skillChoices, 2, true, 63, renderSkill);
        if (skill !== null)
            return skill;
    }
}
async function boot() {
    const audio = new AudioPresenter();
    const [paletteAsset, titleAsset] = await Promise.all([
        getAsset('PLAYPAL'), getAsset('TITLEPIC')
    ]);
    const palette = createPalette(decodeBytes(paletteAsset.payload));
    const titleIndices = decodeBytes(titleAsset.payload);
    if (titleAsset.mediaType !== 'application/x-doom-indexed' ||
        titleIndices.length !== 320 * 200) {
        throw new TypeError('title screen asset is invalid');
    }
    blit(canvas, applyPalette(titleIndices, palette));
    status.textContent = 'DoomDB · Mocha Doom inside Oracle\nClick or press Enter to start';
    await awaitStart(audio);
    status.textContent = 'Loading authentic menu patches from Oracle…';
    const menuPatches = await loadMenuPatches();
    status.style.opacity = '0';
    const speculative = { current: null };
    const skill = await chooseSkill(titleIndices, palette, menuPatches, () => {
        if (speculative.current !== null)
            return;
        const promise = newGame(3);
        speculative.current = { skill: 3, promise };
        promise.catch(() => { speculative.current = null; });
    });
    // Mocha's authentic tic-0 framebuffer contains only the tiled border flat:
    // vanilla Display() does not render the player view until gametic advances.
    // Restore the last complete presentation while the retained worker starts.
    blit(canvas, applyPalette(titleIndices, palette));
    status.style.opacity = '1';
    const gameStartedAt = performance.now();
    status.textContent = 'Starting a new game inside Oracle…\nBuilding the Doom engine in the database.';
    const startTicker = window.setInterval(() => {
        const seconds = Math.round((performance.now() - gameStartedAt) / 1000);
        status.textContent = `Starting a new game inside Oracle…\nBuilding the Doom engine in the database · ${seconds}s`;
    }, 500);
    let game;
    try {
        const prepared = speculative.current;
        if (prepared !== null && prepared.skill === skill) {
            game = await prepared.promise.catch(() => newGame(skill));
        }
        else {
            if (prepared !== null)
                prepared.promise.catch(() => undefined);
            game = await newGame(skill);
        }
    }
    finally {
        window.clearInterval(startTicker);
    }
    let frame = await decodePayload(game.payload);
    const initialPainted = frame.tic > 0;
    if (initialPainted)
        blit(canvas, applyPalette(frame.indices, palette));
    trace('initial', { tic: frame.tic, painted: initialPainted, frameSha: frame.frameSha });
    state.loading = false;
    state.setMode(frame.mode);
    await audio.consume(frame.audio);
    status.textContent = `W/S move · A/D turn · ${fireLabel} · Space use · Tab menu · M map\nClick game for mouse capture${captureHint} · 30 FPS pipeline warming up…`;
    window.setTimeout(() => { status.style.opacity = '0.35'; }, 6000);
    let latest = {
        seq: 0, turn: 0, forward: 0, strafe: 0, run: 0, fire: 0, use: 0,
        weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: ''
    };
    let nextSequence = 0;
    let nextPresentation = 1;
    let submitInFlight = 0;
    let fetchInFlight = 0;
    let syncInFlight = false;
    let pipelineError = false;
    let nextFetch = 1;
    let presenting = false;
    let presentationTimer = 0;
    const commandPeriodMs = 32;
    const presentationPeriodMs = 31.8;
    const submitDepth = 4;
    const fetchDepth = 2;
    const presentationBuffer = 4;
    const submitted = new Set();
    const retryFetch = [];
    const completed = new Map();
    const present = () => {
        if (presenting)
            return false;
        const next = completed.get(nextPresentation);
        if (next === undefined)
            return false;
        presenting = true;
        const sequence = nextPresentation;
        completed.delete(sequence);
        nextPresentation += 1;
        try {
            frame = next;
            blit(canvas, applyPalette(frame.indices, palette));
            state.setMode(frame.mode);
            audio.enqueue(frame.audio, cause => console.error('audio presentation failed', cause));
            trace('present', { sequence, frameSha: frame.frameSha });
        }
        finally {
            presenting = false;
        }
        return true;
    };
    const presentationLoop = () => {
        presentationTimer = 0;
        const painted = present();
        // When a server frame misses its nominal display slot, check the local
        // decoded queue promptly. setInterval previously waited another complete
        // 31.8 ms period even when the frame arrived a millisecond later.
        presentationTimer = window.setTimeout(presentationLoop, painted ? presentationPeriodMs : 4);
    };
    const startPresentation = () => {
        if (presentationTimer !== 0 || completed.size < presentationBuffer)
            return;
        status.textContent = `W/S move · A/D turn · ${fireLabel} · Space use · Tab menu · M map\nDatabase pipeline active · ${document.pointerLockElement === canvas ? 'mouse captured' : 'click game to capture mouse'}${captureHint}`;
        presentationTimer = window.setTimeout(presentationLoop, 0);
    };
    // Live movement, USE, weapon selection, and every catalog fire mode now use
    // the correlated retained worker. Presentation-only controls remain on the
    // synchronous compatibility path.
    const retainedCommand = (command) => command.pause === 0 &&
        command.automap === 0 && command.menu === 'NONE' &&
        command.cheat.length === 0;
    const submitTick = () => {
        const sequence = ++nextSequence;
        const outgoing = { ...latest, seq: sequence };
        trace('submit', { sequence, command: outgoing });
        submitInFlight += 1;
        void submitStep(game.session, outgoing)
            .then(() => { submitted.add(sequence); })
            .catch(cause => {
            const error = cause instanceof Error ? cause : new Error('submit failed');
            pipelineError = true;
            armRestart(`Game pipeline stopped: ${error.message}`);
        })
            .finally(() => { submitInFlight -= 1; });
    };
    const fetchTick = (sequence) => {
        fetchInFlight += 1;
        void pollFrame(game.session, sequence)
            .then(payload => payload === null ? null : decodePayload(payload))
            .then(decoded => {
            if (decoded === null)
                retryFetch.push(sequence);
            else {
                completed.set(sequence, decoded);
                trace('decoded', { sequence });
                startPresentation();
            }
        })
            .catch(cause => {
            pipelineError = true;
            const error = cause instanceof Error ? cause : new Error('fetch failed');
            armRestart(`Game pipeline stopped: ${error.message}`);
        })
            .finally(() => { fetchInFlight -= 1; });
    };
    const syncTick = () => {
        const sequence = ++nextSequence;
        const outgoing = { ...latest, seq: sequence };
        syncInFlight = true;
        status.style.opacity = '1';
        status.textContent = 'Applying database control action…';
        void step(game.session, outgoing).then(decodePayload).then(decoded => {
            completed.set(sequence, decoded);
            startPresentation();
            nextFetch = sequence + 1;
            window.setTimeout(() => { status.style.opacity = '0.35'; }, 1500);
        }).catch(cause => {
            pipelineError = true;
            const error = cause instanceof Error ? cause : new Error('control action failed');
            armRestart(`Game pipeline stopped: ${error.message}`);
        }).finally(() => { syncInFlight = false; });
    };
    const send = (command) => {
        latest = command;
        trace('input', { command });
    };
    const gesture = () => {
        void audio.enable();
    };
    bindInput(canvas, touch.buttons, send, () => {
        state.muted = !state.muted;
        audio.setMuted(state.muted);
    }, gesture);
    document.addEventListener('visibilitychange', () => {
        state.visible = document.visibilityState === 'visible';
    });
    let nextDispatch = performance.now() + commandPeriodMs;
    window.setInterval(() => {
        const now = performance.now();
        if (pipelineError)
            return;
        // Page focus is not a reliable lifecycle signal: Chrome can load the game
        // while the address bar, DevTools, or another window owns focus and never
        // emit a balancing window focus event. Pause only genuinely hidden tabs so
        // a visible game can never freeze forever on its initial frame.
        if (!state.visible) {
            nextDispatch = now + commandPeriodMs;
            return;
        }
        while (fetchInFlight < fetchDepth) {
            if (retryFetch.length > 0)
                fetchTick(retryFetch.shift());
            else if (nextFetch <= nextSequence && submitted.has(nextFetch))
                fetchTick(nextFetch++);
            else
                break;
        }
        if (!retainedCommand(latest)) {
            if (!syncInFlight && submitInFlight === 0 && fetchInFlight === 0 &&
                nextFetch > nextSequence)
                syncTick();
            return;
        }
        const prefill = nextSequence < submitDepth;
        // The first request owns worker claim/warmup. Sending all four prefill
        // requests before that claim completes creates a harmless but noisy ORDS
        // capacity race and forces the idempotent retry path.
        if (nextSequence > 0 && prefill && !submitted.has(1))
            return;
        if (syncInFlight || submitInFlight >= submitDepth ||
            nextSequence + 1 > nextPresentation + 4 ||
            (!prefill && now < nextDispatch))
            return;
        submitTick();
        if (prefill) {
            if (nextSequence === submitDepth)
                nextDispatch = now + commandPeriodMs;
        }
        else {
            nextDispatch += commandPeriodMs;
        }
    }, 4);
}
void boot().catch(cause => {
    const error = cause instanceof Error ? cause : new Error('client bootstrap failed');
    armRestart(`Game startup failed: ${error.message}`);
    console.error(error);
});
