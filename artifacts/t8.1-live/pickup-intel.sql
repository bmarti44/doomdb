set pagesize 500 linesize 220
column type_name format a18
declare
  l_session varchar2(32); l_payload blob;
begin
  select session_token into l_session from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=45 and s.saved_tic=1407 order by g.created_at desc
  ) where rownum=1;
  doom_history.load_game(l_session,45,l_payload);
  commit;
end;
/
select m.mobj_id,d.type_name,m.x,m.y,
       (select b.sector_id from table(doom_bsp_locate(m.x,m.y)) b where rownum=1) sector_id,
       round(sqrt(power(m.x-p.x,2)+power(m.y-p.y,2)),1) distance
from mobjs m
join doom_thing_type_def d on d.thing_type=m.thing_type
join players p on p.session_token=m.session_token and p.player_id=0
where m.session_token=(
  select session_token from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=45 and s.saved_tic=1407 order by g.created_at desc
  ) where rownum=1
)
and d.category='pickup' and m.health>0
order by distance,m.mobj_id;
exit
