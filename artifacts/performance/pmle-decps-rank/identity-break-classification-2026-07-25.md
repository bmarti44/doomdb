# TeaVM authority identity-break classification — 2026-07-25

Status: `CLASSIFIED; SEMANTIC PROMOTION EVIDENCE STILL REQUIRED`

The byte difference between the ledger-proven `2848ef7a…` authority and the
reproducible `5ec18cbe…` successor is generated-code identity, not an
unrecorded Doom simulation-source edit.

## Source audit

- The authority adapter Java sources, Mocha patch set
  `0002/0003/0004/0006`, and OJVM build inputs have no diff from the build
  commit that produced the predecessor.
- Both successor builds bind the same TeaVM input-JAR SHA-256
  `2ca1278998385efb83aba0358119f70f2e135b569b446f6b43f6afddf51ca914`,
  Mocha bytecode SHA-256
  `c6d26633316b7a6251e79b9013bfb16ca877e2d93642ebbaba17bfc66c8861a4`,
  TeaVM `0.15.0`, ADVANCED optimization, and canonical-table SHA-256
  `058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44`.
- The build added a fixed Maven `project.build.outputTimestamp`. A controlled
  A/B holding the input-JAR digest constant changed the generated output:
  `2026-07-25T00:00:00Z` produced `09295542…` (1,081,340 bytes), while
  `2026-07-24T00:00:00Z` produced `333fc793…` (1,081,337 bytes). Repeating the
  latter timestamp reproduced `333fc793…` byte-for-byte. This proves that
  archive timestamp/build-shape metadata reaches TeaVM's generated identity;
  it does not claim that timestamp alone explains every predecessor byte.
- Two clean, fixed-input successor builds independently reproduced
  `5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`
  at 1,081,335 bytes. Clean/incremental build state is therefore treated as a
  build input for identity purposes, while clean rebuilds are the only
  promotion-producing path.

## Changed-region classification

The first large structural divergence reported around predecessor minified
class `BdB` is TeaVM class-library code. A non-minified diagnostic build maps
the exact constructor shape

`JR.call(this); <field>=0; <field>=0`

and its BOM/little-endian decode branches to
`org.teavm.classlib.java.nio.charset.impl.UTF16Decoder`
(`jnci_UTF16Decoder`, fields `$bom0` and `$littleEndian`). It is not a Doom
ticker, thinker, RNG, checkpoint, multiplayer, or renderer class. Cascading
minified symbol renames after that class explain why a small ordering change
creates a large positional diff.

The diagnostic build is evidence only:

- SHA-256
  `cc106b3c65a05282ee8b39cc01ee7bdebb9345075aeb7ddf658155c2a16a3e46`
- 3,700,967 bytes
- ADVANCED, `minifying=false`

## Promotion consequence

Classification does not grant semantic inheritance. The `5ec18cbe…` bytes
must independently pass Node 5,250-tic parity, direct-MLE dual-clock rank,
canonical, 762-tic co-op, membership/recovery, and the 13,272-tic every-tic
ledger before promotion. The raw timestamp A/B and debug-named build remain
diagnostic evidence and may never substitute for those gates.

Authoritative raw records:

- `identity-break-output-timestamp-ab-2026-07-25.log`
- `identity-break-debug-named-build-2026-07-25.log`
- `identity-break-debug-named-authority.js`
- `build-reproducible-successor-5ec18cbe4cff.log`

PMLE_DECPS_IDENTITY_BREAK_CLASSIFICATION|PASS|predecessor=2848ef7a8dc4|successor=5ec18cbe4cff|changed_class=org.teavm.classlib.java.nio.charset.impl.UTF16Decoder|classification=TEAVM_GENERATED_CLASSLIB_ORDERING|semantic_inheritance=REJECTED
