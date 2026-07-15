# T0.2 blocked evidence

> Resolved on 2026-07-14. The factory SPFILE exhausted the 2 GiB cgroup. Using
> Oracle's supported PFILE/SPFILE mechanism to set `sga_target=1024m` and
> `pga_aggregate_target=256m` allowed the exact pinned image to reach
> `FREEPDB1` readiness under the unchanged 2 CPU / 2 GiB limits. The live
> acceptance command subsequently reported `PASS T0.2 (9/9 capabilities)`.

The static Oracle capability package passes and the local/cloud probe files are
byte-identical. The required live result is not available.

On 2026-07-14 the pinned amd64 Oracle Free image
`gvenzl/oracle-free:23.26.2-full@sha256:df18ebc6...` was started with the
contractual `--cpus=2 --memory=2g` limits. It unpacked its data files, mounted
FREE, and began `ALTER DATABASE OPEN`, but did not finish opening FREEPDB1 after
more than five minutes. External measurements repeatedly showed approximately
200% CPU and 1.99/2.00 GiB resident memory. A SQL*Plus connection to FREEPDB1
did not complete, and even a later `docker exec` diagnostic could not be
scheduled while the container remained saturated. The container was not OOM
killed.

The limits were not raised because Section 4.2 makes them part of the local
topology. T0.2 therefore cannot claim its required live result-bearing examples.
The next attempt should determine whether supported initialization settings can
make this exact pinned image start within the same limits; reducing capability
coverage or changing the image is not permitted.
