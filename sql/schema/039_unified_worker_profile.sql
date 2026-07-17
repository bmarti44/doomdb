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
  add_column('LEDGER_US');
  add_column('WORLD_PACK_US');
  add_column('WORLD_SPLIT');
  add_column('WORLD_ACTIVE');
  add_column('WORLD_ENABLED');
  add_column('WORLD_REQUIRED');
  add_column('WORLD_HYBRID');
  add_column('PRE_MOVEMENT_APPLY_US');
  add_column('WORLD_ADVANCE_US');
  add_column('GEOMETRY_PACK_US');
  add_column('WORLD_SYNC_US');
  add_column('PROJECTILE_PACK_US');
  add_column('POST_WORLD_US');
  add_column('JAVA_PREPARE_US');
  add_column('APPLY_US');
  add_column('WORLD_APPLY_US');
  add_column('DELTA_APPLY_US');
  add_column('STATE_US');
  add_column('RENDER_US');
  add_column('RENDER_CALL_US');
  add_column('RENDER_UPDATE_US');
  add_column('RENDER_KERNEL_US');
  add_column('BSP_US');
  add_column('SOLID_US');
  add_column('PORTAL_US');
  add_column('PORTAL_RESET_US');
  add_column('PORTAL_SORT_US');
  add_column('PORTAL_WALK_US');
  add_column('PLANE_US');
  add_column('SPRITE_US');
  add_column('PRESENTATION_US');
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

declare
  l_count number;
begin
  select count(*) into l_count from user_tab_columns
    where table_name='DOOM_WORKER_REQUEST' and column_name='ASYNC_MODE';
  if l_count=0 then
    execute immediate 'alter table doom_worker_request add (async_mode number(1) default 0 not null)';
    execute immediate 'alter table doom_worker_request add constraint doom_worker_request_async_ck check(async_mode in(0,1))';
  end if;
end;
/

declare
  l_count number;
begin
  select count(*) into l_count from user_indexes
    where index_name='DOOM_WORKER_REQUEST_FRONTIER_UQ';
  if l_count=0 then
    execute immediate q'~create unique index doom_worker_request_frontier_uq on doom_worker_request(
      case when request_status in('QUEUED','PROCESSING','COMMITTED') then session_token end,
      case when request_status in('QUEUED','PROCESSING','COMMITTED') then save_lineage end,
      case when request_status in('QUEUED','PROCESSING','COMMITTED') then generation end,
      case when request_status in('QUEUED','PROCESSING','COMMITTED') then expected_command_seq end)~';
  end if;
end;
/

-- The hot write path must not block on direct-path container I/O. All three
-- authoritative payloads remain redo-logged, while RETENTION NONE avoids old
-- SecureFile versions for immutable insert-once rows.
alter table doom_worker_result modify lob(response_blob)
  (cache logging retention none);
