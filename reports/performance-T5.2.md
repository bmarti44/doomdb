# T5.2 renderer performance review

Status: reviewed; no numeric acceptance threshold applies.

The complete frozen `./verify.sh task T5.2` run took **69.35 seconds** wall
time on the isolated local Oracle Free container constrained to 2 CPUs and 2
GiB. That measurement includes evaluator self-checks, all 18 mutation
witnesses, the production source audit, dense-frame cardinality/coordinate
checks, two complete deterministic SHA-256 frame reads, and the final routed
20-ID / 1,856,885-assertion result.

The independent dashboard capture queried all 64,000 palette pixels and 256
PLAYPAL rows, encoded and decoded the canonical indexed PNG, checked its exact
reviewed hashes, and wrote the review payload in 12.49 seconds on the same
stack. The resulting PNG is 22,440 bytes. The verified frame contains 37,835
floor/ceiling pixels, 5,781 upper/lower portal-piece pixels, and 20,384 solid
wall pixels.

The implementation uses analytic running clip bounds, stable row-number
selection, indexed texel lookups, and one priority ranking over wall, plane, and
horizon candidates. It contains no pixel loop, recursive render CTE, dynamic
SQL, reduced resolution, or alternate renderer. Performance is acceptable for
this correctness milestone; later frame caching/RLE work may optimize transport
without changing this canonical 320x200 relation.
