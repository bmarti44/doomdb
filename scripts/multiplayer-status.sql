whenever sqlerror exit failure rollback
set pagesize 100 linesize 260 trimspool on feedback off verify off

prompt MULTIPLAYER_LIFECYCLE
select match_state,count(*) matches
from doom_match
group by match_state
order by match_state;

prompt MULTIPLAYER_ACTIVE
column match_ref format a12
column game_mode format a10
column worker_status format a12
select substr(lower(standard_hash(m.match_id,'SHA256')),1,12) match_ref,
       m.game_mode,m.current_tic,w.worker_mode,w.worker_status,
       (select count(*) from doom_match_member p where p.match_id=m.match_id
         and p.member_state<>'LEFT') players,
       round(m.current_tic/greatest(1,
         (cast(systimestamp as date)-cast(m.started_at as date))*86400),2) average_hz,
       (select coalesce(max(c.tic),0)-m.current_tic from doom_match_command c
         where c.match_id=m.match_id) command_lead,
       greatest(0,w.generation-1) recoveries,
       (select round(percentile_cont(.95) within group(order by
         extract(day from (t.committed_at-t.deadline_at))*86400000+
         extract(hour from (t.committed_at-t.deadline_at))*3600000+
         extract(minute from (t.committed_at-t.deadline_at))*60000+
         extract(second from (t.committed_at-t.deadline_at))*1000),2)
         from doom_match_tic t where t.match_id=m.match_id and t.tic>0) tic_p95_ms,
       (select count(*) from doom_match_frame f where f.match_id=m.match_id) frame_rows,
       (select coalesce(sum(f.response_bytes),0) from doom_match_frame f
         where f.match_id=m.match_id) frame_bytes,
       (select count(*) from doom_match_checkpoint c where c.match_id=m.match_id)
         checkpoints
from doom_match m join doom_match_worker_control w on w.match_id=m.match_id
where m.match_state='ACTIVE'
order by match_ref;

prompt MULTIPLAYER_ACTIVE_PLAYERS
select substr(lower(standard_hash(m.match_id,'SHA256')),1,12) match_ref,
       p.player_slot+1 player_number,p.member_state,
       (select count(*) from doom_match_input_event i where i.match_id=p.match_id
         and i.player_slot=p.player_slot) input_revisions,
       (select count(*) from doom_match_command c where c.match_id=p.match_id
         and c.player_slot=p.player_slot) applied_commands,
       (select count(*) from doom_match_command c where c.match_id=p.match_id
         and c.player_slot=p.player_slot and c.command_source like 'NEUTRAL_%')
         neutral_commands,
       (select round(avg(f.response_bytes),1) from doom_match_frame f
         where f.match_id=p.match_id and f.player_slot=p.player_slot)
         average_response_bytes
from doom_match m join doom_match_member p on p.match_id=m.match_id
where m.match_state='ACTIVE' and p.member_state<>'LEFT'
order by match_ref,player_number;

prompt TRANSPORT_LATENCY_AND_HTTP_REJECTS=browser ResourceTiming plus ORDS access log
