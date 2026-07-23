whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off

begin execute immediate 'drop procedure doom_mle_hybrid_draw_batches';
exception when others then if sqlcode <> -4043 then raise; end if; end;
/
begin execute immediate 'drop procedure doom_mle_hybrid_draw_calls';
exception when others then if sqlcode <> -4043 then raise; end if; end;
/
begin execute immediate 'drop procedure doom_mle_hybrid_render';
exception when others then if sqlcode <> -4043 then raise; end if; end;
/
begin execute immediate 'drop mle module doom_mle_hybrid_bench';
exception when others then if sqlcode not in (-4080, -4103) then raise; end if; end;
/
begin execute immediate 'drop mle env doom_mle_hybrid_env';
exception when others then if sqlcode not in (-4080, -4103, -4104, -4105) then raise; end if; end;
/
