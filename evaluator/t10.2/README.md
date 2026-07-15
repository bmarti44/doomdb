# T10.2 thin-client evaluator

This evaluator freezes a client-only contract. It never imports client code into
its independent decoder and it does not inspect or implement the REST/database
engine. Browser runs require `DOOM_T102_BASE_URL` and intercept only the three
normal object-AutoREST calls needed by the deterministic client fixtures. Every
other request, HTTP failure, request failure, console error, or page error fails.

The production source inventory is exactly `api.ts`, `input.ts`, `codec.ts`,
`palette.ts`, `canvas.ts`, `audio.ts`, `presentation-state.ts`, and `main.ts`.
Production provides one `canvas[data-doom-canvas]` with intrinsic dimensions
320×200 and semantic icon controls named in `fixtures.json`. These hooks expose
presentation semantics, not evaluator state or expected results.

Responsive screenshots are written only to `/tmp` and are checked through live
geometry, visibility, hit-target, overlap, overflow, and raw canvas-byte probes.
They are evidence for later human inspection, not approved goldens. The visual
checkpoint remains `PENDING`; this evaluator contains no screenshot baseline,
snapshot update mode, golden-generation command, or invented image identity.

Run live acceptance with:

```sh
DOOM_T102_BASE_URL=http://127.0.0.1:8080/ evaluator/t10.2/run-visible.sh
```

Missing production, URL, compiler result, browser, report, screenshot, test id,
or assertion fails closed. The evaluator pins Chromium/Playwright through the
repository lock and configures one worker, no retry, `forbidOnly`, and
`updateSnapshots: 'none'`.
