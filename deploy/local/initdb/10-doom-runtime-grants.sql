whenever sqlerror exit sql.sqlcode rollback
alter session set container = FREEPDB1;
grant execute on sys.dbms_crypto to DOOM;
grant execute on sys.dbms_aq to DOOM;
grant execute on sys.dbms_aqadm to DOOM;
grant execute on sys.dbms_alert to DOOM;
grant select on sys.v_$rsrcpdbmetric to DOOM;
grant select on sys.v_$session to DOOM;
grant select on sys.v_$process to DOOM;
grant create job to DOOM;
