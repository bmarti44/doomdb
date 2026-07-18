whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off heading off

declare
  type names_t is table of varchar2(128) index by pls_integer;
  names names_t;
  compiled number;
  missing number:=0;
begin
  names(1):='rr/RendererState';
  names(2):='rr/RendererState$BSP';
  names(3):='rr/RendererState$SegDrawer';
  names(4):='rr/RendererState$Planes';
  names(5):='rr/UnifiedRenderer';
  names(6):='rr/UnifiedRenderer$Indexed';
  names(7):='rr/UnifiedRenderer$Segs';
  names(8):='rr/PlaneDrawer';
  names(9):='rr/AbstractThings';
  names(10):='rr/SimpleThings';
  names(11):='rr/SimpleTextureManager';
  names(12):='rr/Visplanes';
  names(13):='rr/VisSprites';
  names(14):='rr/SpriteManager';
  names(15):='rr/drawfuns/DoomColumnFunction';
  names(16):='rr/drawfuns/R_DrawColumnBoomOpt$Indexed';
  names(17):='rr/drawfuns/R_DrawColumnBoom$Indexed';
  names(18):='rr/drawfuns/R_DrawSpan$Indexed';
  names(19):='rr/drawseg_t';
  names(20):='rr/visplane_t';
  names(21):='rr/vissprite_t';
  names(22):='rr/column_t';
  names(23):='rr/SegVars';
  names(24):='rr/ViewVars';
  names(25):='rr/node_t';
  names(26):='rr/line_t';
  names(27):='rr/cliprange_t';
  names(28):='rr/drawfuns/ColVars';
  names(29):='rr/drawfuns/DoomSpanFunction';
  names(30):='rr/drawfuns/R_DrawFuzzColumn$Indexed';
  names(31):='rr/drawfuns/R_DrawFuzzColumnLow$Indexed';
  names(32):='rr/drawfuns/R_DrawTranslatedColumn$Indexed';
  names(33):='rr/drawfuns/R_DrawTranslatedColumnLow$Indexed';
  names(34):='rr/drawfuns/R_DrawColumnBoomLow$Indexed';
  names(35):='rr/drawfuns/R_DrawColumnBoomOptLow$Indexed';
  names(36):='rr/drawfuns/R_DrawSpanLow$Indexed';
  names(37):='doom/ticcmd_t';
  names(38):='doom/DoomStatus';
  names(39):='p/ActionFunctions';
  names(40):='p/ActiveStates';
  names(41):='p/Actions/ActiveStates/Ai';
  names(42):='p/UnifiedGameMap';
  names(43):='p/intercept_t';
  names(44):='p/divline_t';
  names(45):='doomdb/mocha/DoomDbMochaAdapter';
  names(46):='s/DummySFX';
  -- DoomMain owns the per-frame Ticker/Display orchestration. Any integration
  -- patch that reloads this class invalidates its native methods even when all
  -- renderer/action callees remain compiled.
  names(47):='doom/DoomMain';

  for i in 1..names.count loop
    compiled:=dbms_java.compile_class(names(i));
    dbms_output.put_line('MOCHADOOM_NATIVE class='||names(i)||
      ' newly_compiled='||compiled);
  end loop;
  -- USER_JAVA_METHODS is an expensive dictionary view after native compilation.
  -- Scan it once; the former per-class scan could spend minutes in dictionary
  -- I/O and made a successful build appear hung.
  for method in (
    select name from user_java_methods
     where method_name<>'<clinit>'
       and is_abstract='NO'
       and is_compiled<>'YES'
  ) loop
    for i in 1..names.count loop
      if method.name=names(i) then
        missing:=missing+1;
        exit;
      end if;
    end loop;
  end loop;
  if missing<>0 then
    raise_application_error(-20000,
      missing||' selected methods are not natively compiled');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-NATIVE-RENDERER');
end;
/
