set pagesize 100 linesize 220 feedback off
select sector_id,floor_height,ceiling_height,special,tag from doom_map_sector
where sector_id in (70,71,72,74,81,86,87) order by sector_id;
rollback;
