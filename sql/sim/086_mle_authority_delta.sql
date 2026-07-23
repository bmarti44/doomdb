whenever sqlerror exit failure rollback
set define off

create or replace package doom_mle_authority_delta authid definer as
  function encode(
    p_tic in number,
    p_generation in number,
    p_membership_epoch in number,
    p_membership_bitmap in raw,
    p_active_players in number,
    p_previous_chain_sha in varchar2,
    p_canonical_state_sha in varchar2,
    p_command_vector in raw,
    p_audio_json in varchar2 default '[]',
    p_complete in number default 0
  ) return raw deterministic;
end doom_mle_authority_delta;
/

create or replace package body doom_mle_authority_delta as
  c_error constant pls_integer := -20796;

  function u32(p_value number) return raw deterministic is
  begin
    if p_value is null or p_value < 0 or p_value > 2147483647 or
       p_value != trunc(p_value) then
      raise_application_error(c_error, 'DMD1 uint32 value');
    end if;
    return utl_raw.cast_from_binary_integer(p_value, utl_raw.big_endian);
  end;

  function u16(p_value number) return raw deterministic is
  begin
    if p_value is null or p_value < 0 or p_value > 65535 or
       p_value != trunc(p_value) then
      raise_application_error(c_error, 'DMD1 uint16 value');
    end if;
    return utl_raw.substr(u32(p_value), 3, 2);
  end;

  function sha_bytes(p_value varchar2, p_name varchar2) return raw deterministic is
  begin
    if p_value is null or not regexp_like(p_value, '^[0-9a-f]{64}$') then
      raise_application_error(c_error, 'DMD1 ' || p_name || ' SHA-256');
    end if;
    return hextoraw(p_value);
  end;

  function encode(
    p_tic in number,
    p_generation in number,
    p_membership_epoch in number,
    p_membership_bitmap in raw,
    p_active_players in number,
    p_previous_chain_sha in varchar2,
    p_canonical_state_sha in varchar2,
    p_command_vector in raw,
    p_audio_json in varchar2 default '[]',
    p_complete in number default 0
  ) return raw deterministic is
    l_flags pls_integer := 0;
    l_prefix raw(52);
    l_tail raw(32767);
    l_audio raw(32000);
    l_canonical raw(32) := hextoraw(rpad('00', 64, '0'));
    l_chain raw(32);
  begin
    if p_tic < 1 or p_generation < 1 or p_membership_epoch < 1 then
      raise_application_error(c_error, 'DMD1 frontier');
    end if;
    if p_membership_bitmap is null or utl_raw.length(p_membership_bitmap) != 1 or
       to_number(rawtohex(p_membership_bitmap), 'xx') not between 1 and 15 then
      raise_application_error(c_error, 'DMD1 membership bitmap');
    end if;
    if p_active_players not between 2 and 4 or p_active_players != trunc(p_active_players) then
      raise_application_error(c_error, 'DMD1 active players');
    end if;
    if p_complete not in (0, 1) then
      raise_application_error(c_error, 'DMD1 complete flag');
    end if;
    if p_command_vector is null or utl_raw.length(p_command_vector) != 32 then
      raise_application_error(c_error, 'DMD1 command vector');
    end if;
    l_audio := utl_i18n.string_to_raw(nvl(p_audio_json, '[]'), 'AL32UTF8');
    if utl_raw.length(l_audio) > 32000 then
      raise_application_error(c_error, 'DMD1 audio length');
    end if;
    if p_canonical_state_sha is not null then
      l_flags := l_flags + 1;
      l_canonical := sha_bytes(p_canonical_state_sha, 'canonical state');
    end if;
    if p_complete = 1 then l_flags := l_flags + 2; end if;
    l_prefix := utl_raw.concat(
      utl_raw.cast_to_raw('DMD1'), u32(p_tic), u32(p_generation),
      u32(p_membership_epoch), p_membership_bitmap,
      hextoraw(to_char(p_active_players, 'fm0x')), u16(l_flags),
      sha_bytes(p_previous_chain_sha, 'previous chain'));
    l_tail := utl_raw.concat(l_canonical, p_command_vector,
      u16(utl_raw.length(l_audio)), l_audio);
    l_chain := dbms_crypto.hash(
      utl_raw.concat(l_prefix, l_tail), dbms_crypto.hash_sh256);
    return utl_raw.concat(l_prefix, l_chain, l_tail);
  end;
end doom_mle_authority_delta;
/
