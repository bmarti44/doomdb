export type Command = {
  seq: number;
  turn: number;
  forward: number;
  strafe: number;
  run: number;
  fire: number;
  use: number;
  weapon: number;
  pause: number;
  automap: number;
  menu: string;
  cheat: string;
};

type RestDocument = Record<string, unknown>;

const ROOT = '/ords/doom/doom_api/';
let uppercaseProcedures = false;

async function post(path: string, body: RestDocument): Promise<RestDocument> {
  const request = () => fetch(`${ROOT}${uppercaseProcedures ? path.toUpperCase() : path}`, {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body)
  });
  let response = await request();
  // ORDS 26.2's generated package endpoints retain the catalog procedure
  // case even though older/local test doubles accept lowercase routes.
  if (response.status === 404 && !uppercaseProcedures) {
    uppercaseProcedures = true;
    response = await request();
  }
  if (!response.ok) throw new Error(`${path} request failed: ${response.status}`);
  const value: unknown = await response.json();
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new TypeError(`${path} response is invalid`);
  }
  return value as RestDocument;
}

const delay = (milliseconds: number): Promise<void> =>
  new Promise(resolve => window.setTimeout(resolve, milliseconds));

async function postStep(body: RestDocument): Promise<RestDocument> {
  let lastFailure: Error | undefined;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    try { return await post('step', body); }
    catch (cause) {
      lastFailure = cause instanceof Error ? cause : new Error('step request failed');
      if (attempt === 3) break;
      await delay(25 * (attempt + 1));
    }
  }
  throw lastFailure ?? new Error('step request failed');
}

function stringField(document: RestDocument, name: string): string {
  const value = document[name];
  if (typeof value !== 'string' || value.length === 0) {
    throw new TypeError(`${name} response field is invalid`);
  }
  return value;
}

export type NewGameResult = {session: string; payload: string};
export type AssetResult = {payload: string; mediaType: string};

export async function newGame(skill = 3): Promise<NewGameResult> {
  const document = await post('new_game', {p_skill: skill});
  const session = stringField(document, 'p_session');
  if (!/^[0-9a-f]{32}$/.test(session)) throw new TypeError('session response is invalid');
  return {session, payload: stringField(document, 'p_payload')};
}

export async function step(session: string, command: Command): Promise<string> {
  // The command sequence is the idempotency key. A retry after an ORDS/AQ
  // timeout returns the immutable committed response instead of applying twice.
  const document = await postStep({
    p_session: session,
    p_commands: JSON.stringify({v: 1, commands: [command]})
  });
  return stringField(document, 'p_payload');
}

export async function getAsset(name: string): Promise<AssetResult> {
  const document = await post('get_asset', {p_asset_name: name});
  return {
    payload: stringField(document, 'p_payload'),
    mediaType: stringField(document, 'p_media_type')
  };
}
