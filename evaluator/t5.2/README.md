# T5.2 clip-window and interval-plane evaluator candidate

Status: **approved under standing user authorization**. This evaluator adds no
production SQL and does not modify T4 or T5.1 public contracts. Its inherited
integrity pointer pins the final accepted T5.1 manifest, which in turn pins the
current complete renderer and human-reviewed visible-golden chain.

The user's standing authorization was separately applied after direct
original-resolution inspection of the actual database-generated T5.2 spawn-east
frame and a from-scratch indexed-PNG decode. `goldens/integrity-T5.2.json` pins
that approved 320x200 PNG and its concrete review record. This visual freeze did
not change the analytic mini-scenes, expectations, assertions, mutations,
reference renderer, Oracle runner, or reviewed production interface.

## Reviewed production interface

T5.2 adds the bound table SQL macro `DOOM_R2_PIXELS(p_session VARCHAR2)`.
It returns exactly 64,000 rows with `SESSION_TOKEN`, `COLUMN_NO`, `ROW_NO`,
`PALETTE_INDEX`, `LAYER_ORDINAL`, and `SECTOR_INTERVAL_ORDINAL`. Layer ordinals
are floor `0`, ceiling `1`, sky `3`, unobstructed interval plane `4`, inherited
solid wall `10`, lower portal piece `11`, and upper portal piece `12`.

The macro consumes the frozen T5.1 `DOOM_R2_PORTAL_HITS` and
`DOOM_R2_SECTOR_INTERVALS` relations. Running analytic upper/lower screen clip
bounds select visible portal pieces. Floor and ceiling reverse projection selects
the sector interval containing reconstructed depth; it never falls back to the
R1 nearest-sector limitation.

Adjacent `SKY1` ceilings suppress their upper wall piece. Sky is camera mapped
and full-bright. Other texels pass once through the active sector's floored,
clamped COLORMAP band. Animation frame selection uses persisted `CURRENT_TIC`
and checked-in animation groups. Horizontal wall coordinate includes analytic
distance, seg offset, and signed sidedef x offset. Vertical origin applies the
role-specific upper/lower unpegged bit before signed sidedef y offset. Negative
coordinates use floor modulus with the actual asset dimensions.

## Independent oracle

`reference.mjs` is a hand-authored analytic mini-scene renderer independent of
production SQL, seed output, and earlier renderer oracles. Seven 320x200 scenes
isolate a height step, narrow window, adjacent sky, flat/wall animation at tic
17, signed offsets, upper pegging, and lower pegging. Each scene freezes all
64,000 unique palette indices, layer counts, spot pixels, and a complete
palette-byte SHA-256. The manifest declares 20 stable IDs and 1,856,885
assertions. Eighteen mutations cover interval selection, clip pieces, sky,
animation, offsets, pegging, modulus, pixel centers, COLORMAP, pixel integrity,
set-based SQL, recursion, dynamic SQL, and embedded answers.
