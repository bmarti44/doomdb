whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off
create or replace view doom_api_presentation_rows as
    with
    session_state as (
      select session_row.session_token,session_row.game_mode,
        session_row.paused,session_row.menu_state,
        session_row.automap_state,session_row.map_status,
        player.player_id,player.x player_x,player.y player_y,
        player.angle,player.health,player.armor,
        player.blue_key,player.yellow_key,player.red_key,
        player.ammo_bullets,player.ammo_shells,player.ammo_rockets,
        player.ammo_cells,player.selected_weapon,
        player.kill_count,player.item_count,player.secret_count
      from game_sessions session_row
      join (select distinct session_token from frame_column) selected_session
        on selected_session.session_token=session_row.session_token
      join players player
        on player.session_token=session_row.session_token
       and player.player_id=session_row.current_player_id
    ),
    columns_320 as (
      select level-1 column_no from dual connect by level<=320
    ),
    rows_200 as (
      select level-1 row_no from dual connect by level<=200
    ),
    ordinals_513 as (
      select level-1 ordinal_no from dual connect by level<=513
    ),
    digit_positions as (
      select level character_ordinal from dual connect by level<=3
    ),
    canvas as (
      select /*+ materialize */ state.session_token,column_axis.column_no,
        row_axis.row_no
      from session_state state
      cross join columns_320 column_axis
      cross join rows_200 row_axis
    ),
    world_pixels as (
      select /*+ materialize */ world.*
      from session_state state
      join doom_r2_pixel_rows world
        on world.session_token=state.session_token
      where state.game_mode in ('GAME','DEAD') and world.row_no<168
    ),
    masked_pixels as (
      select /*+ materialize */ masked.*
      from session_state state
      join doom_r2_masked_candidate_rows masked
        on masked.session_token=state.session_token
      where state.game_mode in ('GAME','DEAD')
        and masked.is_selected=1 and masked.row_no<168
    ),
    world_candidates as (
      select world.session_token,world.column_no,world.row_no,
        coalesce(masked.palette_index,world.palette_index) palette_index,
        case when masked.palette_index is null then 10 else 20 end layer_ordinal,
        coalesce(masked.source_kind,'WORLD') source_kind,
        case when masked.palette_index is not null then
          to_char(masked.source_id,'FM9999999990',
            'NLS_NUMERIC_CHARACTERS=''.,''')
        else to_char(world.sector_interval_ordinal,'FM9999999990',
          'NLS_NUMERIC_CHARACTERS=''.,''') end source_id
      from world_pixels world
      left join masked_pixels masked
        on masked.session_token=world.session_token
       and masked.column_no=world.column_no and masked.row_no=world.row_no
    ),
    weapon_choice as (
      select state.*,
        case state.selected_weapon
          when 'FIST' then 'PUNGA0'
          when 'PISTOL' then 'PISGA0'
          when 'SHOTGUN' then 'SHTGA0'
          when 'CHAINGUN' then 'CHGGA0'
          when 'ROCKET_LAUNCHER' then 'MISGA0'
          when 'PLASMA_RIFLE' then 'PLSGA0'
          when 'CHAINSAW' then 'SAWGA0'
          else 'PISGA0'
        end asset_name
      from session_state state
      where state.game_mode in ('GAME','DEAD')
    ),
    weapon_asset as (
      select choice.*,asset.asset_id,asset.width,asset.height
      from weapon_choice choice
      join doom_asset asset
        on asset.asset_kind='sprite_patch'
       and asset.asset_name=choice.asset_name
    ),
    weapon_candidates as (
      select weapon.session_token,
        floor((320-weapon.width)/2)+texel.x column_no,
        200-weapon.height+texel.y row_no,texel.c palette_index,
        30 layer_ordinal,'WEAPON' source_kind,weapon.asset_name source_id
      from weapon_asset weapon
      join at texel on texel.a=weapon.asset_id and texel.c>=0
      where floor((320-weapon.width)/2)+texel.x between 0 and 319
        and 200-weapon.height+texel.y between 0 and 199
    ),
    hud_patch_candidates as (
      select state.session_token,texel.x column_no,168+texel.y row_no,
        texel.c palette_index,40 layer_ordinal,
        'HUD_PATCH' source_kind,asset.asset_name source_id
      from session_state state
      join doom_asset asset
        on asset.asset_kind='ui_patch' and asset.asset_name='STBAR'
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.game_mode in ('GAME','DEAD','AUTOMAP')
    ),
    hud_values as (
      select state.session_token,'AMMO' field_name,
        to_char(case state.selected_weapon
          when 'SHOTGUN' then state.ammo_shells
          when 'ROCKET_LAUNCHER' then state.ammo_rockets
          when 'PLASMA_RIFLE' then state.ammo_cells
          else state.ammo_bullets end,'FM000',
          'NLS_NUMERIC_CHARACTERS=''.,''') field_value,
        44 right_edge,171 top_row,43 layer_ordinal
      from session_state state
      where state.game_mode in ('GAME','DEAD','AUTOMAP')
      union all
      select state.session_token,'HEALTH',to_char(state.health,'FM000',
        'NLS_NUMERIC_CHARACTERS=''.,'''),
        90,171,43 from session_state state
      where state.game_mode in ('GAME','DEAD','AUTOMAP')
      union all
      select state.session_token,'ARMOR',to_char(state.armor,'FM000',
        'NLS_NUMERIC_CHARACTERS=''.,'''),
        221,171,43 from session_state state
      where state.game_mode in ('GAME','DEAD','AUTOMAP')
    ),
    hud_characters as (
      select value_row.*,character_axis.character_ordinal,
        substr(value_row.field_value,character_axis.character_ordinal,1) glyph,
        length(value_row.field_value) character_count
      from hud_values value_row
      cross join digit_positions character_axis
      where character_axis.character_ordinal<=length(value_row.field_value)
    ),
    hud_text_candidates as (
      select chars.session_token,
        chars.right_edge-(chars.character_count-chars.character_ordinal+1)*13+
          texel.x column_no,
        chars.top_row+texel.y row_no,texel.c palette_index,
        chars.layer_ordinal,'TEXT' source_kind,
        chars.field_name||':'||chars.character_ordinal source_id
      from hud_characters chars
      join doom_asset asset
        on asset.asset_kind='ui_patch'
       and asset.asset_name='STTNUM'||chars.glyph
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where chars.right_edge-(chars.character_count-chars.character_ordinal+1)*13+
              texel.x between 0 and 319
        and chars.top_row+texel.y between 0 and 199
    ),
    key_values as (
      select state.session_token,0 key_ordinal,state.blue_key present
      from session_state state
      union all
      select state.session_token,1,state.yellow_key from session_state state
      union all
      select state.session_token,2,state.red_key from session_state state
    ),
    key_candidates as (
      select state.session_token,239+key_row.key_ordinal*10+texel.x column_no,
        171+texel.y row_no,texel.c palette_index,44 layer_ordinal,
        'HUD_PATCH' source_kind,asset.asset_name source_id
      from session_state state
      join key_values key_row on key_row.session_token=state.session_token
      join doom_asset asset
        on asset.asset_kind='ui_patch'
       and asset.asset_name='STKEYS'||case key_row.key_ordinal
         when 0 then '0' when 1 then '1' else '2' end
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.game_mode in ('GAME','DEAD','AUTOMAP')
        and key_row.present=1
    ),
    pause_candidates as (
      select state.session_token,floor((320-asset.width)/2)+texel.x column_no,
        4+texel.y row_no,texel.c palette_index,50 layer_ordinal,
        'PAUSE' source_kind,asset.asset_name source_id
      from session_state state
      join doom_asset asset
        on asset.asset_kind='ui_patch' and asset.asset_name='M_PAUSE'
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.paused=1
    ),
    menu_background as (
      select state.session_token,texel.x column_no,texel.y row_no,
        texel.c palette_index,60 layer_ordinal,'MENU_PATCH' source_kind,
        asset.asset_name source_id
      from session_state state
      join doom_asset asset
        on asset.asset_kind='ui_patch' and asset.asset_name='TITLEPIC'
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.game_mode='MENU'
    ),
    menu_patches as (
      select state.session_token,floor((320-asset.width)/2)+texel.x column_no,
        placement.top_row+texel.y row_no,texel.c palette_index,
        placement.layer_ordinal,
        case when placement.asset_name='M_DOOM' then 'MENU_PATCH'
             else 'TEXT' end source_kind,
        placement.asset_name source_id
      from session_state state
      cross apply (
        select 'M_DOOM' asset_name,15 top_row,70 layer_ordinal from dual
        union all select 'M_NGAME',80,70 from dual
        union all select 'M_EPISOD',105,70 from dual
        union all select 'M_SKILL',130,70 from dual
      ) placement
      join doom_asset asset
        on asset.asset_kind='ui_patch'
       and asset.asset_name=placement.asset_name
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.game_mode='MENU'
        and floor((320-asset.width)/2)+texel.x between 0 and 319
        and placement.top_row+texel.y between 0 and 199
    ),
    menu_selection as (
      select state.session_token,54+texel.x column_no,
        80+least(2,greatest(0,coalesce(to_number(
          case when validate_conversion(state.menu_state as number)=1
               then state.menu_state end),0)))*25+texel.y row_no,
        texel.c palette_index,71 layer_ordinal,'TEXT' source_kind,
        'SELECTED:'||state.menu_state source_id
      from session_state state
      join doom_asset asset
        on asset.asset_kind='ui_patch' and asset.asset_name='STKEYS0'
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.game_mode='MENU'
    ),
    map_bounds as (
      select min(vertex.x) min_x,max(vertex.x) max_x,
        min(vertex.y) min_y,max(vertex.y) max_y
      from doom_vertex vertex
    ),
    automap_segments as (
      select state.session_token,line.linedef_id,line.flags,
        start_vertex.x start_x,start_vertex.y start_y,
        end_vertex.x end_x,end_vertex.y end_y,
        bounds.min_x,bounds.max_x,bounds.min_y,bounds.max_y,
        least(512,greatest(
          ceil(abs(end_vertex.x-start_vertex.x)*319/
            nullif(bounds.max_x-bounds.min_x,0)),
          ceil(abs(end_vertex.y-start_vertex.y)*167/
            nullif(bounds.max_y-bounds.min_y,0)),1)) step_count
      from session_state state
      cross join map_bounds bounds
      cross join doom_linedef line
      join doom_vertex start_vertex
        on start_vertex.vertex_id=line.start_vertex_id
      join doom_vertex end_vertex
        on end_vertex.vertex_id=line.end_vertex_id
      where state.game_mode='AUTOMAP'
        and (state.automap_state='FULL' or bitand(line.flags,128)=0)
    ),
    automap_line_candidates as (
      select segment.session_token,
        least(319,greatest(0,round((segment.start_x+
          (segment.end_x-segment.start_x)*step_axis.ordinal_no/segment.step_count-
          segment.min_x)*319/nullif(segment.max_x-segment.min_x,0)))) column_no,
        least(167,greatest(0,167-round((segment.start_y+
          (segment.end_y-segment.start_y)*step_axis.ordinal_no/segment.step_count-
          segment.min_y)*167/nullif(segment.max_y-segment.min_y,0)))) row_no,
        case when segment.flags is null then 176 else 176 end palette_index,
        65 layer_ordinal,'AUTOMAP_LINE' source_kind,
        to_char(segment.linedef_id,'FM9999999990',
          'NLS_NUMERIC_CHARACTERS=''.,''') source_id
      from automap_segments segment
      cross join ordinals_513 step_axis
      where step_axis.ordinal_no<=segment.step_count
    ),
    automap_background as (
      select canvas.session_token,canvas.column_no,canvas.row_no,
        0 palette_index,60 layer_ordinal,'AUTOMAP' source_kind,
        'BACKGROUND' source_id
      from canvas
      join session_state state on state.session_token=canvas.session_token
      where state.game_mode='AUTOMAP' and canvas.row_no<168
    ),
    automap_player_candidates as (
      select state.session_token,
        least(319,greatest(0,round((state.player_x-bounds.min_x)*319/
          nullif(bounds.max_x-bounds.min_x,0))))+marker.delta_x column_no,
        least(167,greatest(0,167-round((state.player_y-bounds.min_y)*167/
          nullif(bounds.max_y-bounds.min_y,0))))+marker.delta_y row_no,
        112 palette_index,66 layer_ordinal,'AUTOMAP_PLAYER' source_kind,
        to_char(state.player_id,'FM9999999990',
          'NLS_NUMERIC_CHARACTERS=''.,''') source_id
      from session_state state
      cross join map_bounds bounds
      cross apply (
        select -2 delta_x,0 delta_y from dual union all
        select -1,0 from dual union all select 0,0 from dual union all
        select 1,0 from dual union all select 2,0 from dual union all
        select 0,-2 from dual union all select 0,-1 from dual union all
        select 0,1 from dual union all select 0,2 from dual
      ) marker
      where state.game_mode='AUTOMAP'
    ),
    intermission_background as (
      select state.session_token,texel.x column_no,texel.y row_no,
        texel.c palette_index,60 layer_ordinal,
        'INTERMISSION_PATCH' source_kind,asset.asset_name source_id
      from session_state state
      join doom_asset asset
        on asset.asset_kind='ui_patch' and asset.asset_name='WIMAP0'
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.game_mode='INTERMISSION' and state.map_status='COMPLETE'
    ),
    intermission_patches as (
      select state.session_token,floor((320-asset.width)/2)+texel.x column_no,
        placement.top_row+texel.y row_no,texel.c palette_index,
        70 layer_ordinal,
        case when placement.asset_name='WIENTER' then 'INTERMISSION_PATCH'
             else 'TEXT' end source_kind,
        placement.asset_name source_id
      from session_state state
      cross apply (
        select 'WIENTER' asset_name,20 top_row from dual
        union all select 'WIOSTK',70 from dual
        union all select 'WIOSTS',95 from dual
        union all select 'WITIME',120 from dual
      ) placement
      join doom_asset asset
        on asset.asset_kind='ui_patch'
       and asset.asset_name=placement.asset_name
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where state.game_mode='INTERMISSION' and state.map_status='COMPLETE'
        and floor((320-asset.width)/2)+texel.x between 0 and 319
        and placement.top_row+texel.y between 0 and 199
    ),
    intermission_values as (
      select state.session_token,'KILLS' field_name,
        to_char(state.kill_count,'FM000',
          'NLS_NUMERIC_CHARACTERS=''.,''') field_value,250 right_edge,
        70 top_row from session_state state
      where state.game_mode='INTERMISSION' and state.map_status='COMPLETE'
      union all
      select state.session_token,'ITEMS',to_char(state.item_count,'FM000',
        'NLS_NUMERIC_CHARACTERS=''.,'''),
        250,95 from session_state state
      where state.game_mode='INTERMISSION' and state.map_status='COMPLETE'
      union all
      select state.session_token,'SECRETS',to_char(state.secret_count,'FM000',
        'NLS_NUMERIC_CHARACTERS=''.,'''),
        250,120 from session_state state
      where state.game_mode='INTERMISSION' and state.map_status='COMPLETE'
    ),
    intermission_characters as (
      select value_row.*,character_axis.character_ordinal,
        substr(value_row.field_value,character_axis.character_ordinal,1) glyph,
        length(value_row.field_value) character_count
      from intermission_values value_row
      cross join digit_positions character_axis
      where character_axis.character_ordinal<=length(value_row.field_value)
    ),
    intermission_text_candidates as (
      select chars.session_token,
        chars.right_edge-(chars.character_count-chars.character_ordinal+1)*15+
          texel.x column_no,
        chars.top_row+texel.y row_no,texel.c palette_index,
        71 layer_ordinal,'TEXT' source_kind,
        chars.field_name||':'||chars.character_ordinal source_id
      from intermission_characters chars
      join doom_asset asset
        on asset.asset_kind='ui_patch'
       and asset.asset_name='WINUM'||chars.glyph
      join at texel on texel.a=asset.asset_id and texel.c>=0
      where chars.right_edge-(chars.character_count-chars.character_ordinal+1)*15+
              texel.x between 0 and 319
        and chars.top_row+texel.y between 0 and 199
    ),
    candidates as (
      select canvas.session_token,canvas.column_no,canvas.row_no,
        0 palette_index,0 layer_ordinal,'CANVAS' source_kind,
        'BACKGROUND' source_id
      from canvas
      union all select * from world_candidates
      union all select * from weapon_candidates
      union all select * from hud_patch_candidates
      union all select * from hud_text_candidates
      union all select * from key_candidates
      union all select * from pause_candidates
      union all select * from menu_background
      union all select * from menu_patches
      union all select * from menu_selection
      union all select * from automap_background
      union all select * from automap_line_candidates
      union all select * from automap_player_candidates
      union all select * from intermission_background
      union all select * from intermission_patches
      union all select * from intermission_text_candidates
    ),
    ranked as (
      select candidates.*,
        row_number() over (
          partition by session_token,column_no,row_no
          order by layer_ordinal desc,source_kind,source_id,palette_index
        ) winner_ordinal
      from candidates
      where column_no between 0 and 319 and row_no between 0 and 199
        and palette_index between 0 and 255
    )
    select session_token,column_no,row_no,palette_index,layer_ordinal,
      source_kind,source_id
    from ranked
    where winner_ordinal=1
    order by column_no,row_no;
commit;
