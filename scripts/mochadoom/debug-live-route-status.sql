set verify off feedback off heading off pagesize 0 linesize 32767

-- SQL*Plus usage:
--   @scripts/mochadoom/debug-live-route-status.sql <32-hex-session> [0|1]
-- Enabling affects only the already-claimed worker for this session. The next
-- generation resets it to zero, and no field is exposed through AutoREST.
define route_session='&1'
define route_enable='&2'

update doom_worker_control
set route_diagnostics=case when '&&route_enable'='1' then 1 else 0 end,
    route_status_tic=case when '&&route_enable'='1' then route_status_tic end,
    route_status=case when '&&route_enable'='1' then route_status end
where target_session='&&route_session'
  and regexp_like('&&route_session','^[0-9a-f]{32}$')
  and '&&route_enable' in('0','1');
commit;

select 'ROUTE_STATUS|'||route_status_tic||'|'||route_status
from doom_worker_control
where target_session='&&route_session' and route_status is not null;
