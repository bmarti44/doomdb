#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

must_ignore=(
  secrets/oracle_password.txt
  secrets/nested/service.token
  .env
  deploy/cloud/.env.production
  private.key
  cloud/wallet/cwallet.sso
  terraform/production.tfvars
  .tmp-secret-audit/password.txt
)

for path in "${must_ignore[@]}"; do
  if ! git check-ignore --quiet --no-index "$path"; then
    printf 'secret path is not ignored: %s\n' "$path" >&2
    exit 1
  fi
done

must_remain_visible=(
  secrets/oracle_password.txt.example
  .env.example
  deploy/cloud/.env.production.example
)

for path in "${must_remain_visible[@]}"; do
  if git check-ignore --quiet --no-index "$path"; then
    printf 'safe example template is unexpectedly ignored: %s\n' "$path" >&2
    exit 1
  fi
done

while IFS= read -r path; do
  case "$path" in
    *.example|tests/fixtures/*) continue ;;
  esac
  if [[ "$path" =~ (^|/)secrets?/ ]] ||
     [[ "$path" =~ (^|/)\.env($|\.) ]] ||
     [[ "$path" =~ \.(key|pem|p12|pfx|jks|keystore|token|secret|secrets|tfvars)$ ]] ||
     [[ "$path" =~ \.tfvars\.json$ ]]; then
    printf 'tracked secret-like path requires removal or an explicit safe-template exception: %s\n' "$path" >&2
    exit 1
  fi
done < <(git ls-files)

printf 'PASS secret ignore audit (%d ignored paths, %d visible templates, no tracked secret-like paths)\n' \
  "${#must_ignore[@]}" "${#must_remain_visible[@]}"
