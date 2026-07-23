whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off

begin execute immediate 'drop function doom_mle_adb_arithmetic';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_mle_adb_probe';
exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop mle env doom_mle_adb_env';
exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;
/

create mle env doom_mle_adb_env pure;
create mle module doom_mle_adb_probe language javascript as
export function arithmetic(iterations,seed){
  let value=seed|0;
  for(let i=0;i<(iterations|0);i++){
    value=(Math.imul(value^i,1664525)+1013904223)|0;
    value=(value+(value>>>16))|0;
  }
  return value;
}
/
create function doom_mle_adb_arithmetic(p_iterations number,p_seed number)
return number as mle module doom_mle_adb_probe env doom_mle_adb_env
signature 'arithmetic(number,number)';
/
