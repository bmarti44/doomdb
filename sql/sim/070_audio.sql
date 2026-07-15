-- T7.3 database-authored audio timeline. This package participates in the
-- owning tic transaction and deliberately owns no transaction boundary.
create or replace package doom_audio authid definer as
  procedure emit(p_session in varchar2,p_tic in number);
end doom_audio;
/

create or replace package body doom_audio as
  procedure emit(p_session in varchar2,p_tic in number) is
  begin
    insert into audio_events(
      session_token,tic,event_ordinal,asset_kind,asset_name,volume,separation)
    select p_session,
           g.tic,
           row_number() over(
             partition by g.tic
             order by d.event_class,
                      coalesce(g.actor_mobj_id,0),
                      coalesce(g.target_mobj_id,0),
                      g.event_ordinal
           )-1,
           d.asset_kind,
           d.asset_name,
           d.volume,
           d.separation
      from game_events g
      join game_sessions s
        on s.session_token=g.session_token
       and s.save_lineage=g.lineage
      join doom_audio_event_def d
        on d.event_type=g.event_type
      join doom_asset a
        on a.asset_kind=d.asset_kind
       and a.asset_name=d.asset_name
     where g.session_token=p_session
       and g.lineage=s.save_lineage
       and g.tic=p_tic
     order by g.tic,d.event_class,coalesce(g.actor_mobj_id,0),
              coalesce(g.target_mobj_id,0),g.event_ordinal;
  end emit;
end doom_audio;
/
