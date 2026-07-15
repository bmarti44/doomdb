whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback

begin
  ords.drop_rest_for_schema(
    p_schema => sys_context('USERENV', 'CURRENT_SCHEMA'));
  commit;
end;
/

drop package transport_probe_api;
drop table transport_probe_tx purge;
