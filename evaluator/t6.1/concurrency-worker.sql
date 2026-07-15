set serveroutput on
declare p blob;h raw(32);begin doom_tic_tx.apply_batch('62626262626262626262626262626262','{"v":1,"commands":[{"seq":1,"turn":0,"forward":1,"strafe":0,"run":0,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":""}]}',p);h:=dbms_crypto.hash(p,dbms_crypto.hash_sh256);commit;dbms_output.put_line('T61_RESULT '||lower(rawtohex(h)));end;
/
