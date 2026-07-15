# T5.1 portal and sector timeline evaluator candidate

This evaluator is approved under the user's standing authorization. It adds no
production SQL and does not modify T4 evaluators, the root verifier, or reviewed
render contracts. Its integrity chain pins the completed T4.2 implementation,
the completed T4.3 evaluator, and the separately reviewed T4.3 visible goldens.

The fixed production interface consists of two session-bound table SQL macros:

- `DOOM_R2_PORTAL_HITS(p_session VARCHAR2)` retains every `DOOM_R1_HITS` row
  with `SESSION_TOKEN`, `COLUMN_NO`, `HIT_ORDINAL`, `HIT_T`, `HIT_U`,
  `LINEDEF_ID`, `SEG_ID`, `FACING_SIDE`, facing/opposite sidedef and sector ids,
  `IS_ACTIVE`, `FROM_SECTOR_ID`, `TO_SECTOR_ID`, opening and upper/lower piece
  bounds, and closed/transition/termination flags.
- `DOOM_R2_SECTOR_INTERVALS(p_session VARCHAR2)` exposes `SESSION_TOKEN`,
  `COLUMN_NO`, `INTERVAL_ORDINAL`, `T_START`, `T_END`, `SECTOR_ID`, current
  floor/ceiling, terminating linedef id, and final-interval flag.

Every analytic hit is retained, including incompatible coincident hits and hits
after a solid termination. Only active, sector-compatible rows advance the
timeline. Openings are `[max(floors), min(ceilings)]`; equality is closed.
Facing-to-opposite height differences define upper/lower pieces. Stable order is
exactly `(hit_t, linedef_id, seg_id, facing_side)` without early rounding.

The independent JavaScript oracle imports no production parser or renderer. Its
hand-authored scenes cover a window, chained steps, open and closed doors,
overlap, a vertex tie with a deliberate zero-length interval, three nested
portals, one-sided termination, and an unterminated far interval. Joint
translation is byte-identical. Reflection preserves all timeline semantics and
flips only the facing-side bit within numeric tolerance.

The manifest declares 20 stable IDs and 674 assertions. Eighteen semantic
mutations cover nearest-only reduction, tie/facing reversal, compatibility,
opening math, closed equality, forced portals, missing pieces, stale sector,
far/final interval, determinant/rounding, procedural loops, static heights, and
fixture embedding. The production source audit is deliberately fail-closed and
will remain red until the approved implementation exists.
