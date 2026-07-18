declare
  l_session varchar2(32); l_payload blob;
begin
  select session_token into l_session from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=18 and s.saved_tic=1425 order by g.created_at desc
  ) where rownum=1;
  doom_history.load_game(l_session,18,l_payload);
  commit;
end;
/
exit
