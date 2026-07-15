# T5.2 implementation report

Status: **COMPLETE** against promoted evaluator manifest
`62bca74b9f9916a5dfb2c3f1543322356982c3ac1c3c025e5842242ee34cc5fe`
and visible-golden integrity
`e59b635cdda850ae092d940ac38fb62cbf8e8b2e1ea6812ad67b61a7ebcc4995`.

Route: `T5.2-IMPL | Sol | high | attempt 1`.

`sql/render/r2/020_pixels.sql` adds the session-bound
`DOOM_R2_PIXELS(p_session)` table SQL macro and its set-based backing views. It
keeps the complete T5.1 sector timeline, computes cumulative portal clip
windows with analytic `MAX`/`MIN`, reverse-projects floor and ceiling samples
into their owning sector intervals, suppresses shared-sky upper pieces, maps
sky full-bright, advances checked-in flat/wall animation groups from
`GAME_SESSIONS.CURRENT_TIC`, honors signed sidedef/seg offsets and distinct
upper/lower pegging anchors, applies negative-safe floor modulus, and maps each
raw texel through the active sector COLORMAP band.

Fresh isolated bootstrap installed 537 deterministic seed files and all 25
ordered SQL entries. The existing 24-entry order was preserved and the R2
pixel renderer was appended immediately after the portal timeline and before
grants. Drop coverage, the root T5.2 task route, and the live dashboard capture
were added. All three production objects (`DOOM_R2_ANIMATION_FRAMES`,
`DOOM_R2_PIXEL_ROWS`, and `DOOM_R2_PIXELS`) compiled `VALID`.

Acceptance evidence:

```text
PASS T5.2-EVAL-SELF-CHECK (56/56 fixture-contract assertions)
PASS T5.2-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T5.2-SOURCE-AUDIT (1 SQL file; analytic clip windows, interval planes, animation, sky and pegging)
PASS T5.2-VISIBLE-GOLDEN (1/1 human-reviewed database PNG)
PASS T5.2-ORACLE-PRODUCTION (9 live checks; SHA-256 df931aead5a878018c9ad36cff0b73ed56545b290dcff9f59001fbec9a3f11f4)
PASS T5.2-VISIBLE (20/20 test ids, 1856885/1856885 declared assertions)
PASS T5.1-VISIBLE (20/20 test ids, 674/674 declared assertions)
PASS T5.1-DYNAMIC-SECTOR-HEIGHTS (5/5 assertions)
PASS T7.1-VISIBLE (23/23 test ids, 1582/1582 declared assertions)
PASS T7.1-HISTORY-CLOSURE
PASS T1.2-static (10/10 assertions)
PASS secret ignore audit
```

The reviewed database frame and dashboard frame are byte-identical indexed
PNGs with SHA-256
`e98ba9a6a894cc091d000f1c00cc0ed0b41d51ac5397818e836e5a73b1d47711`.
The dashboard labels it as human-reviewed R2 output and applies only the
database-provided palette in the browser. No mock pixels or evaluator data are
used in rendering decisions.
