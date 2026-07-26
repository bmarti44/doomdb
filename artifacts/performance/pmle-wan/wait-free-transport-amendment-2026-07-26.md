WAN_TRANSPORT_AMENDMENT|APPROVED|authority=Brian Martin|transport=WAIT_FREE_IMMEDIATE_BATCHING|transport_legs=2

# Approved wait-free managed-ADB transport amendment — 2026-07-26

Authorized by Brian Martin. Managed Autonomous Database production delivery
uses immediate, wait-free transition batching because the approved held-poll
shape requested 500 ms but resumed at 7,575 ms p95 under Autonomous Resource
Manager.

The latency contract is two measured HTTP legs: the input POST and subsequent
confirmed-transition retrieval, plus the adaptive input-lead window and one
authoritative processing tic. Simulation authority, confirmed-only client
semantics, DMD1 chain verification, command ordering, neutral substitution,
fairness accounting, hidden-tab release/resync, and presentation gates are
unchanged.

This approval authorizes the full managed-OCI qualification matrix at
50±10 ms, 100±20 ms, and 200±40 ms. Each cell runs 90 seconds of warmup plus
600 scored seconds. It does not authorize gate relaxation or reclassify prior
diagnostic evidence.
