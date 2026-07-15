# T2.4 implementation report

Status: PASS.

Route: `T2.4-IMPL | Terra | medium | attempt 1`.

## Deliverables

- `tools/wad/generate-seed.mjs` implements the approved six-input CLI and
  rejects any WAD other than Freedoom 0.13.0 Phase 1.
- `sql/seed/seed-manifest.json` and 537 sorted SQL files are checked in. The
  canonical SQL tree SHA-256 is
  `c3429549387c9f9b5ca71cebe8fa2b7c686c5f56c1dcf6c094a5080fee5cb3fc`.
- The tree contains 292 things, 1,196 vertices, 1,175 linedefs, 1,829
  sidedefs, 182 sectors, 2,057 segs, 682 subsectors, 681 nodes, 4,141 REJECT
  bytes, 7,528 BLOCKMAP bytes, palette 0, COLORMAP bands 0 through 31, 465
  selected WAD source rows, 566 assets, 854 asset-source relations, and
  3,040,239 dense signed texels.
- Texels use deterministic numeric asset ids in the compact `AT(A,X,Y,C)`
  seed relation. This avoids repeating kind/name strings in every dense row;
  `DOOM_ASSET` retains the exact closure identity and hashes. T3.1 must give
  `AT.A` a foreign key to `DOOM_ASSET.ASSET_ID` when it supplies the schema.
- Every statement has at most 500 logical rows. Every output byte is ASCII,
  LF-only, final-LF, and free of volatile data.

The bootstrap order was not changed: PLAN.md assigns the constrained schema
and ordered seed loader to T3.1, so these inserts cannot be loaded before that
schema exists.

## Verification

- approved visible evaluator: `PASS T2.4-VISIBLE (18/18 test ids, 168/168
  declared assertions)`;
- deterministic two-temporary-tree generation: covered by the visible suite;
- checked tree regeneration identity: 537/537 SQL hashes and manifest equal;
- semantic mutation execution: M01-M07 and M08-M14 were run sequentially in
  isolated temporary repositories, for 14/14 killed through assertion paths;
- M08 mutates the emitted last-occurrence selection rule because this pinned
  IWAD has no duplicated non-map asset lump names; only map lump names repeat,
  and those correctly use the separate map-confined selection rule;
- T2.1: 10/10; T2.2: 19/19 visible ids and 10/10 mutations; T2.3: 16/16
  visible ids and 12/12 mutations;
- immutable audit: all seven approved T2.4 evaluator files and three chained
  integrity baselines match their approved SHA-256 values;
- production-isolation audit: generator and generated SQL contain no evaluator,
  golden, expectation, mutation-spec, or test-id path/reference.
