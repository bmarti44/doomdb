# T2.2 binary WAD parser

Status: **PASS**

Route: Terra, high effort, implementation attempt 1. The T2.2 evaluator was
explicitly approved by the user before implementation and remained immutable.

## Delivered

- `tools/wad/parser.ts` is the production TypeScript parser. It uses a bounded
  `DataView` reader for signed and unsigned little-endian fields and emits one
  deterministic compact JSON document through `tools/wad/parse.mjs`.
- Directory provenance includes source offset, byte size, occurrence index, and
  SHA-256. Name lookup uses the last occurrence while retaining every row.
- Map lookup stops at the next map marker and reads THINGS, LINEDEFS, SIDEDEFS,
  VERTEXES, SEGS, SSECTORS, NODES, SECTORS, REJECT, and BLOCKMAP.
- Fixed-record sizes and cross-lump references are validated before output.
  Node children retain unsigned `0x8000` classification, REJECT bits are LSB
  first, and BLOCKMAP list headers/terminators are excluded from linedef lists.
- THING skill bits, ambush, and the raw not-single-player bit are reported
  independently, with remaining bits preserved as `unknownFlagBits`.
- PLAYPAL, COLORMAP, PNAMES, both texture directories, patch posts, tall-patch
  continuation, transparent gaps, opaque palette index zero, sprite naming,
  flats, Doom sound data, MUS, and the pinned WAD's MIDI music input are parsed.
- All rejected inputs use exit 2, empty stdout, and a stable `ERROR WAD_CODE`
  diagnostic without raw exceptions or platform messages.
- `tests/verify-wad-parser-mutations.mjs` applies the ten approved semantic
  source mutations in isolated temporary copies. Every copy must retain a green
  fixture self-check and loadable parser before an assertion failure counts as
  a kill.

Node 24's erasable-TypeScript runtime executes `parser.ts` directly. The small
`parser.mjs` facade gives other ESM callers a conventional import extension;
the CLI has no compiler or package-install dependency.

## Acceptance evidence

Focused visible and mutation checks:

```text
$ node evaluator/t2.2/run-visible.mjs
PASS T2.2-VISIBLE (19/19 test ids)
$ node tests/verify-wad-parser-mutations.mjs
PASS T2.2-MUTATIONS (10/10 semantic mutants killed)
$ tsc --noEmit --noCheck --allowImportingTsExtensions --module nodenext --moduleResolution nodenext --target es2024 tools/wad/parser.ts
PASS (exit 0)
```

The pinned Freedoom 0.13.0 Phase 1 WAD was streamed directly from the verified
archive into the parser. The live result reproduces the plan's grounded facts:

```text
kind=IWAD
things=292 linedefs=1175 sidedefs=1829 vertexes=1196
segs=2057 ssectors=682 nodes=681 sectors=182
bounds x=-704..3248 y=-1064..2336
music=MThd
```

Two independent pinned-WAD processes emitted byte-identical compact JSON:

```text
8c495e504bb40689a6a8c0a3cd11953e12b3faf885e09be2fbeb4fcbb2e58056
8c495e504bb40689a6a8c0a3cd11953e12b3faf885e09be2fbeb4fcbb2e58056
```

Evaluator and regression gates:

```text
$ node evaluator/t2.2/self-check.mjs
PASS T2.2-EVAL-SELF-CHECK (17/17 fixture-contract assertions)
$ T2.2 pending-integrity hash audit
PASS T2.2 evaluator immutable-source audit (9/9 hashes)
$ tests/verify-freedoom-vendor.sh
PASS T2.1 (10/10 assertions; offline)
$ scripts/verify_env.sh
ENV RESULT: PASS
$ tests/verify-oracle-probes.sh
oracle capability probe package: PASS
$ scripts/check-transport-contract.sh
PASS T0.3-static (12/12 assertions)
$ node evaluator/run-foundation.mjs T0.4
PASS T0.4 (8/8 assertions)
$ tests/verify-local-stack.sh
PASS T1.1-static (27 assertions)
$ tests/verify-bootstrap-static.sh
PASS T1.2-static (10/10 assertions)
$ tests/verify-cloud-skeleton.sh
PASS T1.3 (12/12 assertions)
$ node evaluator/audit-production.mjs
{"passed":true,"roots":["client/src","sql","deploy"]}
```

## Changed files

- `tools/wad/parser.ts`
- `tools/wad/parser.mjs`
- `tools/wad/parse.mjs`
- `tests/verify-wad-parser-mutations.mjs`
- `package.json` (`type: module` for warning-free native TypeScript loading)
- `reports/routing.log`
- `reports/task-T2.2.md`

No evaluator artifact, approved expectation, golden, or root `verify.sh` was
modified.

## Integration dispatch

The evaluator-owned root dispatcher may route `./verify.sh task T2.2` to:

```sh
node evaluator/t2.2/run-visible.mjs
node tests/verify-wad-parser-mutations.mjs
```
