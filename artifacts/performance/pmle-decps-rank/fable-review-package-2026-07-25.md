# Fable review package — 2026-07-25

## Closed correctness and lifecycle evidence

The promoted/deployed authority is `5ec18cbe…` (1,081,335 bytes). It passes
the 13,272-tic every-tic ledger, canonical, 762-tic co-op, membership,
four-cell async-admission race, and five-cell warm-slot lifecycle batteries.
Artifact-specific recovery and final soak remain cutover gates.

The async-admission four-cell-to-fix map is:

1. READY/status claim storm -> generation-fenced idempotent authority claim;
   8 callers produced exactly 1 claim.
2. LEAVE during STARTING -> atomic cancellation/capacity release;
   terminal `CANCELLED`, active capacity 0.
3. worker FAILED during STARTING -> bounded failed-control reconciliation;
   client-visible `CANCELLED` within 5 seconds.
4. dispatcher death before initial publish -> full-incarnation stale-claim
   failure plus one replacement; exactly 1 replacement survived.

## Admission sample spread

Browser-observed READY click to first generation-fenced ACTIVE:

- 100 ms yield:
  `4525, 4900, 4725, 4906, 4571, 4418, 4473, 4723, 4599, 4899`;
  p50 4,599 ms, p95/max 4,906 ms, PASS.
- 0 ms yield:
  `8749, 7423, 6429, 6441, 6628, 6506, 4288, 7308, 7580, 6339`;
  p50 6,506 ms, p95/max 8,749 ms, FAIL.

The 100 ms scheduling yield is explicitly **venue-local Oracle Free
evidence**. It is a tunable heuristic, not a correctness dependency or cloud
constant, and must be remeasured during OCI acceptance.

## Performance decisions

- Current whole-route de-CPS performance: 19.788 tics/s; quiet windows clear
  35 Hz, peak windows remain about 7–9 tics/s.
- Fresh Node profile: sight/BSP 23.558% (below its 25% selector), mobj
  long/flag 14.042%, active-state dispatch 9.299%, movement/AI 8.368%.
- Narrow mobj low-word candidate: exact property/Node parity, but direct MLE
  improvements were 1.035% p50, 4.122% p95, 2.707% throughput, and 1.401%
  median high-awake. **Rejected below 5%; not promoted.**
- Final-artifact default-async pair: one matched window (701–800) improved
  25.501% by corrected wall median and 41.079% by GET_TIME throughput.
  Four/10,500 clock suspects were excluded under the 0.5% cap. This is a
  **LANDING_SIGNAL**, not yet a production qualification.
- OCI Always Free 26ai arithmetic remains 171–189 ns/op and gather 91 ns/B:
  exact live DB rendering/JIT venue branch remains closed under the standing
  >=100 ns rule. The default-async local ticker signal does not alter that
  OCI verdict without an OCI ticker remeasurement.

## Requested review

1. Confirm that the localized async landing signal should next receive an
   independent fresh-session pair plus a third same-session pass to test
   persistence, before the SIMPLE/reduced-inline diagnostic is considered.
2. Confirm the strengthened clock rule: a landing window must clear 20% on
   both corrected SYSTIMESTAMP median and its authoritative GET_TIME
   throughput, with <=0.5% symmetric suspect exclusions.
3. Confirm that the narrow low-word route is closed at 2.707% throughput and
   should not consume a full differential battery.

Evidence details:

- `../pmle-browser-role-swap/admission-decision-2026-07-25.md`
- `../pmle-worker-lifecycle/async-admission-races-decps-5ec18cbe-2026-07-25-v5.md`
- `mobj-low-word-decision-2026-07-25.md`
- `async-jit-decision-2026-07-25.md`
