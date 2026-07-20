import assert from 'node:assert/strict';
import fs from 'node:fs';

const compose = fs.readFileSync(new URL('../compose.yaml', import.meta.url), 'utf8');
const wrapper = fs.readFileSync(new URL('../deploy/local/ords-entrypoint.sh', import.meta.url), 'utf8');
const hook = fs.readFileSync(new URL('../deploy/local/ords-entrypoint.d/30-doomdb-autorest.sh', import.meta.url), 'utf8');
const dbWrapper = fs.readFileSync(new URL('../deploy/local/db-entrypoint.sh', import.meta.url), 'utf8');

assert.match(compose, /jetty-gzip\.xml:\/doomdb\/jetty-gzip\.xml:ro/);
assert.doesNotMatch(compose, /jetty-gzip\.xml:\/etc\/ords\/config/);
assert.match(wrapper, /mkdir -p \/etc\/ords\/config\/global\/standalone\/etc/);
assert.match(wrapper, /cp \/doomdb\/jetty-gzip\.xml/);
assert.match(compose, /DOOMDB_APP_PASSWORD_FILE: \/run\/secrets\/doom_password/);
assert.match(compose, /020_ords_enable\.sql:\/doomdb\/020_ords_enable\.sql:ro/);
assert.match(hook, /cat \/doomdb\/020_ords_enable\.sql/);
assert.match(hook, /sql -s \/nolog/);
assert.doesNotMatch(hook, /set -x|echo +["']?\$\{?password/i);
assert.match(dbWrapper, /java_pool_size=256m/,
  'two retained multiplayer sessions need headroom above the 117 MiB class graph');
assert.match(dbWrapper, /spfile_target=\$\(readlink -f "\$\{spfile_path\}"\)/);
assert.match(dbWrapper, /persisted_spfile="\$\{ORACLE_BASE\}\/oradata\/dbconfig/);
assert.match(dbWrapper, /create spfile='%s' from pfile/);

console.log('PASS LOCAL-ORDS-BOOTSTRAP ownership/autorest-postinstall');
