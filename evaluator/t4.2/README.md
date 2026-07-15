# T4.2 independent R1 pixel evaluator candidate

Status: **pending explicit user approval**. This evaluator fixes R1 first-light
pixel semantics before production implementation. It does not modify or weaken
the pending T4.1 candidate it consumes.

## Reviewed production interface

T4.2 adds one standalone table SQL macro:

```sql
DOOM_R1_PIXELS(p_session VARCHAR2)
```

It reads the bound `GAME_SESSIONS`/`PLAYERS` row and
`DOOM_R1_NEAREST(p_session)`. It returns exactly 64,000 rows with columns
`SESSION_TOKEN`, `COLUMN_NO`, `ROW_NO`, `PALETTE_INDEX`, and `LAYER_ORDINAL`.
Coordinates are the complete Cartesian range 0..319 by 0..199, palette values
are 0..255, and R1 layer ordinals are floor `0`, ceiling `1`, solid wall `10`.
The macro is relational and reads dense texels from `AT` through `DOOM_ASSET`,
plus `DOOM_COLORMAP_TEXEL`; it does not persist the frame.

The canonical frame is the 64,000 palette bytes in `(column_no,row_no)` order.
Its SHA-256 is independent of session token and row-source order.

## Fixed R1 semantics

Projection and pixel centers follow Appendix C. The nearest solid hit's facing
sector supplies R1 floor, ceiling, and light. This documented nearest-sector
limitation is accepted only for R1. Floor and ceiling use reverse projection and
`floor_mod`, never Oracle `MOD`, before sampling 64x64 flats.

For a one-sided solid, the facing middle texture is sampled. For a closed
two-sided solid, upper is selected at/above the opposite ceiling and lower below
it; if that role is `-`, the first present role in upper, lower, middle order is
used. Horizontal wall position is seg offset plus distance along the seg plus
sidedef x offset. Vertical position uses pixel-center world z, y offset, and the
upper/lower unpegged flags. A missing/transparent required solid texel fails.

Light band is `clamp(floor((255-light_level)/8),0,31)`. Every floor, ceiling,
and wall texel is mapped through that `COLORMAP` band.

## Independent evidence

`reference.mjs` decodes the pinned WAD directly and contains its own patch,
texture-composition, flat, map, intersection, projection, and sampling logic. It
imports no production parser, seed SQL, renderer, manifest, or T4.1 oracle.
Visible expectations include a hand-authored mini-map and three E1M1 poses:
spawn east, spawn north, and spawn south. Central-west is deliberately excluded:
its nearest static closed line has no facing wall texture in the WAD and cannot
satisfy this task's solid-texture contract without inventing a fallback texel.

The live Oracle check proves exact cardinality, no gaps or duplicates, palette
range, independent spot pixels, raw-byte hashes, equal frames across distinct
sessions, and rerun stability. Source audits reject procedural pixel loops,
dynamic SQL, inline poses, expected frames/hashes, evaluator reads, default
number formatting, and test/caller inspection.

