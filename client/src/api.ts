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

async function post(path: string, body: RestDocument): Promise<RestDocument> {
  const response = await fetch(`${ROOT}${path}/`, {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body)
  });
  if (!response.ok) throw new Error(`${path} request failed: ${response.status}`);
  const value: unknown = await response.json();
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new TypeError(`${path} response is invalid`);
  }
  return value as RestDocument;
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
  const document = await post('step', {
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
