whenever sqlerror continue
begin execute immediate 'drop procedure doom_wasm2js_cost_release';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_cost_memory';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_cost_lowering';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_cost_js';exception when others then null;end;
/
begin execute immediate 'drop function doom_wasm2js_cost_linear';exception when others then null;end;
/
begin execute immediate 'drop mle module doom_wasm2js_cost_bridge';exception when others then null;end;
/
begin execute immediate 'drop mle env doom_wasm2js_cost_env';exception when others then null;end;
/
begin execute immediate 'drop mle module doom_wasm2js_cost_engine';exception when others then null;end;
/
begin execute immediate 'drop table doom_wasm2js_cost_source purge';exception when others then null;end;
/
commit;
