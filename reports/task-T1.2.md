# T1.2 ordered bootstrap report

- Route: Luna medium
- Attempt: 1
- Added a fail-fast SQL wrapper accepting a filename or standard input.
- Every entry pins numeric, territory, language, and time-zone session settings.
- Added an explicit, duplicate-rejecting bootstrap order manifest.
- Added an idempotent bootstrap-state DDL/DML unit.
- Evaluator schema deletion is restricted to `DOOMDB_EVAL[_SUFFIX]`.
- Static verification: `PASS T1.2-static (10/10 assertions)`.
- Live verification on a fresh Compose stack: `PASS T1.2-live (5/5
  assertions)`. Two complete bootstraps produced the same semantic row; an
  injected failing seed statement returned nonzero and left that row unchanged.
