import {newGame, pollFrame, step, submitStep, type Command} from './api.js';
import {AudioPresenter} from './audio.js';
import {createDoomCanvas, blit} from './canvas.js';
import {decodeBytes, decodePayload} from './codec.js';
import {bindInput, type ControlName} from './input.js';
import {applyPalette, createPalette} from './palette.js';
import {PresentationState} from './presentation-state.js';
import {getAsset} from './api.js';

const controlNames: readonly ControlName[] = [
  'forward', 'backward', 'turn-left', 'turn-right', 'fire',
  'use', 'automap', 'menu', 'pause', 'audio'
];

function stylesheet(): HTMLStyleElement {
  const style = document.createElement('style');
  style.textContent = `
    :root{touch-action:none;background:#000;color-scheme:dark}
    *{box-sizing:border-box}
    html,body{width:100%;height:100%;margin:0;overflow:hidden;background:#000}
    body{display:grid;place-items:center}
    [data-doom-shell]{width:100vw;height:100vh;display:grid;place-items:center}
    canvas[data-doom-canvas]{display:block;width:min(100vw,160vh);height:auto;max-width:100vw;max-height:100vh;image-rendering:pixelated;image-rendering:crisp-edges;background:#000}
    [data-doom-controls]{display:none}
    [data-doom-status]{position:fixed;left:12px;top:12px;z-index:4;padding:8px 10px;border:1px solid #7778;border-radius:6px;background:#000c;color:#eee;font:13px/1.35 system-ui;white-space:pre-line;pointer-events:none}
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

function controls(): {element: HTMLElement; buttons: Map<ControlName, HTMLButtonElement>} {
  const element = document.createElement('section');
  element.dataset.doomControls = '';
  element.setAttribute('aria-label', 'Touch controls');
  const buttons = new Map<ControlName, HTMLButtonElement>();
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
  return {element, buttons};
}

const state = new PresentationState();
const canvas = createDoomCanvas();
const shell = document.createElement('div');
shell.dataset.doomShell = '';
const touch = controls();
const status = document.createElement('div');
status.dataset.doomStatus = '';
status.textContent = 'Starting a new game inside Oracle…\nThe first frame currently takes about 10 seconds.';
shell.append(canvas, touch.element, status);
document.head.append(stylesheet());
document.body.replaceChildren(shell);

async function boot(): Promise<void> {
  const audio = new AudioPresenter();
  const game = await newGame();
  let frame = await decodePayload(game.payload);
  const paletteAsset = await getAsset('PLAYPAL');
  const palette = createPalette(decodeBytes(paletteAsset.payload));
  blit(canvas, applyPalette(frame.indices, palette));
  state.loading = false;
  state.setMode(frame.mode);
  await audio.consume(frame.audio);
  status.textContent = 'W/S move · A/D turn · Ctrl fire · Space use\n30 FPS database pipeline warming up…';
  window.setTimeout(() => { status.style.opacity = '0.35'; }, 6000);

  let latest: Command = {
    seq: 0, turn: 0, forward: 0, strafe: 0, run: 0, fire: 0, use: 0,
    weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: ''
  };
  let nextSequence = 0;
  let nextPresentation = 1;
  let submitInFlight = 0;
  let fetchInFlight = false;
  let syncInFlight = false;
  let pipelineError = false;
  let nextFetch = 1;
  let presenting = false;
  let presentationTimer = 0;
  const commandPeriodMs = 32;
  const presentationPeriodMs = 31.8;
  const submitDepth = 4;
  const presentationBuffer = 10;
  const submitted = new Set<number>();
  const retryFetch: number[] = [];
  const completed = new Map<number, typeof frame>();
  const present = async (): Promise<void> => {
    if (presenting) return;
    const next = completed.get(nextPresentation);
    if (next === undefined) return;
    presenting = true;
    completed.delete(nextPresentation);
    nextPresentation += 1;
    try {
      frame = next;
      blit(canvas, applyPalette(frame.indices, palette));
      state.setMode(frame.mode);
      await audio.consume(frame.audio);
    } finally { presenting = false; }
  };
  const startPresentation = (): void => {
    if (presentationTimer !== 0 || completed.size < presentationBuffer) return;
    status.textContent = 'W/S move · A/D turn · Ctrl fire · Space use\n30 FPS database pipeline active';
    presentationTimer = window.setInterval(() => { void present(); }, presentationPeriodMs);
  };
  // USE is now covered by the retained split-world gate. FIRE still has two
  // catalog cases (barrel recursion and player splash projectiles) that must
  // drain the pipeline and use the complete SQL oracle instead of stopping the
  // async client with a rejected SUBMIT_STEP.
  const retainedCommand = (command: Command): boolean => command.fire === 0 &&
    command.pause === 0 && command.automap === 0 && command.menu === 'NONE' &&
    command.cheat.length === 0;
  const submitTick = (): void => {
    const sequence = ++nextSequence;
    const outgoing = {...latest, seq: sequence};
    submitInFlight += 1;
    void submitStep(game.session, outgoing)
      .then(() => { submitted.add(sequence); })
      .catch(cause => {
        const error = cause instanceof Error ? cause : new Error('submit failed');
        pipelineError = true;
        status.style.opacity = '1';status.textContent = `Game pipeline stopped: ${error.message}`;
      })
      .finally(() => { submitInFlight -= 1; });
  };
  const fetchTick = (sequence: number): void => {
    fetchInFlight = true;
    void pollFrame(game.session, sequence)
      .then(payload => payload === null ? null : decodePayload(payload))
      .then(decoded => {
        if (decoded === null) retryFetch.push(sequence);
        else { completed.set(sequence, decoded);startPresentation(); }
      })
      .catch(cause => {
        pipelineError = true;const error = cause instanceof Error ? cause : new Error('fetch failed');
        status.style.opacity = '1';status.textContent = `Game pipeline stopped: ${error.message}`;
      })
      .finally(() => { fetchInFlight = false; });
  };
  const syncTick = (): void => {
    const sequence = ++nextSequence;
    const outgoing = {...latest, seq: sequence};
    syncInFlight = true;
    status.style.opacity = '1';status.textContent = 'Applying database control action…';
    void step(game.session, outgoing).then(decodePayload).then(decoded => {
      completed.set(sequence, decoded);startPresentation();nextFetch = sequence + 1;
      window.setTimeout(() => {status.style.opacity = '0.35';}, 1500);
    }).catch(cause => {
      pipelineError = true;const error = cause instanceof Error ? cause : new Error('control action failed');
      status.style.opacity = '1';status.textContent = `Game pipeline stopped: ${error.message}`;
    }).finally(() => { syncInFlight = false; });
  };
  const send = (command: Command): void => {
    latest = command;
  };
  const gesture = (): void => {
    void audio.enable();
  };
  bindInput(touch.buttons, send, () => {
    state.muted = !state.muted;
    audio.setMuted(state.muted);
  }, gesture);
  window.addEventListener('focus', () => { state.focused = true; });
  window.addEventListener('blur', () => { state.focused = false; });
  document.addEventListener('visibilitychange', () => {
    state.visible = document.visibilityState === 'visible';
  });
  let nextDispatch = performance.now() + commandPeriodMs;
  window.setInterval(() => {
    const now = performance.now();
    if (pipelineError) return;
    if (!state.visible || !state.focused) {
      nextDispatch = now + commandPeriodMs;
      return;
    }
    if (!fetchInFlight) {
      if (retryFetch.length > 0) fetchTick(retryFetch.shift()!);
      else if (nextFetch <= nextSequence && submitted.has(nextFetch)) fetchTick(nextFetch++);
    }
    if (!retainedCommand(latest)) {
      if (!syncInFlight && submitInFlight === 0 && !fetchInFlight &&
          nextFetch > nextSequence) syncTick();
      return;
    }
    const prefill = nextSequence < submitDepth;
    // The first request owns worker claim/warmup. Sending all four prefill
    // requests before that claim completes creates a harmless but noisy ORDS
    // capacity race and forces the idempotent retry path.
    if (nextSequence > 0 && prefill && !submitted.has(1)) return;
    if (syncInFlight || submitInFlight >= submitDepth ||
        nextSequence + 1 > nextPresentation + 16 ||
        (!prefill && now < nextDispatch)) return;
    submitTick();
    if (prefill) {
      if (nextSequence === submitDepth) nextDispatch = now + commandPeriodMs;
    } else {
      nextDispatch += commandPeriodMs;
    }
  }, 4);
}

void boot().catch(cause => {
  const error = cause instanceof Error ? cause : new Error('client bootstrap failed');
  status.style.opacity = '1';
  status.textContent = `Game startup failed: ${error.message}\nReturn to / for stack status, then refresh.`;
  console.error(error);
});
