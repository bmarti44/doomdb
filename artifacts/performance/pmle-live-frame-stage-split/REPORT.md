# OCI live-frame stage decomposition — 2026-07-29

Classification: `DIAGNOSTIC_NOT_GATE`.

The shipping authority and renderer were held constant. Coordinator
`2065b452537d5348155590a570b4b4c0442ecd7bf9e9711c7b6a56adebc36059`
split complete two-POV framebuffer preparation from the persistent-locator
write without changing their order or bytes.

## Production venue result

The no-pixel-polling, two-player OCI cell sustained 25.057 authoritative
tics/s after a 10-second warmup. Eight consecutive 100-tic windows measured:

- complete two-POV generation: 29.541–32.129 ms/tic average;
- generation maxima: 69.495–135.603 ms;
- one 128,016-byte persistent BLOB publication: 1.990–2.209 ms/tic average;
- publication maxima: 2.688–3.608 ms.

This establishes generation/composition—not the MLE-to-SQL BLOB
boundary—as the current limiter. Compression or larger persistence batches
cannot recover the missing 30 FPS margin.

## Bit-identical static-camera A/B

Coordinator
`8f005189021d476dfe9c75718fee8dfa0a47e235efd5567242a8b2f81f203249`
replaces 320 identity column copies with one `TypedArray.set` only when
confirmed x/y/angle/view-z are exactly unchanged. The old and new indexed
framebuffers are property-tested byte-for-byte.

On the same OCI shape it sustained 25.701 tics/s, a 2.57% producer uplift.
Five 100-tic windows measured 28.387–29.559 ms/tic average generation and
1.996–2.136 ms/tic average publication. The optimization is retained because
it is exact and positive, but it does not close the 30 FPS gate.

The public source row and two READY retained slots were verified after
deployment. Authority
`66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873`
and renderer
`c60a34dd81d6e184be7262f494ff3070adb1ab2fb926ecaafedc4043b22cf93c`
did not change.
