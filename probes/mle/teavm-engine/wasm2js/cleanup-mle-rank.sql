whenever sqlerror continue
begin execute immediate 'drop procedure doom_wasm2js_rank_release';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_memory';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_lowering';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_canonical_chunk';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_canonical_length';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_step';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_init';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_table_load';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_table_allocate';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_iwad_load';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_rank_iwad_allocate';exception when others then null;end;
/
begin execute immediate 'drop mle module doom_wasm2js_rank_bridge';exception when others then null;end;
/
begin execute immediate 'drop mle env doom_wasm2js_rank_env';exception when others then null;end;
/
begin execute immediate 'drop mle module doom_wasm2js_rank_engine';exception when others then null;end;
/
begin execute immediate 'drop table doom_wasm2js_rank_source purge';exception when others then null;end;
/
commit;
