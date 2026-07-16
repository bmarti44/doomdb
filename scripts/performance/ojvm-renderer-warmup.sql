whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off timing off

declare
  payload blob;
  batch_started number;
begin
  dbms_lob.createtemporary(payload, true);
  for batch_index in 1 .. 10 loop
    batch_started := dbms_utility.get_time;
    for frame_index in 1 .. 50 loop
      doom_bsp_kernel_fill(payload);
    end loop;
    dbms_output.put_line(
      'WARM frames=' || batch_index * 50 ||
      ' batch_ms=' ||
      to_char((dbms_utility.get_time - batch_started) * 10, 'FM9999990.000')
    );
  end loop;
  dbms_lob.freetemporary(payload);
end;
/

declare
  missing_methods number;
begin
  select count(*)
  into missing_methods
  from user_java_methods
  where name = 'DoomBspKernelBench'
    and method_name in (
      'traverseAndProject', 'projectSeg', 'applySolidCoverage',
      'applyPortalWalk', 'drawActiveWall', 'drawWallPiece', 'drawPlanes',
      'drawMaskedWall', 'drawSprites', 'projectSprite', 'rasterSprite',
      'composeTicZeroPresentation', 'prepareFrameSha',
      'buildPackedTicZeroJson', 'compressJson', 'renderTicZero'
    )
    and is_compiled <> 'YES';
  if missing_methods <> 0 then
    raise_application_error(-20000,
      missing_methods || ' hot OJVM renderer methods are not compiled');
  end if;
end;
/

select 'OJVM methods=' || count(*) ||
  ' compiled=' || sum(case when is_compiled = 'YES' then 1 else 0 end)
from user_java_methods
where name = 'DoomBspKernelBench';

exit
