create table doom_engine_artifact (
  artifact_name varchar2(64) not null,
  engine_revision varchar2(64) not null,
  media_type varchar2(100) not null,
  payload_sha256 varchar2(64) not null,
  payload_bytes blob not null,
  created_at timestamp with time zone default systimestamp not null,
  constraint doom_engine_artifact_pk primary key (artifact_name),
  constraint doom_engine_artifact_name_ck check (
    regexp_like(artifact_name, '^[a-z0-9][a-z0-9._-]{0,63}$')),
  constraint doom_engine_artifact_revision_ck check (
    regexp_like(engine_revision, '^[0-9a-f]{40}$')),
  constraint doom_engine_artifact_sha_ck check (
    regexp_like(payload_sha256, '^[0-9a-f]{64}$'))
)
lob (payload_bytes) store as securefile (
  cache logging retention none
);
