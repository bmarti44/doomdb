set serveroutput on size unlimited
set verify off feedback off heading off pagesize 0 linesize 4000

declare
  l_session varchar2(32);
  l_lineage varchar2(64);
  l_status varchar2(4000);
begin
  select session_token into l_session from (
    select session_token from game_sessions
      where game_mode='GAME' and current_tic>0
      order by created_at desc,current_tic desc
  ) where rownum=1;
  select save_lineage into l_lineage
    from game_sessions where session_token=l_session;
  doom_mocha_bridge.reconstruct(l_session,l_lineage,l_status);
  dbms_output.put_line(l_status);
  dbms_output.put_line(doom_mocha_probe);
end;
/
