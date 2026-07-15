# T2.4 independent deterministic-seed evaluator candidate

This directory is evaluator-owned and pending explicit user approval. It fixes
the visible deterministic SQL seed contract before a production generator is
authored. Literal values were independently read from the pinned Freedoom
0.13.0 Phase 1 IWAD; approved T2.3 documents define the asset closure, but do
not supply expected hashes or texels.

## Production interface after approval

The implementation entrypoint is:

```sh
node tools/wad/generate-seed.mjs \
  --wad /path/to/freedoom1.wad \
  --engine-defs tools/wad/engine-defs.json \
  --asset-closure tools/wad/asset-closure.json \
  --animations tools/wad/animation-groups.json \
  --rng tools/wad/rng-table.json \
  --out /new-or-empty/output-directory
```

It writes `seed-manifest.json` and one or more `.sql` files beneath the output
directory. No other output file is allowed. Input documents and output paths
must not be inferred from evaluator paths or environment flags.

All output is 7-bit ASCII, LF-only, ends in LF, contains no volatile values,
and is byte stable. SQL uses explicit column lists and literal values. Each
insert statement is a complete Oracle statement ending in `;` and represents at
most 500 logical rows. Batches need not be independently rerunnable.

`seed-manifest.json` is canonical two-space JSON with this public shape:

- `schema:1`, `wadSha256`, `map:"E1M1"`, `encoding:"ASCII"`,
  `newline:"LF"`, `maxRowsPerBatch:500`;
- `planCounts` and `mapBounds`, exactly as fixed in `expectations.json`, plus
  player-one spawn `{thingIndex:157,x:-416,y:256,angle:0,flags:7}`;
- `sources`, one row per used WAD directory entry: `directoryIndex`, `name`,
  zero-based `occurrence`, `offset`, `size`, `sha256`, and
  `selection:"last-occurrence"` for globally looked-up lumps (map rows use
  `selection:"map-confined"`);
- `assets`, sorted by `(kind,name)`, with exact T2.3 closure keys, ordered
  `sourceLumps`, an ordered `sourceSha256` array, dimensions when decoded,
  `rawSha256` for single-lump raw assets, and `texelSha256` for flats and decoded
  patch/wall assets. A texel hash is SHA-256 of row-major signed int16 little-
  endian palette values; transparent is `-1`;
- `spotTexels`, exactly the approved literal probes;
- `files`, sorted by relative POSIX path, each containing `path`, `dataset`,
  `rowCount`, `batchCount`, `maxRowsInBatch`, and the exact byte `sha256`;
- `sqlTreeSha256`, SHA-256 over each sorted SQL file as
  `path + NUL + file-sha256 + LF`.

Manifest datasets must expose exact logical row totals for `things`, `vertices`,
`linedefs`, `sidedefs`, `sectors`, `segs`, `ssectors`, `nodes`, `rejectBytes`,
`blockmapBytes`, `paletteTexels`, `colormapTexels`, `wadSources`, `assets`,
`assetSources`, and `assetTexels`. SQL comments do not count as rows. Every
manifest source SHA and asset `(kind,name)` plus provenance relation must occur
in the seed SQL; unrelated WAD content is forbidden.

The E1M1 closure is exact: the generated asset-key set must equal
`asset-closure.json`, neither merely contain it nor expand names by namespace.
Duplicate WAD names use last-occurrence lookup, while the ten map inputs are
confined between E1M1 and the next map marker. PLAYPAL uses palette 0 only;
COLORMAP uses maps 0 through 31 only.

Run the candidate self-check with:

```sh
node evaluator/t2.4/self-check.mjs
```

After approval and implementation, `run-visible.mjs` performs two clean
generations and validates their complete trees. Mutation execution is deferred
until production exists; fourteen semantic mutation intents and named kill
tests are pinned now.
