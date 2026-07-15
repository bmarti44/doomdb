set pagesize 1000 linesize 220 feedback off
select t.thing_id,t.thing_type,d.type_name,d.category,t.x,t.y,t.flags
from doom_map_thing t join doom_thing_type_def d on d.thing_type=t.thing_type
where d.category in ('pickup','weapon_pickup')
  and t.x between 800 and 2400 and t.y between 400 and 1800
order by t.x,t.y,t.thing_id;
rollback;
