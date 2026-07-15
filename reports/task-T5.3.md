# T5.3 implementation report

Status: **COMPLETE** against final promoted evaluator manifest
`8e5969b517dac26fa2143dfd6cbedee9cde1ec1a0e09eca775a4f72070aebc1b`
and human-reviewed visible-golden integrity
`24b543562a13c80db22edd376e93a7a5b3c30d28dc2e01db7d28a165210c0860`.

Route: `T5.3-IMPL | Sol | high | attempt 1`.

`sql/render/r2/030_masked.sql` adds the session-bound
`DOOM_R2_MASKED_CANDIDATES(p_session)` and
`DOOM_R2_MASKED_PIXELS(p_session)` table SQL macros. The relational pipeline
projects transparent two-sided middle textures and current `MOBJS`, resolves
rotation-zero and eight-way directional sprite assets including dual-name
mirrors, retains palette zero while discarding absent texels, applies screen,
portal-window, and strict solid-wall depth clips, and selects one deterministic
winner by unrounded depth, source class, stable source id, asset row, and asset
column. All 123 reviewed sprite patches carry their immutable WAD origin
offsets in a relational production catalog.

The existing 28-entry simulation/render bootstrap was preserved and T5.3 was
appended as entry 29 immediately after `DOOM_R2_PIXELS`. Dependency-safe drop
coverage and the root `T5.3` task route were added. The isolated Oracle stack
compiled the three views and two SQL macros `VALID` with no invalid production
objects.

Acceptance evidence:

```text
PASS T5.3-EVAL-SELF-CHECK (346/346 fixture-contract assertions)
PASS T5.3-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T5.3-SOURCE-AUDIT (1 SQL file; set-based masked and sprite composition)
PASS T5.3-ORACLE-PRODUCTION
PASS T5.3-VISIBLE (17/17 test ids, 988/988 declared assertions)
PASS T5.2-VISIBLE (20/20 test ids, 1856885/1856885 declared assertions)
PASS T5.1-VISIBLE (20/20 test ids, 674/674 declared assertions)
PASS T5.1-DYNAMIC-SECTOR-HEIGHTS (5/5 assertions)
PASS T1.2-static (10/10 assertions)
PASS T3.1-static (24/24 assertions)
PASS secret ignore audit
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
```

The live evaluator completed in approximately 20 seconds on the constrained
two-CPU/2-GiB isolated database; no numeric performance threshold was imposed.
An initially unbounded off-screen projection was replaced with bounded on-screen
sampling plus one opaque representative candidate for a wholly off-screen
billboard, preserving the explicit screen-clip fact while preventing near-plane
candidate explosion. The unchanged frozen live suite remained green afterward.

Independent review approved three actual 320x200 database frames. Overlay counts
were 7,106 at spawn, 335 facing north, and 105 facing south. Frame SHA-256 values
begin `f34741d9`, `5ae974c2`, and `3fe12e73`; reviewed PNG SHA-256 values begin
`3b9dec01`, `05493918`, and `49892ad4`. Independent indexed-PNG decoding matched
all 64,000 SQL palette pixels per pose. The dashboard now serves those exact
reviewed bytes with a pose selector and overlay/source diagnostics.

During the dependency cascade, the independent evaluator team corrected the
T5.1 source audit's `WINDOW` substring false positive without changing T5.1
behavior or production. T5.3 consumed only the resulting final T5.1/T5.2
manifests. A separate evaluator-only T5.3 correction named the final
`SECTOR_STATE` columns and supplied `DAMAGE_CLOCK=0`; production and all masked
renderer expectations remained unchanged.
