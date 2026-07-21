-- Append-only, two-tic multiplayer input overlay. Immutable command rows keep
-- their reservation/idempotency role; the applied per-tic ledger remains the
-- canonical replay source.
declare
  l_count number;
begin
  select count(*) into l_count from user_tab_columns
    where table_name='DOOM_MATCH_MEMBER' and column_name='PRESENTED_TIC';
  if l_count=0 then
    execute immediate 'alter table doom_match_member add (presented_tic number(12) default 0 not null)';
  end if;
end;
/

begin
  execute immediate q'~create table doom_match_input_event (
    match_id varchar2(32) not null,
    player_slot number(1) not null,
    input_seq number(12) not null,
    effective_tic number(12) not null,
    membership_epoch number(12) not null,
    generation number(12) not null,
    ticcmd_raw raw(8) not null,
    command_sha varchar2(64) not null,
    accepted_at timestamp with time zone not null,
    constraint doom_match_input_event_pk primary key(match_id,player_slot,input_seq),
    constraint doom_match_input_event_member_fk foreign key(match_id,player_slot)
      references doom_match_member(match_id,player_slot) on delete cascade,
    constraint doom_match_input_event_frontier_ck check(
      input_seq>0 and effective_tic>0 and membership_epoch>0 and generation>0),
    constraint doom_match_input_event_raw_ck check(vsize(ticcmd_raw)=8),
    constraint doom_match_input_event_sha_ck check(
      regexp_like(command_sha,'^[0-9a-f]{64}$'))
  )~';
exception when others then if sqlcode<>-955 then raise;end if;
end;
/

begin
  execute immediate 'create index doom_match_input_event_apply_ix on doom_match_input_event(match_id,player_slot,membership_epoch,effective_tic,input_seq)';
exception when others then if sqlcode<>-955 then raise;end if;
end;
/

commit;
