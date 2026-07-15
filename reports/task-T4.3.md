# T4.3 first-light visual checkpoint

Status: **PASS — visible baseline reviewed and frozen**.

Route: `T4.3-IMPL | Terra | medium | attempt 1`.

## Machine acceptance

Three token-isolated poses were captured from the verified
`DOOM_R1_PIXELS` implementation on the already-fresh 2 CPU / 2 GiB Oracle
stack. The frozen SQL adapter independently emitted 64,000 pixels, PLAYPAL, and
analytic Appendix E runs. The separate Node implementation expanded RLE,
created raw RGBA and deterministic indexed PNGs, parsed those PNGs back, and
produced six column plus eight pixel diagnostics per pose.

```text
PASS T4.3-EVAL-SELF-CHECK (43/43 fixture-contract assertions)
PASS T4.3-EVAL-MUTATION-SELF-CHECK (16/16 isolated mutations killed)
PASS T4.3-SOURCE-AUDIT (584 production files, independent decoder)
PASS T4.3-CAPTURE (3/3 database poses; SQL RLE, RGBA, indexed PNG and diagnostics agree)
PASS T4.3-VISIBLE-GOLDENS (3/3 human-reviewed database PNGs)
PASS T4.3 (1282017/1282017 assertions)
```

Final frozen evaluator manifest:

```text
38927540dc430ff6d3476738f122577ec15bf4ab104628282a4f19a7e7c5977a  evaluator/integrity.pending-T4.3.json
```

The evaluator remained separate from production. Two evaluator-only Oracle
compatibility/wiring corrections were independently routed and re-frozen before
acceptance: replacing a macro-in-CTE shape rejected by Oracle with equivalent
inline views, and passing the already-frozen eight diagnostic pixel coordinates
to the existing diagnostic function. Neither changed captured pixels or PNGs.

## Direct visual review

All three actual 320×200 PNGs were opened at original resolution and inspected:

- **East:** a coherent industrial corridor. Ceiling grid and floor perspective
  converge consistently; structural columns, wall panels, grates, and yellow
  hazard stripes remain aligned. There are no torn columns, transposition, or
  missing screen bands.
- **North:** the nearby dark wall is correctly bounded by a ceiling plane and a
  receding floor. Texture scale, horizon, and low-light COLORMAP treatment are
  internally consistent, with no palette noise or PNG damage.
- **South:** the opposing view is visibly distinct from north while retaining
  consistent projection, floor sampling, and lighting. No rotation, replayed
  frame, corrupt band, or missing pixel was observed.

The images are approved as the R1 first-light baseline under the user's standing
authorization. This does not waive R1's documented nearest-hit-sector
floor/ceiling limitation for final gameplay.

## Frozen identities

| Pose | Frame SHA-256 | RGBA SHA-256 | PNG SHA-256 |
|---|---|---|---|
| spawn east | `47302a67b53ef176a84a54b1247a85fc88e45f695af2554ff278265e118f65b4` | `a0903655b7150c7a86aea6060bbadc28b6c6093f52c3294994acbae9bb8b732a` | `d46e56cd3f6d87ff2977bc3bcdce988ae00997df10e1b110827b93a3c42efb7b` |
| spawn north | `46c8a2ca36446249b89385e0b901064304e3fc6212ce027ff06dc5c8d1b429c6` | `67f51584359223c7b789220c87bb50e3f2689ae0c6bdf31c63fc8fcfec136db1` | `2db00d6a02668b636d606e792a81aa2ceb4294bfa5c5866bb3686da379c509f7` |
| spawn south | `b920598f8363b34715764745c8130271e9b39f3edcc05125b06d82fdff20a34f` | `b51306bb4bb1a7726f1bfda1ea8b922ad080855b7db66da0ba01514f2fb779eb` | `5ee8b950fa8076a9b5930103c53167a67d612a22f4eb95fa960d2854ab778286` |

The separately reviewed baseline is [t4.3-visible.json](../goldens/t4.3-visible.json),
frozen by `goldens/integrity-T4.3.json` (`8b6ed7eca00188dff759b3ee2d8a15d7fc04d1b294bac4106e1d581139febc63`).

## Dashboard

The live review app at `http://localhost:8080/` now serves all three byte-exact
PNG identities and a keyboard-accessible pose selector. Direct HTTP SHA-256
checks match the reviewed files, and the page labels P4 first light complete.
