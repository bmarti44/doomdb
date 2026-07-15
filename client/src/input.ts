import type {Command} from './api.js';

export type ControlName = 'forward' | 'backward' | 'turn-left' | 'turn-right' |
  'fire' | 'use' | 'automap' | 'menu' | 'pause' | 'audio';

type Emit = (command: Command) => void;
type AudioToggle = () => void;

const keyControls: Readonly<Record<string, ControlName>> = {
  KeyW: 'forward', ArrowUp: 'forward', KeyS: 'backward', ArrowDown: 'backward',
  KeyA: 'turn-left', ArrowLeft: 'turn-left', KeyD: 'turn-right', ArrowRight: 'turn-right',
  ControlLeft: 'fire', Space: 'use', Tab: 'automap', Escape: 'menu', KeyP: 'pause', KeyM: 'audio'
};

const held = new Set<ControlName>();
function command(): Command {
  return {
    seq: 0,
    turn: Number(held.has('turn-right')) - Number(held.has('turn-left')),
    forward: Number(held.has('forward')) - Number(held.has('backward')),
    strafe: 0,
    run: 0,
    fire: Number(held.has('fire')),
    use: Number(held.has('use')),
    weapon: 0,
    pause: Number(held.has('pause')),
    automap: Number(held.has('automap')),
    menu: held.has('menu') ? 'OPTIONS' : 'NONE',
    cheat: ''
  };
}

export function bindInput(controls: ReadonlyMap<ControlName, HTMLButtonElement>, emit: Emit,
                          toggleAudio: AudioToggle, gesture: () => void): void {
  const update = (name: ControlName, down: boolean): void => {
    if (name === 'audio') {
      if (down) toggleAudio();
    } else if (down) {
      held.add(name);
    } else {
      held.delete(name);
    }
    emit(command());
  };

  window.addEventListener('keydown', event => {
    const name = keyControls[event.code];
    if (name === undefined || event.repeat) return;
    event.preventDefault();
    gesture();
    update(name, true);
  });
  window.addEventListener('keyup', event => {
    const name = keyControls[event.code];
    if (name === undefined) return;
    event.preventDefault();
    update(name, false);
  });

  const release = (): void => {
    held.clear();
    emit(command());
  };
  window.addEventListener('blur', release);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') release();
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
