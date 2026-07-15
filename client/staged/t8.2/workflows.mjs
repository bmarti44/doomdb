const KEYS = ['seq','turn','forward','strafe','run','fire','use','weapon',
  'pause','automap','menu','cheat'];
const MENUS = new Set(['NONE','OPEN','DOWN','UP','SELECT','BACK','RESTART']);
const CHEAT = /^(?:|GOD|ALL|NOCLIP|FULLMAP|REWIND:(?:0|[1-9][0-9]*))$/;

export function command(seq, patch = {}) {
  const value = {seq,turn:0,forward:0,strafe:0,run:0,fire:0,use:0,weapon:0,
    pause:0,automap:0,menu:'NONE',cheat:'',...patch};
  if (Object.keys(value).sort().join('|') !== [...KEYS].sort().join('|')) {
    throw new TypeError('command must have exact version-one keys');
  }
  for (const key of ['seq','turn','forward','strafe','run','fire','use','weapon','pause','automap']) {
    if (!Number.isInteger(value[key])) throw new TypeError(`${key} must be an integer`);
  }
  if (![-1,0,1].includes(value.turn) || ![-1,0,1].includes(value.forward) ||
      ![-1,0,1].includes(value.strafe) || value.weapon < 0 || value.weapon > 9 ||
      !['run','fire','use','pause','automap'].every(key => [0,1].includes(value[key])) ||
      !MENUS.has(value.menu) || !CHEAT.test(value.cheat)) {
    throw new TypeError('command control is invalid');
  }
  return Object.freeze(value);
}

function field(document, name) {
  const value = document?.[name] ?? document?.[name.toUpperCase()] ??
    document?.items?.[0]?.[name] ?? document?.items?.[0]?.[name.toUpperCase()];
  if (typeof value !== 'string' || value.length === 0) {
    throw new TypeError(`${name} response field is invalid`);
  }
  return value;
}

export class WorkflowClient {
  #post;
  #session = null;
  #frontier = 0;
  #lastRequest = null;

  constructor(post) {
    if (typeof post !== 'function') throw new TypeError('POST transport required');
    this.#post = post;
  }

  get session() { return this.#session; }
  get frontier() { return this.#frontier; }

  async newGame(skill) {
    if (!Number.isInteger(skill) || skill < 1 || skill > 5) {
      throw new TypeError('skill must be an integer from one through five');
    }
    const response = await this.#post('new_game/', {p_skill:skill});
    const token = field(response,'p_session');
    if (!/^[0-9a-f]{32}$/.test(token)) throw new TypeError('session is invalid');
    this.#session=token;this.#frontier=0;this.#lastRequest=null;
    return field(response,'p_payload');
  }

  async step(patches) {
    if (this.#session === null) throw new Error('game has not started');
    const list = Array.isArray(patches) ? patches : [patches];
    if (list.length < 1 || list.length > 4) throw new TypeError('one to four commands required');
    const commands = list.map((patch,index)=>command(this.#frontier+index+1,patch));
    const request = {p_session:this.#session,
      p_commands:JSON.stringify({v:1,commands})};
    const response = await this.#post('step/',request);
    this.#frontier += commands.length;
    this.#lastRequest = Object.freeze({path:'step/',body:request});
    return field(response,'p_payload');
  }

  async retryLastStep() {
    if (this.#lastRequest === null) throw new Error('no successful STEP to retry');
    const response=await this.#post(this.#lastRequest.path,this.#lastRequest.body);
    return field(response,'p_payload');
  }

  pause() { return this.step({pause:1}); }
  automap() { return this.step({automap:1}); }
  menu(action) { return this.step({menu:action}); }
  cheat(code) { return this.step({cheat:code}); }
  rewind(tic) {
    if (!Number.isSafeInteger(tic) || tic < 0) throw new TypeError('rewind tic is invalid');
    return this.step({cheat:`REWIND:${tic}`});
  }

  async save(slot) {
    if (this.#session === null) throw new Error('game has not started');
    if (!Number.isInteger(slot) || slot < 0 || slot > 99) throw new TypeError('save slot is invalid');
    return field(await this.#post('save_game/',{p_session:this.#session,p_slot:slot}),
      'p_state_sha');
  }

  async load(slot) {
    if (this.#session === null) throw new Error('game has not started');
    if (!Number.isInteger(slot) || slot < 0 || slot > 99) throw new TypeError('save slot is invalid');
    return field(await this.#post('load_game/',{p_session:this.#session,p_slot:slot}),
      'p_payload');
  }

  async startReplay(fromTic,toTic) {
    if (this.#session === null) throw new Error('game has not started');
    if (!Number.isInteger(fromTic)||!Number.isInteger(toTic)||fromTic<0||toTic<fromTic) {
      throw new TypeError('replay range is invalid');
    }
    return field(await this.#post('start_replay/',{p_session:this.#session,
      p_from_tic:fromTic,p_to_tic:toTic}),'p_replay_id');
  }

  async stepReplay(replayId) {
    if (!/^[0-9a-f]{32}$/.test(replayId)) throw new TypeError('replay id is invalid');
    return field(await this.#post('step_replay/',{p_replay_id:replayId}),'p_payload');
  }
}

