set pagesize 500 linesize 240 trimspool on
column state_id format a24
column type_name format a14
declare
  l_session varchar2(32); l_payload blob;
begin
  select session_token into l_session from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=35 and s.saved_tic=1478 order by g.created_at desc
  ) where rownum=1;
  doom_history.load_game(l_session,35,l_payload);
  commit;
end;
/
select m.mobj_id,d.type_name,m.x,m.y,m.health,m.state_id,m.awake,m.sector_id,
       round(sqrt(power(m.x-p.x,2)+power(m.y-p.y,2)),1) distance
from mobjs m
join doom_thing_type_def d on d.thing_type=m.thing_type
join players p on p.session_token=m.session_token and p.player_id=0
where m.session_token=(
  select session_token from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=35 and s.saved_tic=1478 order by g.created_at desc
  ) where rownum=1
)
and d.category='monster' and m.health>0
order by distance,m.mobj_id;
exit
