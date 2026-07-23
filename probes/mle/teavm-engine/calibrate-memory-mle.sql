whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

begin execute immediate 'drop function doom_mle_memory_cal_release';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_mle_memory_cal_allocate';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_mle_memory_cal';
exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop mle env doom_mle_memory_cal_env';
exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;
/

create mle env doom_mle_memory_cal_env pure;

create mle module doom_mle_memory_cal language javascript as
let retained = null;

export function allocate(bytes) {
  const length = bytes | 0;
  if (length <= 0 || length > 268435456) {
    throw new Error("invalid calibration allocation");
  }
  retained = new Uint8Array(length);
  for (let offset = 0; offset < length; offset += 4096) {
    retained[offset] = 165;
  }
  retained[length - 1] = 165;
  return retained.length;
}

export function release() {
  const previousLength = retained === null ? 0 : retained.length;
  retained = null;
  return previousLength;
}
/

create function doom_mle_memory_cal_allocate(p_bytes number)
return number as mle module doom_mle_memory_cal env doom_mle_memory_cal_env
signature 'allocate(number)';
/

create function doom_mle_memory_cal_release
return number as mle module doom_mle_memory_cal env doom_mle_memory_cal_env
signature 'release()';
/

declare
  c_allocation_bytes constant pls_integer:=134217728;
  -- SQL*Plus startup through the container can take >10 seconds on the
  -- two-core evidence host. Keep each phase open long enough for a complete
  -- independent SYS and /proc observation.
  c_observation_seconds constant pls_integer:=30;
  l_loaded number;
begin
  dbms_application_info.set_module('DOOM_MLE_MEMORY_CAL','RESET');
  l_loaded:=doom_mle_memory_cal_release;

  dbms_application_info.set_action('BASELINE_READY');
  dbms_session.sleep(c_observation_seconds);

  dbms_application_info.set_action('TOUCHING_128M');
  l_loaded:=doom_mle_memory_cal_allocate(c_allocation_bytes);
  if l_loaded<>c_allocation_bytes then
    raise_application_error(-20795,'retained allocation was not fully touched');
  end if;

  dbms_application_info.set_action('ALLOCATED_READY');
  dbms_output.put_line('PMLE_MLE_MEMORY_CAL_ALLOCATION|bytes='||c_allocation_bytes||
    '|loaded='||l_loaded);
  dbms_session.sleep(c_observation_seconds);

  l_loaded:=doom_mle_memory_cal_release;
  if l_loaded<>c_allocation_bytes then
    raise_application_error(-20794,'retained allocation release mismatch');
  end if;
  dbms_application_info.set_action('RELEASED_READY');
  dbms_session.sleep(c_observation_seconds);
  dbms_application_info.set_module(null,null);
exception when others then
  dbms_application_info.set_action('FAILED');
  begin l_loaded:=doom_mle_memory_cal_release;exception when others then null;end;
  raise;
end;
/

begin execute immediate 'drop function doom_mle_memory_cal_release';end;
/
begin execute immediate 'drop function doom_mle_memory_cal_allocate';end;
/
begin execute immediate 'drop mle module doom_mle_memory_cal';end;
/
begin execute immediate 'drop mle env doom_mle_memory_cal_env';end;
/
