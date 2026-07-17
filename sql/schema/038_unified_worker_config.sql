-- Live upgrade companion for the clean-schema defaults in 050_config.sql.
merge into doom_config d
using (select 'UNIFIED_WORKER_FAILPOINT' config_key,0 number_value,
  cast(null as varchar2(4000)) text_value from dual) s
on(d.config_key=s.config_key)
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,s.text_value);
commit;
merge into doom_config d
using (select 'RENDER_OVERLAP_ENABLED' config_key,0 number_value,
  cast(null as varchar2(4000)) text_value from dual) s
on(d.config_key=s.config_key)
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,s.text_value);
commit;
merge into doom_config d
using (select 'RENDER_OVERLAP_WAIT_MS' config_key,100 number_value,
  cast(null as varchar2(4000)) text_value from dual) s
on(d.config_key=s.config_key)
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,s.text_value);
commit;
merge into doom_config d
using (select 'RENDER_OVERLAP_DECISION_MS' config_key,2000 number_value,
  cast(null as varchar2(4000)) text_value from dual) s
on(d.config_key=s.config_key)
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,s.text_value);
commit;
merge into doom_config d
using (select 'UNIFIED_WORKER_SPLIT_USE_ENABLED' config_key,0 number_value,
  cast(null as varchar2(4000)) text_value from dual) s
on(d.config_key=s.config_key)
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,s.text_value);
commit;
merge into doom_config d
using (select 'UNIFIED_WORKER_PARITY_INTERVAL' config_key,0 number_value,
  cast(null as varchar2(4000)) text_value from dual) s
on(d.config_key=s.config_key)
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,s.text_value);
commit;
