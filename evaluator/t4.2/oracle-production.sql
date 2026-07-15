whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

set constraints all deferred;

declare
  k_a constant varchar2(32):='42424242424242424242424242424242';
  k_b constant varchar2(32):='43434343434343434343434343434343';
  l_weapon varchar2(32); l_n number; l_hash varchar2(64); l_hash2 varchar2(64); l_checks number:=0;
  procedure fail(m varchar2) is begin raise_application_error(-20942,m); end;
  procedure eq(a number,e number,n varchar2) is begin l_checks:=l_checks+1;if a is null or a!=e then fail(n||' expected '||e||' got '||nvl(to_char(a,'FM9999999990','NLS_NUMERIC_CHARACTERS=''.,'''),'NULL'));end if;end;
  procedure eqs(a varchar2,e varchar2,n varchar2) is begin l_checks:=l_checks+1;if a is null or a!=e then fail(n||' mismatch');end if;end;
  function frame_hash(tok varchar2) return varchar2 is
    b blob; r raw(4);
  begin
    dbms_lob.createtemporary(b,true);for p in (select palette_index from table(doom_r1_pixels(tok)) order by column_no,row_no) loop r:=utl_raw.substr(utl_raw.cast_from_binary_integer(p.palette_index,utl_raw.big_endian),4,1);dbms_lob.writeappend(b,1,r);end loop;
    if dbms_lob.getlength(b)!=64000 then fail('canonical hash byte count');end if;l_checks:=l_checks+1;
    return lower(rawtohex(dbms_crypto.hash(b,dbms_crypto.hash_sh256)));
  end;
  procedure probe(tok varchar2,c number,r number,p number,l number,n varchar2) is ap number;al number;
  begin select palette_index,layer_ordinal into ap,al from table(doom_r1_pixels(tok)) where column_no=c and row_no=r;eq(ap,p,n||' palette');eq(al,l,n||' layer');end;
  procedure validate_dense(tok varchar2,n varchar2) is total number;uniq number;bad number;missing number;dups number;floors number;ceilings number;walls number;
  begin
    select count(*),count(distinct to_char(column_no,'FM000')||':'||to_char(row_no,'FM000')),sum(case when column_no<0 or column_no>319 or row_no<0 or row_no>199 or palette_index<0 or palette_index>255 or palette_index!=trunc(palette_index) or layer_ordinal not in(0,1,10) then 1 else 0 end),sum(case when layer_ordinal=0 then 1 else 0 end),sum(case when layer_ordinal=1 then 1 else 0 end),sum(case when layer_ordinal=10 then 1 else 0 end)
      into total,uniq,bad,floors,ceilings,walls from table(doom_r1_pixels(tok));eq(total,64000,n||' total');eq(uniq,64000,n||' unique');eq(nvl(bad,0),0,n||' range');
    select count(*) into missing from (select c.column_no,r.row_no from (select level-1 column_no from dual connect by level<=320)c cross join (select level-1 row_no from dual connect by level<=200)r minus select column_no,row_no from table(doom_r1_pixels(tok)));eq(missing,0,n||' gaps');
    select count(*) into dups from (select column_no,row_no from table(doom_r1_pixels(tok)) group by column_no,row_no having count(*)!=1);eq(dups,0,n||' duplicates');
    if floors=0 or ceilings=0 or walls=0 then fail(n||' missing semantic layer');end if;l_checks:=l_checks+1;
  end;
  procedure set_pose(tok varchar2,a number) is begin update players set x=-416,y=256,z=0,view_height=41,angle=a where session_token=tok and player_id=0;end;
begin
  select min(weapon_id) into l_weapon from doom_weapon_def;
  for i in 0..1 loop
    insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
      values(case i when 0 then k_a else k_b end,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T42',0,systimestamp+interval '1' hour,systimestamp);
    insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
      values(case i when 0 then k_a else k_b end,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
    update game_sessions set current_player_id=0 where session_token=case i when 0 then k_a else k_b end;
  end loop;
  select count(*) into l_n from user_objects where object_name='DOOM_R1_PIXELS' and object_type='FUNCTION' and status='VALID';eq(l_n,1,'valid pixel macro');
  validate_dense(k_a,'spawn east');
  probe(k_a,0,0,111,1,'east 0/0');probe(k_a,0,99,110,10,'east 0/99');probe(k_a,0,199,6,0,'east 0/199');probe(k_a,79,35,5,1,'east 79/35');probe(k_a,79,100,105,10,'east 79/100');probe(k_a,79,170,1,0,'east 79/170');probe(k_a,159,63,79,1,'east 159/63');probe(k_a,159,99,77,10,'east 159/99');probe(k_a,159,159,5,0,'east 159/159');probe(k_a,160,100,5,10,'east 160/100');probe(k_a,240,180,2,0,'east 240/180');probe(k_a,319,199,0,0,'east 319/199');
  eqs(frame_hash(k_a),'47302a67b53ef176a84a54b1247a85fc88e45f695af2554ff278265e118f65b4','east hash');
  set_pose(k_a,90);validate_dense(k_a,'spawn north');
  probe(k_a,0,0,5,1,'north 0/0');probe(k_a,0,99,5,10,'north 0/99');probe(k_a,0,199,0,0,'north 0/199');probe(k_a,79,35,79,10,'north 79/35');probe(k_a,79,100,111,10,'north 79/100');probe(k_a,79,170,111,0,'north 79/170');probe(k_a,159,63,5,10,'north 159/63');probe(k_a,159,99,107,10,'north 159/99');probe(k_a,159,159,111,0,'north 159/159');probe(k_a,160,100,110,10,'north 160/100');probe(k_a,240,180,1,0,'north 240/180');probe(k_a,319,199,108,0,'north 319/199');
  eqs(frame_hash(k_a),'46c8a2ca36446249b89385e0b901064304e3fc6212ce027ff06dc5c8d1b429c6','north hash');
  set_pose(k_a,270);validate_dense(k_a,'spawn south');
  probe(k_a,0,0,109,10,'south 0/0');probe(k_a,0,99,108,10,'south 0/99');probe(k_a,0,199,5,0,'south 0/199');probe(k_a,319,0,111,1,'south 319/0');probe(k_a,79,100,111,10,'south 79/100');probe(k_a,79,170,111,0,'south 79/170');probe(k_a,159,63,5,10,'south 159/63');probe(k_a,159,99,110,10,'south 159/99');probe(k_a,159,159,0,0,'south 159/159');probe(k_a,160,100,6,10,'south 160/100');probe(k_a,240,180,111,0,'south 240/180');probe(k_a,319,199,6,0,'south 319/199');
  eqs(frame_hash(k_a),'b920598f8363b34715764745c8130271e9b39f3edcc05125b06d82fdff20a34f','south hash');
  set_pose(k_a,0);set_pose(k_b,0);
  select count(*) into l_n from ((select column_no,row_no,palette_index,layer_ordinal from table(doom_r1_pixels(k_a)) minus select column_no,row_no,palette_index,layer_ordinal from table(doom_r1_pixels(k_b))) union all (select column_no,row_no,palette_index,layer_ordinal from table(doom_r1_pixels(k_b)) minus select column_no,row_no,palette_index,layer_ordinal from table(doom_r1_pixels(k_a))));eq(l_n,0,'session equivalence');
  l_hash:=frame_hash(k_a);l_hash2:=frame_hash(k_a);eqs(l_hash,l_hash2,'rerun hash');
  rollback;dbms_output.put_line('PASS T4.2-ORACLE-PRODUCTION ('||l_checks||' live checks)');
end;
/
