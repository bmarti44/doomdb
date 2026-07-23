-- Solo uses the accepted two-slot authority/checkpoint format with an
-- uncredentialed neutral peer. Keep existing databases on that proven shape;
-- an interrupted development install may briefly have widened this constraint.
declare
  l_condition varchar2(4000);
begin
  select search_condition_vc into l_condition
    from user_constraints
    where constraint_name='DOOM_MATCH_PLAYERS_CK'
      and table_name='DOOM_MATCH';
  if instr(lower(replace(l_condition,'"','')),'between 1 and 4')>0 then
    execute immediate
      'alter table doom_match drop constraint doom_match_players_ck';
    execute immediate
      'alter table doom_match add constraint doom_match_players_ck '||
      'check(max_players between 2 and 4)';
  end if;
end;
/
