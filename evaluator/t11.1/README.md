# T11.1 independent Autonomous Database evaluator

This evaluator accepts only a live Oracle Autonomous Database 23ai-or-later
deployment reached through its managed ORDS origin. It does not accept Oracle
Free, a local ORDS container, a replayed transcript, a dry run, or source-only
evidence. Missing cloud credentials makes the live gate fail with `NOT RUN` and
a nonzero exit; it never produces PASS.

The implementation must run the byte-identical reviewed P0 capability and
transport probes first, deploy the same ordered schema, seed, engine and REST
SQL used locally with SQLcl 26.2.0.181.2110, then collect a secret-free evidence
document. The evaluator independently requires Autonomous service provenance,
all required feature results, exact transport behavior, resource observations,
least grants, exact AutoREST exposure, valid compilation, canonical seed
count/hash equality against a freshly measured local baseline, and every direct
API family through the actual managed ORDS URL.

Credentials and wallet material remain environment-only, outside the repository,
mode 0600 where files are unavoidable, absent from command lines, reports, logs,
JSON and retained artifacts, and deleted on every exit path. Evidence stores only
SHA-256 identifiers for target and origin. Endpoint URLs, tenancy/database names,
wallet paths, tokens, passwords, AWS values, authorization headers and connection
strings are forbidden.

`run-visible.sh` performs evaluator self, mutation, source, integrity, foundation
and adversarial checks before invoking `scripts/verify-cloud-database.sh`. That
production driver must create `/tmp/doomdb-t111-evidence.json` atomically only
after all live commands succeed. This evaluator authors no cloud deployment,
does not connect to external infrastructure, and does not manufacture evidence.
