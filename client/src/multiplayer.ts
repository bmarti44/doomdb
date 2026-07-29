import {
  createMatch, getAsset, joinMatch, leaveMatch, leaveMatchOnUnload, matchStatus,
  exchangeMatchPixelBatch,matchInputFrontier,
  matchCheckpoint,pollMatchTransitions,
  readyMatch,reviseMatchInput,touchMatchPresence,
  MatchCapacityError, MatchUnavailableError,
  type Command, type MatchCredentials, type MatchStatus
} from './api.js';

import {
  createColumnMajorIndexedPaletteBlitter, createDoomCanvas,
  createIndexedBlitter
} from './canvas.js';
import {decodeBytes} from './codec.js';
import {bindInput, type ControlName} from './input.js';
import {createPalette,createPaletteSet} from './palette.js';
import {decodeDatabasePixelTransport,nextDatabaseFrameTic}
  from './pixel-batch.js';
import type {DatabasePixelFrame} from './pixel-batch.js';
import type {ConfirmedPresentation} from './authority-mirror.js';
import {
  ConfirmedWanPolicy,confirmedBatchPlayoutDecision,confirmedPlayoutDecision
}
  from './authority-wan.js';

type LocalMatch = {
  match: string;
  playerCapability: string;
  playerSlot: number;
  hostCapability?: string;
  joinCapability?: string;
};

// Ordinary internet stalls are drained from the already-confirmed queue at
// the bounded 2x playout rate. Visible clients never discard presentation
// snapshots; hidden tabs use the explicit checkpoint-resync path instead.
const HIDDEN_CHECKPOINT_THRESHOLD_MS = 5_000;
const HIDDEN_POLL_LEASE_RELEASE_MS = 1_500;
const soloMode = document.body.hasAttribute('data-doom-solo');
const soloStartedAt = soloMode ? performance.now() : 0;
const launchParameters = new URLSearchParams(
  location.search.length > 1 ? location.search : location.hash.slice(1));
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
  [data-solo-modes]{position:fixed;right:12px;top:12px;z-index:4;width:150px;
    padding:10px;background:#080808e8;border:1px solid #7778}
  [data-solo-modes] strong,[data-solo-modes] small{display:block}
  [data-solo-modes] small{color:#aaa;margin:4px 0 8px}
  [data-solo-modes] button{display:block;width:100%;margin-top:6px}
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
    <button data-cancel-queue type="button" hidden>Cancel admission wait</button>
    <p data-message class="muted">Create a match, or open a private join link from the host.</p>
  </section>
  <section data-game><div data-hud>Waiting for match…</div></section>
  ${soloMode ? `<aside data-solo-modes>
    <strong>Private single-player</strong>
    <small>The neutral lockstep peer cannot be joined.</small>
    <button type="button" data-switch-mode="COOP">Start co-op</button>
    <button type="button" data-switch-mode="DEATHMATCH">Start deathmatch</button>
  </aside>` : ''}
  <p>${soloMode ? '' : '<a href="./">Single-player</a> · '}<a href="../">Status dashboard</a></p>`;
document.body.replaceChildren(main);
if (!soloMode && (requestedMode === 'COOP' || requestedMode === 'DEATHMATCH')) {
  const mode = main.querySelector<HTMLSelectElement>('select[name="mode"]');
  if (mode !== null) mode.value = requestedMode;
}

const lobby = main.querySelector<HTMLElement>('[data-lobby]')!;
const createForm = main.querySelector<HTMLFormElement>('[data-create]')!;
const joinForm = main.querySelector<HTMLFormElement>('[data-join]')!;
const room = main.querySelector<HTMLElement>('[data-room]')!;
const roomStatus = main.querySelector<HTMLElement>('[data-room-status]')!;
const message = main.querySelector<HTMLElement>('[data-message]')!;
const readyButton = main.querySelector<HTMLButtonElement>('[data-ready]')!;
const cancelQueueButton =
  main.querySelector<HTMLButtonElement>('[data-cancel-queue]')!;
const shareWrap = main.querySelector<HTMLElement>('[data-share-wrap]')!;
const shareInput = main.querySelector<HTMLInputElement>('[data-share]')!;
const copyButton = main.querySelector<HTMLButtonElement>('[data-copy]')!;
const game = main.querySelector<HTMLElement>('[data-game]')!;
const hud = main.querySelector<HTMLElement>('[data-hud]')!;
const canvas = createDoomCanvas();
game.prepend(canvas);
const soloPresentationAssets = soloMode ?
  Promise.all([getAsset('PLAYPAL_ALL'),getAsset('TITLEPIC')]) : null;

const trace = (name: string, detail: object): void => {
  window.dispatchEvent(new CustomEvent(`doom:multiplayer-${name}`, {
    detail: {at: performance.now(), ...detail}
  }));
};

const storageKey = (match: string): string => `doomdb.match.${match}`;
const soloCurrentKey = 'doomdb.solo.current';
const matchStorage = soloMode ? localStorage : sessionStorage;
const saveLocal = (value: LocalMatch): void => {
  matchStorage.setItem(storageKey(value.match), JSON.stringify(value));
  if (soloMode) matchStorage.setItem(soloCurrentKey,value.match);
};
const loadLocalFrom = (store: Storage,match: string): LocalMatch | null => {
  try {
    const value = JSON.parse(store.getItem(storageKey(match)) ?? 'null') as unknown;
    if (typeof value !== 'object' || value === null) return null;
    const candidate = value as Partial<LocalMatch>;
    if (candidate.match !== match || !/^[0-9a-f]{64}$/.test(candidate.playerCapability ?? '') ||
        (candidate.playerSlot !== 0 && candidate.playerSlot !== 1)) return null;
    return candidate as LocalMatch;
  } catch { return null; }
};
const loadLocal = (match: string): LocalMatch | null =>
  loadLocalFrom(matchStorage,match) ??
  (soloMode ? loadLocalFrom(sessionStorage,match) : null);

const retirePriorSolo = async (): Promise<void> => {
  const matches = new Set<string>();
  const stores = [localStorage,sessionStorage];
  for (const store of stores) {
    const current = store.getItem(soloCurrentKey);
    if (current !== null) matches.add(current);
  }
  // Migration fallback for solo credentials saved before the explicit pointer
  // existed. Multiplayer hosts retain host/join capabilities; the solo host
  // deliberately stores neither, so this cannot retire a co-op lobby.
  for (const store of stores) {
    for (let index = 0; index < store.length; index++) {
      const key = store.key(index);
      if (key?.startsWith('doomdb.match.')) {
        const match = key.slice('doomdb.match.'.length);
        const candidate = loadLocalFrom(store,match);
        if (candidate?.playerSlot === 0 &&
            candidate.hostCapability === undefined &&
            candidate.joinCapability === undefined) matches.add(match);
      }
    }
  }
  // Notify any live owner before retiring its database match. Storage events
  // reach another tab immediately, aborting its long poll before LEAVE_MATCH
  // changes the authoritative match to a terminal state.
  for (const store of stores) store.removeItem(soloCurrentKey);
  for (const match of matches) {
    const prior = loadLocal(match);
    try {
      if (prior !== null && prior.playerSlot === 0) {
        await leaveMatch(prior.match,prior.playerCapability);
      }
    } catch {
      // Expired/already-finished credentials are already retired. Any real
      // remaining capacity conflict is still rejected by CREATE_MATCH.
    } finally {
      for (const store of stores) store.removeItem(storageKey(match));
    }
  }
};

const setBusy = (busy: boolean): void => {
  for (const button of createForm.querySelectorAll<HTMLButtonElement>('button')) button.disabled = busy;
  for (const button of joinForm.querySelectorAll<HTMLButtonElement>('button')) button.disabled = busy;
  copyButton.disabled = busy;
  readyButton.disabled = busy || latestStatus === null ||
    latestStatus.memberCount !== latestStatus.maxPlayers;
};
const showError = (cause: unknown): void => {
  message.className = 'error';
  message.textContent = cause instanceof Error ? cause.message : String(cause);
  setBusy(false);
};
const showSoloError = (cause: unknown): void => {
  hud.className = 'error';
  hud.textContent = `SINGLE PLAYER\n${
    cause instanceof Error ? cause.message : String(cause)}`;
  setBusy(false);
};
const transientAuthorityFailure = (cause: unknown): boolean =>
  cause instanceof MatchCapacityError ||
  cause instanceof Error &&
    /request failed: (?:429|502|503|504|555)\b/.test(cause.message);

let local: LocalMatch | null = null;
let latestStatus: MatchStatus | null = null;
let ready = false;
let lobbyTimer = 0;
let lobbyDelay = 500;
let priorLobbyState = '';
let gameStarted = false;
let admissionController: AbortController | null = null;
let unloadLeaveSent = false;

const releaseLocalMatchOnUnload = (): void => {
  admissionController?.abort();
  if (unloadLeaveSent || local === null) return;
  unloadLeaveSent = true;
  const leaving = local;
  local = null;
  for (const store of [localStorage,sessionStorage]) {
    store.removeItem(storageKey(leaving.match));
    if (store.getItem(soloCurrentKey) === leaving.match) {
      store.removeItem(soloCurrentKey);
    }
  }
  leaveMatchOnUnload(leaving.match,leaving.playerCapability);
};

for (const button of main.querySelectorAll<HTMLButtonElement>('[data-switch-mode]')) {
  button.addEventListener('click',() => {
    const mode=button.dataset.switchMode;
    if ((mode!=='COOP'&&mode!=='DEATHMATCH')||local===null) return;
    for (const candidate of main.querySelectorAll<HTMLButtonElement>(
      '[data-switch-mode]')) candidate.disabled=true;
    const prior=local;
    // Signal any duplicate solo tab before ending its authority. Release the
    // match first so Free's single-game slot is available to the lobby below.
    for (const store of [localStorage,sessionStorage]) {
      store.removeItem(soloCurrentKey);
    }
    void leaveMatch(prior.match,prior.playerCapability).then(() => {
      for (const store of [localStorage,sessionStorage]) {
        store.removeItem(storageKey(prior.match));
      }
      location.assign(`./multiplayer.html?mode=${mode}`);
    }).catch(cause => {
      for (const candidate of main.querySelectorAll<HTMLButtonElement>(
        '[data-switch-mode]')) candidate.disabled=false;
      showSoloError(cause);
    });
  });
}

const admissionDelay = (milliseconds: number, signal: AbortSignal):
    Promise<void> => new Promise((resolve,reject) => {
  const timer = window.setTimeout(resolve,milliseconds);
  signal.addEventListener('abort',() => {
    window.clearTimeout(timer);
    reject(new DOMException('Admission wait cancelled','AbortError'));
  },{once:true});
});

async function queuedCreateMatch(
    displayName: string,skill: number,mode: 'COOP' | 'DEATHMATCH',
    maxPlayers: number): Promise<MatchCredentials> {
  admissionController?.abort();
  const controller = new AbortController();
  admissionController = controller;
  cancelQueueButton.hidden = soloMode;
  let delayMs = 500;
  let queuedAt = 0;
  try {
    for (;;) {
      try {
        return await createMatch(
          displayName,skill,mode,maxPlayers,controller.signal);
      } catch (cause) {
        if (!(cause instanceof MatchCapacityError)) throw cause;
        if (queuedAt === 0) queuedAt = performance.now();
        const elapsed = Math.floor((performance.now()-queuedAt)/1000);
        const queueText = `Waiting for the next Oracle game slot… ${elapsed}s`;
        if (soloMode) {
          hud.className = '';
          hud.textContent = `SINGLE PLAYER\n${queueText}\n`
            + 'Local Oracle Free runs one authoritative game at a time.';
        } else {
          message.className = 'muted';
          message.textContent = queueText;
        }
        trace('admission-queued',{elapsed,delayMs});
        await admissionDelay(delayMs,controller.signal);
        delayMs = delayMs < 2_000 ? Math.min(2_000,delayMs*2) : 5_000;
      }
    }
  } finally {
    if (admissionController===controller) admissionController=null;
    cancelQueueButton.hidden = true;
  }
}

cancelQueueButton.addEventListener('click',() => {
  admissionController?.abort();
  message.className = 'muted';
  message.textContent = 'Admission wait cancelled.';
  setBusy(false);
});
// pagehide is the primary lifecycle signal; beforeunload covers engines that
// omit it during a hard refresh/window close. The idempotent guard ensures the
// authenticated LEAVE_MATCH request is queued only once.
window.addEventListener('pagehide',releaseLocalMatchOnUnload,{once:true});
window.addEventListener('beforeunload',releaseLocalMatchOnUnload,{once:true});

function scheduleLobbyRefresh(): void {
  window.clearTimeout(lobbyTimer);
  if (gameStarted || local === null) return;
  lobbyTimer = window.setTimeout(() => {
    void refreshLobby()
      .catch(soloMode ? showSoloError : showError)
      .finally(() => scheduleLobbyRefresh());
  }, lobbyDelay);
}

const joinUrl = (value: LocalMatch): string => {
  const url = new URL('./multiplayer.html', location.href);
  url.search = location.search;
  url.hash = `join=${value.match}.${value.joinCapability ?? ''}`;
  return url.toString();
};

async function refreshLobby(): Promise<void> {
  if (local === null) return;
  const capability = local.hostCapability ?? local.playerCapability;
  latestStatus = await matchStatus(local.match, capability);
  if (latestStatus.state==='READY_TO_START' && ready) {
    await readyMatch(local.match,local.playerCapability,true);
    latestStatus=await matchStatus(local.match,capability);
  }
  const startupPhase = latestStatus.recoveryStatus === 'WARMING'
    ? 'deploy-time MLE prewarm' : 'warm authority assignment';
  const soloProgress = soloMode && latestStatus.state === 'STARTING' ?
    ` · ${startupPhase} ${Math.floor((performance.now()-soloStartedAt)/1000)}s`
      + ' · local Free deploy warmup ~120s; measured New Game p95 3.44s afterward' : '';
  const stateKey = `${latestStatus.state}|${latestStatus.memberCount}|${latestStatus.readyCount}|${latestStatus.recoveryStatus}`;
  lobbyDelay = stateKey === priorLobbyState ?
    (lobbyDelay < 2000 ? Math.min(2000,lobbyDelay*2) : 5000) : 500;
  priorLobbyState = stateKey;
  roomStatus.textContent = `Match ${local.match} · player ${local.playerSlot + 1}\n${latestStatus.memberCount}/${latestStatus.maxPlayers} joined · ${latestStatus.readyCount} ready · ${latestStatus.state} · recovery ${latestStatus.recoveryStatus}${soloProgress}`;
  if (soloMode && latestStatus.state === 'STARTING') {
    hud.className = '';
    hud.textContent = `SINGLE PLAYER\n${startupPhase}…\n${Math.floor((performance.now()-soloStartedAt)/1000)}s elapsed · recovery ${latestStatus.recoveryStatus}`;
  }
  readyButton.textContent = ready ? 'Not ready' : 'Ready';
  readyButton.disabled = latestStatus.memberCount !== latestStatus.maxPlayers;
  if (latestStatus.state === 'ACTIVE' && !gameStarted) {
    gameStarted = true;
    window.clearTimeout(lobbyTimer);
    await startDatabaseFrameGame(local, latestStatus);
  }
}

async function enterLobby(value: LocalMatch): Promise<void> {
  local = value;saveLocal(value);
  history.replaceState(null, '', `#resume=${value.match}`);
  createForm.hidden = true;joinForm.hidden = true;room.hidden = false;
  message.textContent = 'Capabilities remain only in this browser session.';
  if (value.joinCapability !== undefined) {
    shareInput.value = joinUrl(value);shareWrap.hidden = false;
  }
  await refreshLobby();
  scheduleLobbyRefresh();
}

createForm.addEventListener('submit', event => {
  event.preventDefault();setBusy(true);
  const data = new FormData(createForm);
  const mode = data.get('mode') === 'DEATHMATCH' ? 'DEATHMATCH' : 'COOP';
  void queuedCreateMatch(
    String(data.get('name')), Number(data.get('skill')), mode,2)
    .then(value => enterLobby({...value, playerSlot: 0}))
    .catch(showError).finally(() => setBusy(false));
});
joinForm.addEventListener('submit', event => {
  event.preventDefault();setBusy(true);
  const data = new FormData(joinForm);
  const match = String(data.get('match')).toLowerCase();
  const prior = loadLocal(match);
  void joinMatch(match, String(data.get('join')).toLowerCase(),
    String(data.get('name')), prior?.playerCapability ?? null)
    .then(value => enterLobby({match, ...value}))
    .catch(showError).finally(() => setBusy(false));
});
readyButton.addEventListener('click', () => {
  if (local === null) return;
  setBusy(true);ready = !ready;
  void readyMatch(local.match, local.playerCapability, ready)
    .then(() => refreshLobby()).catch(cause => {ready = !ready;showError(cause);})
    .finally(() => setBusy(false));
});
copyButton.addEventListener('click', () => {
  void navigator.clipboard.writeText(shareInput.value).then(() => {
    copyButton.textContent = 'Copied';window.setTimeout(() => {copyButton.textContent = 'Copy private join link';}, 1200);
  }).catch(showError);
});

function signedByte(value: number): number {
  return Math.max(-127, Math.min(127, Math.trunc(value)));
}
function ticcmd(command: Command): string {
  const bytes = new Uint8Array(8);
  bytes[0] = signedByte(Math.abs(command.forward) > 1 ? command.forward : command.forward * (command.run ? 50 : 25));
  bytes[1] = signedByte(Math.abs(command.strafe) > 1 ? command.strafe : command.strafe * (command.run ? 40 : 24));
  const turn = command.turn === 0 ? 0 : -Math.sign(command.turn) *
    (Math.abs(command.turn) > 1 ? Math.abs(command.turn) * 256 : (command.run ? 1280 : 320));
  new DataView(bytes.buffer).setInt16(2, turn, false);
  let buttons = (command.fire ? 1 : 0) | (command.use ? 2 : 0);
  if (command.weapon > 0) buttons |= 4 | ((command.weapon - 1) << 3);
  bytes[7] = buttons;
  return Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
}

async function startDatabaseFrameGame(
    value: LocalMatch, status: MatchStatus): Promise<void> {
  lobby.hidden = true;game.dataset.active = '';
  hud.textContent = 'Loading the database framebuffer stream…';
  const [presentationAssets, initialInputSequence] = await Promise.all([
    soloPresentationAssets ??
      Promise.all([getAsset('PLAYPAL_ALL'),getAsset('TITLEPIC')]),
    matchInputFrontier(value.match,value.playerCapability)
  ]);
  const [paletteAsset,titleAsset] = presentationAssets;
  const palettes=createPaletteSet(decodeBytes(paletteAsset.payload));
  const basePalette=createPalette(palettes.subarray(0,256*3));
  const blitTitle = createIndexedBlitter(canvas,basePalette);
  const blitDatabaseFrame =
    createColumnMajorIndexedPaletteBlitter(canvas,palettes);
  blitTitle(decodeBytes(titleAsset.payload));

  let latest:Command={seq:0,turn:0,forward:0,strafe:0,run:0,fire:0,use:0,
    weapon:0,pause:0,automap:0,menu:'NONE',cheat:''};
  let inputSequence=initialInputSequence;
  let retryInput:{
    sequence:number;hex:string;targetTic:number;command:Command
  }|null=null;
  let pendingInput:{
    sequence:number;hex:string;targetTic:number;command:Command
  }|null=null;
  let stopped=false;
  let suspended=document.hidden;
  let hiddenAt=suspended?performance.now():0;
  let serverTic=status.currentTic;
  let presentedTic=-1;
  let transportTic=-1;
  let membershipEpoch=status.membershipEpoch;
  let generation=status.generation;
  let nextFrameAt=0;
  let playoutStarted=false;
  let playoutMode:'ACCELERATE'|'FREE'|'DECELERATE'='FREE';
  let starvationActive=false;
  let inputCatchupThroughTic=-1;
  let lastEffectiveInputHex:string|null=null;
  let pixelPollEpoch=0;
  let lastFrameBatchAt=0;
  let transportEstablished=false;
  let urgentPixelInput=false;
  let inputPostInFlight=false;
  let presenceInFlight=false;
  // Six confirmed frames cover the compressed, contention-free OCI poll
  // tail. Input response catches up by accelerating already-confirmed frames;
  // it never deletes or predicts presentation state.
  const wan=new ConfirmedWanPolicy(6,6);
  // A real input transition may time-compress already-confirmed frames down
  // to two frames of reserve. With native 35-Hz database publication the
  // reserve refills without dropping, predicting, or reordering any frame.
  // Input catch-up may spend part of the confirmed reserve, but two frames
  // did not cover an ordinary 40-60 ms managed-ORDS tail after HUD payloads
  // were enabled. Retain three exact database frames before accelerating;
  // four crossed the 250-ms visual input gate on the same OCI workload.
  const pixelInputCatchupFloor=3;
  let activePixelInputCatchupFloor=pixelInputCatchupFloor;
  const pixelInputLeadTics=1;
  const paintedAt:number[]=[];
  const frames=new Map<number,DatabasePixelFrame>();
  const pixelPollInFlight=new Set<number>();
  const arrivedTransportTics=new Set<number>();
  const pixelPollLegs=1;
  // The Always Free PDB has one guaranteed API execution lane beside the
  // retained worker. An immediate request after every 1-2 frame response
  // creates an ORDS/session convoy across two browsers. Let another native
  // tic accrue after a successful steady-state response so each crossing
  // amortizes more frames while the confirmed playout reserve is spent.
  const pixelPollBatchDelayMs=35;
  const buttons=new Map<ControlName,HTMLButtonElement>();
  let schedulePixelPolls=(_delayMs=0):void=>{};
  const fail=(cause:unknown):void=>{
    stopped=true;
    hud.className='error';
    hud.textContent=cause instanceof Error?cause.message:String(cause);
  };
  const touchPresence=():void=>{
    if(stopped||suspended||presenceInFlight)return;
    presenceInFlight=true;
    void touchMatchPresence(value.match,value.playerCapability)
      .then(result=>{
        if(stopped||suspended)return;
        if(result.membershipEpoch!==membershipEpoch
            ||result.generation<generation) {
          throw new Error('database-frame presence fence changed');
        }
        if(result.generation>generation) {
          generation=result.generation;
          resetPixelTransport();
        }
      }).catch(cause=>{
        if(stopped||suspended)return;
        if(!transientAuthorityFailure(cause))fail(cause);
      }).finally(()=>{presenceInFlight=false;});
  };
  const updateHud=():void=>{
    const elapsed=paintedAt.length>1?paintedAt.at(-1)!-paintedAt[0]!:0;
    const fps=elapsed>0?(paintedAt.length-1)*1000/elapsed:0;
    const role=soloMode?'SINGLE PLAYER':`${status.mode} · PLAYER ${value.playerSlot+1}`;
    hud.textContent=`${role} · DB FRAME ${presentedTic} · SERVER ${serverTic}`
      + `\n${fps.toFixed(1)} FPS · database pixels · buffer ${frames.size}`
      + `/${wan.playoutBufferTics} · canvas copy only`;
  };
  const queueInput=(command:Command):void=>{
    const inputHex=ticcmd(command);
    const changed=inputHex!==ticcmd(latest);
    latest=command;
    // Coalesce UI samples that have not started an HTTP post without
    // consuming another idempotent sequence. Forward+turn key events commonly
    // arrive in the same browser task; replacing N with N+1 here creates a
    // permanent hole that the authoritative API correctly refuses.
    const sequence=pendingInput?.sequence??inputSequence+1;
    if(pendingInput===null)inputSequence=sequence;
    pendingInput={sequence,hex:inputHex,
      targetTic:serverTic+pixelInputLeadTics,command:{...latest}};
    trace('input',{inputSequence:sequence,command:latest,
      targetTic:pendingInput.targetTic,source:'database-frame-client'});
    if(changed) {
      urgentPixelInput=true;
      schedulePixelPolls(0);
    }
  };
  bindInput(canvas,buttons,queueInput,()=>{},()=>{});
  queueInput(latest);
  canvas.addEventListener('click',()=>{
    if(document.pointerLockElement!==canvas)void canvas.requestPointerLock();
  });
  canvas.focus();

  // Genuine input changes use the compact revision endpoint. Folding input
  // into an already-running framebuffer exchange made controls wait behind
  // BLOB selection/compression; this remains serialized per player and never
  // emits unchanged keepalives.
  const postInput=():void=>{
    if(stopped||suspended||inputPostInFlight)return;
    const input=retryInput??pendingInput;
    if(input===null)return;
    if(retryInput!==null)retryInput=null;
    else pendingInput=null;
    inputPostInFlight=true;
    let retryDelayMs=0;
    const started=performance.now();
    void reviseMatchInput(
      value.match,value.playerCapability,input.sequence,input.hex,input.targetTic)
      .then(result=>{
        if(stopped||suspended)return;
        const finished=performance.now();
        if(result.accepted!==1
            ||result.membershipEpoch!==membershipEpoch
            ||result.generation<generation) {
          throw new Error('database-frame input fence changed');
        }
        if(result.generation>generation) {
          generation=result.generation;
          resetPixelTransport();
        }
        trace('input-effective',{inputSequence:input.sequence,
          effectiveTic:result.effectiveTic,command:input.command,
          targetTic:input.targetTic,roundTripMs:finished-started,
          source:'database-frame-client'});
        const changedInput=input.hex!==lastEffectiveInputHex;
        lastEffectiveInputHex=input.hex;
        if(playoutStarted&&changedInput) {
          inputCatchupThroughTic=Math.max(
            inputCatchupThroughTic,result.effectiveTic);
          // A control response that already spent most of the 250-ms visual
          // budget may consume one additional *confirmed* reserve frame.
          // Normal inputs retain the measured three-frame cadence floor.
          activePixelInputCatchupFloor=finished-started>80
            ? pixelInputCatchupFloor-1
            : pixelInputCatchupFloor;
        }
        urgentPixelInput=true;
        schedulePixelPolls(0);
      }).catch(cause=>{
        if(stopped||suspended)return;
        retryInput=input;
        urgentPixelInput=true;
        if(transientAuthorityFailure(cause))retryDelayMs=250;
        else fail(cause);
      }).finally(()=>{
        inputPostInFlight=false;
        if(!stopped&&!suspended&&(retryInput!==null||pendingInput!==null))
          window.setTimeout(postInput,retryDelayMs);
      });
  };

  const pump=():void=>{
    if(stopped||suspended)return;
    postInput();
    const now=performance.now();
    // Present every confirmed database framebuffer. Input latency must be
    // controlled by transport and reserve depth, never by deleting gun,
    // sprite, or world-animation frames from the authoritative stream.
    const nextTic=presentedTic<0
      ? Math.min(...frames.keys())
      : nextDatabaseFrameTic(presentedTic);
    const frame=frames.get(nextTic);
    if(frame===undefined) {
      if(playoutStarted&&now>=nextFrameAt+1000/70&&!starvationActive) {
        starvationActive=true;
        trace('pixel-starvation',{
          presentedTic,transportTic,selectedDepth:wan.playoutBufferTics,
          expectedBatchTics:wan.expectedConfirmedBatchTics,
          source:'database-framebuffer'});
      }
      return;
    }
    if(now<nextFrameAt)return;
    if(!playoutStarted) {
      // A batched transport's real display offset is reserve plus one batch:
      // starting after only the first batch creates a sawtooth that reaches
      // zero immediately before every response. Retain the selected reserve
      // after consuming a normal batch by waiting for depth+batch frames.
      const startupFrames=Math.min(64,
        wan.playoutBufferTics+wan.expectedConfirmedBatchTics);
      if(frames.size<startupFrames)return;
      playoutStarted=true;playoutMode='FREE';
      trace('pixel-playout-start',{
        tic:nextTic,bufferedFrames:frames.size,
        selectedDepth:wan.playoutBufferTics,
        expectedBatchTics:wan.expectedConfirmedBatchTics,startupFrames,
        source:'database-framebuffer'});
    }
    starvationActive=false;
    frames.delete(nextTic);
    blitDatabaseFrame(frame.indices,frame.paletteIndex);
    presentedTic=nextTic;
    paintedAt.push(now);
    if(paintedAt.length>120)paintedAt.shift();
    // Keep the atomic transport centered on a spendable confirmed reserve.
    // The database emits every authoritative 35-Hz tic. Drive presentation
    // from the confirmed-occupancy setpoint so service tails consume reserve
    // rather than becoming visible pauses.
    const decision=confirmedBatchPlayoutDecision(
      frames.size,wan.playoutBufferTics,
      wan.expectedConfirmedBatchTics,playoutMode);
    const inputCatchup=inputCatchupThroughTic>presentedTic
      &&frames.size>activePixelInputCatchupFloor;
    playoutMode=inputCatchup?'ACCELERATE':decision.mode;
    const nativePixelInterval=1000/35;
    let interval=nativePixelInterval;
    if(playoutMode==='ACCELERATE') {
      // Input catch-up needs less than the general 2x backlog ceiling. A
      // 20-ms clock preserves more confirmed reserve during rapid fire/turn
      // changes while still removing roughly one tic of visual latency per
      // three presented frames.
      interval=inputCatchup?20:nativePixelInterval/2;
    } else if(playoutMode==='DECELERATE') {
      // Recover reserve continuously without manufacturing a long paint gap.
      // 31 ms remains above 30 FPS and gives the Free-tier publication path
      // enough headroom to refill the confirmed reserve.
      interval=31;
    }
    nextFrameAt=nextFrameAt<=0?now+interval:
      Math.max(nextFrameAt+interval,now+1000/70);
    if(inputCatchupThroughTic>=0&&presentedTic>=inputCatchupThroughTic) {
      inputCatchupThroughTic=-1;
      activePixelInputCatchupFloor=pixelInputCatchupFloor;
      if(pendingInput===null&&retryInput===null&&!inputPostInFlight)
        urgentPixelInput=false;
    }
    trace('present',{tic:presentedTic,serverTic,
      bufferedFrames:frames.size,selectedDepth:wan.playoutBufferTics,
      expectedBatchTics:wan.expectedConfirmedBatchTics,
      playoutMode,frameIndices:frame.indices,
      source:'database-framebuffer'});
    updateHud();
    schedulePixelPolls(0);
  };

  const resetPixelTransport=():void=>{
    pixelPollEpoch+=1;
    pixelPollInFlight.clear();
    arrivedTransportTics.clear();
    transportEstablished=false;
    frames.clear();transportTic=-1;presentedTic=-1;
    nextFrameAt=0;playoutStarted=false;playoutMode='FREE';
    urgentPixelInput=pendingInput!==null||retryInput!==null;
    inputCatchupThroughTic=-1;lastEffectiveInputHex=null;
    starvationActive=false;wan.resetConfirmedBatchDelivery();
    paintedAt.length=0;lastFrameBatchAt=0;
  };
  const launchPixelPoll=(expectedTic:number):void=>{
    if(stopped||suspended||pixelPollInFlight.has(expectedTic))return;
    pixelPollInFlight.add(expectedTic);
    const requestEpoch=pixelPollEpoch;
    const requestAfterTic=expectedTic<0?-1:expectedTic-1;
    const requestGeneration=generation;
    let nextPollDelayMs=8;
    void exchangeMatchPixelBatch(
      value.match,value.playerCapability,requestAfterTic,8)
      .then(async result=>{
        if(requestEpoch!==pixelPollEpoch||stopped||suspended)return;
        const finished=performance.now();
        if(result.inputAccepted!==0||result.effectiveTic!==null) {
          throw new Error('input-free database-frame exchange changed');
        }
        if(result.membershipEpoch!==membershipEpoch) {
          throw new Error('database-frame generation fence changed');
        }
        if(result.generation<requestGeneration) {
          throw new Error('database-frame generation regressed');
        }
        if(result.generation>requestGeneration) {
          trace('pixel-resync',{reason:'generation',fromGeneration:generation,
            toGeneration:result.generation,source:'database-framebuffer'});
          generation=result.generation;
          serverTic=result.currentTic;
          resetPixelTransport();
          postInput();
          schedulePixelPolls();
          return;
        }
        serverTic=Math.max(serverTic,result.currentTic);
        if(result.frameCount>0&&result.firstTic!==null
            &&result.lastTic!==null&&result.payload!==null) {
          const batch=await decodeDatabasePixelTransport(
            decodeBytes(result.payload),value.playerSlot);
          if(batch.length!==result.frameCount
              ||batch[0]?.tic!==result.firstTic
              ||batch.at(-1)?.tic!==result.lastTic) {
            throw new Error('database frame batch fence changed');
          }
          if(!transportEstablished) {
            trace('pixel-resync',{reason:'ring-gap',
              expectedTic:transportTic+1,firstTic:batch[0]!.tic,
              generation,source:'database-framebuffer'});
            frames.clear();arrivedTransportTics.clear();
            presentedTic=batch[0]!.tic-1;
            transportTic=batch[0]!.tic-1;
            nextFrameAt=0;playoutStarted=false;playoutMode='FREE';
            starvationActive=false;wan.resetConfirmedBatchDelivery();
            paintedAt.length=0;
            transportEstablished=true;
          } else if(batch[0]!.tic!==expectedTic) {
            // The 64-entry ring advanced beyond an exact reserved request.
            // Establish a new confirmed cursor and invalidate the other lane;
            // no frame is invented, skipped inside the new stream, or reused.
            trace('pixel-resync',{reason:'ring-gap',
              expectedTic,firstTic:batch[0]!.tic,
              generation,source:'database-framebuffer'});
            resetPixelTransport();
            transportEstablished=true;
            presentedTic=batch[0]!.tic-1;
            transportTic=batch[0]!.tic-1;
          }
          for(const frame of batch) {
            if(frame.tic>presentedTic)frames.set(frame.tic,frame);
            arrivedTransportTics.add(frame.tic);
          }
          for(let next=nextDatabaseFrameTic(transportTic);
              arrivedTransportTics.delete(next);
              next=nextDatabaseFrameTic(transportTic)) {
            transportTic=next;
          }
          if(frames.size>64) {
            if(playoutStarted) {
              throw new Error('database frame backlog exceeded');
            }
            // A worker starts ticking before a newly attached browser has
            // fetched palettes and entered playout. Joining live does not
            // require replaying that pre-attachment history: retain one
            // confirmed batch plus the selected reserve and establish the
            // cursor immediately before it. Live playout remains consecutive.
            const retain=Math.min(64,
              wan.playoutBufferTics+wan.expectedConfirmedBatchTics+2);
            const firstRetained=transportTic-retain+1;
            for(const tic of frames.keys()) {
              if(tic<firstRetained)frames.delete(tic);
            }
            presentedTic=firstRetained-1;
            trace('pixel-resync',{
              reason:'startup-backlog',firstRetained,transportTic,
              retainedFrames:frames.size,source:'database-framebuffer'});
          }
          wan.observeConfirmedBatch(finished,batch.length);
          trace('pixel-batch',{
            frameCount:batch.length,selectedDepth:wan.playoutBufferTics,
            preClampDepth:wan.preClampPlayoutBufferTics,
            expectedBatchTics:wan.expectedConfirmedBatchTics,
            bufferedFrames:frames.size,source:'database-framebuffer'});
          pump();
          lastFrameBatchAt=finished;
          // Startup still fills immediately. Once playout is active, one
          // native-tic delay raises the batch cardinality and reduces pressure
          // on the single Free-tier API lane. This is transport batching only:
          // every confirmed framebuffer remains ordered and presentable.
          nextPollDelayMs=playoutStarted?pixelPollBatchDelayMs:0;
          if(requestEpoch!==pixelPollEpoch)schedulePixelPolls();
        } else {
          // Once caught up, aim the next request at the following native tic
          // instead of issuing several empty database calls per frame. A real
          // backlog still drains immediately through the branch above.
          const predicted=lastFrameBatchAt>0
            ? lastFrameBatchAt+1000/35-finished
            : 1000/70;
          nextPollDelayMs=Math.max(4,Math.min(20,predicted));
        }
        postInput();
      }).catch(cause=>{
        if(requestEpoch!==pixelPollEpoch||stopped||suspended)return;
        if(transientAuthorityFailure(cause)) {
          nextPollDelayMs=250;
          hud.textContent=`${soloMode?'SINGLE PLAYER':status.mode}`
            + ` · DB FRAME ${presentedTic}\nRecovering retained MLE authority…`;
        } else fail(cause);
      }).finally(()=>{
        if(requestEpoch!==pixelPollEpoch)return;
        pixelPollInFlight.delete(expectedTic);
        if(!stopped&&!suspended)schedulePixelPolls(nextPollDelayMs);
      });
  };
  schedulePixelPolls=(delayMs=0):void=>{
    if(stopped||suspended)return;
    window.setTimeout(()=>{
      if(stopped||suspended)return;
      if(!transportEstablished) {
        // Attach at the live frontier. Replaying the retained 64-tic ring
        // before presentation starts creates artificial backlog and latency;
        // those frames predate this browser's live viewing interval.
        if(pixelPollInFlight.size===0)launchPixelPoll(Math.max(0,serverTic));
        return;
      }
      // Refill while one complete batch still sits above the selected reserve.
      // Waiting until only the reserve remained exposed ordinary 100-250 ms
      // Free-tier database tails directly to the canvas. One outstanding
      // request per client avoids the ORDS/session convoy caused by delayed
      // duplicate hedges while preserving a spendable confirmed reserve.
      if(playoutStarted&&!urgentPixelInput
          &&frames.size>wan.playoutBufferTics
            +wan.expectedConfirmedBatchTics)return;
      // One wait-free request returns every immediately available DPD1 tic as
      // a player-specific DPB2. This amortizes ORDS and temporary-response
      // work without delaying worker publication to fill a batch.
      for(let expected=nextDatabaseFrameTic(transportTic),leg=0;
          leg<pixelPollLegs&&pixelPollInFlight.size<pixelPollLegs;
          expected=nextDatabaseFrameTic(expected),leg+=1) {
        if(!pixelPollInFlight.has(expected)
            &&!arrivedTransportTics.has(expected))launchPixelPoll(expected);
      }
    },delayMs);
  };
  document.addEventListener('visibilitychange',()=>{
    suspended=document.hidden;
    if(suspended) {
      resetPixelTransport();
      hiddenAt=performance.now();
      trace('visibility',{
        state:'hidden',strategy:'immediate-pixel-poll-release',
        source:'database-framebuffer'});
      return;
    }
    if(!suspended&&!stopped) {
      const hiddenMilliseconds=Math.max(0,performance.now()-hiddenAt);
      trace('pixel-resync',{
        reason:'visibility',hiddenMilliseconds,
        source:'database-framebuffer'});
      touchPresence();
      schedulePixelPolls();
    }
  });
  window.addEventListener('pagehide',()=>{stopped=true;},{once:true});
  // Presence has a dedicated one-Hz lifecycle leg. Pixel reads stay
  // transactionally read-only so an idempotent hedge can bypass a stranded
  // ORDS request without serializing on this player's membership row.
  // PACED_INPUT reuses the latest accepted command. Reposting an unchanged
  // command every 250 ms would convoy on the worker's 35-Hz match-row lock.
  // Genuine keyboard/pointer transitions enter through queueInput directly.
  // A four-millisecond sampler turned a 32 ms target into a visible 36 ms
  // bucket, while requestAnimationFrame produced a 40 ms cloud-browser p95.
  // One-millisecond sampling remains the measured best scheduler on this
  // venue; the pump's deadline check prevents early presentation.
  updateHud();touchPresence();schedulePixelPolls();
  window.setInterval(touchPresence,1_000);
  window.setInterval(pump,1);
}

/** Retained diagnostic fallback; production admission uses database pixels. */
export async function startMleGame(
    value: LocalMatch, status: MatchStatus): Promise<void> {
  const [
    {AudioPresenter},
    {decodeAuthorityBatch},
    {ConfirmedAuthorityMirror},
    {authorityRootChainSha},
    {createBrowserAuthorityEngines,restoreBrowserAuthorityCheckpoint},
  ]=await Promise.all([
    import('./audio.js'),
    import('./authority-batch.js'),
    import('./authority-mirror.js'),
    import('./authority.js'),
    import('./teavm-browser.js'),
  ]);
  lobby.hidden = true;game.dataset.active = '';
  hud.textContent = 'Loading SHA-verified Doom engine and IWAD…';
  const audio = new AudioPresenter();
  const [presentationAssets, initialInputSequence, engines] = await Promise.all([
    soloPresentationAssets ??
      Promise.all([getAsset('PLAYPAL'),getAsset('TITLEPIC')]),
    matchInputFrontier(value.match, value.playerCapability),
    createBrowserAuthorityEngines(status)
  ]);
  const [paletteAsset,titleAsset]=presentationAssets;
  const blitIndexed = createIndexedBlitter(canvas,
    createPalette(decodeBytes(paletteAsset.payload).subarray(0,256*3)));
  blitIndexed(decodeBytes(titleAsset.payload));

  const rootChainSha = await authorityRootChainSha(
    value.match, status.membershipEpoch);
  let mirror = new ConfirmedAuthorityMirror(
    engines.verifier, engines.presenter, value.playerSlot,
    {tic: 0, generation: 1, membershipEpoch: status.membershipEpoch,
      chainSha: rootChainSha});
  // Network acquisition and TeaVM frame production have separate cursors.
  // Keeping the next HTTP request behind eight verifier+renderer steps turns
  // browser compute time into transport dead time and cannot sustain 35 Hz on
  // a WAN. Batches are still decoded and applied in strict chain order.
  let transportFrontier = mirror.frontier;
  let applyChain: Promise<void> = Promise.resolve();
  const wan = new ConfirmedWanPolicy();
  const presentations = new Map<number, {
    presentation: ConfirmedPresentation;
    audio: Parameters<InstanceType<typeof AudioPresenter>['enqueue']>[0];
  }>();
  let latest: Command = {seq: 0, turn: 0, forward: 0, strafe: 0, run: 0,
    fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: ''};
  let inputSequence = initialInputSequence;
  const inputQueue: {
    sequence: number;
    command: Command;
    hex: string;
    targetTic: number;
    leadTics: number;
  }[] = [];
  let inputPosting = false;
  let polling = false;
  let requestPresentationPump:()=>void=()=>{};
  let pollEpoch = 0;
  let pollController: AbortController | null = null;
  let presentationSuspended = document.hidden;
  let hiddenAt = presentationSuspended ? performance.now() : 0;
  let checkpointResyncing = false;
  let stopped = false;
  let presentedTic = 0;
  let serverTic = status.currentTic;
  let nextPresentationAt = 0;
  let presentationStarted = false;
  let playoutMode:'ACCELERATE'|'FREE'|'DECELERATE'='FREE';
  const paintedAt: number[] = [];
  const buttons = new Map<ControlName, HTMLButtonElement>();
  const observeWanRoundTrip = (roundTripMs: number, nowMs: number,
    minimumLeadTics = 2): void => {
    const before = wan.inputLeadTics;
    wan.observeRoundTrip(roundTripMs, nowMs, minimumLeadTics);
    if (wan.inputLeadTics !== before) {
      trace('lead', {from: before, to: wan.inputLeadTics});
    }
  };

  const fail = (cause: unknown): void => {
    stopped = true;pollEpoch += 1;pollController?.abort();
    if (cause instanceof MatchUnavailableError) {
      for (const store of [localStorage,sessionStorage]) {
        store.removeItem(storageKey(value.match));
        if (store.getItem(soloCurrentKey)===value.match) {
          store.removeItem(soloCurrentKey);
        }
      }
    }
    hud.className = 'error';
    hud.textContent = cause instanceof Error ? cause.message : String(cause);
  };
  const stopStaleSoloClient = (): void => {
    if (stopped) return;
    stopped = true;pollEpoch += 1;pollController?.abort();
    inputQueue.length = 0;
  };
  window.addEventListener('pagehide',stopStaleSoloClient,{once:true});
  if (soloMode) {
    window.addEventListener('storage',event => {
      if (event.key===soloCurrentKey && event.newValue!==value.match) {
        stopStaleSoloClient();
      }
    });
  }
  const updateHud = (): void => {
    const elapsed = paintedAt.length > 1 ? paintedAt.at(-1)! - paintedAt[0]! : 0;
    const fps = elapsed > 0 ? (paintedAt.length - 1) * 1000 / elapsed : 0;
    const role=soloMode ? 'SINGLE PLAYER' :
      `${status.mode} · PLAYER ${value.playerSlot + 1}`;
    hud.textContent = `${role} · TIC ${presentedTic}`
      + ` · CONFIRMED ${mirror.frontier.tic} · SERVER ${serverTic}`
      + `\n${fps.toFixed(1)} FPS · lead ${wan.inputLeadTics}`
      + ` · playout ${wan.playoutBufferTics} · confirmed-only`;
  };

  const queueInput = (command: Command): void => {
    latest = command;
    const leadTics = wan.inputLeadTics;
    const targetTic = wan.inputTargetTic(mirror.frontier.tic);
    const pendingIndex=inputPosting ? 1 : 0;
    let sequence:number;
    if (inputQueue.length>pendingIndex) {
      // Preserve the next required idempotent sequence while replacing UI
      // samples that have not begun an HTTP post. One slow ORDS request must
      // not turn obsolete key states into a multi-second submission tail.
      sequence=inputQueue[pendingIndex]!.sequence;
      inputQueue.splice(pendingIndex,1,{sequence,command:{...latest},
        hex:ticcmd(latest),targetTic,leadTics});
    } else {
      inputSequence += 1;sequence=inputSequence;
      inputQueue.push({sequence, command: {...latest},
        hex: ticcmd(latest), targetTic, leadTics});
    }
    trace('input', {inputSequence:sequence, command: latest,
      targetTic, leadTics});
  };
  bindInput(canvas, buttons, queueInput,
    () => {}, () => { void audio.enable(); });
  // An idle player still authors the neutral command being sampled. Without
  // this initial event the authority correctly classifies early tics as
  // NEUTRAL_INITIAL until the first physical key change.
  queueInput(latest);
  canvas.addEventListener('click', () => {
    if (document.pointerLockElement !== canvas) void canvas.requestPointerLock();
  });
  canvas.focus();

  const postInput = (): void => {
    if (stopped || presentationSuspended || checkpointResyncing ||
        inputPosting || inputQueue.length === 0) return;
    inputPosting = true;
    const input = inputQueue[0]!;
    const started = performance.now();
    // The chartered lockstep contract schedules from the client's verified
    // confirmed frontier. Adding a separately advertised server frontier here
    // double-counts delivery lag and inflates every input by the backlog.
    const targetTic = input.targetTic;
    void reviseMatchInput(value.match, value.playerCapability,
      input.sequence, input.hex, targetTic).then(result => {
        const finished = performance.now();
        observeWanRoundTrip(finished - started, finished);
        if (result.accepted !== 1 ||
            result.membershipEpoch !== mirror.frontier.membershipEpoch ||
            result.generation < mirror.frontier.generation) {
          throw new Error('multiplayer input fence changed');
        }
        inputQueue.shift();
        trace('input-effective', {inputSequence: input.sequence,
          effectiveTic: result.effectiveTic, command: input.command,
          targetTic, roundTripMs: finished - started,
          leadTics: input.leadTics});
      }).catch(cause => {
        if (transientAuthorityFailure(cause)) {
          trace('recovery-wait',{path:'input',message:String(cause)});
        } else {
          fail(cause);
        }
      }).finally(() => { inputPosting = false; });
  };

  const poll = (): void => {
    if (stopped || presentationSuspended || checkpointResyncing || polling) return;
    polling = true;
    const requestEpoch = pollEpoch;
    const controller = new AbortController();
    pollController = controller;
    const frontier = transportFrontier;
    const pollStarted = performance.now();
    void pollMatchTransitions(value.match, value.playerCapability,
      frontier.tic, transitionHoldMs, 32, controller.signal).then(async result => {
        if (requestEpoch !== pollEpoch) return;
        const batch = await decodeAuthorityBatch(result.payload, frontier);
        const pollFinished = performance.now();
        if (!batch.timedOut) {
          // Remove the database's measured idle hold from wall time. The
          // remainder is the observed transport/ORDS round trip. The batch
          // frontier gap is a second, direct estimate of how far ahead input
          // must be scheduled from this verified frontier.
          observeWanRoundTrip(
            Math.max(0,pollFinished-pollStarted-batch.holdElapsedMs),
            pollFinished,
            batch.committedFrontierTic-mirror.frontier.tic+1);
        }
      trace('batch',{holdElapsedMs:batch.holdElapsedMs,
        wallMs:pollFinished-pollStarted,count:batch.transitions.length,
        committedFrontierTic:batch.committedFrontierTic,
        leadTics:wan.inputLeadTics});
      serverTic = Math.max(serverTic, result.currentTic, batch.committedFrontierTic);
      const last = batch.transitions.at(-1);
      if (last !== undefined) {
        transportFrontier = {tic:last.tic,generation:last.generation,
          membershipEpoch:last.membershipEpoch,chainSha:last.chainSha};
      }
      // The database lease is already gone and the decoded chain provides the
      // next safe cursor. Start the next one-outstanding poll before running
      // the CPU-heavy browser verifier/presenter for this batch.
      if (pollController === controller) {
        polling=false;pollController=null;
        if (!stopped && !presentationSuspended && !checkpointResyncing) {
          window.setTimeout(poll,0);
        }
      }
      applyChain=applyChain.then(async()=>{
        if (requestEpoch !== pollEpoch) return;
        const applyBatchStarted = performance.now();
        let maximumApplyMs = 0;
        for (const transition of batch.transitions) {
          if (requestEpoch !== pollEpoch) return;
          const applyStarted = performance.now();
          const presentation = await mirror.apply(transition);
          maximumApplyMs = Math.max(maximumApplyMs,
            performance.now()-applyStarted);
          presentations.set(transition.tic, {
            presentation, audio: transition.audio
          });
          trace('confirmed', {tic: transition.tic, chainSha: transition.chainSha,
              generation: transition.generation,
            membershipEpoch: transition.membershipEpoch});
          // The interval pump is a fallback cadence clock. Under sustained
          // TeaVM apply work, browser task arbitration can select this chain
          // repeatedly and halve paint cadence. Offer the already-confirmed
          // frame directly after each completed transition.
          requestPresentationPump();
          // Promise continuations alone remain in the microtask queue. Give
          // every generated frame a paint opportunity, but let confirmed
          // mirror apply catch up at 4x. Visible presentation retains its
          // separate 2x ceiling below; this only shortens verification/render
          // preparation backlog and never skips or presents a transition.
          const yieldMs=Math.max(0,Math.min(1000/140,
            nextPresentationAt-performance.now()));
          await new Promise<void>(resolve=>window.setTimeout(resolve,yieldMs));
        }
        if (batch.transitions.length>0) {
          // A DMB1 batch is one delivery event. Treating every transition in
          // the same response as a zero-gap network arrival falsely inflates
          // jitter and then drains the resulting buffer at 2x.
          wan.observeConfirmedDelivery(performance.now());
          trace('playout',{
            selectedTics:wan.playoutBufferTics,
            preClampDesiredTics:wan.preClampPlayoutBufferTics
          });
        }
        trace('apply-batch',{count:batch.transitions.length,
          wallMs:performance.now()-applyBatchStarted,
          maximumApplyMs});
      });
      await applyChain;
      }).catch(cause => {
        if (requestEpoch !== pollEpoch || controller.signal.aborted) return;
        if (cause instanceof Error &&
            cause.message.includes('DMB1_RESYNC_REQUIRED')) {
          trace('recovery-wait',{path:'transitions',
            message:'confirmed checkpoint resync required'});
          void checkpointResync(0);
          return;
        }
        if (transientAuthorityFailure(cause)) {
          trace('recovery-wait',{path:'transitions',message:String(cause)});
          hud.textContent = `${soloMode ? 'SINGLE PLAYER' : status.mode}`
            + ` · TIC ${presentedTic}\nRecovering retained MLE authority…`;
        } else {
          fail(cause);
        }
      }).finally(() => {
        if (pollController === controller) {
          polling = false;pollController = null;
          // Free defaults to immediate batches. WAN-qualified deployments
          // select a bounded hold via the page URL; the database enforces both
          // the 500 ms ceiling and one outstanding poll per player.
          if (!stopped && !presentationSuspended && !checkpointResyncing) {
            window.setTimeout(poll, 20);
          }
        }
      });
  };

  const checkpointResync = async (hiddenMilliseconds: number): Promise<void> => {
    if (stopped || checkpointResyncing) return;
    checkpointResyncing = true;pollEpoch += 1;pollController?.abort();
    try {
      // Do not restore either engine while an already-decoded batch is still
      // mutating it. Epoch checks discard every queued batch after this point.
      await applyChain;
      const frontier = mirror.frontier;
      const checkpoint = await matchCheckpoint(
        value.match, value.playerCapability, 0);
      serverTic = Math.max(serverTic, checkpoint.currentTic);
      if (!checkpoint.ready) {
        trace('visibility', {state:'visible',strategy:'batch-catch-up',
          hiddenMs:hiddenMilliseconds,frontierTic:frontier.tic});
        return;
      }
      if (checkpoint.checkpointTic < 1 ||
          checkpoint.membershipEpoch !== frontier.membershipEpoch ||
          checkpoint.generation < frontier.generation ||
          !/^[0-9a-f]{64}$/.test(checkpoint.chainSha) ||
          !/^[0-9a-f]{64}$/.test(checkpoint.checkpointSha) ||
          checkpoint.payload === null) {
        throw new Error('browser checkpoint resync fence changed');
      }
      await restoreBrowserAuthorityCheckpoint(
        engines, decodeBytes(checkpoint.payload), checkpoint.checkpointSha,
        checkpoint.checkpointTic);
      mirror = new ConfirmedAuthorityMirror(
        engines.verifier, engines.presenter, value.playerSlot, {
          tic: checkpoint.checkpointTic,
          generation: checkpoint.generation,
          membershipEpoch: checkpoint.membershipEpoch,
          chainSha: checkpoint.chainSha
        });
      transportFrontier=mirror.frontier;
      presentations.clear();
      presentedTic = checkpoint.checkpointTic;
      presentationStarted = false;nextPresentationAt = 0;
      playoutMode='FREE';
      trace('resync',{tic:presentedTic,reason:'confirmed-checkpoint'});
      trace('visibility',{state:'visible',strategy:'checkpoint-resync',
        hiddenMs:hiddenMilliseconds,frontierTic:presentedTic});
      updateHud();
    } catch (cause) {
      if (transientAuthorityFailure(cause)) {
        trace('recovery-wait',{path:'checkpoint',message:String(cause)});
      } else {
        fail(cause);
      }
    } finally {
      checkpointResyncing = false;
      if (!stopped && !presentationSuspended) poll();
    }
  };

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      if (presentationSuspended) return;
      presentationSuspended = true;hiddenAt = performance.now();
      pollEpoch += 1;pollController?.abort();
      trace('visibility',{state:'hidden',strategy:'suspend',
        frontierTic:mirror.frontier.tic});
      window.setTimeout(() => {
        if (presentationSuspended && performance.now()-hiddenAt >=
            HIDDEN_POLL_LEASE_RELEASE_MS) {
          trace('visibility',{state:'hidden',strategy:'poll-lease-released',
            frontierTic:mirror.frontier.tic});
        }
      },HIDDEN_POLL_LEASE_RELEASE_MS);
      return;
    }
    if (!presentationSuspended) return;
    const hiddenMilliseconds = Math.max(0,performance.now()-hiddenAt);
    presentationSuspended = false;
    if (hiddenMilliseconds >= HIDDEN_CHECKPOINT_THRESHOLD_MS) {
      void checkpointResync(hiddenMilliseconds);
    } else {
      trace('visibility',{state:'visible',strategy:'batch-catch-up',
        hiddenMs:hiddenMilliseconds,frontierTic:mirror.frontier.tic});
      poll();
    }
  });

  const pump = (): void => {
    if (stopped || presentationSuspended || checkpointResyncing) return;
    postInput();
    const target = wan.presentationTargetTic(mirror.frontier.tic);
    const now = performance.now();
    // Engine/IWAD verification takes about two seconds on a cold browser while
    // the authority continues at 35 Hz. Once every intervening transition has
    // been verified and applied, begin at the confirmed playout target rather
    // than replaying that cold-load backlog forever at the same 35 Hz rate.
    // This discards presentation snapshots only; it never skips mirror state.
    if (!presentationStarted && target>0 &&
        serverTic-mirror.frontier.tic<=2 && presentations.has(target)) {
      for (const tic of presentations.keys())
        if (tic<target) presentations.delete(tic);
      presentedTic=target-1;
      presentationStarted=true;
      playoutMode='FREE';
      trace('resync',{tic:presentedTic,reason:'confirmed-startup'});
    }
    if (!presentationStarted) return;
    const next = presentations.get(presentedTic + 1);
    if (next !== undefined && now >= nextPresentationAt) {
      // Keep the playout clock on its original 35 Hz timeline. Resetting it
      // to `now` after a delayed callback permanently preserved every
      // transport/event-loop stall as additional presentation lag. One frame
      // per pump lets a confirmed-only client drain that backlog without
      // reordering, predicting, or inventing a tic.
      if (nextPresentationAt <= 0) nextPresentationAt = now;
      presentations.delete(next.presentation.tic);
      blitIndexed(next.presentation.frame);
      audio.enqueue(next.audio, fail);
      presentedTic = next.presentation.tic;
      paintedAt.push(now);if (paintedAt.length > 60) paintedAt.shift();
      // The free-running playout clock spends only already-applied confirmed
      // frames. Buffer occupancy, not a frozen frontier-relative target,
      // controls bounded acceleration/deceleration.
      const bufferOccupancy=mirror.frontier.tic-presentedTic;
      const playoutDecision =
        confirmedPlayoutDecision(bufferOccupancy,wan.playoutBufferTics,
          playoutMode);
      playoutMode=playoutDecision.mode;
      const playoutInterval=playoutDecision.intervalMs;
      // Recover clock debt at no more than the approved 2x visible ceiling.
      // Waiting a fresh 28.6 ms after every late callback adds an avoidable
      // fractional tic to confirmed-to-presented latency; using the original
      // deadline while retaining a 14.3 ms floor preserves the ceiling.
      nextPresentationAt=Math.max(
        nextPresentationAt+playoutInterval,now+1000/70);
      trace('present', {tic: presentedTic, chainSha: next.presentation.chainSha,
        leadTics: wan.inputLeadTics,
        playoutTics: wan.playoutBufferTics,
        bufferOccupancy,
        playoutMode,
        confirmedFrontierTic: mirror.frontier.tic,
        presentationLagTics: mirror.frontier.tic-presentedTic,
        serverTic});
      updateHud();
    }
  };
  requestPresentationPump=pump;
  updateHud();poll();window.setInterval(pump, 4);
  window.setInterval(()=>{
    if (!stopped && !presentationSuspended && !checkpointResyncing &&
        inputQueue.length===0 && !inputPosting) {
      queueInput(latest);
    }
  },1000);
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
  createForm.hidden = true;joinForm.hidden = true;
  readyButton.hidden = true;shareWrap.hidden = true;
  lobby.hidden = true;game.dataset.active = '';
  hud.textContent = 'SINGLE PLAYER\nStarting a new game inside Oracle…';
  void soloPresentationAssets?.then(([paletteAsset,titleAsset]) => {
    const blit=createIndexedBlitter(canvas,
      createPalette(decodeBytes(paletteAsset.payload).subarray(0,256*3)));
    blit(decodeBytes(titleAsset.payload));
  }).catch(showSoloError);
  ready = true;setBusy(true);
  void retirePriorSolo().then(() =>
    queuedCreateMatch('PLAYER 1',soloSkill,'COOP',1)).then(async value => {
    const credentials: LocalMatch = {
      match:value.match,playerCapability:value.playerCapability,playerSlot:0
    };
    await enterLobby(credentials);
    hud.textContent = 'SINGLE PLAYER\nInitializing the retained MLE authority…';
    await readyMatch(value.match,value.playerCapability,true);
    await refreshLobby();
  }).catch(showSoloError).finally(() => setBusy(false));
} else if (hash.startsWith('join=')) {
  const [match = '', join = ''] = hash.slice(5).split('.');
  if (/^[0-9a-f]{32}$/.test(match) && /^[0-9a-f]{64}$/.test(join)) {
    (joinForm.elements.namedItem('match') as HTMLInputElement).value = match;
    (joinForm.elements.namedItem('join') as HTMLInputElement).value = join;
  }
} else if (hash.startsWith('resume=')) {
  const match = hash.slice(7);
  const saved = loadLocal(match);
  if (saved !== null) void enterLobby(saved).catch(showError);
}
