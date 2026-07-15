# T4.3 first-light checkpoint evaluator candidate

This evaluator consumes the pending T4.2 table SQL macro
`DOOM_R1_PIXELS(p_session VARCHAR2)` without changing its public contract. The
adapter captures exactly 64,000 rows as `{column,row,cidx}` and independently
derives Appendix E column runs in SQL. An observation JSON contains `schema`,
the bound `pose`, the 256-entry PLAYPAL `palette`, captured `rows`, and SQL
`cols`. `run-observation.mjs` performs a separate Node expansion, raw-RGBA
conversion, deterministic indexed-PNG encoding, PNG parsing, and diagnostics.

The generated PNG and RGBA artifacts are review material, not approved visible
goldens. `fixtures.json` deliberately says `PENDING` and contains no golden
hash. After implementation produces all three images, execution must stop for
the user's visual decision. Only an explicit approval may populate a separately
reviewed golden baseline and make the visible-golden acceptance active.

`capture-pose.sql` is the evaluator-only database adapter. Its three spools
observe pixels, PLAYPAL, and an analytic SQL run grouping separately.
`build-observation.mjs` converts those numeric CSV files without importing any
production module. `run-observation.mjs` then supplies the second implementation
of RLE expansion, palette conversion, PNG encoding, and PNG parsing.

Candidate-only checks:

```sh
node evaluator/t4.3/self-check.mjs
node evaluator/t4.3/mutation-self-check.mjs
node evaluator/t4.3/source-audit.mjs
```
