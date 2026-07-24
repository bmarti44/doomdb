whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off
begin execute immediate 'drop procedure doom_teavm_sim_release';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_memory';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_state';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_canonical_state';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_canonical_chunk';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_canonical_length';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_checkpoint_chunk';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_checkpoint_length';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_restore';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_restore_warm';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_restore_load';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_restore_allocate';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_step';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_step_bare';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_step_command';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_initialize';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_multi_step';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_authority_step';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_multi_init';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_multi_init_skill';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_multi_init_game';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_load';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_allocate';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_table_load';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_sim_table_allocate';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_teavm_simulation';
exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop mle env doom_teavm_sim_env';
exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;
/
begin execute immediate 'drop table doom_teavm_sim_source purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
