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

rm -f "${ORACLE_HOME}/dbs/spfileFREE.ora"
printf "create spfile='%s/dbs/spfileFREE.ora' from pfile='/tmp/doomdb-init.ora';\nexit\n" \
  "${ORACLE_HOME}" | sqlplus -s / as sysdba

exec /opt/oracle/container-entrypoint.sh
