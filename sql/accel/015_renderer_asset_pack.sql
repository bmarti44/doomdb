whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

declare
  l_blob blob;
  l_hex varchar2(32764);
  l_count number;

  procedure flush_buffer is
    l_raw raw(16382);
  begin
    if l_hex is null then return; end if;
    l_raw:=hextoraw(l_hex);
    dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);
    l_hex:=null;
  end;

  procedure build_pack(p_kind varchar2,p_expected number) is
  begin
    dbms_lob.createtemporary(l_blob,true,dbms_lob.call);
    l_hex:=null;l_count:=0;
    for texel in (
      select /*+ leading(a) use_nl(t) index(t at_xy_ix) */ t.c
      from doom_asset a join at t on t.a=a.asset_id
      where a.asset_kind=p_kind
      order by a.asset_id,t.y,t.x
    ) loop
      l_hex:=l_hex||to_char(texel.c+1,'FM0XXX');
      l_count:=l_count+1;
      if length(l_hex)>=32760 then flush_buffer; end if;
    end loop;
    flush_buffer;
    if l_count<>p_expected or dbms_lob.getlength(l_blob)<>p_expected*2 then
      raise_application_error(-20000,p_kind||' renderer pack size mismatch');
    end if;
    insert into doom_renderer_asset_pack(asset_kind,format_version,
      element_count,payload_sha256,encoded_bytes)
    values(p_kind,1,l_count,
      lower(rawtohex(dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256))),l_blob);
    dbms_lob.freetemporary(l_blob);
  end;
begin
  delete from doom_renderer_asset_pack;
  build_pack('wall_texture',1256192);
  build_pack('flat',200704);
  build_pack('sprite_patch',331474);
  build_pack('ui_patch',173170);
end;
/

commit;

select asset_kind,format_version,element_count,dbms_lob.getlength(encoded_bytes) bytes
from doom_renderer_asset_pack order by asset_kind;
