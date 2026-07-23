whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- Production cutover fence. The preserved OJVM differential oracle belongs to
-- repository/dev tooling only; no Java call spec or Java schema object may
-- survive in the deployed application schema.
declare
  function quoted(p_name varchar2) return varchar2 is
  begin
    return '"'||replace(p_name,'"','""')||'"';
  end;
begin
  for call_spec_ in (
    select object_name,object_type
    from user_objects object_
    where object_type in('FUNCTION','PROCEDURE')
      and exists (
        select 1 from user_source source_
        where source_.name=object_.object_name
          and source_.type=object_.object_type
          and regexp_like(source_.text,'LANGUAGE[[:space:]]+JAVA','i'))
    order by object_type,object_name
  ) loop
    execute immediate 'drop '||lower(call_spec_.object_type)||' '||
      quoted(call_spec_.object_name);
  end loop;

  for java_object_ in (
    select object_name,object_type
    from user_objects
    where object_type in('JAVA SOURCE','JAVA CLASS','JAVA RESOURCE')
    order by case object_type
      when 'JAVA CLASS' then 1 when 'JAVA RESOURCE' then 2 else 3 end,
      object_name
  ) loop
    execute immediate 'drop java '||
      case java_object_.object_type
        when 'JAVA SOURCE' then 'source '
        when 'JAVA CLASS' then 'class '
        else 'resource '
      end||quoted(java_object_.object_name);
  end loop;
end;
/

declare
  l_java_objects number;
  l_java_call_specs number;
begin
  select count(*) into l_java_objects from user_objects
    where object_type like 'JAVA%';
  select count(*) into l_java_call_specs
  from user_objects object_
  where object_type in('FUNCTION','PROCEDURE')
    and exists (
      select 1 from user_source source_
      where source_.name=object_.object_name
        and source_.type=object_.object_type
        and regexp_like(source_.text,'LANGUAGE[[:space:]]+JAVA','i'));
  if l_java_objects<>0 or l_java_call_specs<>0 then
    raise_application_error(-20796,
      'production OJVM purge failed: java_objects='||l_java_objects||
      ' java_call_specs='||l_java_call_specs);
  end if;
end;
/
