whenever sqlerror exit failure rollback

-- Some runtime objects deliberately reference packages or columns installed
-- later in the bootstrap graph.  Close those forward dependencies explicitly
-- so a clean bootstrap finishes with no INVALID objects.
alter trigger doom_game_events_bir compile;
alter procedure doom_renderer_delta_fill compile;
alter procedure doom_renderer_snapshot_fill compile;
alter package doom_unified_worker compile body;

declare
  l_invalid number;
begin
  select count(*) into l_invalid from user_objects where status<>'VALID';
  if l_invalid<>0 then
    raise_application_error(-20000,'bootstrap left invalid runtime objects='||l_invalid);
  end if;
end;
/
