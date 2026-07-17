import {newGame, step, type Command} from './api.js';
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
shell.append(canvas, touch.element);
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

  let latest: Command = {
    seq: 0, turn: 0, forward: 0, strafe: 0, run: 0, fire: 0, use: 0,
    weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: ''
  };
  let nextSequence = 0;
  let nextPresentation = 1;
  let inFlight = 0;
  let presenting = false;
  let presentationTimer = 0;
  const framePeriodMs = 32;
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
    if (presentationTimer !== 0 || completed.size < 6) return;
    presentationTimer = window.setInterval(() => { void present(); }, framePeriodMs);
  };
  const tick = (): void => {
    const sequence = ++nextSequence;
    const outgoing = {...latest, seq: sequence};
    inFlight += 1;
    void step(game.session, outgoing)
      .then(decodePayload)
      .then(decoded => { completed.set(sequence, decoded); startPresentation(); })
      .finally(() => { inFlight -= 1; });
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
  let nextDispatch = performance.now() + framePeriodMs;
  window.setInterval(() => {
    const now = performance.now();
    if (!state.visible || !state.focused) {
      nextDispatch = now + framePeriodMs;
      return;
    }
    if (now < nextDispatch || inFlight >= 3) return;
    tick();
    nextDispatch += framePeriodMs;
  }, 4);
}

void boot().catch(cause => {
  const error = cause instanceof Error ? cause : new Error('client bootstrap failed');
  queueMicrotask(() => { throw error; });
});
