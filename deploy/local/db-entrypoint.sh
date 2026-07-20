#!/usr/bin/env bash
set -Eeuo pipefail

# The pinned image's default memory target cannot open FREEPDB1 reliably inside
# the required 2 GiB cgroup. Recreate its SPFILE from Oracle's generated PFILE
# before the vendor entrypoint starts, using supported Oracle configuration.
pfile_source=$(find /opt/oracle/admin/FREE/pfile -maxdepth 1 -type f -name 'init.ora.*' -print -quit)
if [[ -z "${pfile_source}" ]]; then
  printf '%s\n' 'ERROR: Oracle generated PFILE was not found.' >&2
  exit 1
fi

cp "${pfile_source}" /tmp/doomdb-init.ora
sed -i \
  -e 's/^sga_target=.*/sga_target=1024m/' \
  -e 's/^pga_aggregate_target=.*/pga_aggregate_target=256m/' \
  /tmp/doomdb-init.ora
# Reserve viable floors for the retained OJVM graph and the database's hot
# relational working set. Oracle Free may rebalance above these floors inside
# its fixed 1 GiB SGA as classes and game ledgers become hot.
printf '%s\n' \
  'shared_pool_size=256m' \
  'java_pool_size=256m' \
  'db_cache_size=256m' >>/tmp/doomdb-init.ora

spfile_path="${ORACLE_HOME}/dbs/spfileFREE.ora"
# On initialized volumes this is a symlink into /opt/oracle/oradata/dbconfig.
# Replacing only the symlink creates an orphan DB-home file which the vendor
# entrypoint discards when it restores the persistent link.
persisted_spfile="${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}/spfile${ORACLE_SID}.ora"
if [[ -e "${persisted_spfile}" ]]; then
  spfile_target="${persisted_spfile}"
  rm -f "${spfile_target}"
elif [[ -L "${spfile_path}" && -e "${spfile_path}" ]]; then
  spfile_target=$(readlink -f "${spfile_path}")
  rm -f "${spfile_target}"
else
  spfile_target="${spfile_path}"
  rm -f "${spfile_target}"
fi
printf "create spfile='%s' from pfile='/tmp/doomdb-init.ora';\nexit\n" \
  "${spfile_target}" | sqlplus -s / as sysdba
unset spfile_path persisted_spfile spfile_target

exec /opt/oracle/container-entrypoint.sh
