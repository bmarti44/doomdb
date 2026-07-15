# T5.4 weapon, HUD, menu, pause, automap, and intermission evaluator candidate

This evaluator is approved under the user's standing authorization after an
evaluator-only dependency refresh. It adds no production SQL, does not modify
earlier evaluators, and now pins the separately reviewed nine-frame T5.4 visible
golden manifest. The human checkpoint directly inspected every actual 320x200
database PNG and independently verified PNG CRC/IDAT/palette/frame identity,
state-difference regions, and deterministic live recapture.

The frozen ancestry pins final T5.1 (`7b02f8ce...`), final T5.2
(`b95895c2...`) and its reviewed visible manifest (`e59b635c...`), plus final
T5.3 (`8e5969b5...`) and its reviewed visible manifest (`24b54356...`). This
refresh changes no T5.4 behavior, fixture, expectation, assertion, mutation,
reference, Oracle runner, source policy, golden, or production interface.

The accepted T5.4 visible manifest is `goldens/integrity-T5.4.json` at
`5f227adead95b36364b1d7bd06cd68a745ae4f55565885c21229bc7dc983c854`.
It freezes pistol, shotgun, pause, two menu selections, normal/full automap,
intermission, and hidden HUD values. The evaluator semantics, 22 IDs/448,566
assertions, and 18 mutations remain unchanged.

The fixed production interface is one session-bound table SQL macro:

- `DOOM_R2_PRESENTATION(p_session VARCHAR2)` returns exactly 64,000 rows with
  `SESSION_TOKEN`, `COLUMN_NO`, `ROW_NO`, `PALETTE_INDEX`, `LAYER_ORDINAL`,
  `SOURCE_KIND`, and `SOURCE_ID`.

The result is the final 320x200 palette canvas, not an overlay. World pixels are
composed first; weapon, HUD, menu, pause, automap, and intermission decisions are
database-owned. WAD patch holes have texel `-1` and preserve the lower layer.
The stable winner for a coordinate is the highest reviewed layer ordinal, then a
stable source identity. Final palette indices are always 0 through 255.

`GAME_SESSIONS.GAME_MODE`, `PAUSED`, `MENU_STATE`, and `AUTOMAP_STATE`, plus the
current `PLAYERS` row, are the only presentation controls. The macro resolves
art through `DOOM_ASSET` and `AT`. Database-generated text is clipped to the
canvas and is not browser text. Automap source lines are projected and rasterized
from `DOOM_LINEDEF`/`DOOM_VERTEX`; `AUTOMAP_STATE='FULL'` reveals hidden lines.
The client never supplies projected endpoints.

The independent JavaScript oracle imports no production parser, SQL, or renderer.
It uses hand-authored transparent patch matrices, glyphs, line geometry, and
state variations. It freezes nine complete 64,000-byte documents: ordinary game,
alternate weapon, pause, two menu selections, ordinary/full automap,
intermission, and HUD health/ammo/key variation. Region-difference checks isolate
weapon, pause, menu selection, hidden automap geometry, and HUD fields.

The manifest declares 22 stable IDs and 448,566 assertions. Eighteen isolated
mutations cover transparency, weapon selection/placement, HUD/text, pause,
automap state/ownership, menu selection, layer order, relational WAD provenance,
exact canvas size, deterministic ties, clipping, procedural loops, and evaluator
coupling. The fail-closed source audit remains red until implementation exists.
