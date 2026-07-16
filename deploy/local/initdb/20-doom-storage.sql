whenever sqlerror exit sql.sqlcode rollback

-- The retained worker writes hundreds of KiB of redo-logged state per tic.
-- Presize the local substrate so foreground frames do not pay 10 MiB datafile
-- extensions or cycle through the image's 200 MiB redo groups every minute.
alter session set container = FREEPDB1;
alter database datafile '/opt/oracle/oradata/FREE/FREEPDB1/users01.dbf'
  resize 4096M;
alter database datafile '/opt/oracle/oradata/FREE/FREEPDB1/users01.dbf'
  autoextend on next 512M maxsize 10240M;

alter session set container = CDB$ROOT;
alter database add logfile group 4
  ('/opt/oracle/oradata/FREE/redo04.log') size 1G;
alter database add logfile group 5
  ('/opt/oracle/oradata/FREE/redo05.log') size 1G;
alter database add logfile group 6
  ('/opt/oracle/oradata/FREE/redo06.log') size 1G;
alter system switch logfile;
alter system checkpoint;
alter system switch logfile;
alter system checkpoint;
alter system switch logfile;
alter system checkpoint;
alter database drop logfile group 1;
alter database drop logfile group 2;
alter database drop logfile group 3;
