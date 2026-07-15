whenever sqlerror exit sql.sqlcode rollback
set define off serveroutput on size unlimited
declare
  k_token constant varchar2(32):='62626262626262626262626262626262';
  procedure clear_map is begin delete from doom_block_line;delete from doom_block_cell;delete from doom_linedef;delete from doom_map_linedef;delete from doom_map_sidedef;delete from doom_map_vertex;delete from sector_state;delete from doom_map_sector;delete from eval_region;end;
  procedure sector_(p_id number,p_floor number,p_ceiling number) is begin insert into doom_map_sector values(p_id,p_floor,p_ceiling);insert into sector_state values(k_token,p_id,p_floor,p_ceiling);end;
  procedure line_(p_id number,p_x1 number,p_y1 number,p_x2 number,p_y2 number,p_flags number,p_right number,p_left number) is
    l_len number:=sqrt(power(p_x2-p_x1,2)+power(p_y2-p_y1,2));
  begin
    insert into doom_map_vertex values(p_id*2,p_x1,p_y1);insert into doom_map_vertex values(p_id*2+1,p_x2,p_y2);
    insert into doom_map_sidedef values(p_id*2,p_right);if p_left is not null then insert into doom_map_sidedef values(p_id*2+1,p_left);end if;
    insert into doom_map_linedef values(p_id,p_id*2,p_id*2+1,p_flags,p_id*2,case when p_left is null then null else p_id*2+1 end);
    insert into doom_linedef values(p_id,p_id*2,p_id*2+1,p_flags,p_id*2,case when p_left is null then null else p_id*2+1 end,mdsys.sdo_geometry(2002,null,null,mdsys.sdo_elem_info_array(1,2,1),mdsys.sdo_ordinate_array(p_x1,p_y1,p_x2,p_y2)),l_len,(p_x2-p_x1)/l_len,(p_y2-p_y1)/l_len);
    insert into doom_block_line values(0,(select count(*) from doom_block_line),p_id);
  end;
  procedure player_(p_x number,p_y number,p_z number,p_noclip number:=0) is begin update players set x=p_x,y=p_y,z=p_z,view_height=41,noclip=p_noclip where session_token=k_token and player_id=0;end;
  procedure region_(p_x number,p_low number,p_high number) is begin insert into eval_region values(p_x,p_low,p_high);end;
  procedure check_(p_label varchar2,p_dx number,p_dy number,p_x number,p_y number,p_z number,p_sector number,p_contacts number,p_first number:=null,p_second number:=null) is
    l_count number;l_x number;l_y number;l_z number;l_sector number;l_contacts number;l_first number;l_second number;l_eye number;
  begin
    select count(*),min(dest_x),min(dest_y),min(dest_z),min(destination_sector_id),min(contact_count),min(first_blocker_id),min(second_blocker_id),min(eye_z)
      into l_count,l_x,l_y,l_z,l_sector,l_contacts,l_first,l_second,l_eye from table(doom_player_move(k_token,p_dx,p_dy));
    if l_count<>1 or abs(l_x-p_x)>1e-7 or abs(l_y-p_y)>1e-7 or abs(l_z-p_z)>1e-7 or l_sector<>p_sector or l_contacts<>p_contacts or nvl(l_first,-1)<>nvl(p_first,-1) or nvl(l_second,-1)<>nvl(p_second,-1) or abs(l_eye-(p_z+41))>1e-7 then raise_application_error(-20863,p_label||' mismatch');end if;
  end;
begin
  insert into game_sessions values(k_token,0);insert into players(session_token,player_id,x,y,z,view_height) values(k_token,0,0,0,0,41);
  -- Head-on, oblique slide, continuous tunneling, and noclip use one one-sided wall.
  clear_map;sector_(0,0,128);insert into doom_block_cell values(0,0,0,-5000,-5000,0);line_(10,64,-128,64,128,0,0,null);
  player_(0,0,0);check_('head-on',100,0,48,0,0,0,1,10);player_(0,0,0);check_('oblique',100,30,48,30,0,0,1,10);
  player_(-500,0,0);check_('tunneling',1000,0,48,0,0,0,1,10);player_(0,0,0,1);check_('noclip',100,0,100,0,0,0,0);
  -- Stable two-contact corner.
  clear_map;sector_(0,0,128);insert into doom_block_cell values(0,0,0,-5000,-5000,0);line_(10,64,-128,64,128,0,0,null);line_(11,128,64,-128,64,0,0,null);player_(0,0,0);check_('corner',100,100,48,48,0,0,2,10,11);
  -- Open portal and exact valid step derive destination vertical state.
  clear_map;sector_(0,0,128);sector_(1,0,128);region_(64,0,1);insert into doom_block_cell values(0,0,0,-5000,-5000,0);line_(20,64,-128,64,128,0,0,1);player_(0,0,0);check_('portal',100,0,100,0,0,1,0);
  update doom_map_sector set floor_height=24 where sector_id=1;update sector_state set floor_height=24 where sector_id=1;player_(0,0,0);check_('valid step',100,0,100,0,24,1,0);
  update doom_map_sector set floor_height=0 where sector_id=1;update sector_state set floor_height=25 where sector_id=1;player_(0,0,0);check_('dynamic high step',100,0,48,0,0,0,1,20);
  update sector_state set floor_height=0,ceiling_height=0 where sector_id=1;player_(0,0,0);check_('closed door',100,0,48,0,0,0,1,20);
  -- Explicit blocking flag on an otherwise open two-sided line.
  update sector_state set ceiling_height=128 where sector_id=1;update doom_map_linedef set flags=1;update doom_linedef set flags=1;player_(0,0,0);check_('blocking flag',100,0,48,0,0,0,1,20);
  rollback;dbms_output.put_line('PASS T6.2-ORACLE-MINI-MAP (10 independent live scenarios)');
end;
/
