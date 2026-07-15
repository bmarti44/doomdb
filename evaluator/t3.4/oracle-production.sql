whenever sqlerror exit failure rollback
set define off verify off feedback off heading off pagesize 0 serveroutput on
alter session set nls_numeric_characters='.,' nls_territory='AMERICA' nls_language='AMERICAN' time_zone='UTC';

declare
  l_n number; l_n2 number; l_n3 number; l_text clob;
  type seen_sector_t is table of boolean index by pls_integer;
  l_seen_sector seen_sector_t;
  l_sector_queue sys.odcinumberlist := sys.odcinumberlist(140);
  l_queue_head pls_integer := 1;
  l_current_sector number;
  procedure assert_eq(p_actual number,p_expected number,p_label varchar2) is
  begin if p_actual is null or p_actual!=p_expected then raise_application_error(-20844,p_label||': expected '||p_expected||', got '||nvl(to_char(p_actual),'NULL')); end if; end;
  procedure assert_text(p_actual varchar2,p_expected varchar2,p_label varchar2) is
  begin if p_actual is null or p_actual!=p_expected then raise_application_error(-20845,p_label||': expected '||p_expected||', got '||nvl(p_actual,'NULL')); end if; end;
  procedure append_row(p_row varchar2) is begin dbms_lob.writeappend(l_text,length(p_row),p_row); end;
  function clob_sha return varchar2 is begin return lower(rawtohex(dbms_crypto.hash(l_text,dbms_crypto.hash_sh256))); end;
  procedure reject_probe(p_source number,p_target number,p_expected number) is l_value number;
  begin select rejected into l_value from doom_sector_reject where source_sector_id=p_source and target_sector_id=p_target; assert_eq(l_value,p_expected,'reject '||p_source||','||p_target); end;
begin
  select count(*) into l_n from doom_block_cell; assert_eq(l_n,864,'block cells');
  select count(*) into l_n from doom_block_line; assert_eq(l_n,2064,'block memberships');
  select count(distinct list_word_offset),min(list_word_offset),max(list_word_offset) into l_n,l_n2,l_n3 from doom_block_cell;
  assert_eq(l_n,450,'unique block lists'); assert_eq(l_n2,868,'minimum list offset'); assert_eq(l_n3,3761,'maximum list offset');
  select count(*) into l_n from doom_block_cell where world_min_x=-712+block_x*128 and world_min_y=-1072+block_y*128; assert_eq(l_n,864,'block world minima');
  select count(*) into l_n from doom_block_cell c join doom_block_line m on m.cell_id=c.cell_id join doom_map_linedef l on l.linedef_id=m.linedef_id; assert_eq(l_n,2064,'valid membership references');
  select count(*) into l_n from (select cell_id,count(*) n,max(line_ordinal) mx from doom_block_line group by cell_id) where n!=mx+1; assert_eq(l_n,0,'dense membership ordinals');
  select count(*) into l_n from doom_block_cell where (block_x=10 and block_y=10 and list_word_offset=1880) or (block_x=20 and block_y=15 and list_word_offset=2534); assert_eq(l_n,2,'known block cells');
  select count(*) into l_n from doom_block_line m join doom_block_cell c on c.cell_id=m.cell_id where (c.block_x=10 and c.block_y=10 and ((m.line_ordinal=0 and m.linedef_id=553) or (m.line_ordinal=1 and m.linedef_id=1159))) or (c.block_x=20 and c.block_y=15 and ((m.line_ordinal=0 and m.linedef_id=251) or (m.line_ordinal=1 and m.linedef_id=252))); assert_eq(l_n,4,'known block lists');
  dbms_lob.createtemporary(l_text,true);
  for r in (select c.block_x,c.block_y,m.line_ordinal,m.linedef_id from doom_block_cell c join doom_block_line m on m.cell_id=c.cell_id order by c.cell_id,m.line_ordinal) loop append_row(to_char(r.block_x,'FM9990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||to_char(r.block_y,'FM9990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||to_char(r.line_ordinal,'FM9990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||to_char(r.linedef_id,'FM9990','NLS_NUMERIC_CHARACTERS=''.,''')||chr(10)); end loop;
  assert_eq(dbms_lob.getlength(l_text),23691,'block document bytes'); assert_text(clob_sha,'5f24718d6471411d84e29a4386ca4bc2d9a953062c7542669ce133e7813622de','block document hash'); dbms_lob.freetemporary(l_text);

  select count(*),sum(rejected) into l_n,l_n2 from doom_sector_reject; assert_eq(l_n,33124,'reject pair rows'); assert_eq(l_n2,23490,'reject set bits');
  select count(*) into l_n from doom_sector_reject where byte_offset=floor((source_sector_id*182+target_sector_id)/8) and bit_offset=mod(source_sector_id*182+target_sector_id,8) and rejected in (0,1); assert_eq(l_n,33124,'reject addressing');
  reject_probe(0,0,0); reject_probe(0,1,0); reject_probe(1,0,0); reject_probe(140,140,0); reject_probe(140,0,1); reject_probe(0,140,1); reject_probe(181,181,0); reject_probe(42,117,1); reject_probe(117,42,1);
  dbms_lob.createtemporary(l_text,true);
  for r in (select source_sector_id,target_sector_id,rejected from doom_sector_reject order by source_sector_id,target_sector_id) loop append_row(to_char(r.source_sector_id,'FM9990')||':'||to_char(r.target_sector_id,'FM9990')||':'||to_char(r.rejected,'FM0')||chr(10)); end loop;
  assert_eq(dbms_lob.getlength(l_text),291200,'reject document bytes'); assert_text(clob_sha,'10e7c2bcc1a2e71c210b959e024f5780e49433a5f45cc055fd32a4165c2b60bf','reject document hash'); dbms_lob.freetemporary(l_text);

  select count(*) into l_n from doom_sector_edge; assert_eq(l_n,1166,'directed graph edges');
  select count(*) into l_n from doom_sector_edge a left join doom_sector_edge b on b.edge_id=case when mod(a.edge_id,2)=0 then a.edge_id+1 else a.edge_id-1 end and b.source_sector_id=a.target_sector_id and b.target_sector_id=a.source_sector_id and b.linedef_id=a.linedef_id and b.sound_block=a.sound_block and b.opening=a.opening where b.edge_id is null; assert_eq(l_n,0,'inverse edge symmetry');
  select count(*) into l_n from doom_sector_edge where sound_block=1; assert_eq(l_n,0,'pinned sound-block edges');
  select min(opening),max(opening) into l_n,l_n2 from doom_sector_edge; assert_eq(l_n,8,'minimum opening'); assert_eq(l_n2,696,'maximum opening');
  dbms_lob.createtemporary(l_text,true);
  for r in (select edge_id,source_sector_id,target_sector_id,linedef_id,sound_block from doom_sector_edge order by edge_id) loop append_row(to_char(r.edge_id,'FM9990')||':'||to_char(r.source_sector_id,'FM9990')||':'||to_char(r.target_sector_id,'FM9990')||':'||to_char(r.linedef_id,'FM9990')||':'||to_char(r.sound_block,'FM0')||chr(10)); end loop;
  assert_eq(dbms_lob.getlength(l_text),20384,'graph document bytes'); assert_text(clob_sha,'66aad841726f62b0df10105e49f6ce91abbd0a2025edd1804dade401503fd4e4','graph document hash'); dbms_lob.freetemporary(l_text);

  select count(*) into l_n from user_property_graphs where graph_name='DOOM_SECTOR_GRAPH'; assert_eq(l_n,1,'property graph catalog object');
  select count(*) into l_n from graph_table(doom_sector_graph match (s is sector)-[e is passable]->(t is sector) columns (e.edge_id as edge_id)); assert_eq(l_n,1166,'GRAPH_TABLE edge scan');
  l_seen_sector(140) := true;
  while l_queue_head <= l_sector_queue.count loop
    l_current_sector := l_sector_queue(l_queue_head);
    for r in (
      select distinct source_sector_id, target_sector_id
        from graph_table(
          doom_sector_graph
          match (s is sector)-[e is passable]->(t is sector)
          columns (
            s.sector_id as source_sector_id,
            t.sector_id as target_sector_id
          )
        )
    ) loop
      if r.source_sector_id = l_current_sector
         and not l_seen_sector.exists(r.target_sector_id) then
        l_seen_sector(r.target_sector_id) := true;
        l_sector_queue.extend;
        l_sector_queue(l_sector_queue.count) := r.target_sector_id;
      end if;
    end loop;
    l_queue_head := l_queue_head + 1;
  end loop;
  l_n := l_sector_queue.count;
  assert_eq(l_n,38,'spawn component reachability');
  select count(*) into l_n from doom_map_sector s where not exists (select 1 from doom_sector_edge e where e.source_sector_id=s.sector_id); assert_eq(l_n,25,'isolated sectors');
  dbms_output.put_line('PASS T3.4-ORACLE-PRODUCTION');
end;
/
