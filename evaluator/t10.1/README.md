# T10.1 independent evaluator

This frozen evaluator accepts only the Section 5.4 object-AutoREST contract. Its
15 stable IDs declare 1,457 assertions across exact package metadata, grants and
enabled objects, raw HTTP methods and representations, gzip/frame decoding,
atomic malformed-input handling, cached retry bytes, two concurrency shapes,
save/load, replay, assets, health, CORS, source/schema policy, mutations, and
integrity ancestry.

## Production handoff

The implementation owns `sql/rest/010_doom_api.sql` and
`sql/rest/020_ords_enable.sql` (or sets `T101_SOURCE_FILES` to its comma-separated
equivalents). The package base URL must be supplied as `DOOM_T101_BASE_URL`, for
example `https://host/ords/schema/doom_api/`; the enabled view URL is supplied as
`DOOM_T101_HEALTH_URL`. Isolated local HTTP additionally requires
`DOOM_T101_ALLOW_HTTP=1`. Missing endpoints or variables fail rather than skip.

Run `evaluator/t10.1/run-visible.sh` only after all upstream production and the
ORDS deployment are installed. It performs source policy, direct Oracle metadata,
then raw HTTP acceptance. `DOOM_T101_BASE_URL` must end at the package object so
the evaluator can independently probe sibling base-object paths.

No custom ORDS modules/handlers are accepted. `PUBLIC_HEALTH` must have no
updatable columns. `USER_ORDS_ENABLED_OBJECTS` must contain exactly `DOOM_API`
and `PUBLIC_HEALTH`; any extra enabled object fails. The direct transport oracle
requires exact POST JSON routes, gzip magic, compact canonical JSON field order,
independently reconstructed frame hashes, deterministic asset bytes, restricted
CORS, and inaccessible base tables.

This directory contains evaluator material only. It does not provide production
package logic, schema DDL, deployment changes, or invented endpoint responses.
