-- Idempotent live upgrade for durable per-request worker stage tracing.
declare
  procedure add_column(p_name varchar2) is
    l_count number;
  begin
    select count(*) into l_count from user_tab_columns
      where table_name='DOOM_WORKER_RESULT' and column_name=p_name;
    if l_count=0 then
      execute immediate 'alter table doom_worker_result add ('||p_name||' number)';
    end if;
  end;
begin
  add_column('PREPARE_US');
  add_column('APPLY_US');
  add_column('STATE_US');
  add_column('RENDER_US');
  add_column('RENDER_CALL_US');
  add_column('RENDER_UPDATE_US');
  add_column('RENDER_KERNEL_US');
  add_column('CODEC_US');
  add_column('BLOB_US');
  add_column('RESPONSE_COPY_US');
  add_column('RESPONSE_HASH_US');
  add_column('STATE_ENCODE_US');
  add_column('STATE_BLOB_US');
  add_column('STATE_COMPARE_US');
  add_column('STATE_OBJECT_ENCODE_US');
  add_column('STATE_CHANGED');
  add_column('STATE_REUSED');
  add_column('STATE_REMOVED');
  add_column('HISTORY_US');
  add_column('HISTORY_ENCODE_US');
  add_column('HISTORY_BLOB_US');
  add_column('HISTORY_PERSIST_US');
  add_column('FINALIZE_US');
  add_column('COMMIT_US');
end;
/

-- The hot write path must not block on direct-path container I/O. All three
-- authoritative payloads remain redo-logged, while RETENTION NONE avoids old
-- SecureFile versions for immutable insert-once rows.
alter table doom_worker_result modify lob(response_blob)
  (cache logging retention none);
alter table tic_commands modify lob(state_blob)
  (cache logging retention none);
alter table state_history modify lob(snapshot_blob)
  (cache logging retention none);
