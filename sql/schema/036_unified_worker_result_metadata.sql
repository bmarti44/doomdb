-- Idempotent upgrade for dashboard databases created before durable worker
-- results carried response/state/frame integrity metadata.  Never fabricate
-- hashes for a committed legacy result: a nonempty old table requires an
-- explicit reviewed data migration.
declare
  l_rows number;l_columns number;
  procedure add_column(p_name varchar2,p_definition varchar2) is
    l_count number;l_nullable varchar2(1);
  begin
    select count(*),max(nullable) into l_count,l_nullable from user_tab_columns
      where table_name='DOOM_WORKER_RESULT' and column_name=p_name;
    if l_count=0 then
      if l_rows<>0 then
        raise_application_error(-20830,
          'cannot synthesize DOOM_WORKER_RESULT.'||p_name||' for legacy rows');
      end if;
      execute immediate 'alter table doom_worker_result add ('||
        p_name||' '||p_definition||' not null)';
    elsif l_nullable<>'N' then
      if l_rows<>0 then
        raise_application_error(-20832,
          'cannot prove DOOM_WORKER_RESULT.'||p_name||' for legacy rows');
      end if;
      execute immediate 'alter table doom_worker_result modify ('||
        p_name||' not null)';
    end if;
  end;
  procedure drop_constraint(p_name varchar2) is
  begin
    execute immediate 'alter table doom_worker_result drop constraint '||p_name;
  exception when others then if sqlcode<>-2443 then raise;end if;
  end;
begin
  select count(*) into l_rows from doom_worker_result;
  add_column('STATE_SHA','varchar2(64)');
  add_column('FRAME_SHA','varchar2(64)');
  add_column('RESPONSE_BYTES','number(8)');
  add_column('RESPONSE_SHA','varchar2(64)');
  select count(*) into l_columns from user_tab_columns
    where table_name='DOOM_WORKER_RESULT'
      and column_name in('STATE_SHA','FRAME_SHA','RESPONSE_BYTES','RESPONSE_SHA')
      and nullable='N';
  if l_columns<>4 then
    raise_application_error(-20831,'worker result metadata columns must be NOT NULL');
  end if;
  drop_constraint('DOOM_WORKER_RESULT_DELTA_CK');
  drop_constraint('DOOM_WORKER_RESULT_SHA_CK');
  execute immediate q'~alter table doom_worker_result add constraint
    doom_worker_result_delta_ck check(
      delta_version between 1 and 255 and delta_count between 0 and 255 and
      delta_bytes>=0 and response_bytes>=0)~';
  execute immediate q'~alter table doom_worker_result add constraint
    doom_worker_result_sha_ck check(
      regexp_like(delta_sha,'^[0-9a-f]{64}$') and
      regexp_like(state_sha,'^[0-9a-f]{64}$') and
      regexp_like(frame_sha,'^[0-9a-f]{64}$') and
      regexp_like(response_sha,'^[0-9a-f]{64}$'))~';
end;
/
