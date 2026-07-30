#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'two-POV cloud evidence requires %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || {
  printf '%s\n' 'two-POV cloud evidence requires the DOOM schema' >&2
  exit 2
}
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]] || {
  printf '%s\n' 'two-POV cloud evidence wallet is invalid' >&2
  exit 2
}
[[ -x "$SQL_CLIENT" ]] || {
  printf '%s\n' 'two-POV cloud evidence SQL client is unavailable' >&2
  exit 2
}

app_url="${T112_HOSTED_INDEX_URL:-https://G53C2244DAB9063-DOOMDB.adb.us-ashburn-1.oraclecloudapps.com/ords/doom/app/}"
minimum_fps="${DOOMDB_MULTIPLAYER_MINIMUM_FPS:-30}"
[[ "$minimum_fps" == 20 || "$minimum_fps" == 30 ]] || {
  printf 'two-POV minimum FPS must be 20 or 30: %s\n' "$minimum_fps" >&2
  exit 2
}
lock="${PMLE_LIVE_FRAME_LOCK:-$root/versions.lock}"
[[ -s "$lock" && ! -L "$lock" ]] || {
  printf 'two-POV live-frame lock is unavailable: %s\n' "$lock" >&2
  exit 2
}
stamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
output="${1:-$root/artifacts/performance/pmle-live-frame-authority/oci-two-pov-$stamp.log}"
samples="${output%.log}.json"
score_start_tic="${DOOMDB_MULTIPLAYER_SCORE_START_TIC:-0}"
[[ "$score_start_tic" =~ ^[0-9]+$ && "$score_start_tic" -le 100000 ]] || {
  printf 'two-POV score-start tic is invalid: %s\n' "$score_start_tic" >&2
  exit 2
}
[[ ! -e "$output" ]] || {
  printf 'refusing to overwrite two-POV evidence: %s\n' "$output" >&2
  exit 2
}
[[ ! -e "$samples" ]] || {
  printf 'refusing to overwrite two-POV samples: %s\n' "$samples" >&2
  exit 2
}
mkdir -p "$(dirname "$output")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-two-pov.XXXXXX")"
chmod 700 "$tmp"
cleanup(){
  local status=$?
  trap - EXIT HUP INT TERM
  rm -rf "$tmp"
  unset ADB_PASSWORD
  exit "$status"
}
trap cleanup EXIT HUP INT TERM
export TNS_ADMIN="$ADB_WALLET_DIR"

multiplayer_url="$(
  node -e '
    const url=new URL("multiplayer.html",process.argv[1]);
    if(url.protocol!=="https:"||!/[/]ords[/]doom[/]app[/]multiplayer[.]html$/.test(url.pathname))
      throw new Error("hosted multiplayer URL is invalid");
    process.stdout.write(url.href);
  ' "$app_url"
)"
origin="$(node -e 'process.stdout.write(new URL(process.argv[1]).origin)' "$app_url")"
IFS=$'\t' read -r authority_sha renderer_sha coordinator_sha < <(
  node - "$lock" <<'NODE'
import fs from 'node:fs';
const versions=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const live=versions.teaVM?.liveFrameRenderer;
const deployed=[
  live?.deployedOutputSha256,
  live?.deployedCoordinatorSha256
];
if(deployed.some(Boolean)&&!deployed.every(value=>/^[0-9a-f]{64}$/.test(value)))
  throw new Error('partial live-frame deployment provenance is forbidden');
const values=[
  versions.teaVM?.outputSha256,
  live?.deployedOutputSha256??live?.outputSha256,
  live?.deployedCoordinatorSha256??live?.coordinatorSha256
];
if(values.some(value=>!/^[0-9a-f]{64}$/.test(value??'')))
  throw new Error('live-frame artifact provenance is not pinned');
if(versions.teaVM.outputSha256!==live.authorityCandidateSha256)
  throw new Error('live-frame authority candidate is not promoted');
process.stdout.write(values.join('\t')+'\n');
NODE
)

cat >"$tmp/artifact.sql" <<'SQL'
set pagesize 0 feedback off heading off verify off echo off trimout on trimspool on linesize 32767
select 'PMLE_OCI_TWO_POV_ARTIFACT|authority_sha256='||authority_sha256||
  '|renderer_sha256='||renderer_sha256||
  '|coordinator_sha256='||coordinator_sha256
  from doom_mle_live_frame_source where artifact_id=1;
SQL
query_deployed_artifact(){
  local phase="$1" artifact_log="$tmp/artifact-$1.log" marker
  {
    printf '%s\n' 'whenever oserror exit failure rollback' \
      'whenever sqlerror exit sql.sqlcode rollback' \
      'set echo off verify off define off'
    printf 'connect %s/"%s"@%s\n' \
      "$ADB_USERNAME" "$ADB_PASSWORD" "$ADB_CONNECTION_STRING"
    command cat "$tmp/artifact.sql"
    printf '%s\n' 'exit success rollback'
  } | timeout 180 "$SQL_CLIENT" -s /nolog |
    node "$root/scripts/redact-cloud-output.mjs" >"$artifact_log"
  marker="$(
    node "$root/scripts/verify-live-frame-artifact-marker.mjs" \
      "$artifact_log" "$authority_sha" "$renderer_sha" "$coordinator_sha"
  )" || {
      printf 'deployed two-POV artifact provenance mismatch: %s\n' \
        "$phase" >&2
      tail -20 "$artifact_log" >&2
      return 1
    }
  printf 'PMLE_OCI_TWO_POV_ARTIFACT_ATTEST|phase=%s|%s\n' \
    "$phase" "${marker#PMLE_OCI_TWO_POV_ARTIFACT|}"
}

printf 'PMLE_OCI_TWO_POV|BEGIN|frames=300|renderer=DATABASE_PIXELS|url_origin_sha256=%s\n' \
  "$(printf %s "$origin" | shasum -a 256 | awk '{print $1}')" |
  tee "$output"
query_deployed_artifact BEFORE | tee -a "$output"
DOOMDB_PLAY_BASE_URL="$origin" \
DOOMDB_MULTIPLAYER_URL="$multiplayer_url" \
DOOMDB_MATCH_MODE=COOP \
DOOMDB_TEST_ORDS_RESTART=0 \
DOOMDB_REQUIRE_DATABASE_PIXELS=1 \
DOOMDB_MULTIPLAYER_FRAMES=300 \
DOOMDB_MULTIPLAYER_MINIMUM_FPS="$minimum_fps" \
DOOMDB_MULTIPLAYER_SCORE_START_TIC="$score_start_tic" \
DOOMDB_MATCH_ID_FILE="$tmp/match-id" \
DOOMDB_MULTIPLAYER_EVIDENCE_PATH="$samples" \
DOOMDB_EXPECTED_AUTHORITY_SHA256="$authority_sha" \
DOOMDB_EXPECTED_RENDERER_SHA256="$renderer_sha" \
DOOMDB_EXPECTED_COORDINATOR_SHA256="$coordinator_sha" \
  node tests/verify-p13.3-multiplayer-client.mjs 2>&1 | tee -a "$output"

if [[ "$score_start_tic" -gt 0 ]]; then
  match_id="$(tr -d '[:space:]' <"$tmp/match-id")"
  [[ "$match_id" =~ ^[0-9a-f]{32}$ ]] || {
    printf 'checkpoint-crossing match id is invalid\n' >&2
    exit 2
  }
  checkpoint_log="$tmp/checkpoint-observation.log"
  {
    printf '%s\n' 'whenever oserror exit failure rollback' \
      'whenever sqlerror exit sql.sqlcode rollback' \
      'set echo off verify off define off' \
      'set pagesize 0 feedback off heading off trimout on trimspool on linesize 32767 serveroutput on size unlimited'
    printf 'connect %s/"%s"@%s\n' \
      "$ADB_USERNAME" "$ADB_PASSWORD" "$ADB_CONNECTION_STRING"
    cat <<SQL
declare
  l_tic number:=0;
  l_deadline timestamp with time zone:=
    (localtimestamp at time zone 'UTC')+interval '60' second;
begin
  loop
    select nvl(max(tic),0) into l_tic
      from doom_match_checkpoint where match_id='$match_id';
    exit when l_tic>0;
    if (localtimestamp at time zone 'UTC')>=l_deadline then
      raise_application_error(-20796,
        'asynchronous checkpoint did not reach durable storage');
    end if;
    dbms_session.sleep(.25);
  end loop;
  dbms_output.put_line('PMLE_CHECKPOINT_CROSSING|'||l_tic);
end;
/
select 'PMLE_CHECKPOINT_STAGE|tic='||tic||
       '|save_ms='||to_char(save_elapsed_ms,'FM999999990D999',
         'NLS_NUMERIC_CHARACTERS=''.,''')||
       '|publish_ms='||to_char(publish_elapsed_ms,'FM999999990D999',
         'NLS_NUMERIC_CHARACTERS=''.,''')
  from doom_match_checkpoint
 where match_id='$match_id'
 order by tic;
select 'PMLE_PUBLICATION_GAP|tic='||tic||
       '|gap_ms='||to_char(gap_ms,'FM999999990D999',
         'NLS_NUMERIC_CHARACTERS=''.,''')
  from (
    select tic,
      extract(day from gap_)*86400000+
      extract(hour from gap_)*3600000+
      extract(minute from gap_)*60000+
      extract(second from gap_)*1000 gap_ms
      from (
        select tic,published_at-lag(published_at) over(order by tic) gap_
          from doom_match_live_frame_views
         where match_id='$match_id' and tic>=0
      )
     where gap_ is not null
     order by gap_ms desc
  )
 where rownum=1;
select 'PMLE_WORKER_SLOW|tic='||tic||
       '|elapsed_ms='||to_char(elapsed_ms,'FM999999990D999',
         'NLS_NUMERIC_CHARACTERS=''.,''')||
       '|mle_ms='||to_char(nvl(mle_ms,0),'FM999999990D999',
         'NLS_NUMERIC_CHARACTERS=''.,''')||
       '|post_mle_ms='||to_char(nvl(post_mle_ms,0),'FM999999990D999',
         'NLS_NUMERIC_CHARACTERS=''.,''')
  from doom_match_slow_call
 where match_id='$match_id'
 order by tic;
SQL
    printf '%s\n' 'exit success rollback'
  } | timeout 180 "$SQL_CLIENT" -s /nolog |
    node "$root/scripts/redact-cloud-output.mjs" >"$checkpoint_log"
  cat "$checkpoint_log" | tee -a "$output"
  checkpoint_marker="$(
    sed -n 's/[[:space:]]*$//;/^PMLE_CHECKPOINT_CROSSING|[0-9][0-9]*$/p' \
      "$checkpoint_log" | tail -1
  )"
  checkpoint_tic="${checkpoint_marker#PMLE_CHECKPOINT_CROSSING|}"
  [[ "$checkpoint_marker" == "PMLE_CHECKPOINT_CROSSING|$checkpoint_tic" &&
    "$checkpoint_tic" =~ ^[1-9][0-9]*$ ]] || {
    printf 'durable checkpoint marker is missing\n' >&2
    exit 2
  }
  node - "$samples" "$checkpoint_tic" <<'NODE' | tee -a "$output"
import assert from 'node:assert/strict';
import fs from 'node:fs';
const evidence=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const checkpoint=Number(process.argv[3]);
assert.equal(evidence.framesPerPlayer,300);
for(const player of evidence.players) {
  assert.ok(player.presents[0].tic<checkpoint);
  assert.ok(player.presents.at(-1).tic>checkpoint);
}
process.stdout.write(
  `PMLE_OCI_CHECKPOINT_CROSSING|PASS|checkpoint_tic=${checkpoint}`+
  `|windows=${evidence.players.map(player=>
    `${player.presents[0].tic}-${player.presents.at(-1).tic}`).join('/')}\n`);
NODE
fi

grep -Eq '^PASS P13[.]3-MULTIPLAYER-CLIENT mode=COOP renderer=DATABASE_PIXELS .*frames=300 p0=[0-9.]+fps .* p1=[0-9.]+fps ' \
  "$output"
DOOMDB_MULTIPLAYER_MINIMUM_FPS="$minimum_fps" \
node tests/evaluate-live-frame-two-pov.mjs "$samples" \
  "$authority_sha" "$renderer_sha" "$coordinator_sha" | tee -a "$output"

# The browser receives no deployment-private metadata. Bind its samples to the
# actual Oracle-resident tuple on both sides of the scored window rather than
# merely echoing versions.lock into the evidence.
query_deployed_artifact AFTER | tee -a "$output"

samples_sha="$(shasum -a 256 "$samples" | awk '{print $1}')"
printf 'PMLE_OCI_TWO_POV|PASS|frames_per_player=300|minimum_fps=%s|renderer=DATABASE_PIXELS|authority_sha256=%s|renderer_sha256=%s|coordinator_sha256=%s|samples_sha256=%s\n' \
  "$minimum_fps" "$authority_sha" "$renderer_sha" "$coordinator_sha" "$samples_sha" |
  tee -a "$output"
