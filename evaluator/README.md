# Evaluator foundation

This directory is test-only. It is never copied into a production image, static
client artifact, or database schema. The evaluator observes production through
the same AutoREST surface as a user and through explicitly test-only database
credentials supplied to the evaluator container.

## Trust and mount boundary

`compose.evaluator.yaml` is the reviewable deployment design. The evaluator
checkout, approved fixtures, and optional `/held-back` seed directory are mounted
read-only. The container itself is read-only, has a tmpfs scratch directory, has
no workspace write mount, Docker socket, host PID namespace, or privileged mode,
and joins only an internal network shared with ORDS. Production containers never
mount evaluator paths. The held-back directory is absent from implementation
contexts and its loader accepts only regular JSON files below that mount.

`integrity.json` records the reviewed inputs. There is intentionally no snapshot
update or golden-generation command. Changes require an evaluator-author review,
a newly reviewed integrity file, and explicit user approval.

## Commands

Run `./verify.sh task T0.4` for the visible foundation checks and
`./verify.sh evaluator-self-test` for deliberate attacks against the harness.
The task is a review candidate only; these commands do not grant approval.

The mutation runner uses isolated temporary copies. A mutation is killed only
when its baseline and health checks pass, its patch applies, its build/deploy
probe succeeds, and the named semantic assertion fails with the expected reason.
The two foundation canaries prove both the killed and surviving paths. The 20
production mutations remain pending until their owning evaluator tasks provide
approved patches and named assertions.
