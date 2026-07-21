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
  -- Mocha is the selected playable engine after worker/recovery/AutoREST gates.
  -- SQL remains installed as the independently executable differential oracle.
  select 'GAME_ENGINE', cast(null as number), 'MOCHA' from dual union all
  select 'UNIFIED_WORKER_ENABLED', 1, cast(null as varchar2(4000)) from dual union all
  -- A cold resident session admits the retained renderer/state packs before
  -- its first dequeue; steady-state calls remain millisecond-bounded.
  -- A cold OJVM worker can spend tens of seconds linking the Mocha class
  -- graph after an instance restart. Keep the bounded claim alive long enough
  -- to retain that warm session instead of timing out and repeating the cost.
  select 'UNIFIED_WORKER_WAIT_SECONDS', 120, cast(null as varchar2(4000)) from dual union all
  select 'UNIFIED_WORKER_IDLE_SECONDS', 600, cast(null as varchar2(4000)) from dual union all
  select 'UNIFIED_WORKER_MAX_PACK_BYTES', 2000, cast(null as varchar2(4000)) from dual union all
  select 'UNIFIED_WORKER_POOL_SIZE', 4, cast(null as varchar2(4000)) from dual union all
  -- Frozen into each match control row at start. PACED_INPUT remains an
  -- opt-in spike until its deterministic and two-browser selection gates pass.
  select 'MATCH_WORKER_MODE', cast(null as number), 'LOCKSTEP' from dual union all
  select 'UNIFIED_WORKER_FAILPOINT', 0, cast(null as varchar2(4000)) from dual union all
  select 'UNIFIED_WORKER_PARITY_INTERVAL', 0, cast(null as varchar2(4000)) from dual union all
  select 'UNIFIED_WORKER_SPLIT_USE_ENABLED', 0, cast(null as varchar2(4000)) from dual union all
  select 'RENDER_OVERLAP_ENABLED', 0, cast(null as varchar2(4000)) from dual union all
  select 'RENDER_OVERLAP_WAIT_MS', 100, cast(null as varchar2(4000)) from dual union all
  select 'RENDER_OVERLAP_DECISION_MS', 2000, cast(null as varchar2(4000)) from dual union all
  select 'MAP_NAME', cast(null as number), 'E1M1' from dual union all
  select 'WAD_SHA256', cast(null as number), '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d' from dual
) s
on (d.config_key = s.config_key)
when matched then update set d.number_value=s.number_value, d.text_value=s.text_value
when not matched then insert (config_key, number_value, text_value)
values (s.config_key, s.number_value, s.text_value);
