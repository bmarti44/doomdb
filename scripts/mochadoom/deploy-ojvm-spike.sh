#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container="${DOOMDB_MOCHA_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="/opt/oracle/product/26ai/dbhomeFree"
revision="c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93"
iwad_sha="7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d"
tmp="/tmp/doomdb-mocha-$$"

[[ -n "$container" ]] || { printf 'database container is not running\n' >&2; exit 1; }
[[ "$(git -C "$root/third_party/mochadoom" rev-parse HEAD)" == "$revision" ]] || {
  printf 'Mocha Doom submodule is not at pinned revision %s\n' "$revision" >&2
  exit 1
}

cleanup() {
  docker exec "$container" rm -rf "$tmp" >/dev/null 2>&1 || true
  rm -rf "$host_tmp"
}
host_tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-mocha.XXXXXX")"
trap cleanup EXIT

unzip -p "$root/vendor/freedoom/0.13.0/freedoom-0.13.0.zip" \
  freedoom-0.13.0/freedoom1.wad >"$host_tmp/freedoom1.wad"
actual_iwad_sha="$(shasum -a 256 "$host_tmp/freedoom1.wad" | awk '{print $1}')"
[[ "$actual_iwad_sha" == "$iwad_sha" ]] || {
  printf 'Freedoom IWAD SHA mismatch: %s\n' "$actual_iwad_sha" >&2
  exit 1
}

mkdir -p "$host_tmp/source"
cp -R "$root/third_party/mochadoom/src/." "$host_tmp/source"
# Upstream contains a mix of CRLF and LF Java sources. Normalize only the
# disposable build copy so patch overlays are portable across host tools.
find "$host_tmp/source" -name '*.java' -exec perl -pi -e 's/\r$//' {} +
# Keep the pinned upstream tree pristine. The OJVM integration is a small,
# reviewable patch overlay applied only to the disposable build tree.
for overlay in "$root"/patches/mochadoom/*.patch; do
  patch --batch --forward -d "$host_tmp/source" -p2 <"$overlay"
done
find "$host_tmp/source" -name '*.orig' -delete
# OJVM System.exit can tear down a live session JVM instead of returning a
# catchable stored-procedure error. Mechanically fence all 18 pinned upstream
# numeric exit sites in the disposable build tree, then fail closed if upstream
# introduces a shape this rewrite does not cover.
find "$host_tmp/source" -name '*.java' -exec perl -pi -e \
  's/System\.exit\((-?[0-9]+)\);/doomdb.mocha.OjvmExit.block($1);/g' {} +
if rg -n 'System\.exit\(' "$host_tmp/source"; then
  printf 'unfenced Mocha Doom System.exit path remains\n' >&2
  exit 1
fi

docker exec "$container" mkdir -p "$tmp/source" "$tmp/classes" "$tmp/adapter"
docker cp "$host_tmp/source/." "$container:$tmp/source" >/dev/null
docker cp "$root/java/mochadoom-ojvm/src/." "$container:$tmp/adapter" >/dev/null
docker cp "$root/tools/mochadoom/DoomMochaIwadLoader.java" \
  "$container:$tmp/DoomMochaIwadLoader.java" >/dev/null
docker cp "$host_tmp/freedoom1.wad" "$container:$tmp/freedoom1.wad" >/dev/null

docker exec -d "$container" bash -lc \
  "find '$tmp/source' '$tmp/adapter' -name '*.java' -print0 | \
   xargs -0 '$java_home/jdk/bin/javac' --release 11 -encoding UTF-8 \
     -J-Xms64m -J-Xmx256m \
     -cp '$java_home/jdbc/lib/ojdbc11.jar' -d '$tmp/classes' \
     >'$tmp/javac.log' 2>&1; printf '%s' \"\$?\" >'$tmp/javac.status'"
javac_status=""
for _ in $(seq 1 180); do
  if docker exec "$container" test -f "$tmp/javac.status"; then
    javac_status="$(docker exec "$container" cat "$tmp/javac.status")"
    break
  fi
  sleep 1
done
if [[ -z "$javac_status" ]]; then
  printf 'javac did not finish within 180 seconds\n' >&2
  docker exec "$container" tail -n 40 "$tmp/javac.log" >&2 || true
  exit 1
fi
if ((javac_status != 0)); then
  docker exec "$container" tail -n 80 "$tmp/javac.log" >&2 || true
  exit "$javac_status"
fi
docker exec "$container" bash -lc \
  "find '$tmp/classes' -name '*.class' -exec touch -t 200001010000 {} +; \
   cd '$tmp/classes'; find . -name '*.class' -print | LC_ALL=C sort >'$tmp/classes.list'; \
   '$java_home/jdk/bin/jar' --create --file '$tmp/mochadoom-ojvm.jar' \
     --no-manifest @'$tmp/classes.list'"

jar_sha="$(docker exec "$container" sha256sum "$tmp/mochadoom-ojvm.jar" | awk '{print $1}')"
class_count="$(docker exec "$container" bash -lc "find '$tmp/classes' -name '*.class' | wc -l")"

table_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tables where owner='DOOM' and table_name='DOOM_ENGINE_ARTIFACT';
SQL" | tail -n 1 | tr -d '[:space:]')"
if [[ "$table_present" == 0 ]]; then
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\\r\\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$root/sql/schema/041_mochadoom.sql"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
fi
command_table_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tables where owner='DOOM' and table_name='DOOM_MOCHA_COMMAND';
SQL" | tail -n 1 | tr -d '[:space:]')"
lineage_table_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tables where owner='DOOM' and table_name='DOOM_MOCHA_LINEAGE';
SQL" | tail -n 1 | tr -d '[:space:]')"
if [[ "$command_table_present" == 1 && "$lineage_table_present" == 0 ]]; then
  legacy_rows="$(docker exec "$container" bash -lc \
    "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from doom.doom_mocha_command;
SQL" | tail -n 1 | tr -d '[:space:]')"
  [[ "$legacy_rows" == 0 ]] || {
    printf 'legacy Mocha command ledger has %s rows; refusing destructive migration\n' \
      "$legacy_rows" >&2
    exit 1
  }
  docker exec "$container" bash -lc \
    "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
alter session set container=FREEPDB1;
drop table doom.doom_mocha_command cascade constraints purge;
SQL"
  command_table_present=0
fi
if [[ "$command_table_present" == 0 && "$lineage_table_present" == 1 ]]; then
  printf 'Mocha lineage table exists without its command table\n' >&2
  exit 1
fi
if [[ "$command_table_present" == 0 ]]; then
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$root/sql/schema/042_mocha_command.sql"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
fi
frame_cache_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tables where owner='DOOM'
  and table_name='DOOM_MOCHA_FRAME_CACHE';
SQL" | tail -n 1 | tr -d '[:space:]')"
if [[ "$frame_cache_present" == 0 ]]; then
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$root/sql/schema/043_mocha_frame_cache.sql"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
fi
save_slot_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tables where owner='DOOM'
  and table_name='DOOM_MOCHA_SAVE_SLOT';
SQL" | tail -n 1 | tr -d '[:space:]')"
if [[ "$save_slot_present" == 0 ]]; then
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$root/sql/schema/044_mocha_save_slot.sql"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
fi
initial_frame_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tables where owner='DOOM'
  and table_name='DOOM_MOCHA_INITIAL_FRAME';
SQL" | tail -n 1 | tr -d '[:space:]')"
if [[ "$initial_frame_present" == 0 ]]; then
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$root/sql/schema/045_mocha_initial_frame.sql"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
fi
frame_ledger_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tables where owner='DOOM'
  and table_name='DOOM_MOCHA_FRAME_LEDGER';
SQL" | tail -n 1 | tr -d '[:space:]')"
if [[ "$frame_ledger_present" == 0 ]]; then
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$root/sql/schema/046_mocha_frame_ledger.sql"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
fi
state_column_present="$(docker exec "$container" bash -lc \
  "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_tab_columns where owner='DOOM'
  and table_name='DOOM_MOCHA_COMMAND' and column_name='STATE_SHA';
SQL" | tail -n 1 | tr -d '[:space:]')"
if [[ "$state_column_present" == 0 ]]; then
  legacy_rows="$(docker exec "$container" bash -lc \
    "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from doom.doom_mocha_command;
SQL" | tail -n 1 | tr -d '[:space:]')"
  [[ "$legacy_rows" == 0 ]] || {
    printf 'Mocha command ledger has %s rows without state hashes\n' \
      "$legacy_rows" >&2
    exit 1
  }
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\r\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    printf '%s\n' 'whenever sqlerror exit failure rollback'
    printf '%s\n' 'alter table doom_mocha_command add state_sha varchar2(64) not null;'
    printf '%s\n' 'alter table doom_mocha_command drop constraint doom_mocha_command_sha_ck;'
    printf '%s\n' "alter table doom_mocha_command add constraint doom_mocha_command_sha_ck check(regexp_like(ticcmd_sha,'^[0-9a-f]{64}$') and regexp_like(state_sha,'^[0-9a-f]{64}$') and regexp_like(frame_sha,'^[0-9a-f]{64}$'));"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
fi
{
  printf 'connect DOOM/"'
  docker exec "$container" sh -c "tr -d '\\r\\n' < /run/secrets/doom_password"
  printf '"@FREEPDB1\n'
  cat "$root/sql/accel/030_mochadoom_calls.sql"
} | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog

docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$java_home/jdbc/lib/ojdbc11.jar" -d "$tmp" "$tmp/DoomMochaIwadLoader.java"
docker exec "$container" bash -lc \
  "DOOMDB_PASSWORD=\$(tr -d '\\r\\n' </run/secrets/doom_password) \
   '$java_home/jdk/bin/java' -cp '$tmp:$java_home/jdbc/lib/ojdbc11.jar' \
   DoomMochaIwadLoader 'jdbc:oracle:thin:@//localhost:1521/FREEPDB1' DOOM \
   '$tmp/freedoom1.wad' '$iwad_sha' '$revision'"

# The full resolver can detach from/close docker exec's controlling stream.
# Launch it detached and rendezvous through status files so that behavior
# cannot terminate this orchestration shell before verification runs.
docker exec -d "$container" sh -c \
  "'$java_home/bin/loadjava' -force -resolve -user DOOM@FREEPDB1 \
   '$tmp/mochadoom-ojvm.jar' < /run/secrets/doom_password \
   >'$tmp/loadjava.log' 2>&1; printf '%s' \"\$?\" >'$tmp/loadjava.status'"
load_status=""
for _ in $(seq 1 180); do
  if docker exec "$container" test -f "$tmp/loadjava.status"; then
    load_status="$(docker exec "$container" cat "$tmp/loadjava.status")"
    break
  fi
  sleep 1
done
if [[ -z "$load_status" ]]; then
  printf 'loadjava did not finish within 180 seconds\n' >&2
  docker exec "$container" tail -n 40 "$tmp/loadjava.log" >&2 || true
  exit 1
fi
if ((load_status != 0)); then
  printf 'loadjava returned %d; validating final schema-object status\n' \
    "$load_status" >&2
fi

# loadjava can return while Oracle's resolver is still finishing this 800+
# class graph. Wait for the schema to settle instead of sampling transient
# INVALID forward references.
resolved=0
for _ in $(seq 1 60); do
  invalid_count="$(docker exec "$container" bash -lc \
    "'$java_home/bin/sqlplus' -s / as sysdba <<'SQL'
set heading off feedback off pages 0
alter session set container=FREEPDB1;
select count(*) from dba_objects where owner='DOOM' and object_type in ('JAVA CLASS','JAVA RESOURCE') and status<>'VALID';
SQL" | tail -n 1 | tr -d '[:space:]')"
  if [[ "$invalid_count" == 0 ]]; then
    resolved=1
    break
  fi
  sleep 2
done
[[ "$resolved" == 1 ]] || {
  printf 'Mocha Doom Java graph did not resolve; invalid objects=%s\n' \
    "$invalid_count" >&2
  exit 1
}

{
  printf 'connect DOOM/"'
  docker exec "$container" sh -c "tr -d '\\r\\n' < /run/secrets/doom_password"
  printf '"@FREEPDB1\n'
  printf '%s\n' 'whenever sqlerror exit failure rollback'
  printf '%s\n' 'set heading off feedback off pages 0 lines 32767 serveroutput on'
  printf '%s\n' "merge into doom_config d using(select 'GAME_ENGINE' config_key,'MOCHA' text_value from dual)s on(d.config_key=s.config_key) when not matched then insert(config_key,text_value) values(s.config_key,s.text_value);"
  cat "$root/sql/sim/082_mochadoom_bridge.sql"
  cat "$root/scripts/mochadoom/compile-hot-renderer.sql"
  printf '%s\n' 'select doom_mocha_probe from dual;'
  printf '%s\n' 'select doom_mocha_iwad_probe from dual;'
  printf '%s\n' "declare n number; begin select count(*) into n from user_objects where object_type in ('JAVA CLASS','JAVA RESOURCE') and status<>'VALID'; if n<>0 then raise_application_error(-20000,'invalid Java objects='||n); end if; dbms_output.put_line('PASS MOCHADOOM-OJVM-RESOLVE classes=$class_count'); end;"
  printf '%s\n' '/'
} | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog

printf 'PASS MOCHADOOM-OJVM-BUILD classes=%s jar_sha256=%s\n' \
  "$class_count" "$jar_sha"
