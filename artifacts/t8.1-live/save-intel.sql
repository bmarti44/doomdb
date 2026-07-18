set pagesize 200 linesize 220
column session_token format a34
column save_lineage format a34
select s.session_token,s.slot_number,s.saved_tic,s.lineage,
       g.current_tic,g.last_command_seq,g.save_lineage,g.created_at
from save_slots s join game_sessions g on g.session_token=s.session_token
where s.slot_number between 75 and 80
order by g.created_at desc,s.slot_number;
exit
