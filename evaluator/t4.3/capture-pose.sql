whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define on verify off echo off feedback off heading off pagesize 0 linesize 200 trimspool on termout off
alter session set nls_numeric_characters='.,';

update players set x=&2,y=&3,angle=&4 where session_token='&1' and player_id=0;

spool &5.pixels.csv
select to_char(column_no,'FM9990')||','||to_char(row_no,'FM9990')||','||to_char(palette_index,'FM9990')
from table(doom_r1_pixels('&1'))
order by column_no,row_no;
spool off

spool &5.palette.csv
select to_char(palette_index,'FM9990')||','||to_char(red,'FM9990')||','||to_char(green,'FM9990')||','||to_char(blue,'FM9990')
from doom_palette_texel order by palette_index;
spool off

spool &5.rle.csv
select to_char(column_no,'FM9990')||','||to_char(min(row_no),'FM9990')||','||to_char(count(*),'FM9990')||','||to_char(min(palette_index),'FM9990')
from (
  select p.*,sum(changed) over(partition by column_no order by row_no rows unbounded preceding) grp
  from (
    select column_no,row_no,palette_index,
           case when lag(palette_index) over(partition by column_no order by row_no)=palette_index then 0 else 1 end changed
    from table(doom_r1_pixels('&1'))
  ) p
) g
group by column_no,grp order by column_no,min(row_no);
spool off
rollback;
exit success
