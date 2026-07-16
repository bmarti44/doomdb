-- Idempotent upgrade for retained workers created before the state catalog
-- digest became part of the durable ownership fence.
declare
  l_column number;
begin
  select count(*) into l_column from user_tab_columns
    where table_name='DOOM_WORKER_CONTROL' and column_name='STATE_MAP_SHA';
  if l_column=0 then
    execute immediate 'alter table doom_worker_control add (state_map_sha varchar2(64))';
  end if;
end;
/

-- Keep the new-column references in a later execution unit. Oracle resolves
-- static SQL while compiling a PL/SQL block, before a dynamic ALTER in that
-- same block could make the column visible.
declare
  l_map_text clob;l_map_blob blob;l_map_sha varchar2(64);l_active number;
  l_dest integer:=1;l_src integer:=1;l_context integer:=0;l_warning integer;
begin
  select count(*) into l_active from doom_worker_control
    where target_session is not null and state_map_sha is null;
  if l_active>0 then
    select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,
      sprite_prefix,sprite_frame,rotations null on null returning varchar2)
      order by state_id returning clob) into l_map_text from doom_state_def;
    dbms_lob.createtemporary(l_map_blob,true,dbms_lob.call);
    dbms_lob.converttoblob(l_map_blob,l_map_text,dbms_lob.lobmaxsize,
      l_dest,l_src,nls_charset_id('AL32UTF8'),l_context,l_warning);
    if l_warning<>0 then
      raise_application_error(-20833,'worker state-map encoding');
    end if;
    l_map_sha:=lower(rawtohex(dbms_crypto.hash(l_map_blob,dbms_crypto.hash_sh256)));
    update doom_worker_control set state_map_sha=l_map_sha
      where target_session is not null and state_map_sha is null;
  end if;
  begin
    execute immediate 'alter table doom_worker_control drop constraint doom_worker_control_target_ck';
  exception when others then if sqlcode<>-2443 then raise;end if;end;
  execute immediate q'~alter table doom_worker_control add constraint
    doom_worker_control_target_ck check(
      (target_session is null and target_lineage is null and state_map_sha is null) or
      (regexp_like(target_session,'^[0-9a-f]{32}$') and
       regexp_like(target_lineage,'^[0-9a-f]{64}$') and
       regexp_like(state_map_sha,'^[0-9a-f]{64}$')))~';
end;
/
