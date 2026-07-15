# T4.2 solid wall, floor, ceiling, texture, and light

Status: **PASS**.

Route: `T4.2-IMPL | Sol | high | attempt 3`.

## Acceptance

The approved, corrected frozen evaluator passed on a fresh isolated Oracle Free
23ai stack constrained to 2 CPUs and 2 GiB:

```text
PASS T4.2-EVAL-SELF-CHECK (139/139 fixture-contract assertions)
PASS T4.2-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T4.2-SOURCE-AUDIT (1 SQL files; canonical order; no procedural pixel loop or dynamic SQL; no expected frame)
PASS T4.2-ORACLE-PRODUCTION (101 live checks)
PASS T4.2-VISIBLE (20/20 test ids, 384426/384426 declared assertions)
real 587.08
```

Frozen evaluator integrity remained exact:

```text
b58d3423a5a4b7b67bd8ff5e776cbee590421fd5c80ee5af3d0da810d192f57e  evaluator/t4.2/oracle-production.sql
1cd2021266edea250fd11f9d285a5cdeb3d1fe826c5b557a3d95408d4cd70429  evaluator/integrity.pending-T4.2.json
```

## Production result

`sql/render/r1/020_pixels.sql` defines the reviewed table SQL macro and a
set-based relational view. It returns exactly 64,000 session-bound rows in
canonical column/row order, samples composed wall textures and flats from `AT`,
applies negative-safe floor modulus, pegging and sidedef offsets, and maps every
raw texel through the facing sector's COLORMAP light band.

Two changes removed the prior pathological plan:

- the 320 nearest solid hits are materialized once per query;
- integral BINARY_DOUBLE texture coordinates are explicitly cast to NUMBER,
  making all `(asset_id,y,x)` columns index access predicates instead of
  scanning every texel belonging to an asset for each pixel.

`DBMS_XPLAN.DISPLAY_CURSOR` confirmed full `AT` A/Y/X access. A canonical 64K
database extraction then completed in seconds; the 587-second figure above is
the complete evaluator's many deliberate rerenders, anti-gap MINUS queries,
pose changes, cross-session comparisons, and hashes. This replaces the prior
single dense aggregate that produced no row after 513 seconds (and an earlier
1,890-second attempt).

Exact binary-double operation order matches the independent JavaScript/WAD
oracle at texel boundaries. All 64,000 east pixels compare equal and hash to:

```text
47302a67b53ef176a84a54b1247a85fc88e45f695af2554ff278265e118f65b4
```

## Regressions and review artifact

```text
PASS T4.1-VISIBLE (1296/1296 declared assertions)
PASS T3.2 (136/136 assertions)
PASS T3.3-VISIBLE (455/455 declared assertions)
PASS T3.4-VISIBLE (3300/3300 declared assertions)
PASS dashboard database frame (64000/64000 pixels; sha256 47302a67...)
PASS live dashboard frame 47302a67... 64000
```

`scripts/build-review-frame.mjs` reproducibly creates
`client/dist/review/frame.json` solely from `DOOM_R1_PIXELS` and the relational
palette. The live dashboard renders those database palette bytes at 320x200;
no mock or browser-side game reconstruction is used. T4.3's separate human
visual checkpoint remains intentionally unclaimed.
