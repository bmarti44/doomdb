# T3.4 BLOCKMAP, REJECT, and sector graph implementation report

Status: **PASS**.

## Delivered

- `sql/accel/010_blockmap_reject_graph.sql` materializes the reviewed
  `DOOM_BLOCK_CELL`, `DOOM_BLOCK_LINE`, `DOOM_SECTOR_REJECT`, and
  `DOOM_SECTOR_EDGE` interfaces entirely with set-based SQL.
- BLOCKMAP decoding combines little-endian byte rows into words, sign-extends
  both origins, preserves every row-major cell and shared list offset, excludes
  framing words, and retains source membership ordinals and duplicates.
- REJECT decoding emits the full source-major sector-pair relation using
  least-significant-bit-first addressing with constrained zero/one values.
- Graph edges include both stable directions of each distinct-sector,
  two-sided linedef having positive static opening. Parallel physical edges
  remain distinct, and flag `0x40` supplies `sound_block` in both directions.
- `DOOM_SECTOR_GRAPH` is a real Oracle SQL property graph. Installation fails
  closed unless a fixed one-hop `GRAPH_TABLE` scan succeeds.
- The obsolete pre-T3.4 `DOOM_SECTOR_EDGE` definition was removed. Ordered
  property-graph/table teardown, the bootstrap acceleration allowlist/order,
  and `verify.sh task T3.4` are integrated without removing T3.2, T3.3, secret,
  or cloud behavior.

## Canonical production evidence

The complete fourteen-entry bootstrap was executed twice against the local
production schema. The second run first dropped the existing property graph
and dependent tables, proving complete-process idempotence, then reproduced:

```text
864 DOOM_BLOCK_CELL rows
2,064 DOOM_BLOCK_LINE rows
33,124 DOOM_SECTOR_REJECT rows
1,166 DOOM_SECTOR_EDGE rows
1,166 GRAPH_TABLE installation rows
BOOTSTRAP COMPLETE (14 files)
```

Canonical verification after the second rebuild:

```text
PASS T3.4-EVAL-SELF-CHECK (60/60 fixture-contract assertions)
PASS T3.4-EVAL-MUTATION-SELF-CHECK (17/17 isolated mutations killed)
PASS T3.4-SOURCE-AUDIT (1 SQL files)
PASS T3.4-ORACLE-PRODUCTION
PASS T3.4-VISIBLE (17/17 test ids, 3300/3300 declared assertions)
```

This includes exact binary-derived counts, references, dense ordinals,
negative origins/world minima, ordered BLOCKMAP document hash, all explicit
REJECT bits and probes, ordered REJECT document hash, symmetric graph edges,
opening bounds, ordered graph document hash, property-graph catalog validity,
fixed one-hop `GRAPH_TABLE` use, bounded spawn reachability, and isolated
sector counts.

## Integrity, mutation, regression, and isolation evidence

The corrected evaluator remained immutable during implementation. Its frozen
manifest and production SQL hashes were rechecked:

```text
6f1bd528776949ca4bc4b08f3fae80b810c38c11c7a9d556be134170400f5651  evaluator/integrity.pending-T3.4.json
ea19db8612dee2b72b13fa38f1169203b11062c9d82eec557d5ddace5e58271c  evaluator/t3.4/oracle-production.sql
```

All seventeen approved semantic mutation witnesses are killed by their named
assertion paths. Production source contains no procedural decoder, dynamic
SQL, evaluator/report/golden reads, caller or process inspection, embedded
expected documents, or fixture-specific branches.

Regression and policy checks:

```text
PASS T3.3-VISIBLE (15/15 test ids, 455/455 declared assertions)
PASS T3.2 (136/136 assertions)
PASS T3.1-static (24/24 assertions)
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
PASS T1.3 (12/12 assertions)
PASS secret ignore audit (8 ignored paths, 3 visible templates, no tracked secret-like paths)
PASS production isolation audit
```

The temporary `doomdb-t34` container, network, and volume were removed after
verification. The long-lived shared database volume predated T3.3's new
first-volume DBMS_CRYPTO initialization mount, so its intended direct grant was
reconciled once through SYS before the canonical checks. Fresh volumes already
receive that grant automatically and no credential was written to source or
output.
