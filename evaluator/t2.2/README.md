# T2.2 visible evaluator contract

This directory is evaluator-owned. It contains no parser implementation and no
Freedoom bytes. `visible-fixtures.mjs` hand-assembles a small synthetic PWAD from
explicit field values. `expectations.json` and `directory-expectations.json` are
independently recorded expected observations; the visible runner never derives
an expected parser result from production output.

## Visible parser interface

The implementation item supplies `tools/wad/parse.mjs` with this interface:

```text
node tools/wad/parse.mjs --wad FILE --map E1M1
```

Success is exit 0, empty stderr, and one compact JSON object followed by LF on
stdout. Its evaluator-facing keys are the keys in `expectations.json` plus the
full `directory` array. Extra top-level implementation metadata is permitted if
it is deterministic and contains no timestamps or environment-derived values.

Rejection is exit 2, empty stdout, and exactly `ERROR WAD_CODE` plus LF on
stderr. The stable codes are public API: malformed input must not escape a raw
RangeError, assertion, stack trace, or platform-dependent message.

Run the evaluator-owned fixture audit before implementation exists:

```text
node evaluator/t2.2/self-check.mjs
```

After T2.2-IMPL exists, run `node evaluator/t2.2/run-visible.mjs`. The runner
creates WAD files only in an OS temporary directory and removes them afterward.

## Deliberate edge choices

- `DUPLUMP` appears twice. Both directory rows remain in provenance, while name
  lookup resolves occurrence 1.
- An `E1M2` marker and sentinel `THINGS` follow E1M1. They make cross-marker
  lookup observable.
- All numeric multibyte fields are little-endian; signed positions, offsets and
  heights include negatives.
- Node children are unsigned 16-bit fields with bit `0x8000` masked only after
  classifying them as subsectors.
- THING bit `0x10` is reported as the raw `notSinglePlayer` file bit. The parser
  does not infer runtime multiplayer behavior from it or from skill bits.
- The tall patch's second post has raw top-delta 5 after a post at 250, so its
  interpreted row is 255. A palette index of zero remains opaque; only gaps
  between posts are transparent.
- BLOCKMAP list-leading zero and `0xffff` terminators are framing, not linedefs.
  REJECT bits are read least-significant-bit first in sector-pair row order.

`mutation-specs.json` fixes ten independently reviewable semantic source-patch
requirements and their sole admissible kill tests. A compiler error, patch
application failure, timeout, or different test failure is not a mutation kill.

