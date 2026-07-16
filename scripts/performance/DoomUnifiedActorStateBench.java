import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.sql.Clob;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.HashMap;
import oracle.sql.NUMBER;

/** Typed retained owner coordinating the accepted fresh-death and CHASE kernels. */
public final class DoomUnifiedActorStateBench {
  private static final int HEADER_BYTES=12,MODE_DEATH=1,MODE_CHASE=2,MODE_ATTACK=3;
  private static Owner committed,pending;
  private static String pendingRequest,lastError="";
  private static int pendingMode;
  private static byte[] pendingChild;

  private DoomUnifiedActorStateBench() {}

  private static final class Owner {
    String session,lineage,stateMapSha;long generation,tic,seq;
    int rng,nextMobj,nextEvent,playerId,playerTarget,killCount,count;
    int playerHealth,playerArmor,playerArmorType,playerAlive,playerSector;
    NUMBER playerX,playerY,playerZ;
    int[] id,thingType,stateIndex,stateTics,health,flags,target,sector,direction,awake,cooldown;
    int[] healthSeen,deathProcessed,behaviorIndex;
    NUMBER[] x,y,z,radius,height;
    String[] stateId,stateAction;
    int[] stateNext,stateDefaultTics;
    int[] behaviorThing,behaviorDeathState,behaviorDropThing,behaviorPainChance;
    int[] behaviorDamageBase,behaviorDamageDice;
    int[][] behaviorState;
    NUMBER[] behaviorSpeed,behaviorMeleeRange;
    String[] behaviorAttack;
    Owner copy(){
      Owner o=new Owner();o.session=session;o.lineage=lineage;o.stateMapSha=stateMapSha;
      o.generation=generation;o.tic=tic;o.seq=seq;o.rng=rng;o.nextMobj=nextMobj;
      o.nextEvent=nextEvent;o.playerId=playerId;o.playerTarget=playerTarget;o.killCount=killCount;o.count=count;
      o.playerX=playerX;o.playerY=playerY;o.playerZ=playerZ;o.playerHealth=playerHealth;
      o.playerArmor=playerArmor;o.playerArmorType=playerArmorType;o.playerAlive=playerAlive;
      o.playerSector=playerSector;
      o.id=id.clone();o.thingType=thingType.clone();o.stateIndex=stateIndex.clone();
      o.stateTics=stateTics.clone();o.health=health.clone();o.flags=flags.clone();
      o.target=target.clone();o.sector=sector.clone();o.direction=direction.clone();
      o.awake=awake.clone();o.cooldown=cooldown.clone();o.healthSeen=healthSeen.clone();
      o.deathProcessed=deathProcessed.clone();o.behaviorIndex=behaviorIndex.clone();
      o.x=x.clone();o.y=y.clone();o.z=z.clone();o.radius=radius.clone();o.height=height.clone();
      o.stateId=stateId;o.stateAction=stateAction;o.stateNext=stateNext;
      o.stateDefaultTics=stateDefaultTics;
      o.behaviorThing=behaviorThing;o.behaviorDeathState=behaviorDeathState;
      o.behaviorDropThing=behaviorDropThing;o.behaviorSpeed=behaviorSpeed;
      o.behaviorAttack=behaviorAttack;o.behaviorState=behaviorState;
      o.behaviorPainChance=behaviorPainChance;o.behaviorDamageBase=behaviorDamageBase;
      o.behaviorDamageDice=behaviorDamageDice;o.behaviorMeleeRange=behaviorMeleeRange;return o;
    }
  }

  private static void require(boolean value,String message){if(!value)throw new IllegalStateException(message);}
  private static int int_(byte[] b,int o){return ((b[o]&255)<<24)|((b[o+1]&255)<<16)|((b[o+2]&255)<<8)|(b[o+3]&255);}
  private static int ushort(byte[] b,int o){return ((b[o]&255)<<8)|(b[o+1]&255);}
  private static NUMBER number(byte[] b,int offset){
    int length=b[offset]&255;require(length>=1&&length<=22,"unified NUMBER");
    byte[] value=new byte[length];System.arraycopy(b,offset+1,value,0,length);return new NUMBER(value);
  }
  private static byte[] failure(Throwable error){
    lastError=error.getClass().getName()+":"+error.getMessage();
    byte[] out=new byte[HEADER_BYTES];out[0]='D';out[1]='U';out[2]='O';out[3]='P';out[4]=1;out[5]=1;return out;
  }
  private static byte[] wrap(int mode,byte[] child,int length){
    byte[] out=new byte[HEADER_BYTES+length];out[0]='D';out[1]='U';out[2]='O';out[3]='P';
    out[4]=1;out[5]=0;out[6]=(byte)mode;
    out[8]=(byte)(length>>>24);out[9]=(byte)(length>>>16);out[10]=(byte)(length>>>8);out[11]=(byte)length;
    System.arraycopy(child,0,out,HEADER_BYTES,length);return out;
  }
  private static byte[] raw(ResultSet row,int column)throws Exception{return row.getBytes(column);}
  private static String hex(byte[] bytes){
    char[] out=new char[bytes.length*2],digits="0123456789abcdef".toCharArray();
    for(int i=0;i<bytes.length;i++){out[i*2]=digits[(bytes[i]>>>4)&15];out[i*2+1]=digits[bytes[i]&15];}
    return new String(out);
  }
  private static String stateMapSha(Connection c)throws Exception{
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery(
        "select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,"+
        "sprite_prefix,sprite_frame,rotations null on null returning varchar2) "+
        "order by state_id returning clob) from doom_state_def")){
      require(r.next(),"unified state map");Clob value=r.getClob(1);
      String text=value.getSubString(1,(int)value.length());value.free();
      return hex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8)));
    }
  }

  private static Owner loadOwner(Connection c,String session,String lineage,long generation,
      String mapSha)throws Exception{
    Owner o=new Owner();o.session=session;o.lineage=lineage;o.generation=generation;o.stateMapSha=mapSha;
    try(PreparedStatement s=c.prepareStatement("select current_tic,last_command_seq,rng_cursor,"+
        "current_player_id,save_lineage from game_sessions where session_token=?")){
      s.setString(1,session);try(ResultSet r=s.executeQuery()){require(r.next(),"unified session");
        o.tic=r.getLong(1);o.seq=r.getLong(2);o.rng=r.getInt(3);o.playerId=r.getInt(4);
        require(lineage.equals(r.getString(5)),"unified lineage");}}
    try(PreparedStatement s=c.prepareStatement("select utl_raw.cast_from_number(x),"+
        "utl_raw.cast_from_number(y),utl_raw.cast_from_number(z),kill_count,health,armor,"+
        "armor_type,alive,(select sector_id from table(doom_bsp_locate(p.x,p.y)) where rownum=1) "+
        "from players p where session_token=? and player_id=?")){
      s.setString(1,session);s.setInt(2,o.playerId);try(ResultSet r=s.executeQuery()){require(r.next(),"unified player");
        o.playerX=new NUMBER(raw(r,1));o.playerY=new NUMBER(raw(r,2));o.playerZ=new NUMBER(raw(r,3));
        o.killCount=r.getInt(4);o.playerHealth=r.getInt(5);o.playerArmor=r.getInt(6);
        o.playerArmorType=r.getInt(7);o.playerAlive=r.getInt(8);o.playerSector=r.getInt(9);}}
    try(PreparedStatement s=c.prepareStatement("select count(*) from mobjs where session_token=? and mobj_id=?")){
      s.setString(1,session);s.setInt(2,o.playerId);try(ResultSet r=s.executeQuery()){r.next();
        o.playerTarget=r.getInt(1)==0?-1:o.playerId;}}
    try(PreparedStatement s=c.prepareStatement("select coalesce(max(mobj_id),0)+1 from mobjs where session_token=?")){
      s.setString(1,session);try(ResultSet r=s.executeQuery()){r.next();o.nextMobj=r.getInt(1);}}
    try(PreparedStatement s=c.prepareStatement("select coalesce(max(event_ordinal)+1,0) from game_events " +
        "where session_token=? and tic=?")){s.setString(1,session);s.setLong(2,o.tic);
      try(ResultSet r=s.executeQuery()){r.next();o.nextEvent=r.getInt(1);}}

    HashMap<String,Integer> stateIndex=new HashMap<String,Integer>();int states=0;
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_state_def")){
      r.next();states=r.getInt(1);o.stateId=new String[states];o.stateAction=new String[states];
      o.stateNext=new int[states];o.stateDefaultTics=new int[states];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery(
        "select state_id,tics,next_state_id,action_name from doom_state_def order by state_id")){
      int i=0;while(r.next()){o.stateId[i]=r.getString(1);stateIndex.put(o.stateId[i],Integer.valueOf(i));
        o.stateDefaultTics[i]=r.getInt(2);o.stateAction[i]=r.getString(4);i++;}
      require(i==states,"unified state rows");}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery(
        "select state_id,next_state_id from doom_state_def order by state_id")){
      int i=0;while(r.next()){String next=r.getString(2);Integer ni=next==null?null:stateIndex.get(next);
        require(next==null||ni!=null,"unified next state");o.stateNext[i++]=ni==null?-1:ni.intValue();}}
    HashMap<Integer,Integer> behavior=new HashMap<Integer,Integer>();
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_monster_def")){r.next();int n=r.getInt(1);
      o.behaviorThing=new int[n];o.behaviorDeathState=new int[n];o.behaviorDropThing=new int[n];
      o.behaviorSpeed=new NUMBER[n];o.behaviorMeleeRange=new NUMBER[n];o.behaviorAttack=new String[n];
      o.behaviorPainChance=new int[n];o.behaviorDamageBase=new int[n];o.behaviorDamageDice=new int[n];
      o.behaviorState=new int[6][n];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select thing_type,"+
        "utl_raw.cast_from_number(speed),attack_kind,see_state_id,chase_state_id,melee_state_id,"+
        "missile_state_id,pain_state_id,death_state_id,coalesce(drop_thing_type,-1),pain_chance,"+
        "utl_raw.cast_from_number(melee_range),damage_base,damage_dice " +
        "from doom_monster_def order by thing_type")){int i=0;while(r.next()){
      o.behaviorThing[i]=r.getInt(1);o.behaviorSpeed[i]=new NUMBER(raw(r,2));o.behaviorAttack[i]=r.getString(3);
      for(int k=0;k<6;k++){String state=r.getString(4+k);Integer mapped=state==null?null:stateIndex.get(state);
        require(state==null||mapped!=null,"unified behavior state");o.behaviorState[k][i]=mapped==null?-1:mapped.intValue();}
      o.behaviorDeathState[i]=o.behaviorState[5][i];o.behaviorDropThing[i]=r.getInt(10);
      o.behaviorPainChance[i]=r.getInt(11);o.behaviorMeleeRange[i]=new NUMBER(raw(r,12));
      o.behaviorDamageBase[i]=r.getInt(13);o.behaviorDamageDice[i]=r.getInt(14);
      behavior.put(Integer.valueOf(o.behaviorThing[i]),Integer.valueOf(i++));}}
    try(PreparedStatement s=c.prepareStatement("select count(*) from mobjs m join doom_monster_def d " +
        "on d.thing_type=m.thing_type where m.session_token=?")){s.setString(1,session);
      try(ResultSet r=s.executeQuery()){r.next();o.count=r.getInt(1);}}
    int n=o.count;o.id=new int[n];o.thingType=new int[n];o.stateIndex=new int[n];o.stateTics=new int[n];
    o.health=new int[n];o.flags=new int[n];o.target=new int[n];o.sector=new int[n];o.direction=new int[n];
    o.awake=new int[n];o.cooldown=new int[n];o.healthSeen=new int[n];o.deathProcessed=new int[n];
    o.behaviorIndex=new int[n];o.x=new NUMBER[n];o.y=new NUMBER[n];o.z=new NUMBER[n];
    o.radius=new NUMBER[n];o.height=new NUMBER[n];
    try(PreparedStatement s=c.prepareStatement("select mobj_id,thing_type,state_id,state_tics,"+
        "utl_raw.cast_from_number(x),utl_raw.cast_from_number(y),utl_raw.cast_from_number(z),"+
        "utl_raw.cast_from_number(radius),utl_raw.cast_from_number(height),health,flags,"+
        "coalesce(target_mobj_id,-1),coalesce(sector_id,(select sector_id from table("+
        "doom_bsp_locate(m.x,m.y)) where rownum=1)),"+
        "move_direction,awake,attack_cooldown,"+
        "coalesce(monster_health_seen,-1),death_processed from mobjs m where session_token=? " +
        "and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type) order by mobj_id")){
      s.setString(1,session);try(ResultSet r=s.executeQuery()){int i=0;while(r.next()){
        o.id[i]=r.getInt(1);o.thingType[i]=r.getInt(2);Integer si=stateIndex.get(r.getString(3));
        require(si!=null,"unified actor state");o.stateIndex[i]=si.intValue();o.stateTics[i]=r.getInt(4);
        o.x[i]=new NUMBER(raw(r,5));o.y[i]=new NUMBER(raw(r,6));o.z[i]=new NUMBER(raw(r,7));
        o.radius[i]=new NUMBER(raw(r,8));o.height[i]=new NUMBER(raw(r,9));o.health[i]=r.getInt(10);
        o.flags[i]=r.getInt(11);o.target[i]=r.getInt(12);o.sector[i]=r.getInt(13);
        o.direction[i]=r.getInt(14);o.awake[i]=r.getInt(15);o.cooldown[i]=r.getInt(16);
        o.healthSeen[i]=r.getInt(17);o.deathProcessed[i]=r.getInt(18);
        Integer bi=behavior.get(Integer.valueOf(o.thingType[i]));require(bi!=null,"unified behavior");
        o.behaviorIndex[i]=bi.intValue();i++;}require(i==n,"unified actor rows");}}
    return o;
  }

  private static Clob queryClob(Connection c,String sql,String session)throws Exception{
    try(PreparedStatement s=c.prepareStatement(sql)){s.setString(1,session);try(ResultSet r=s.executeQuery()){
      require(r.next(),"unified snapshot");return r.getClob(1);}}
  }

  public static String load(String session,String lineage,long generation,String stateMapSha){
    try{
      require(pending==null&&session!=null&&session.matches("[0-9a-f]{32}")&&lineage!=null&&
          lineage.matches("[0-9a-f]{64}")&&generation>0&&stateMapSha!=null&&
          stateMapSha.matches("[0-9a-f]{64}"),"unified load");
      Connection c=DriverManager.getConnection("jdbc:default:connection:");
      require(DoomSimCatalogBench.loadCatalog().startsWith("OK|"),"unified catalog");
      require(stateMapSha.equals(stateMapSha(c)),"unified state map fence");
      Owner candidate=loadOwner(c,session,lineage,generation,stateMapSha);
      Clob sectors=queryClob(c,"select json_arrayagg(json_array(sector_id,floor_height,"+
          "ceiling_height returning varchar2) order by sector_id returning clob) from sector_state " +
          "where session_token=?",session);
      Clob chaseActors=queryClob(c,"select json_arrayagg(json_array(m.mobj_id,m.x,m.y,m.z,"+
          "m.radius,m.height,m.health,d.speed returning varchar2) order by m.mobj_id returning clob) " +
          "from mobjs m join doom_monster_def d on d.thing_type=m.thing_type where m.session_token=?",session);
      String chase=DoomMonsterChaseBench.load(session,lineage,generation,sectors,chaseActors);
      String los=DoomRetainedLosBench.load(sectors);
      sectors.free();chaseActors.free();require(chase.startsWith("OK|"),"unified chase load "+chase);
      require(los.startsWith("OK|"),"unified LOS load "+los);
      Clob deaths=queryClob(c,"with state_index as (select state_id,row_number() over(order by state_id)-1 idx " +
          "from doom_state_def) select json_arrayagg(json_array(m.mobj_id,m.health,m.monster_health_seen,"+
          "m.attack_cooldown,m.awake,m.state_tics,m.death_processed,m.flags,m.target_mobj_id,"+
          "m.move_direction,ds.idx,dd.tics,m.x,m.y,m.z,coalesce(m.sector_id,(select sector_id from " +
          "table(doom_bsp_locate(m.x,m.y)) where rownum=1)),d.drop_thing_type,ss.idx,sd.tics,"+
          "case when d.drop_thing_type is null then null else coalesce(tt.radius,8) end,"+
          "case when d.drop_thing_type is null then null else coalesce(tt.height,8) end null on null " +
          "returning varchar2) order by m.mobj_id returning clob) from mobjs m join doom_monster_def d " +
          "on d.thing_type=m.thing_type join state_index ds on ds.state_id=d.death_state_id join " +
          "doom_state_def dd on dd.state_id=d.death_state_id left join doom_thing_type_def tt on " +
          "tt.thing_type=d.drop_thing_type left join state_index ss on ss.state_id=tt.spawn_state_id " +
          "left join doom_state_def sd on sd.state_id=tt.spawn_state_id where m.session_token=?",session);
      String death=DoomFreshDeathTickBench.load(session,lineage,generation,candidate.killCount,deaths);
      deaths.free();require(death.startsWith("OK|"),"unified death load "+death);
      committed=candidate;lastError="";return "OK|"+candidate.count+"|"+candidate.tic+"|"+
          candidate.seq+"|"+candidate.rng+"|"+candidate.nextMobj+"|"+candidate.nextEvent;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
  }

  private static void fence(String s,String l,long g,long tic,long seq,int rng,int nm,int ne){
    require(committed!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g,"unified fence");require(committed.tic==tic&&committed.seq==seq&&
        committed.rng==rng&&committed.nextMobj==nm&&committed.nextEvent==ne,"unified frontier");
  }

  private static final class AttackEvent{
    int ordinal,type,actor,target;NUMBER value;String text;
    AttackEvent(int ordinal,int type,int actor,int target,NUMBER value,String text){
      this.ordinal=ordinal;this.type=type;this.actor=actor;this.target=target;
      this.value=value;this.text=text;
    }
  }
  private static int draw(Owner o,int[] draws){
    int value=DoomSimCatalogBench.rng(o.rng);require(value>=0,"unified attack RNG");
    o.rng=(o.rng+1)&255;draws[0]++;return value;
  }
  private static NUMBER distance(Owner o,int i)throws Exception{
    NUMBER dx=o.playerX.sub(o.x[i]),dy=o.playerY.sub(o.y[i]);
    return dx.mul(dx).add(dy.mul(dy)).sqroot();
  }
  private static boolean visible(Owner o,int i){
    int value=DoomRetainedLosBench.visible(o.x[i],o.y[i],o.sector[i],
        o.playerX,o.playerY,o.playerSector);
    require(value>=0,"unified attack LOS "+DoomRetainedLosBench.lastError());return value==1;
  }
  private static void damage(Owner o,int actor,int amount,ArrayList<AttackEvent> events){
    int absorb=0;
    if(o.playerArmorType==2)absorb=Math.min(o.playerArmor,amount/2);
    else if(o.playerArmorType==1)absorb=Math.min(o.playerArmor,(amount*333)/1000);
    o.playerArmor-=absorb;o.playerHealth=Math.max(0,o.playerHealth-(amount-absorb));
    if(o.playerHealth==0)o.playerAlive=0;
    events.add(new AttackEvent(o.nextEvent++,1,actor,-1,new NUMBER(amount),null));
  }
  private static void attack(Owner o,int i,int bi,int[] draws,ArrayList<AttackEvent> events)throws Exception{
    NUMBER range=distance(o,i);String kind=o.behaviorAttack[bi];
    if("MELEE".equals(kind)&&range.compareTo(o.behaviorMeleeRange[bi])>0)return;
    if(!visible(o,i))return;
    if("HITSCAN".equals(kind)){
      int difference=draw(o,draws)-draw(o,draws);
      int damage=o.behaviorDamageBase[bi]*(1+draw(o,draws)%o.behaviorDamageDice[bi]);
      NUMBER miss=DoomSimCatalogBench.hitscanSin(difference).mul(range).abs();
      if(miss.compareTo(new NUMBER(16))<=0)damage(o,o.id[i],damage,events);
      else events.add(new AttackEvent(o.nextEvent++,2,o.id[i],-1,miss,
          DoomSimCatalogBench.hitscanSpreadText(difference)));
    }else if("MELEE".equals(kind)){
      int damage=o.behaviorDamageBase[bi]*(1+draw(o,draws)%o.behaviorDamageDice[bi]);
      damage(o,o.id[i],damage,events);
    }
  }
  private static void numberSlot(DataOutputStream out,NUMBER value)throws Exception{
    byte[] bytes=value.toBytes();require(bytes.length>=1&&bytes.length<=22,"unified attack NUMBER");
    out.writeByte(bytes.length);out.write(bytes);for(int i=bytes.length;i<22;i++)out.writeByte(0);
  }
  private static byte[] attackDelta(Owner o)throws Exception{
    ArrayList<AttackEvent> events=new ArrayList<AttackEvent>();int[] draws=new int[]{0};
    for(int i=0;i<o.count;i++){
      int oldSeen=o.healthSeen[i]<0?o.health[i]:o.healthSeen[i],oldCooldown=o.cooldown[i];
      o.healthSeen[i]=o.health[i];o.cooldown[i]=Math.max(0,oldCooldown-1);
      if(o.health[i]==0){require(o.deathProcessed[i]==1&&o.stateTics[i]==0,
          "unified ATTACK requires settled corpse");continue;}int bi=o.behaviorIndex[i];
      if(o.health[i]<oldSeen){int roll=draw(o,draws);if(roll<o.behaviorPainChance[bi]){
        o.stateIndex[i]=o.behaviorState[4][bi];o.stateTics[i]=o.stateDefaultTics[o.stateIndex[i]];
        o.awake[i]=1;events.add(new AttackEvent(o.nextEvent++,3,o.id[i],o.playerTarget,
            new NUMBER(roll),null));continue;}}
      require(o.awake[i]==1,"unified ATTACK excludes wake/sound phase");int state=o.stateIndex[i];String action;
      if(o.stateTics[i]>0){o.stateTics[i]--;if(o.stateTics[i]>0)continue;
        state=o.stateNext[state];require(state>=0,"unified attack next state");
        o.stateIndex[i]=state;o.stateTics[i]=o.stateDefaultTics[state];action=o.stateAction[state];
      }else action=o.stateAction[state];
      if("CHASE".equals(action)){
        boolean select=oldCooldown==0&&("HITSCAN".equals(o.behaviorAttack[bi])||
            ("MELEE".equals(o.behaviorAttack[bi])&&
             distance(o,i).compareTo(o.behaviorMeleeRange[bi])<=0));
        require(select,"unified ATTACK excludes CHASE movement");
        state="MELEE".equals(o.behaviorAttack[bi])?o.behaviorState[2][bi]:o.behaviorState[3][bi];
        o.stateIndex[i]=state;o.stateTics[i]=o.stateDefaultTics[state];o.cooldown[i]=o.stateTics[i];
        attack(o,i,bi,draws,events);
      }else if("MELEE".equals(action)||"HITSCAN".equals(action))attack(o,i,bi,draws,events);
      else throw new IllegalStateException("unified ATTACK excludes action "+action);
    }
    ByteArrayOutputStream bytes=new ByteArrayOutputStream(8192);DataOutputStream out=new DataOutputStream(bytes);
    out.writeInt(0x4441544b);out.writeByte(1);out.writeByte(0);out.writeShort(o.count);
    out.writeShort(events.size());out.writeShort(draws[0]);out.writeInt(o.rng);
    out.writeInt(o.playerHealth);out.writeInt(o.playerArmor);out.writeInt(o.playerAlive);out.writeInt(o.nextEvent);
    for(int i=0;i<o.count;i++){out.writeInt(o.id[i]);out.writeInt(o.healthSeen[i]);
      out.writeInt(o.cooldown[i]);out.writeInt(o.stateIndex[i]);out.writeInt(o.stateTics[i]);
      out.writeInt(o.awake[i]);}
    for(AttackEvent event:events){out.writeInt(event.ordinal);out.writeInt(event.type);out.writeInt(event.actor);
      out.writeInt(event.target);numberSlot(out,event.value);if(event.text==null)out.writeShort(-1);else out.writeUTF(event.text);}
    out.flush();return bytes.toByteArray();
  }

  public static byte[] prepare(String s,String l,long g,String request,String mode,long tic,long seq,
      int rng,int nextMobj,int nextEvent){
    boolean deathPrepared=false;
    try{
      fence(s,l,g,tic,seq,rng,nextMobj,nextEvent);require(pending==null&&request!=null&&
          request.matches("[0-9a-f]{32}"),"unified request");Owner candidate=committed.copy();
      byte[] child;int childLength,selected;
      if("DEATH".equals(mode)){
        selected=MODE_DEATH;child=DoomFreshDeathTickBench.prepare(s,l,g,request,nextEvent,nextMobj);
        require(child[5]==0,"unified death "+DoomFreshDeathTickBench.lastError());
        deathPrepared=true;
        int actors=ushort(child,6),drops=ushort(child,8),events=ushort(child,10);
        childLength=24+actors*40+drops*92+events*20;
        require(actors==candidate.count,"unified death count");
        for(int i=0;i<actors;i++){int o=24+i*40;require(int_(child,o)==candidate.id[i],"unified death actor");
          candidate.healthSeen[i]=int_(child,o+4);candidate.cooldown[i]=int_(child,o+8);
          candidate.stateIndex[i]=int_(child,o+12);candidate.stateTics[i]=int_(child,o+16);
          candidate.deathProcessed[i]=int_(child,o+20);candidate.awake[i]=int_(child,o+24);
          candidate.flags[i]=int_(child,o+28);candidate.target[i]=int_(child,o+32);
          candidate.direction[i]=int_(child,o+36);}
        candidate.killCount+=actors;candidate.nextMobj=int_(child,16);candidate.nextEvent=int_(child,20);
      }else if("CHASE".equals(mode)){
        selected=MODE_CHASE;child=DoomMonsterChaseBench.prepare(s,l,g,request,
            candidate.playerX,candidate.playerY);require(child[5]==0,"unified chase "+DoomMonsterChaseBench.lastError());
        childLength=child.length;int actors=ushort(child,6);require(actors==candidate.count,"unified chase count");
        for(int i=0;i<actors;i++){int o=8+i*58;require(int_(child,o)==candidate.id[i],"unified chase actor");
          candidate.x[i]=number(child,o+4);candidate.y[i]=number(child,o+27);
          candidate.sector[i]=int_(child,o+50);candidate.direction[i]=int_(child,o+54);}
      }else if("ATTACK".equals(mode)){
        selected=MODE_ATTACK;child=attackDelta(candidate);childLength=child.length;
      }else throw new IllegalStateException("unified mode");
      byte[] result=wrap(selected,child,childLength);pending=candidate;pendingRequest=request;
      pendingMode=selected;pendingChild=Arrays.copyOf(child,childLength);lastError="";return result;
    }catch(Throwable e){
      if(deathPrepared)try{DoomFreshDeathTickBench.discard(s,l,g,request);}catch(Throwable ignored){}
      return failure(e);
    }
  }

  public static String accept(String s,String l,long g,String request){
    try{require(committed!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&pending!=null&&request!=null&&request.equals(pendingRequest),
        "unified pending");String child="OK";
      if(pendingMode==MODE_DEATH)child=DoomFreshDeathTickBench.accept(s,l,g,request);
      else if(pendingMode==MODE_CHASE)child=DoomMonsterChaseBench.acceptWorld(s,l,g,request,pendingChild);
      require("OK".equals(child)||child.startsWith("OK|"),"unified child accept "+child);
      committed=pending;pending=null;pendingRequest=null;pendingChild=null;lastError="";return "OK";
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}

  public static String discard(String s,String l,long g,String request){
    try{require(committed!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&pending!=null&&request!=null&&request.equals(pendingRequest),
        "unified pending");if(pendingMode==MODE_DEATH){String child=DoomFreshDeathTickBench.discard(s,l,g,request);
        require("OK".equals(child),"unified child discard "+child);}pending=null;pendingRequest=null;
      pendingChild=null;lastError="";return "OK";
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  public static String benchmark(String s,String l,long g,String mode,long tic,long seq,int rng,
      int nextMobj,int nextEvent,Clob targets,int iterations){
    NUMBER savedX=null,savedY=null;int savedSector=-1;String activeRequest=null;
    try{
      fence(s,l,g,tic,seq,rng,nextMobj,nextEvent);require(pending==null&&iterations==300&&
          ("CHASE".equals(mode)||"ATTACK".equals(mode)),"unified benchmark");
      NUMBER[] tx=null,ty=null;int[] ts=null;
      if("CHASE".equals(mode)){
        require(targets!=null&&targets.length()<=4096,"unified benchmark targets");
        String text=targets.getSubString(1,(int)targets.length());
        String[] rows=text.substring(1,text.length()-1).trim().split("\\]\\s*,\\s*\\[");
        require(rows.length==4,"unified benchmark target count");tx=new NUMBER[4];ty=new NUMBER[4];ts=new int[4];
        for(int i=0;i<4;i++){String[] f=rows[i].replace("[","").replace("]","").split(",");
          require(f.length==3,"unified benchmark target");tx[i]=new NUMBER(f[0]);ty[i]=new NUMBER(f[1]);
          ts[i]=Integer.parseInt(f[2]);}
        savedX=committed.playerX;savedY=committed.playerY;savedSector=committed.playerSector;
      }
      long[] times=new long[iterations];int bytes=0;
      for(int sample=-20;sample<iterations;sample++){
        if(tx!=null){int target=(sample+20)&3;committed.playerX=tx[target];committed.playerY=ty[target];
          committed.playerSector=ts[target];}
        String request=String.format("%032x",sample+21);activeRequest=request;long started=System.nanoTime();
        byte[] delta=prepare(s,l,g,request,mode,tic,seq,rng,nextMobj,nextEvent);
        require(delta.length>HEADER_BYTES&&delta[5]==0,"unified benchmark prepare "+lastError);
        String discarded=discard(s,l,g,request);require("OK".equals(discarded),"unified benchmark discard");
        activeRequest=null;
        long elapsed=System.nanoTime()-started;if(sample>=0){times[sample]=elapsed;bytes=delta.length;}
      }
      Arrays.sort(times);lastError="";return "OK|"+mode+"|"+iterations+"|"+bytes+"|"+
          times[149]+"|"+times[284]+"|"+times[299];
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
    finally{if(activeRequest!=null&&activeRequest.equals(pendingRequest)){
        pending=null;pendingRequest=null;pendingChild=null;}
      if(savedX!=null&&committed!=null){committed.playerX=savedX;committed.playerY=savedY;
      committed.playerSector=savedSector;}}
  }
  public static String lastError(){try{return lastError;}catch(Throwable e){return e.getClass().getName();}}
}
