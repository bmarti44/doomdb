merge into doom_config d
using (
  select 'FAR_DISTANCE' config_key, 8192 number_value, cast(null as varchar2(4000)) text_value from dual union all
  select 'PLAYER_RADIUS', 16, cast(null as varchar2(4000)) from dual union all
  select 'FRAME_WIDTH', 320, cast(null as varchar2(4000)) from dual union all
  select 'FRAME_HEIGHT', 200, cast(null as varchar2(4000)) from dual union all
  select 'MAX_ACTIVE_SESSIONS', 64, cast(null as varchar2(4000)) from dual union all
  select 'SESSION_TTL_SECONDS', 3600, cast(null as varchar2(4000)) from dual union all
  select 'MAX_COMMAND_BYTES', 65536, cast(null as varchar2(4000)) from dual union all
  select 'MAX_COMMANDS_PER_STEP', 4, cast(null as varchar2(4000)) from dual union all
  select 'MAP_NAME', cast(null as number), 'E1M1' from dual union all
  select 'WAD_SHA256', cast(null as number), '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d' from dual
) s
on (d.config_key = s.config_key)
when matched then update set d.number_value=s.number_value, d.text_value=s.text_value
when not matched then insert (config_key, number_value, text_value)
values (s.config_key, s.number_value, s.text_value);
