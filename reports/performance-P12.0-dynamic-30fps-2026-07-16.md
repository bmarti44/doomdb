# P12.0 dynamic database-worker 30 FPS gate — 2026-07-16

## Result

The strict-durable retained database worker passed its active early-game
300-frame gate at **20.065 ms p50 / 26.008 ms p95**, equivalent to **49.8 / 38.4
FPS**. The maximum was 435.884 ms from an isolated OJVM JIT pause; this report
claims the required p95 result, not hitch-free maximum latency.

The measured boundary includes command preparation, relational delta apply,
canonical state/checkpoint handling, exact retained rendering, packed-v2 codec,
SecureFile response persistence, `COMMIT WRITE BATCH WAIT`, post-commit accept,
and correlated AQ response lookup. It excludes ORDS, network, browser decode,
and blit.

## Selected changes

- Retained projectile mutations use ordered world operations; no relational
  row walking occurs inside OJVM and world cardinality remains stable.
- DTIC carries only changed monster records. SQL validates their ordered IDs
  and catalog/world references, then applies them with bulk DML.
- World update/removal operations use one `FORALL MERGE` path.
- Projectile impact is one information-complete event; its damage and target
  are carried by `PROJECTILE_IMPACT` rather than a redundant second event.
- Exact canonical JSON and history snapshots occur every 64 tics. Intermediate
  `state_sha` values are domain-separated hashes over lineage, tic, command
  chain, and durable delta SHA; explicit state reads remain relational.

## Acceptance evidence

- `unified_worker_checkpoint_state_contract=OK|5|64`
- `unified_worker_event_chain_contract=OK`
- `unified_worker_owner_sql_parity=OK|330|330|280`
- rollback/discard, post-commit recovery, restart fencing: PASS
- two-slot/SID isolation and restart: PASS

Passing-run p95 stages were: prepare 2.380 ms, apply 6.059 ms, state 0.347 ms,
render 11.125 ms, and commit 2.230 ms. Percentiles are independently ranked and
are not additive.

## Remaining boundary

This is a database-worker gate, not a public-playability completion claim. The
worker remains default-off, the public AutoREST route still selects the slow SQL
reference renderer, action bytes for fire/use/weapon selection are not yet
connected, and the fixed ORDS/browser 300-frame measurement remains pending.
