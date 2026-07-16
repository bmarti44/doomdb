whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback

merge into doom_renderer_asset_pack d
using (select 'simulation_kernel' asset_kind from dual) s
on (d.asset_kind=s.asset_kind)
when not matched then insert(asset_kind,format_version,element_count,payload_sha256,encoded_bytes)
values(s.asset_kind,1,1,rpad('0',64,'0'),empty_blob());

commit;
