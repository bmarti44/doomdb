# T3.4 frozen-evaluator infrastructure blocker

Status: **resolved after explicit user approval on 2026-07-14**.

## Resolution

The user explicitly approved the minimal evaluator-only correction. The
reviewed declarations and bounded breadth-first traversal below replaced only
the nonterminating reachability statement; production SQL, fixtures, expected
values, stable test ids, and the 3,300-assertion total did not change.

The corrected evaluator was re-frozen and run against the preserved isolated
`doomdb-t34` database:

```text
PASS T3.4-EVAL-SELF-CHECK (60/60 fixture-contract assertions)
PASS T3.4-EVAL-MUTATION-SELF-CHECK (17/17 isolated mutations killed)
PASS T3.4-SOURCE-AUDIT (1 SQL files)
PASS T3.4-ORACLE-PRODUCTION
PASS T3.4-VISIBLE (17/17 test ids, 3300/3300 declared assertions)
PASS T3.4-EVAL-INTEGRITY (16/16 files)
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
```

Frozen hashes after the approved correction:

```text
ea19db8612dee2b72b13fa38f1169203b11062c9d82eec557d5ddace5e58271c  evaluator/t3.4/oracle-production.sql
6f1bd528776949ca4bc4b08f3fae80b810c38c11c7a9d556be134170400f5651  evaluator/integrity.pending-T3.4.json
```

## Implementation result before the blocker

The approved T3.4 production interface is implemented in
`sql/accel/010_blockmap_reject_graph.sql` using set-based SQL over
`DOOM_BLOCKMAP_BYTE`, `DOOM_REJECT_BYTE`, and the map relations.  It creates
the four reviewed constrained tables and the real `DOOM_SECTOR_GRAPH` SQL
property graph.  The frozen source checks pass:

```text
PASS T3.4-EVAL-SELF-CHECK (60/60 fixture-contract assertions)
PASS T3.4-EVAL-MUTATION-SELF-CHECK (17/17 isolated mutations killed)
PASS T3.4-SOURCE-AUDIT (1 SQL files)
```

An isolated `doomdb-t34` Compose project, database volume, and host port 15341
were used.  The complete checked-in seed, including 3,040,239 texels, was
loaded there.  The acceleration install completed and its fail-closed
`GRAPH_TABLE` scan returned 1,166 edges.

The frozen production evaluator advanced through the BLOCKMAP, REJECT, graph
document, catalog, and `GRAPH_TABLE` assertions to its penultimate statement.
That fact was confirmed directly from the active Oracle SQL id: PL/SQL executes
these statements in order, and the session's current statement was the later
reachability query shown below.  Therefore all preceding exact counts, ordered
document lengths, SHA-256 hashes, references, and graph assertions passed.

## Frozen query defect

The following approved evaluator statement enumerates every acyclic path in a
cyclic, symmetric multigraph before applying `COUNT(DISTINCT ...)`:

```sql
select count(distinct target_sector_id)
  into l_n
  from doom_sector_edge
 start with source_sector_id=140
connect by nocycle prior target_sector_id=source_sector_id;
```

`NOCYCLE` prevents an individual path from revisiting a row.  It does not
compute a visited vertex set across paths.  The number of simple paths is
combinatorial even though the expected connected component has only 38
sectors.  Parallel directed edges further multiply those paths.

Live evidence from the isolated pinned Oracle instance after allowing the
statement to run alone for nearly four minutes:

```text
SID 204 / SERIAL# 58451
SQL_ID cp77k8kbtx7z7
status ACTIVE
event resmgr:cpu quantum
executions 1
CPU 215.8 seconds
elapsed 230.8 seconds
buffer gets 32
rows processed 0
```

The evaluator session was then marked for kill only in the isolated T3.4
database.  Under the plan, a nonterminating evaluator statement is a failure,
not an informational result.

## Minimal evaluator-only correction

The pinned database rejects unbounded variable paths in SQL `GRAPH_TABLE`, so
the finite replacement below performs a breadth-first traversal over fixed
one-hop `GRAPH_TABLE` results.  It preserves the same start sector, edge label,
directed semantics, reachable-sector count, expected value 38, and existing
test id.  It terminates after at most the vertex count and completed in less
than one second on the same isolated database with `REACH=38`.

Add these evaluator-local declarations to the existing anonymous block:

```sql
type seen_sector_t is table of boolean index by pls_integer;
l_seen_sector seen_sector_t;
l_sector_queue sys.odcinumberlist := sys.odcinumberlist(140);
l_queue_head pls_integer := 1;
l_current_sector number;
```

Replace only the nonterminating `CONNECT BY` statement and its immediately
following assertion with:

```sql
l_seen_sector(140) := true;
while l_queue_head <= l_sector_queue.count loop
  l_current_sector := l_sector_queue(l_queue_head);
  for r in (
    select distinct source_sector_id, target_sector_id
      from graph_table(
        doom_sector_graph
        match (s is sector)-[e is passable]->(t is sector)
        columns (
          s.sector_id as source_sector_id,
          t.sector_id as target_sector_id
        )
      )
  ) loop
    if r.source_sector_id = l_current_sector
       and not l_seen_sector.exists(r.target_sector_id) then
      l_seen_sector(r.target_sector_id) := true;
      l_sector_queue.extend;
      l_sector_queue(l_sector_queue.count) := r.target_sector_id;
    end if;
  end loop;
  l_queue_head := l_queue_head + 1;
end loop;
l_n := l_sector_queue.count;
assert_eq(l_n,38,'spawn component reachability');
```

No production SQL, fixture, expected value, test id, assertion count, or other
evaluator statement needs to change.  Approval must be followed by re-freezing
the T3.4 integrity manifest and rerunning the full visible evaluator.
