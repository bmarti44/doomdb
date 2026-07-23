whenever sqlerror exit failure rollback
set define off serveroutput on size unlimited feedback off
declare
  l_payload raw(32767);
  l_chain varchar2(64);
begin
  l_payload := doom_mle_authority_delta.encode(
    p_tic => 1,
    p_generation => 1,
    p_membership_epoch => 7,
    p_membership_bitmap => hextoraw('03'),
    p_active_players => 2,
    p_previous_chain_sha => rpad('0', 64, '0'),
    p_canonical_state_sha =>
      '0031f7e97d3335e0cb2892acd0574e7e0ccb60278d0640c39a8d7ee394d7bc66',
    p_command_vector => hextoraw(rpad('11', 64, '11')),
    p_audio_json => '[[1,0,"DSPISTOL",127,128]]');
  if utl_raw.cast_to_varchar2(utl_raw.substr(l_payload, 1, 4)) != 'DMD1' or
     utl_raw.length(l_payload) != 176 then
    raise_application_error(-20797, 'DMD1 encoded envelope mismatch');
  end if;
  l_chain := lower(rawtohex(utl_raw.substr(l_payload, 53, 32)));
  if l_chain != lower(rawtohex(dbms_crypto.hash(
      utl_raw.concat(utl_raw.substr(l_payload, 1, 52),
        utl_raw.substr(l_payload, 85)), dbms_crypto.hash_sh256))) then
    raise_application_error(-20797, 'DMD1 encoded chain mismatch');
  end if;
  dbms_output.put_line('PASS DMD1 SQL encoder bytes=' ||
    utl_raw.length(l_payload) || ' chain_sha=' || l_chain);
end;
/
