# T5.4 implementation source-first report

Status: **SOURCE GATES PASS; LIVE ORACLE AND VISUAL CHECKPOINT PENDING**

The production source is `sql/render/r2/040_presentation.sql`. It defines the
frozen `DOOM_R2_PRESENTATION(p_session)` table SQL macro and does not modify the
approved evaluator or its manifests.

The macro produces a complete 320x200 canvas and deterministically chooses one
candidate per coordinate by descending layer ordinal and stable source identity.
It composes the existing R2 world and masked render, selected first-person
weapon, WAD status patch, database-derived numeric HUD values and keys, pause,
menu selection, database-owned automap, and intermission statistics. Transparent
WAD texels remain holes. Automap line pixels are a bounded set-based expansion
of `DOOM_LINEDEF` joined to `DOOM_VERTEX`; projected endpoints are never inputs.

Source-first verification:

```text
PASS T5.4-SOURCE-AUDIT (1 SQL files; relational assets, state, geometry, stable set-based layers)
PASS T5.4-EVAL-SELF-CHECK (10328/10328 fixture-contract assertions)
PASS T5.4-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS git diff --check
```

The shared Oracle stack and bootstrap/drop/verify/routing files remain untouched
while T7.3 owns them. Once released, the required remaining work is compilation
on the real schema, the live evaluator, a complete externally timed benchmark,
and actual per-mode PNG capture and visual inspection. No visual golden is
claimed by this source-first checkpoint.
