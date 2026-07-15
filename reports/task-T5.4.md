# T5.4 implementation report

Status: **COMPLETE**

Implementation is complete against final evaluator manifest
`4d6b36bc6fd2bc7da822b5b267e46721805040844a3587ee043c22dd087d9e85`
and visible-golden manifest
`5f227adead95b36364b1d7bd06cd68a745ae4f55565885c21229bc7dc983c854`.
The evaluator and its manifests were not edited.

`sql/render/r2/040_presentation.sql` defines the reviewed
`DOOM_R2_PRESENTATION(p_session)` table SQL macro. It returns one stable winner
for each coordinate of the canonical 320x200 canvas. The set-based candidates
compose R2 world/masked pixels, selected first-person WAD weapon patches, the WAD
status bar, database-derived HUD numbers and keys, pause, menu and selection,
database-owned relational automap lines/player marker, and intermission patches
and statistics. Negative WAD texels remain transparent holes; HUD precedence is
above the weapon. All text and patch coordinates are clipped to the canvas.

The initial live composite exposed two production issues. Oracle did not expand
a SQL-macro parameter referenced inside a deep CTE, so the session predicate was
moved to the outer query, consistent with the working renderer macro pattern.
Oracle also merged the analytic world and masked views into a pathological plan;
materializing their already session/mode-bounded relations reduced one complete
GAME canvas from an abandoned run over 152 seconds to 25.73 seconds. Direct
backing-view timings were 18.71 seconds for 53,760 world rows and 4.57 seconds
for 4,738 selected masked rows. The complete repeated live evaluator took
199.06 seconds on the constrained two-CPU/two-GiB isolated database. No numeric
performance threshold applies.

Acceptance evidence:

```text
PASS T5.4-EVAL-SELF-CHECK (10328/10328 fixture-contract assertions)
PASS T5.4-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T5.4-SOURCE-AUDIT (1 SQL files; relational assets, state, geometry, stable set-based layers)
PASS T5.4-ORACLE-PRODUCTION
PASS T5.4-VISIBLE (22/22 test ids, 448566/448566 declared assertions)
PASS T5.3-VISIBLE (17/17 test ids, 988/988 declared assertions)
PASS T5.2-VISIBLE (20/20 test ids, 1856885/1856885 declared assertions)
PASS T5.1-VISIBLE (20/20 test ids, 674/674 declared assertions)
PASS T5.1-DYNAMIC-SECTOR-HEIGHTS (5/5 assertions)
PASS T1.2-static (10/10 assertions)
PASS T3.1-static (24/24 assertions)
PASS secret ignore audit
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
PASS DOOM_R2_PRESENTATION VALID
```

The isolated fresh bootstrap completed all 33 ordered entries, preserving the
32-entry audio/simulation stack and adding presentation immediately before
grants. Drop coverage and root T5.4 routing are integrated.

`scripts/capture-t5.4-review.mjs` captured nine real database frames in 162.42
seconds under `artifacts/t5.4-review`: pistol, shotgun, paused, menu selections
zero/two, normal/full automap, intermission, and hidden HUD values. Every PNG is
an indexed 320x200 image independently decoded back to the exact 64,000 SQL
palette bytes. All nine frame hashes are distinct, and their source inventories
contain the expected database layer kinds. Independent evaluator-only review
accepted all nine frames. Its final live recapture was byte-identical for 9/9
artifacts, and the final full evaluator again passed 22/22 IDs and
448,566/448,566 assertions. The implementation agent did not edit or approve the
evaluator/golden files.

After acceptance, the disposable `doomdb-t54-live` project, volume, and network
were removed. The default `doomdb` database/ORDS dashboard project remained
running and untouched.
