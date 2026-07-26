whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- Direct grants required by the dedicated production schema. Autonomous
-- Database does not expose the local container bootstrap, and privileges used
-- by stored PL/SQL must not arrive only through a role.
-- CREATE PROPERTY GRAPH is install-validation-only: the production installer
-- validates the relational sector graph, but the authoritative MLE ticker does
-- not query the property-graph object at runtime.
grant create session, create table, create view, create sequence,
  create procedure, create trigger, create type, create job,
  create mle, create property graph to DOOM;
grant execute on sys.dbms_crypto to DOOM;
grant execute on sys.dbms_aq to DOOM;
grant execute on sys.dbms_aqadm to DOOM;
grant execute on sys.dbms_alert to DOOM;
grant select on sys.v_$rsrcpdbmetric to DOOM;
grant select on sys.v_$session to DOOM;
grant select on sys.v_$process to DOOM;
grant select on sys.v_$parameter to DOOM;
commit;
