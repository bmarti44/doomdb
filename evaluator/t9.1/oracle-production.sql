whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
set feedback off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare n number;begin
 select heat into n from(select frame_no,y,x,heat from(select 0 frame_no,0 y,0 x,0 heat from dual)model dimension by(frame_no,y,x)measures(heat)rules sequential order(heat[frame_no is any,y is any,x is any] order by frame_no asc,y desc,x asc=7))where frame_no=0 and y=0 and x=0;
 if n<>7 then raise_application_error(-20991,'MODEL ordered capability probe mismatch');end if;
 dbms_output.put_line('PASS T9.1-ORACLE-CAPABILITY (MODEL + RULES SEQUENTIAL ORDER + dimension ORDER BY)');
end;
/
declare
 n number;raw_frame raw(32767);piece raw(32767);all_frames blob;last_intensity number;cursor runs(p_frame number)is select run_no,start_offset,run_length,intensity from doom_fire_frame_run where frame_no=p_frame order by run_no;
 procedure ok(b boolean,m varchar2)is begin if not b then raise_application_error(-20991,m);end if;end;
begin
 select count(*) into n from user_objects where object_name='DOOM_FIRE' and object_type='PACKAGE' and status='VALID';ok(n=1,'valid DOOM_FIRE package absent');
 select count(*) into n from user_procedures where object_name='DOOM_FIRE' and procedure_name='GENERATE';ok(n=1,'DOOM_FIRE.GENERATE absent/overloaded');
 select count(*) into n from user_tab_columns where table_name='DOOM_FIRE_FRAME_RUN' and column_name in('FRAME_NO','RUN_NO','START_OFFSET','RUN_LENGTH','INTENSITY');ok(n=5,'canonical run columns absent');
 select count(*) into n from user_tab_columns where table_name='DOOM_FIRE_BUILD_PROBE' and column_name in('PROBE_ORDINAL','PROBE_NAME','FRAME_COUNT','WIDTH','HEIGHT','CELL_COUNT','ESTIMATED_BYTES','PREINSERT_RUN_COUNT','RESULT_RUN_COUNT','MODEL_OPERATIONS','STATUS','ELAPSED_MS','PGA_BYTES');ok(n=13,'probe evidence columns absent');
 select count(*) into n from user_source where name='DOOM_FIRE' and type='PACKAGE BODY' and regexp_like(upper(text),'DBMS_RANDOM|SYSDATE|SYSTIMESTAMP|CURRENT_TIMESTAMP|EXECUTE IMMEDIATE|PRAGMA AUTONOMOUS');ok(n=0,'forbidden nondeterminism/dynamic SQL');
 doom_fire.generate;
 select count(*) into n from doom_fire_build_probe where probe_ordinal=1 and probe_name='SMALL' and frame_count=8 and width=16 and height=12 and cell_count=1536 and result_run_count=485 and model_operations=1 and status='PASS' and preinsert_run_count=0 and elapsed_ms>=0 and pga_bytes>=0;ok(n=1,'small preflight evidence mismatch');
 select count(*) into n from doom_fire_build_probe where probe_ordinal=2 and probe_name='FULL' and frame_count=150 and width=160 and height=96 and cell_count=2304000 and result_run_count=604369 and model_operations=1 and status='PASS' and preinsert_run_count=0 and estimated_bytes between 2304000 and 268435456 and elapsed_ms>=0 and pga_bytes>=0;ok(n=1,'full memory/feasibility evidence mismatch');
 select count(*) into n from doom_fire_frame_run;ok(n=604369,'exact full canonical run count mismatch');dbms_output.put_line('T91_RUN_ROWS '||n);
 select count(distinct frame_no) into n from doom_fire_frame_run;ok(n=150,'frame count mismatch');select count(*) into n from(select frame_no from doom_fire_frame_run group by frame_no having frame_no not between 0 and 149 or max(start_offset+run_length)<>15360 or min(start_offset)<>0);ok(n=0,'frame coverage/range mismatch');
 dbms_lob.createtemporary(all_frames,true);
 for f in 0..149 loop raw_frame:=null;n:=0;last_intensity:=null;for r in runs(f)loop ok(r.run_no=n,'non-dense run number frame '||f);ok(r.start_offset=nvl(utl_raw.length(raw_frame),0),'run gap/overlap frame '||f);ok(r.run_length>0 and r.intensity between 0 and 36,'run value/range frame '||f);ok(last_intensity is null or last_intensity<>r.intensity,'mergeable adjacent run frame '||f);piece:=utl_raw.copies(hextoraw(lpad(trim(to_char(r.intensity,'XX')),2,'0')),r.run_length);raw_frame:=utl_raw.concat(raw_frame,piece);last_intensity:=r.intensity;n:=n+1;end loop;ok(utl_raw.length(raw_frame)=15360,'decoded size frame '||f);dbms_lob.writeappend(all_frames,utl_raw.length(raw_frame),raw_frame);dbms_output.put_line('T91_FRAME_HASH '||f||' '||lower(rawtohex(dbms_crypto.hash(raw_frame,dbms_crypto.hash_sh256))));end loop;
 dbms_output.put_line('T91_ANIMATION_HASH '||lower(rawtohex(dbms_crypto.hash(all_frames,dbms_crypto.hash_sh256))));dbms_lob.freetemporary(all_frames);commit;dbms_output.put_line('PASS T9.1-ORACLE-PRODUCTION (full ordered MODEL generation, probes, canonical RLE, hashes)');
end;
/
