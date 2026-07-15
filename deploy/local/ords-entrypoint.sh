#!/usr/bin/env bash
set -Eeuo pipefail

secret_file=${ORACLE_PASSWORD_FILE:-/run/secrets/oracle_password}
if [[ ! -r "${secret_file}" ]]; then
  printf '%s\n' 'ERROR: ORDS database password secret is not readable.' >&2
  exit 1
fi

IFS= read -r ORACLE_PWD < "${secret_file}"
if [[ -z "${ORACLE_PWD}" ]]; then
  printf '%s\n' 'ERROR: ORDS database password secret is empty.' >&2
  exit 1
fi
export ORACLE_PWD
unset ORACLE_PASSWORD_FILE secret_file

# Oracle Free contains an ORDS repository, while a new ORDS config volume is
# empty. The official image treats that same-version combination as already
# installed and cannot create a connection pool. On the first run only, remove
# the bundled repository through the supported ORDS CLI; the vendor entrypoint
# immediately installs 26.2 again and writes the persistent pool configuration.
if [[ ! -f /etc/ords/config/global/settings.xml ]]; then
  mkdir -p /tmp/ords-uninstall
  printf '%s\n' "${ORACLE_PWD}" | /opt/oracle/ords/bin/ords uninstall \
    --admin-user sys \
    --password-stdin \
    --db-hostname "${DBHOST}" \
    --db-port "${DBPORT}" \
    --db-servicename "${DBSERVICENAME}" \
    --force \
    --log-folder /tmp/ords-uninstall
fi

exec /usr/bin/docker-entrypoint.sh "$@"
