# Retained USE split-phase draft — 2026-07-17

Status: **research draft, not selected, not deployed**. Production still rejects
`DMSC/v3 use != 0`; `doom_unified_worker` still executes its proven single-phase
path. This is deliberate: inserting SQL world machines after the current Java
tic changes canonical combat/monster RNG, LOS, events and hashes.

The required canonical order is:

1. validate command and apply player movement only;
2. apply that movement transactionally to SQL without advancing the tic;
3. run generic SQL world machines (USE/WALK, movers, switches, sector effects);
4. synchronize the resulting retained state and live geometry;
5. run weapon, projectile and monster phases against that synchronized image;
6. emit/apply the final delta, render, checkpoint and commit atomically.

Implemented but unselected primitives:

- `DMWG/v3`: map-complete, player Z/health/alive/secret count, RNG/event
  frontier, all sector floor/ceiling/light/timer values and all mobj Z values;
- rollback-staged dynamic floor/ceiling images for player movement, monster
  chase, retained LOS and renderer geometry;
- renderer geometry accept/discard fencing;
- checkpoint template refresh capable of byte-validating SQL canonical state;
- Java `prepareCommandPreWorld` / `finishCommandPostWorld` draft entry points.
- a strict `apply_pre_world_movement` SQL seam which validates DMSC/v3 and the
  fixed DPWM result, writes only player movement, preserves all tic/RNG/event
  frontiers, and leaves a session-local command hash fence required by final
  DCTC apply;
- an exact default-off worker branch (`UNIFIED_WORKER_SPLIT_USE_ENABLED=0`)
  which runs movement -> SQL world machines -> DMWG sync -> projectiles/combat/
  monsters -> final apply/render/commit in canonical order. Public AutoREST
  admits USE to that branch only while the same flag is explicitly enabled;
- lineage-qualified world-event ordinal reads in the world machine, DMWG
  builder, and final delta applier, preventing a rewind/branch from poisoning
  the active lineage's event frontier;
- a dynamic first-door acceptance fixture comparing player, world-machine,
  event, frame-SHA, and map-status outputs against the SQL oracle.
- a complete `DMSV/v1` switch-presentation trailer appended to the post-world
  DMWG image. Its metadata-derived, ordered rows carry on/off state, reset
  timer, and immutable restore texture; the retained renderer stages and rolls
  that image back with the owning tic instead of hard-coding a route switch.

Required before selection:

- execute the new split branch in a disposable live acceptance run and retain
  its rollback/failpoint evidence before any selection;
- prove event ordinal/history-head and state/frame SHA parity, including world
  events preceding combat events;
- pass a generic, no-fixed-linedef matrix for specials 1, 11, 26, 62, 88 and
  117: key deny/allow, once/repeat, exit, WALK crossing, switch reset, full
  door/lift timelines, carry/blocking, rollback and restart mid-mover;
- rerun the 300-frame parity, rollback/recovery and split AutoREST FPS gates.

`autorest-worker-use-acceptance.sql` is only the first dynamic USE-door bridge
fixture. It is intentionally not a completion gate and must not be added to the
production suite until split-phase orchestration is selected.
