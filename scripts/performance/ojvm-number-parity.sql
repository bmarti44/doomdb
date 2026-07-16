whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  failures_ pls_integer:=0;
  cases_ pls_integer:=0;
  java_x number;java_y number;sql_x number;sql_y number;
  java_root number;sql_root number;
  function same_number(p_left number,p_right number) return boolean is
    same_ number;
  begin
    select case when dump(p_left,16)=dump(p_right,16) then 1 else 0 end
      into same_ from dual;
    return same_=1;
  end;
begin
  for angle_index_ in 0..63 loop
    for forward_ in -1..1 loop
      for strafe_ in -1..1 loop
        for run_ in 0..1 loop
          declare angle_ number:=angle_index_*5.625;begin
            sql_x:=(forward_*cos(angle_*acos(-1)/180)+
                    strafe_*sin(angle_*acos(-1)/180))*8*(run_+1);
            sql_y:=(forward_*sin(angle_*acos(-1)/180)-
                    strafe_*cos(angle_*acos(-1)/180))*8*(run_+1);
            java_x:=doom_number_delta_x(angle_,forward_,strafe_,run_);
            java_y:=doom_number_delta_y(angle_,forward_,strafe_,run_);
            cases_:=cases_+1;
            if java_x is null or java_y is null or
               not same_number(java_x,sql_x) or not same_number(java_y,sql_y) then
              failures_:=failures_+1;
              if failures_<=10 then
                dbms_output.put_line('movement mismatch angle='||angle_||' f='||forward_||
                  ' s='||strafe_||' r='||run_||' java=('||java_x||','||java_y||
                  ') sql=('||sql_x||','||sql_y||') error='||doom_number_last_error);
              end if;
            end if;
          end;
        end loop;
      end loop;
    end loop;
  end loop;

  -- Representative exact endpoint-cap root from the SQL collision expression.
  select (-qb-sqrt(greatest(0,disc)))/(2*qa)
    into sql_root
    from (select qa,qb,qb*qb-4*qa*((-416-(-400))*(-416-(-400))+
      (256-240)*(256-240)-16*16) disc
      from (select 8*8+4*4 qa,2*((-416-(-400))*8+(256-240)*4) qb from dual));
  java_root:=doom_number_quadratic_entry(-416,256,-400,240,8,4,16);
  if not same_number(java_root,sql_root) then
    failures_:=failures_+1;
    dbms_output.put_line('quadratic mismatch java='||java_root||' sql='||sql_root);
  end if;

  if failures_<>0 then
    raise_application_error(-20000,'oracle NUMBER parity failures='||failures_||'/'||cases_);
  end if;
  dbms_output.put_line('oracle_number_movement_parity='||cases_||'/'||cases_);
  dbms_output.put_line('oracle_number_quadratic_parity=1/1');
  dbms_output.put_line('oracle_number_lookup_add_benchmark='||
    doom_number_lookup_benchmark(100000));
  dbms_output.put_line('oracle_number_quadratic_benchmark='||
    doom_number_quadratic_benchmark(1000));
end;
/
