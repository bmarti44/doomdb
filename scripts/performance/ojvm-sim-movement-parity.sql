whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);payload_ blob;sql_payload clob;java_payload varchar2(4000);
  x_ number;y_ number;z_ number;dx_ number;dy_ number;
  angle_index_ pls_integer;forward_ pls_integer:=1;strafe_ pls_integer:=0;run_ pls_integer;
  failures_ pls_integer:=0;contacts_ pls_integer:=0;
  load_result_ varchar2(4000);
  function same_number(p_left number,p_right number) return boolean is same_ number;begin
    if p_left is null or p_right is null then return p_left is null and p_right is null;end if;
    select case when dump(p_left,16)=dump(p_right,16) then 1 else 0 end into same_ from dual;
    return same_=1;
  end;
  function same_integer(p_left number,p_right number) return boolean is begin
    return (p_left=p_right) or (p_left is null and p_right is null);
  end;
begin
  load_result_:=doom_sim_catalog_load;
  if substr(load_result_,1,3)<>'OK|' then raise_application_error(-20000,load_result_);end if;
  doom_api.new_game(3,session_,payload_);
  select x,y,z into x_,y_,z_ from players p join game_sessions g
    on g.session_token=p.session_token and g.current_player_id=p.player_id
    where g.session_token=session_;

  for sample_ in 1..270 loop
    angle_index_:=case when sample_<=64 then 0 when sample_<=128 then 16
      when sample_<=192 then 32 when sample_<=256 then 48 else mod(sample_*11,64) end;
    run_:=case when mod(sample_,5)=0 then 1 else 0 end;
    dx_:=(forward_*cos((angle_index_*5.625)*acos(-1)/180)+
          strafe_*sin((angle_index_*5.625)*acos(-1)/180))*8*(run_+1);
    dy_:=(forward_*sin((angle_index_*5.625)*acos(-1)/180)-
          strafe_*cos((angle_index_*5.625)*acos(-1)/180))*8*(run_+1);
    sql_payload:=doom_player_move_payload(session_,dx_,dy_);
    java_payload:=doom_sim_move_payload(x_,y_,z_,angle_index_,forward_,strafe_,run_);
    if json_value(java_payload,'$.error') is not null then
      raise_application_error(-20000,'java movement error '||doom_sim_move_last_error);
    end if;
    if not same_number(json_value(java_payload,'$.dest_x' returning number),
                       json_value(sql_payload,'$.dest_x' returning number)) or
       not same_number(json_value(java_payload,'$.dest_y' returning number),
                       json_value(sql_payload,'$.dest_y' returning number)) or
       not same_number(json_value(java_payload,'$.dest_z' returning number),
                       json_value(sql_payload,'$.dest_z' returning number)) or
       not same_integer(json_value(java_payload,'$.destination_sector_id' returning number),
                        json_value(sql_payload,'$.destination_sector_id' returning number)) or
       not same_integer(json_value(java_payload,'$.contact_count' returning number),
                        json_value(sql_payload,'$.contact_count' returning number)) or
       not same_integer(json_value(java_payload,'$.first_blocker_id' returning number),
                        json_value(sql_payload,'$.first_blocker_id' returning number)) or
       not same_number(json_value(java_payload,'$.first_fraction' returning number),
                       json_value(sql_payload,'$.first_fraction' returning number)) or
       not same_integer(json_value(java_payload,'$.second_blocker_id' returning number),
                        json_value(sql_payload,'$.second_blocker_id' returning number)) or
       not same_number(json_value(java_payload,'$.second_fraction' returning number),
                       json_value(sql_payload,'$.second_fraction' returning number)) then
      failures_:=failures_+1;
      if failures_<=10 then
        dbms_output.put_line('movement mismatch sample='||sample_||' angle='||angle_index_);
        dbms_output.put_line('sql='||dbms_lob.substr(sql_payload,4000,1));
        dbms_output.put_line('java='||java_payload);
      end if;
    end if;
    contacts_:=contacts_+case when json_value(sql_payload,'$.contact_count' returning number)>0
      then 1 else 0 end;
    x_:=json_value(sql_payload,'$.dest_x' returning number);
    y_:=json_value(sql_payload,'$.dest_y' returning number);
    z_:=json_value(sql_payload,'$.dest_z' returning number);
    update players set x=x_,y=y_,z=z_ where session_token=session_ and player_id=(
      select current_player_id from game_sessions where session_token=session_);
  end loop;
  if failures_<>0 then
    raise_application_error(-20000,'movement parity failures='||failures_||'/270 contacts='||contacts_);
  end if;
  dbms_output.put_line('sim_movement_parity=270/270');
  dbms_output.put_line('sim_movement_contact_samples='||contacts_);
  dbms_output.put_line('sim_movement_benchmark_ns='||doom_sim_move_benchmark(300));
  rollback;
end;
/
