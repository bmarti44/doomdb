set feedback off heading off pagesize 0 linesize 32767 trimspool on
select to_char(frame_no,'fm999')||'|'||to_char(start_offset,'fm99999')||'|'||
  to_char(run_length,'fm99999')||'|'||to_char(intensity,'fm99')
from doom_fire_frame_run
order by frame_no,run_no;
