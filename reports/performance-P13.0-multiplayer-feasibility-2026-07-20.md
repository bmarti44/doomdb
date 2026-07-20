# P13.0 multiplayer feasibility — 2026-07-20

## Result

The retained OJVM architecture is viable for database-authoritative
multiplayer. One engine consumed a two-slot ordered ticcmd vector in one world
tic, rendered two deterministic distinct POVs without mutating world state,
and passed shared damage, frag, death, and co-op reborn checks twice from clean
initialization. The probe is internal SQL/OJVM only and is not exposed through
AutoREST.

The two clean POV identities were:

- player 0: `44c4422bda405eb4cdff0c2f4d84d913e2801dd0b53b8cc30ebc8b8bad686651`
- player 1: `9f55a44b95a35841a1d1e8e341a2c49de8f165ababaa563a99cb7e607eb94ae2`

The existing single-player initial-frame gate remained exact after deployment:
tic 0, 64,142-byte DMF3, frame SHA
`a1c9b0378eed9e82425cae593b82dfa44715627d8aa635562b450e4c1af3d3b5`.

## Pinned 300-sample timings

All values are milliseconds. Each sample advances one authoritative world tic,
then renders, hashes, and writes one immutable frame per active POV.

| Active POVs | total p50 | total p95 | total max | largest per-POV render p95 | largest codec p95 | largest BLOB p95 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2.515 | 3.396 | 8.257 | 1.370 | 0.629 | 0.034 |
| 2 | 3.228 | 5.670 | 41.936 | 1.529 | 0.888 | 0.052 |
| 3 | 3.699 | 4.919 | 6.565 | 1.030 | 0.650 | 0.030 |
| 4 | 5.575 | 7.933 | 35.886 | 1.249 | 0.728 | 0.036 |

Every POV produced 283–285 unique frames. The two- and four-player maxima are
isolated tails; the p95 gate has substantial room under 33.3 ms. This clears
only the engine-level feasibility decision. Persistence, command deadlines,
AutoREST submit/poll, per-client decode/paint, replay, and recovery remain P13
acceptance work and must be included before claiming multiplayer FPS.

## Implementation and operational note

The probe and benchmark are catch-all entry points in the bounded adapter with
internal SQL wrappers. They always dispose their session-private engine and
restore `displayplayer` in `finally`. The full patched tree compiled to 823
classes, and the selected 47-class native audit passed.

Native compilation took roughly sixteen minutes after this adapter expansion,
while runtime stayed fast. A later cleanup should move disposable diagnostics
out of the production hot adapter class so adding probe code does not increase
deployment-time native compilation of the gameplay path.
