# T2.3 implementation report

Status: implementation complete; behavior-scope review gate pending.

Route: `T2.3-IMPL | Sol | high | attempt 1`.

## Delivered

- `tools/wad/engine-defs.json`: 49 placed types, eight linedef specials, four
  sector specials, seven player weapons, 17 placed pickups, and 94 reachable
  states.
- `tools/wad/asset-closure.json`: stable canonical rows with direct WAD lump
  provenance for E1M1 surfaces, animation dependencies, sprites, sounds, music,
  and UI.
- `tools/wad/animation-groups.json`: the three approved ordered animation
  groups and eight-tic periods.
- `tools/wad/rng-table.json`: the independently derived 256-byte project table
  and persisted-cursor rule.
- `tools/wad/build-engine-defs.mjs`: deterministic generator using the pinned
  WAD and the production parser.
- `reports/t2.3-behavior-sources.md`: authorship, source, and license narrative.

The generator rejects any WAD whose digest or placed-type set differs from the
approved contract. It resolves wall dependencies through the production
parser's PNAMES indices and fails if any closure source lump is absent.

## Verification

All required checks passed on 2026-07-14:

- approved evaluator: `PASS T2.3-VISIBLE (16/16 test ids)`; 135/135 approved
  assertions;
- mutation harness: 12/12 isolated semantic mutations killed at their intended
  assertion paths;
- evaluator self-check: 36/36 fixture-contract assertions;
- immutable audit: seven T2.3 evaluator files and both earlier approved
  baselines match their reviewed SHA-256 values;
- production static audit: pass for every configured production root;
- earlier gates: T2.1 10/10, T2.2 235/235, and T2.2 mutations 10/10;
- two clean generator runs were byte-identical and equal to the checked-in
  artifacts.

Canonical artifact SHA-256 values:

- `engine-defs.json`: `bcedb529efa0299de09a417085f021808f113609beb0095ae3c6deabc905e48d`
- `asset-closure.json`: `6eddb35c9461f2c5d6740618697b3679b6b832b7651db29c99b20f240b402205`
- `animation-groups.json`: `4693bb2c02cf828f4d1c91620f1610616f470263646a128c83545a002bb79f99`
- `rng-table.json`: `70637d4dccf58ba76ed899e025a070bb726cb3311d909cafcc34b79702f0c846`

No approved evaluator, golden, expectation, or hash was changed.
