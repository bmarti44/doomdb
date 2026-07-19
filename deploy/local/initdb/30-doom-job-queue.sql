whenever sqlerror exit sql.sqlcode rollback
-- Oracle Free derives job_queue_processes=4 from the two-CPU shape, which is
-- exactly the retained-worker pool size. Four long-lived DOOM_UNIFIED_WORKER
-- jobs would then own every slave, leaving no headroom for maintenance jobs
-- or a re-dispatched worker start. Eight slaves are mostly idle-blocked and
-- cost nothing on this stack.
alter system set job_queue_processes = 8 scope = both;
