whenever sqlerror exit failure rollback
set define off

declare
  l_exists number;
begin
  select count(*) into l_exists from user_tables
    where table_name='DOOM_HOSTED_ASSET';
  if l_exists=0 then
    execute immediate q'[
      create table doom_hosted_asset (
        asset_path varchar2(255 char) not null,
        content_type varchar2(128 char) not null,
        cache_control varchar2(128 char) not null,
        content_sha256 char(64 char) not null,
        content_length number(12) not null,
        payload blob not null,
        published_at timestamp with time zone
          default (localtimestamp at time zone 'UTC') not null,
        constraint doom_hosted_asset_pk primary key(asset_path),
        constraint doom_hosted_asset_path_ck check(
          regexp_like(asset_path,'^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$')),
        constraint doom_hosted_asset_mime_ck check(content_type in(
          'text/html; charset=utf-8',
          'text/javascript; charset=utf-8',
          'application/octet-stream',
          'text/css; charset=utf-8',
          'image/png','image/x-icon','image/svg+xml',
          'application/manifest+json','text/plain; charset=utf-8')),
        constraint doom_hosted_asset_cache_ck check(cache_control in(
          'no-cache, no-store, must-revalidate',
          'no-cache, must-revalidate',
          'public, max-age=31536000, immutable')),
        constraint doom_hosted_asset_sha_ck check(
          regexp_like(content_sha256,'^[0-9a-f]{64}$')),
        constraint doom_hosted_asset_length_ck check(content_length>0)
      ) lob(payload) store as securefile(
        cache reads compress medium deduplicate)
    ]';
  end if;
end;
/

declare
  l_columns number;
begin
  select count(*) into l_columns
    from user_tab_columns
    where table_name='DOOM_HOSTED_ASSET'
      and column_name in('ASSET_PATH','CONTENT_TYPE','CACHE_CONTROL',
        'CONTENT_SHA256','CONTENT_LENGTH','PAYLOAD','PUBLISHED_AT');
  if l_columns<>7 then
    raise_application_error(-20771,
      'DOOM_HOSTED_ASSET shape differs from the pinned hosted-static schema');
  end if;
end;
/

begin
  ords.define_module(
    p_module_name=>'doom.hosted.app',
    p_base_path=>'/app/',
    p_items_per_page=>0,
    p_status=>'PUBLISHED',
    p_comments=>'Anonymous DoomDB browser assets only');

  ords.define_template(
    p_module_name=>'doom.hosted.app',
    p_pattern=>'.',
    p_priority=>0,
    p_comments=>'DoomDB browser entry document');
  ords.define_handler(
    p_module_name=>'doom.hosted.app',
    p_pattern=>'.',
    p_method=>'GET',
    p_source_type=>ords.source_type_plsql,
    p_source=>q'[
declare
  l_payload blob;
  l_content_type doom_hosted_asset.content_type%type;
  l_cache_control doom_hosted_asset.cache_control%type;
  l_etag varchar2(66 char);
begin
  select payload,content_type,cache_control,'"'||content_sha256||'"'
    into l_payload,l_content_type,l_cache_control,l_etag
    from doom_hosted_asset where asset_path='index.html';
  :cache_control_header:=l_cache_control;
  if trim(:if_none_match) in(l_etag,'*') then
    owa_util.status_line(304,'Not Modified',false);
    htp.p('ETag: '||l_etag);
    owa_util.http_header_close;
    return;
  end if;
  owa_util.mime_header(l_content_type,false);
  htp.p('ETag: '||l_etag);
  owa_util.http_header_close;
  wpg_docload.download_file(l_payload);
exception
  when no_data_found then
    owa_util.status_line(404,'Not Found',false);
    owa_util.mime_header('text/plain; charset=utf-8',false);
    htp.p('Cache-Control: no-store');
    owa_util.http_header_close;
    htp.prn('Not Found');
end;]',
    p_items_per_page=>0,
    p_comments=>'Database-resident browser entry document');
  ords.define_parameter(
    p_module_name=>'doom.hosted.app',
    p_pattern=>'.',
    p_method=>'GET',
    p_name=>'If-None-Match',
    p_bind_variable_name=>'if_none_match',
    p_source_type=>'HEADER',
    p_param_type=>'STRING',
    p_access_method=>'IN',
    p_comments=>'Strong content-addressed conditional request');
  ords.define_parameter(
    p_module_name=>'doom.hosted.app',
    p_pattern=>'.',
    p_method=>'GET',
    p_name=>'Cache-Control',
    p_bind_variable_name=>'cache_control_header',
    p_source_type=>'HEADER',
    p_param_type=>'STRING',
    p_access_method=>'OUT',
    p_comments=>'Stored entry-document cache policy');

  ords.define_template(
    p_module_name=>'doom.hosted.app',
    p_pattern=>':asset',
    p_priority=>0,
    p_comments=>'Allowlisted DoomDB browser artifact');
  ords.define_handler(
    p_module_name=>'doom.hosted.app',
    p_pattern=>':asset',
    p_method=>'GET',
    p_source_type=>ords.source_type_plsql,
    p_source=>q'[
declare
  l_payload blob;
  l_content_type doom_hosted_asset.content_type%type;
  l_cache_control doom_hosted_asset.cache_control%type;
  l_etag varchar2(66 char);
begin
  select payload,content_type,cache_control,'"'||content_sha256||'"'
    into l_payload,l_content_type,l_cache_control,l_etag
    from doom_hosted_asset where asset_path=:asset;
  :cache_control_header:=l_cache_control;
  if trim(:if_none_match) in(l_etag,'*') then
    owa_util.status_line(304,'Not Modified',false);
    htp.p('ETag: '||l_etag);
    owa_util.http_header_close;
    return;
  end if;
  owa_util.mime_header(l_content_type,false);
  htp.p('ETag: '||l_etag);
  owa_util.http_header_close;
  wpg_docload.download_file(l_payload);
exception
  when no_data_found then
    owa_util.status_line(404,'Not Found',false);
    owa_util.mime_header('text/plain; charset=utf-8',false);
    htp.p('Cache-Control: no-store');
    owa_util.http_header_close;
    htp.prn('Not Found');
end;]',
    p_items_per_page=>0,
    p_comments=>'Database-resident allowlisted browser artifact');
  ords.define_parameter(
    p_module_name=>'doom.hosted.app',
    p_pattern=>':asset',
    p_method=>'GET',
    p_name=>'asset',
    p_bind_variable_name=>'asset',
    p_source_type=>'URI',
    p_param_type=>'STRING',
    p_access_method=>'IN',
    p_comments=>'Exact flat allowlisted asset name');
  ords.define_parameter(
    p_module_name=>'doom.hosted.app',
    p_pattern=>':asset',
    p_method=>'GET',
    p_name=>'If-None-Match',
    p_bind_variable_name=>'if_none_match',
    p_source_type=>'HEADER',
    p_param_type=>'STRING',
    p_access_method=>'IN',
    p_comments=>'Strong content-addressed conditional request');
  ords.define_parameter(
    p_module_name=>'doom.hosted.app',
    p_pattern=>':asset',
    p_method=>'GET',
    p_name=>'Cache-Control',
    p_bind_variable_name=>'cache_control_header',
    p_source_type=>'HEADER',
    p_param_type=>'STRING',
    p_access_method=>'OUT',
    p_comments=>'Stored asset cache policy');
  commit;
end;
/

select 'T112_HOSTED_STATIC_INSTALL|PASS|module=doom.hosted.app|base=/app/'
  as result
from dual;
