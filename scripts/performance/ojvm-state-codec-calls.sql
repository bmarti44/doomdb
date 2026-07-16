whenever sqlerror exit failure rollback

create or replace function doom_state_codec_fill(
  p_session varchar2,
  p_legacy number,
  p_payload blob
) return varchar2 as
language java name
  'DoomStateCodecBench.writeState(java.lang.String,int,java.sql.Blob) return java.lang.String';
/

create or replace function doom_state_codec_total_ns return number as
language java name 'DoomStateCodecBench.lastTotalNanos() return long';
/

create or replace function doom_state_codec_query_ns return number as
language java name 'DoomStateCodecBench.lastQueryNanos() return long';
/

create or replace function doom_state_codec_encode_ns return number as
language java name 'DoomStateCodecBench.lastEncodeNanos() return long';
/

create or replace function doom_state_codec_blob_ns return number as
language java name 'DoomStateCodecBench.lastBlobNanos() return long';
/
