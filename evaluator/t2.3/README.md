# T2.3 independent visible evaluator candidate

This directory is evaluator-owned and pending explicit user approval. It fixes
the visible E1M1 asset/behavior scope before production engine definitions are
authored. Its literal expectations came from an evaluator-owned reader over the
pinned Freedoom 0.13.0 Phase 1 IWAD and from the public behavior contract below,
not from production parser output or Doom engine tables.

## Production interface evaluated after approval

T2.3-IMPL supplies these canonical, two-space-indented JSON files with a final
LF and object keys in the documented order:

- `tools/wad/engine-defs.json`: `schema`, `wad`, `sources`, `thingTypes`,
  `linedefSpecials`, `sectorSpecials`, `weapons`, `pickups`, `states`.
- `tools/wad/asset-closure.json`: `schema`, `wadSha256`, `map`, `assets`.
- `tools/wad/animation-groups.json`: `schema`, `groups`.
- `tools/wad/rng-table.json`: `schema`, `algorithm`, `derivation`, `cursorRule`,
  `values`.
- `reports/t2.3-behavior-sources.md`: a human-readable independent-behavior and
  license narrative matching the structured source records.

Every structured behavior row has nonempty `sourceIds`. A source has `id`,
`title`, `url`, `license`, `usage`, and `copiedCodeOrData:false`. GPL Doom source
may be cited only as behavioral research, never as the origin of registry data,
state tables, arrays, copied code, or translated control flow. Freedoom is the
BSD-3-Clause data/art origin. Public file-format and behavior specifications,
the PLAN contract, and hand-authored project decisions are acceptable origins.

Each of the 49 placed thing types has a row with `id`, `name`, `category`,
`spawnState`, `sourceIds`, plus
category-specific behavior. The five interactive monster rows additionally have
positive `health`, named `seeState`, `attackState`, `painState`, `deathState`,
an optional resolvable `dropType`, and sound references. Each special has `id`,
exact `semantics`, and `sourceIds`. Each weapon has the expected `id`, a nullable
`thingType`, `ammoType`, resolvable `readyState`, `fireState`, `refireState`, and
`flashState`, sound references, and `sourceIds`. Each placed pickup has
`thingType`, a concrete bounded `effect`, `consume:true`, a pickup sound, and
`sourceIds`.

States have unique `id`, integer `tics` (`-1` means a stable terminal), `next`
(null only for a terminal), a concrete non-placeholder `action`, `sourceIds`,
optional sound, and sprite `{prefix,frame,rotations}`. `rotations` is either
`"0"` or `"ALL"`; the evaluator resolves the corresponding pinned WAD lumps.
All thing roots are walked with a finite visited set. Every reference and every
sprite/sound asset encountered must resolve.

Closure assets have unique `(kind,name)`, nonempty `reasons`, and exact
`sourceLumps`. Kinds are `wall_texture`, `flat`, `patch`, `sprite_patch`,
`sound`, `music`, and `ui_patch`. Wall texture `sourceLumps` are the exact PNAMES
patch dependencies in order. Every source lump must exist in the pinned WAD.

The RNG is independently reproducible: concatenate SHA-256 output bytes for the
ASCII labels `DoomDB project RNG v1|0000`, `...|0001`, and so on, then take the
first 256 bytes. Runtime reads the checked-in values and persists a modulo-256
cursor; every gameplay random read advances it exactly once. This is deliberately
not Doom's `P_Random` table.

Run the evaluator-only candidate check now with:

```sh
node evaluator/t2.3/self-check.mjs
```

After implementation, `node evaluator/t2.3/run-visible.mjs` fails closed unless
all five production documents and their graph/closure facts satisfy this
approved contract. Mutation execution is intentionally deferred until an
implementation exists; the candidate pins twelve semantic mutation intents and
their kill tests.
