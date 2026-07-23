whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off

begin execute immediate 'drop function doom_mle_bind_frame';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_mle_bind_bench';
exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_mle_bind_sink purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/

create table doom_mle_bind_sink(id number primary key,payload blob not null);
insert into doom_mle_bind_sink values(1,empty_blob());

create mle module doom_mle_bind_bench language javascript as
import oracledb from 'mle-js-oracledb';
const frame=new Uint8Array(64000);
for(let i=0;i<frame.length;i++) frame[i]=(i*73+(i>>>4)+19)&255;
export function bindFrame(seed){
  frame[0]=seed&255;
  const connection=oracledb.defaultConnection();
  const result=connection.execute(
    'update doom_mle_bind_sink set payload=:payload where id=1',
    {payload:{val:frame,type:oracledb.DB_TYPE_BLOB}});
  return result.rowsAffected;
}
/

create function doom_mle_bind_frame(p_seed number) return number
as mle module doom_mle_bind_bench signature 'bindFrame(number)';
/
