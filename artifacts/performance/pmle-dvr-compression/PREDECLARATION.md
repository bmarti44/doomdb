# MLE DVR frame compression predeclaration — 2026-07-26

Classification: optional database-frame transport experiment. Brian Martin's
subsequent direction makes complete MLE-generated database frames delivered
through ORDS to a framebuffer-only browser the primary target. Compression is
neither the architecture nor the acceptance goal; it may be used only if it
improves that end-to-end path after exact rasterization meets its compute
budget.

## Pinned codec contract

The first candidate is `DOOM_DFR1_RLE` (`codec_id=1`). Canonical truth remains
the 64,000-byte uncompressed indexed framebuffer. `DFR1` is a deterministic
frame-local byte codec:

- a 12-byte header contains magic `DFR1`, uncompressed length, and encoded
  payload length as little-endian unsigned 32-bit values;
- token high bit clear encodes a 1–128-byte literal followed by its bytes;
- token high bit set encodes a 3–130-byte repeated run followed by one byte;
- two-byte repeats remain literals, making tokenization canonical;
- decoders reject bad magic, non-64,000-byte output, length overflow,
  truncated input, trailing bytes, and non-canonical repeat/literal choices.

The persistent record binds codec id, uncompressed length and SHA-256,
compressed length and SHA-256, and the uncompressed frame-chain predecessor.
Only the uncompressed SHA participates in the canonical frame chain.

## Measurement cells and verdicts

All timing cells use the accepted 5,250-tic command stream, one quiet OCI cell
at a time, two-clock suspect detection, a 0.5% exclusion cap, pool
park/restore, alert-window postflight, and no-overwrite evidence.

1. **Codec correctness and rank.** All 5,250 compressed frames must decompress
   byte-identically to the accepted Node frame chain, and independently
   recomputed compressed SHAs must match the stored bytes. Any mismatch rejects
   the codec. Compression p95 must be at most 5.000 ms in both quiet and
   preselected peak windows to remain a 35 Hz candidate. Ratio is reported by
   quiet/peak window and whole route; it is diagnostic rather than a
   correctness gate.
2. **Boundary A/B.** Measure single-frame uncompressed and compressed locator
   persistence, then compressed batch sizes 1, 5, 10, and 35. Each batch must
   preserve per-frame ids, both SHAs, codec id, exact decompression, ordering,
   and zero temporary-LOB growth. A batch size is viable only when its
   amortized render+compress+persist p95 is at most 28.571 ms/frame and its
   bounded backlog returns to zero after the cell. The smallest passing batch
   is selected; if none passes, the workstream records FAIL before a DVR soak.
3. **DVR acceptance.** Predeclared now for the later gate: 12,250 consecutive
   frames (350 seconds at 35 Hz), paced at 35 Hz, zero dropped/reordered frames,
   exact uncompressed chain, zero temporary-LOB growth, ending backlog zero,
   backlog p99 no more than one selected batch, healthy database/alert
   postflight, and process/private-memory below the calibrated absolute
   ceiling.
4. **Serving leg.** A hosted ORDS GET must return one compressed frame with its
   codec id, strong compressed-payload ETag, immutable cache policy, working
   empty-body 304, and a browser decoder sample byte-identical to the
   uncompressed frame SHA.
5. **Historical comparison (`DIAGNOSTIC_NOT_GATE`).** Record single-frame
   render+compress+cross+persist p95 beside the 33.333 ms live bar. This cell
   does not establish the database-frame architecture: the governing gate is
   still complete exact MLE rasterization plus delivery at 30+ unique moving
   client FPS.
