import type {Command} from './api.js';

export type ControlName = 'forward' | 'backward' | 'turn-left' | 'turn-right' |
  'fire' | 'use' | 'automap' | 'menu' | 'pause' | 'audio';

type Emit = (command: Command) => void;
type AudioToggle = () => void;

const keyControls: Record<string, ControlName> = {
  KeyW: 'forward', ArrowUp: 'forward', KeyS: 'backward', ArrowDown: 'backward',
  KeyA: 'turn-left', ArrowLeft: 'turn-left', KeyD: 'turn-right', ArrowRight: 'turn-right',
  KeyF: 'fire', Space: 'use', Tab: 'automap',
  Escape: 'menu', KeyP: 'pause', KeyM: 'audio'
};
// macOS reserves repeated Control presses for host accessibility shortcuts,
// which a windowed browser cannot suppress. Keep classic Ctrl-fire elsewhere.
if (!navigator.platform.startsWith('Mac')) {
  keyControls.ControlLeft = 'fire';
  keyControls.ControlRight = 'fire';
}

const held = new Set<ControlName>();
function command(mouseTurn = 0, mouseFire = false): Command {
  return {
    seq: 0,
    turn: Number(held.has('turn-right')) - Number(held.has('turn-left')) || mouseTurn,
    forward: Number(held.has('forward')) - Number(held.has('backward')),
    strafe: 0,
    run: 0,
    fire: Number(held.has('fire') || mouseFire),
    use: Number(held.has('use')),
    weapon: 0,
    pause: Number(held.has('pause')),
    automap: Number(held.has('automap')),
    menu: held.has('menu') ? 'OPTIONS' : 'NONE',
    cheat: ''
  };
}

export function bindInput(canvas: HTMLCanvasElement,
                          controls: ReadonlyMap<ControlName, HTMLButtonElement>, emit: Emit,
                          toggleAudio: AudioToggle, gesture: () => void): void {
  let mouseTurn = 0;
  let mouseFire = false;
  let mouseTurnTimer = 0;
  const currentCommand = (): Command => command(mouseTurn, mouseFire);
  const clearMouseTurn = (): void => {
    mouseTurnTimer = 0;
    if (mouseTurn === 0) return;
    mouseTurn = 0;
    emit(currentCommand());
  };
  const update = (name: ControlName, down: boolean): void => {
    if (name === 'audio') {
      if (down) toggleAudio();
    } else if (down) {
      held.add(name);
    } else {
      held.delete(name);
    }
    emit(currentCommand());
  };

  window.addEventListener('keydown', event => {
    const name = keyControls[event.code];
    if (name === undefined) return;
    // A held key continues producing repeat events; cancel those as well as
    // the initial press so browser shortcuts do not consume game controls.
    event.preventDefault();
    if (event.repeat) return;
    gesture();
    update(name, true);
  }, {capture: true});
  window.addEventListener('keyup', event => {
    const name = keyControls[event.code];
    if (name === undefined) return;
    event.preventDefault();
    update(name, false);
  }, {capture: true});

  const release = (): void => {
    held.clear();
    mouseTurn = 0;
    mouseFire = false;
    window.clearTimeout(mouseTurnTimer);
    mouseTurnTimer = 0;
    emit(currentCommand());
  };
  window.addEventListener('blur', release);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') release();
  });

  // Pointer Lock reports relative movement even when the cursor reaches a
  // screen edge. Convert each horizontal movement burst into a command pulse
  // long enough for the 32 ms database-tic sampler to observe it.
  document.addEventListener('mousemove', event => {
    if (document.pointerLockElement !== canvas || event.movementX === 0) return;
    mouseTurn = Math.sign(event.movementX);
    window.clearTimeout(mouseTurnTimer);
    mouseTurnTimer = window.setTimeout(clearMouseTurn, 48);
    emit(currentCommand());
  });
  canvas.addEventListener('mousedown', event => {
    if (document.pointerLockElement !== canvas || event.button !== 0) return;
    event.preventDefault();
    gesture();
    mouseFire = true;
    emit(currentCommand());
  });
  document.addEventListener('mouseup', event => {
    if (event.button !== 0 || !mouseFire) return;
    event.preventDefault();
    mouseFire = false;
    emit(currentCommand());
  });
  canvas.addEventListener('contextmenu', event => {
    if (document.pointerLockElement === canvas) event.preventDefault();
  });
  document.addEventListener('pointerlockchange', () => {
    if (document.pointerLockElement === canvas) return;
    mouseTurn = 0;
    mouseFire = false;
    window.clearTimeout(mouseTurnTimer);
    mouseTurnTimer = 0;
    emit(currentCommand());
  });

  for (const [name, button] of controls) {
    const finish = (event: PointerEvent): void => {
      event.preventDefault();
      update(name, false);
    };
    button.addEventListener('pointerdown', event => {
      event.preventDefault();
      gesture();
      update(name, true);
    });
    button.addEventListener('pointerup', finish);
    button.addEventListener('pointercancel', finish);
    button.addEventListener('lostpointercapture', event => {
      if (held.has(name)) finish(event);
    });
    button.addEventListener('pointerleave', event => {
      if (event.buttons === 0 && held.has(name)) finish(event);
    });
  }
}
