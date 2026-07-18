set pagesize 100 linesize 300 long 100000
select doom_player_move_payload(
  (select session_token from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=31 and s.saved_tic=1530 order by g.created_at desc
  ) where rownum=1),16,0) payload
from dual;
exit
