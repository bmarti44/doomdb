# Oracle deadlock reconciliation — 2026-07-24

Status: **harness defects identified; affected diagnostics are not gate
evidence**.

The canonical application transaction lock order is:

```
DOOM_MATCH -> DOOM_MATCH_MEMBER
```

`DOOM_API` and the production MLE worker were audited against that order. The
worker paths which update members after a match update already acquired the
match row with `FOR UPDATE`; member-only maintenance transactions do not later
acquire the match row.

## Alert-log incidents

| Alert time (UTC) | Trace | Classification |
| --- | --- | --- |
| 2026-07-24 15:03:54 | `FREE_ora_310012.trc` | Harness-induced AB-BA. SQL*Plus held member rows then tried to update the match while the worker held the match and selected a member `FOR UPDATE`. Match `5cb6b0e8…`; not accepted gate evidence. |
| 2026-07-24 19:08:49 and 19:08:53 | `FREE_ora_117100.trc`, `FREE_ora_393369.trc` | Two trace sides of the same harness-induced AB-BA during fixed-128 v4 startup. SQL*Plus used member-then-match startup hold while `READY_MATCH` used match-then-member. Match `1f6604d1…`; v4 is VOID. |
| 2026-07-24 01:51:23 and 01:58:02 | `FREE_j003_183530_1.trc`, `FREE_j003_183530_2.trc` | Harness cleanup deleted the parent `DOOM_MATCH` row while Scheduler `J003` inserted a child `DOOM_MATCH_TIC` row. The 01:58 graph binds match `6e9144a6…`, the killed-session v3 diagnostic. This is a cleanup lifecycle race, not an MLE engine deadlock; v3 is diagnostic-only and not gate evidence. |

The original `FREE_j003_183530.trc` lacked the graph because Oracle rotated it
to `_1.trc` and `_2.trc`; both continuations contain readable graphs. Cleanup
now requests worker stop, waits for retained-slot release, and only then
deletes the match.

## Fixed-128 v3–v7 disposition

- v3: diagnostic failure/void; no PASS cited. Its 15:01–15:04 EDT window does
  not contain the 19:08 UTC AB-BA, but the run was already invalid for
  readiness/lifecycle reasons.
- v4: VOID due to the 19:08 UTC startup-hold/`READY_MATCH` AB-BA.
- v5: incomplete diagnostic; no terminal gate marker and no new ORA-00060 in
  its run window.
- v6: diagnostic failure/void; no terminal gate marker and no new ORA-00060
  in its run window.
- v7: accepted PASS. Its run window contains no new ORA-00060.

The soak harness now performs the startup hold in canonical match-before-member
order. Source verification checks the relative statement order, not merely the
presence of both statements. Long-run harnesses snapshot the Oracle alert log
before execution and fail evidence freeze if any new `ORA-` incident appears.
