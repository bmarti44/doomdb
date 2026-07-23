whenever sqlerror exit failure rollback

-- Production authority is the retained TeaVM/MLE worker. The old unified
-- OJVM worker remains a dev-only differential oracle and is never enabled in
-- a production schema compiled without DOOM_DEV_OJVM.
update doom_config
set text_value='MLE',number_value=null
where config_key='GAME_ENGINE';

update doom_config
set number_value=0,text_value=null
where config_key in(
  'UNIFIED_WORKER_ENABLED',
  'UNIFIED_WORKER_SPLIT_USE_ENABLED',
  'RENDER_OVERLAP_ENABLED');

update doom_config
set text_value='PACED_INPUT',number_value=null
where config_key='MATCH_WORKER_MODE';

commit;
