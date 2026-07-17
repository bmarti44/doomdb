-- These tables are created by the staged/tic schemas, after the base schema
-- migrations. Keep their hot-path SecureFile policy at the first valid point
-- in a clean bootstrap instead of relying on an incremental deployment where
-- the columns happened to pre-exist.
alter table tic_commands modify lob(state_blob)
  (cache logging retention none);
alter table state_history modify lob(snapshot_blob)
  (cache logging retention none);
