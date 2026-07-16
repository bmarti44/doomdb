import java.io.ByteArrayOutputStream;
import java.io.ByteArrayInputStream;
import java.io.DataOutputStream;
import java.io.DataInputStream;
import java.sql.Clob;
import java.sql.Blob;
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
  private static final int HEADER_BYTES=12,MODE_DEATH=1,MODE_CHASE=2,MODE_ATTACK=3,MODE_TIC=4,
      MODE_COMMAND_TIC=5,COMMAND_BYTES=24,COMMAND_CHILD_HEADER=105;
  private static Owner committed,pending,spare;
  private static String pendingRequest,lastError="";
  private static int pendingMode;
  private static byte[] pendingChild;
  private static long ticChaseNs,ticLoopNs,ticEncodeNs;
  private static long lastActorTicNs,lastCommandEncodeNs;
  private static final byte[] ticOutput=new byte[32767];
  private static int ticOutputLength;
  private static int[] priorHealthScratch=new int[0],moveMaskScratch=new int[0];
  private static int[] renderOp=new int[0],renderId=new int[0],renderState=new int[0];
  private static NUMBER[] renderX=new NUMBER[0],renderY=new NUMBER[0],renderZ=new NUMBER[0],renderAngle=new NUMBER[0];
  private static int lastRenderUpserts,lastRenderRemoves;

  private DoomUnifiedActorStateBench() {}

  private static final class Owner {
    String session,lineage,stateMapSha;long generation,tic,seq;
    int rng,nextMobj,nextEvent,playerId,playerTarget,killCount,count;
    int playerHealth,playerArmor,playerArmorType,playerAlive,playerSector,playerAngleIndex;
    int playerSound;
    NUMBER playerX,playerY,playerZ,playerEyeZ;
    int[] id,thingType,stateIndex,stateTics,health,flags,target,sector,direction,awake,cooldown;
    int[] healthSeen,deathProcessed,behaviorIndex;
    int[] visibilityCache;
    NUMBER[] x,y,z,radius,height;
    String[] stateId,stateAction;
    int[] stateNext,stateDefaultTics;
    int[] behaviorThing,behaviorDeathState,behaviorDropThing,behaviorPainChance;
    int[] behaviorDamageBase,behaviorDamageDice;
    int[] behaviorProjectileThing;
    int[][] behaviorState;
    NUMBER[] behaviorSpeed,behaviorMeleeRange;
    String[] behaviorAttack;
    int[] spawnThing,spawnState;NUMBER[] spawnRadius,spawnHeight;
    int[] projectileThing,projectileState;NUMBER[] projectileSpeed,projectileRadius,projectileHeight;
    String[] projectileKind;
    WorldMobjs world;int[] worldSlot;
    Owner copy(){
      Owner o=new Owner();o.session=session;o.lineage=lineage;o.stateMapSha=stateMapSha;
      o.generation=generation;o.tic=tic;o.seq=seq;o.rng=rng;o.nextMobj=nextMobj;
      o.nextEvent=nextEvent;o.playerId=playerId;o.playerTarget=playerTarget;o.killCount=killCount;o.count=count;
      o.playerX=playerX;o.playerY=playerY;o.playerZ=playerZ;o.playerEyeZ=playerEyeZ;o.playerHealth=playerHealth;
      o.playerArmor=playerArmor;o.playerArmorType=playerArmorType;o.playerAlive=playerAlive;
      o.playerSector=playerSector;o.playerAngleIndex=playerAngleIndex;
      o.playerSound=playerSound;
      o.id=id.clone();o.thingType=thingType.clone();o.stateIndex=stateIndex.clone();
      o.stateTics=stateTics.clone();o.health=health.clone();o.flags=flags.clone();
      o.target=target.clone();o.sector=sector.clone();o.direction=direction.clone();
      o.awake=awake.clone();o.cooldown=cooldown.clone();o.healthSeen=healthSeen.clone();
      o.deathProcessed=deathProcessed.clone();o.behaviorIndex=behaviorIndex.clone();
      o.visibilityCache=visibilityCache.clone();
      o.x=x.clone();o.y=y.clone();o.z=z.clone();o.radius=radius.clone();o.height=height.clone();
      o.stateId=stateId;o.stateAction=stateAction;o.stateNext=stateNext;
      o.stateDefaultTics=stateDefaultTics;
      o.behaviorThing=behaviorThing;o.behaviorDeathState=behaviorDeathState;
      o.behaviorDropThing=behaviorDropThing;o.behaviorSpeed=behaviorSpeed;
      o.behaviorAttack=behaviorAttack;o.behaviorState=behaviorState;
      o.behaviorPainChance=behaviorPainChance;o.behaviorDamageBase=behaviorDamageBase;
      o.behaviorDamageDice=behaviorDamageDice;o.behaviorMeleeRange=behaviorMeleeRange;
      o.behaviorProjectileThing=behaviorProjectileThing;o.spawnThing=spawnThing;o.spawnState=spawnState;
      o.spawnRadius=spawnRadius;o.spawnHeight=spawnHeight;o.projectileThing=projectileThing;
      o.projectileState=projectileState;o.projectileSpeed=projectileSpeed;
      o.projectileRadius=projectileRadius;o.projectileHeight=projectileHeight;
      o.projectileKind=projectileKind;o.world=world.copy();o.worldSlot=worldSlot.clone();return o;
    }
    void copyFrom(Owner s){session=s.session;lineage=s.lineage;stateMapSha=s.stateMapSha;generation=s.generation;
      tic=s.tic;seq=s.seq;rng=s.rng;nextMobj=s.nextMobj;nextEvent=s.nextEvent;playerId=s.playerId;
      playerTarget=s.playerTarget;killCount=s.killCount;count=s.count;playerHealth=s.playerHealth;
      playerArmor=s.playerArmor;playerArmorType=s.playerArmorType;playerAlive=s.playerAlive;
      playerSector=s.playerSector;playerAngleIndex=s.playerAngleIndex;playerSound=s.playerSound;
      playerX=s.playerX;playerY=s.playerY;playerZ=s.playerZ;playerEyeZ=s.playerEyeZ;
      System.arraycopy(s.stateIndex,0,stateIndex,0,count);System.arraycopy(s.stateTics,0,stateTics,0,count);
      System.arraycopy(s.health,0,health,0,count);System.arraycopy(s.flags,0,flags,0,count);
      System.arraycopy(s.target,0,target,0,count);System.arraycopy(s.sector,0,sector,0,count);
      System.arraycopy(s.direction,0,direction,0,count);System.arraycopy(s.awake,0,awake,0,count);
      System.arraycopy(s.cooldown,0,cooldown,0,count);System.arraycopy(s.healthSeen,0,healthSeen,0,count);
      System.arraycopy(s.deathProcessed,0,deathProcessed,0,count);System.arraycopy(s.x,0,x,0,count);
      System.arraycopy(s.visibilityCache,0,visibilityCache,0,count);
      System.arraycopy(s.y,0,y,0,count);System.arraycopy(s.z,0,z,0,count);System.arraycopy(s.radius,0,radius,0,count);
      System.arraycopy(s.height,0,height,0,count);world.copyFrom(s.world);
      System.arraycopy(s.worldSlot,0,worldSlot,0,count);}
  }

  /** Typed all-MOBJ retained image; monster behavior slots index into this owner. */
  private static final class WorldMobjs{
    int count;int[] id,thing,state,tics,health,flags,target,tracer,reaction,spawnThing,owner;
    int[] exploded,sector,direction,awake,cooldown,healthSeen,deathProcessed;
    NUMBER[] x,y,z,mx,my,mz,angle,radius,height;String[] projectileKind;
    HashMap<Integer,Integer> slot;
    WorldMobjs(int n){count=n;id=new int[n];thing=new int[n];state=new int[n];tics=new int[n];
      health=new int[n];flags=new int[n];target=new int[n];tracer=new int[n];reaction=new int[n];
      spawnThing=new int[n];owner=new int[n];exploded=new int[n];sector=new int[n];direction=new int[n];
      awake=new int[n];cooldown=new int[n];healthSeen=new int[n];deathProcessed=new int[n];
      x=new NUMBER[n];y=new NUMBER[n];z=new NUMBER[n];mx=new NUMBER[n];my=new NUMBER[n];mz=new NUMBER[n];
      angle=new NUMBER[n];radius=new NUMBER[n];height=new NUMBER[n];projectileKind=new String[n];slot=new HashMap<Integer,Integer>();}
    WorldMobjs copy(){WorldMobjs w=new WorldMobjs(count);w.id=id.clone();w.thing=thing.clone();w.state=state.clone();
      w.tics=tics.clone();w.health=health.clone();w.flags=flags.clone();w.target=target.clone();w.tracer=tracer.clone();
      w.reaction=reaction.clone();w.spawnThing=spawnThing.clone();w.owner=owner.clone();w.exploded=exploded.clone();
      w.sector=sector.clone();w.direction=direction.clone();w.awake=awake.clone();w.cooldown=cooldown.clone();
      w.healthSeen=healthSeen.clone();w.deathProcessed=deathProcessed.clone();w.x=x.clone();w.y=y.clone();
      w.z=z.clone();w.mx=mx.clone();w.my=my.clone();w.mz=mz.clone();w.angle=angle.clone();w.radius=radius.clone();
      w.height=height.clone();w.projectileKind=projectileKind.clone();w.slot=new HashMap<Integer,Integer>(slot);return w;}
    int slot(int mobj){Integer value=slot.get(Integer.valueOf(mobj));return value==null?-1:value.intValue();}
    void copyFrom(WorldMobjs w){ensure(w.count);count=w.count;System.arraycopy(w.id,0,id,0,count);
      System.arraycopy(w.thing,0,thing,0,count);System.arraycopy(w.state,0,state,0,count);System.arraycopy(w.tics,0,tics,0,count);
      System.arraycopy(w.health,0,health,0,count);System.arraycopy(w.flags,0,flags,0,count);System.arraycopy(w.target,0,target,0,count);
      System.arraycopy(w.tracer,0,tracer,0,count);System.arraycopy(w.reaction,0,reaction,0,count);
      System.arraycopy(w.spawnThing,0,spawnThing,0,count);System.arraycopy(w.owner,0,owner,0,count);
      System.arraycopy(w.exploded,0,exploded,0,count);System.arraycopy(w.sector,0,sector,0,count);
      System.arraycopy(w.direction,0,direction,0,count);System.arraycopy(w.awake,0,awake,0,count);
      System.arraycopy(w.cooldown,0,cooldown,0,count);System.arraycopy(w.healthSeen,0,healthSeen,0,count);
      System.arraycopy(w.deathProcessed,0,deathProcessed,0,count);System.arraycopy(w.x,0,x,0,count);
      System.arraycopy(w.y,0,y,0,count);System.arraycopy(w.z,0,z,0,count);System.arraycopy(w.mx,0,mx,0,count);
      System.arraycopy(w.my,0,my,0,count);System.arraycopy(w.mz,0,mz,0,count);System.arraycopy(w.angle,0,angle,0,count);
      System.arraycopy(w.radius,0,radius,0,count);System.arraycopy(w.height,0,height,0,count);
      System.arraycopy(w.projectileKind,0,projectileKind,0,count);slot.clear();slot.putAll(w.slot);}
    void ensure(int n){if(id.length>=n)return;int size=Math.max(n,Math.max(16,id.length*2));
      id=Arrays.copyOf(id,size);thing=Arrays.copyOf(thing,size);state=Arrays.copyOf(state,size);tics=Arrays.copyOf(tics,size);
      health=Arrays.copyOf(health,size);flags=Arrays.copyOf(flags,size);target=Arrays.copyOf(target,size);
      tracer=Arrays.copyOf(tracer,size);reaction=Arrays.copyOf(reaction,size);spawnThing=Arrays.copyOf(spawnThing,size);
      owner=Arrays.copyOf(owner,size);exploded=Arrays.copyOf(exploded,size);sector=Arrays.copyOf(sector,size);
      direction=Arrays.copyOf(direction,size);awake=Arrays.copyOf(awake,size);cooldown=Arrays.copyOf(cooldown,size);
      healthSeen=Arrays.copyOf(healthSeen,size);deathProcessed=Arrays.copyOf(deathProcessed,size);
      x=Arrays.copyOf(x,size);y=Arrays.copyOf(y,size);z=Arrays.copyOf(z,size);mx=Arrays.copyOf(mx,size);
      my=Arrays.copyOf(my,size);mz=Arrays.copyOf(mz,size);angle=Arrays.copyOf(angle,size);
      radius=Arrays.copyOf(radius,size);height=Arrays.copyOf(height,size);projectileKind=Arrays.copyOf(projectileKind,size);}
    void append(TicSpawn p){int n=count+1;ensure(n);
      int i=count;id[i]=p.id;thing[i]=p.thing;state[i]=p.state;tics[i]=p.tics;health[i]=p.health;flags[i]=p.flags;
      target[i]=p.target;tracer[i]=p.tracer;reaction[i]=p.reaction;spawnThing[i]=p.spawnThing;owner[i]=p.owner;
      exploded[i]=p.exploded;sector[i]=p.sector;direction[i]=-1;awake[i]=0;cooldown[i]=0;healthSeen[i]=-1;
      deathProcessed[i]=0;x[i]=p.x;y[i]=p.y;z[i]=p.z;mx[i]=p.mx;my[i]=p.my;mz[i]=p.mz;
      angle[i]=NUMBER.zero();radius[i]=p.radius;height[i]=p.height;projectileKind[i]=p.kind;
      require(slot.put(Integer.valueOf(p.id),Integer.valueOf(i))==null,"world append duplicate");count=n;}
    void remove(int expected){int at=slot(expected);require(at>=0,"world remove id");
      for(int i=0;i<count;i++){if(target[i]==expected)target[i]=-1;if(tracer[i]==expected)tracer[i]=-1;
        if(owner[i]==expected)owner[i]=-1;}slot.remove(Integer.valueOf(expected));int n=--count;
      id=removed(id,at,n);thing=removed(thing,at,n);state=removed(state,at,n);tics=removed(tics,at,n);
      health=removed(health,at,n);flags=removed(flags,at,n);target=removed(target,at,n);tracer=removed(tracer,at,n);
      reaction=removed(reaction,at,n);spawnThing=removed(spawnThing,at,n);owner=removed(owner,at,n);
      exploded=removed(exploded,at,n);sector=removed(sector,at,n);direction=removed(direction,at,n);
      awake=removed(awake,at,n);cooldown=removed(cooldown,at,n);healthSeen=removed(healthSeen,at,n);
      deathProcessed=removed(deathProcessed,at,n);x=removed(x,at,n);y=removed(y,at,n);z=removed(z,at,n);
      mx=removed(mx,at,n);my=removed(my,at,n);mz=removed(mz,at,n);angle=removed(angle,at,n);
      radius=removed(radius,at,n);height=removed(height,at,n);projectileKind=removed(projectileKind,at,n);
      slot.clear();for(int i=0;i<n;i++)slot.put(Integer.valueOf(id[i]),Integer.valueOf(i));}
  }
  private static int[] removed(int[] values,int at,int length){if(at<length)System.arraycopy(values,at+1,values,at,length-at);
    return Arrays.copyOf(values,length);}
  private static NUMBER[] removed(NUMBER[] values,int at,int length){if(at<length)System.arraycopy(values,at+1,values,at,length-at);
    return Arrays.copyOf(values,length);}
  private static String[] removed(String[] values,int at,int length){if(at<length)System.arraycopy(values,at+1,values,at,length-at);
    return Arrays.copyOf(values,length);}

  private static void require(boolean value,String message){if(!value)throw new IllegalStateException(message);}
  private static int int_(byte[] b,int o){return ((b[o]&255)<<24)|((b[o+1]&255)<<16)|((b[o+2]&255)<<8)|(b[o+3]&255);}
  private static long long_(byte[] b,int o){return ((long)int_(b,o)<<32)|(int_(b,o+4)&0xffffffffL);}
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
  private static WorldMobjs loadWorld(Connection c,String session,HashMap<String,Integer> states)throws Exception{
    int count;try(PreparedStatement s=c.prepareStatement("select count(*) from mobjs where session_token=?")){
      s.setString(1,session);try(ResultSet r=s.executeQuery()){r.next();count=r.getInt(1);}}
    WorldMobjs w=new WorldMobjs(count);
    try(PreparedStatement s=c.prepareStatement("select mobj_id,thing_type,state_id,state_tics,"+
        "utl_raw.cast_from_number(x),utl_raw.cast_from_number(y),utl_raw.cast_from_number(z),"+
        "utl_raw.cast_from_number(momentum_x),utl_raw.cast_from_number(momentum_y),"+
        "utl_raw.cast_from_number(momentum_z),utl_raw.cast_from_number(angle),"+
        "utl_raw.cast_from_number(radius),utl_raw.cast_from_number(height),health,flags,"+
        "coalesce(target_mobj_id,-1),coalesce(tracer_mobj_id,-1),reaction_time,"+
        "coalesce(spawn_thing_id,-1),coalesce(owner_mobj_id,-1),projectile_kind,exploded,coalesce(sector_id,-1),"+
        "move_direction,awake,attack_cooldown,coalesce(monster_health_seen,-1),death_processed "+
        "from mobjs where session_token=? order by mobj_id")){s.setString(1,session);
      try(ResultSet r=s.executeQuery()){int i=0;while(r.next()){w.id[i]=r.getInt(1);w.thing[i]=r.getInt(2);
        Integer state=states.get(r.getString(3));require(state!=null,"unified world state");w.state[i]=state.intValue();
        w.tics[i]=r.getInt(4);w.x[i]=new NUMBER(raw(r,5));w.y[i]=new NUMBER(raw(r,6));w.z[i]=new NUMBER(raw(r,7));
        w.mx[i]=new NUMBER(raw(r,8));w.my[i]=new NUMBER(raw(r,9));w.mz[i]=new NUMBER(raw(r,10));
        w.angle[i]=new NUMBER(raw(r,11));w.radius[i]=new NUMBER(raw(r,12));w.height[i]=new NUMBER(raw(r,13));
        w.health[i]=r.getInt(14);w.flags[i]=r.getInt(15);w.target[i]=r.getInt(16);w.tracer[i]=r.getInt(17);
        w.reaction[i]=r.getInt(18);w.spawnThing[i]=r.getInt(19);w.owner[i]=r.getInt(20);
        w.projectileKind[i]=r.getString(21);w.exploded[i]=r.getInt(22);w.sector[i]=r.getInt(23);
        w.direction[i]=r.getInt(24);w.awake[i]=r.getInt(25);w.cooldown[i]=r.getInt(26);
        w.healthSeen[i]=r.getInt(27);w.deathProcessed[i]=r.getInt(28);
        require(w.slot.put(Integer.valueOf(w.id[i]),Integer.valueOf(i))==null,"unified world duplicate");i++;}
        require(i==count,"unified world rows");}}
    return w;
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
        "utl_raw.cast_from_number(y),utl_raw.cast_from_number(z),utl_raw.cast_from_number(angle),"+
        "utl_raw.cast_from_number(z+view_height+view_bob),"+
        "kill_count,health,armor,armor_type,alive,"+
        "(select sector_id from table(doom_bsp_locate(p.x,p.y)) where rownum=1) "+
        "from players p where session_token=? and player_id=?")){
      s.setString(1,session);s.setInt(2,o.playerId);try(ResultSet r=s.executeQuery()){require(r.next(),"unified player");
        o.playerX=new NUMBER(raw(r,1));o.playerY=new NUMBER(raw(r,2));o.playerZ=new NUMBER(raw(r,3));
        NUMBER angle=new NUMBER(raw(r,4));o.playerEyeZ=new NUMBER(raw(r,5));double degrees=angle.doubleValue();
        require(degrees>=0&&degrees<360,"unified player angle");o.playerAngleIndex=((int)Math.round(degrees/5.625d))&63;
        require(Math.abs(o.playerAngleIndex*5.625d-degrees)<1e-9,"unified player angle quantum");
        o.killCount=r.getInt(6);o.playerHealth=r.getInt(7);o.playerArmor=r.getInt(8);
        o.playerArmorType=r.getInt(9);o.playerAlive=r.getInt(10);o.playerSector=r.getInt(11);}}
    try(PreparedStatement s=c.prepareStatement("select count(*) from mobjs where session_token=? and mobj_id=?")){
      s.setString(1,session);s.setInt(2,o.playerId);try(ResultSet r=s.executeQuery()){r.next();
        o.playerTarget=r.getInt(1)==0?-1:o.playerId;}}
    try(PreparedStatement s=c.prepareStatement("select coalesce(max(mobj_id),0)+1 from mobjs where session_token=?")){
      s.setString(1,session);try(ResultSet r=s.executeQuery()){r.next();o.nextMobj=r.getInt(1);}}
    // current_tic is already accepted; a new resulting tic always starts event ordinals at zero.
    o.nextEvent=0;
    try(PreparedStatement s=c.prepareStatement("select count(*) from game_events where session_token=? "+
        "and tic=? and event_type in('DAMAGE','BARREL_EXPLODE','PROJECTILE_SPAWN','PROJECTILE_IMPACT','DRY_FIRE')")){
      s.setString(1,session);s.setLong(2,o.tic);try(ResultSet r=s.executeQuery()){r.next();o.playerSound=r.getInt(1)>0?1:0;}}

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
    o.world=loadWorld(c,session,stateIndex);
    HashMap<Integer,Integer> behavior=new HashMap<Integer,Integer>();
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_monster_def")){r.next();int n=r.getInt(1);
      o.behaviorThing=new int[n];o.behaviorDeathState=new int[n];o.behaviorDropThing=new int[n];
      o.behaviorSpeed=new NUMBER[n];o.behaviorMeleeRange=new NUMBER[n];o.behaviorAttack=new String[n];
      o.behaviorPainChance=new int[n];o.behaviorDamageBase=new int[n];o.behaviorDamageDice=new int[n];
      o.behaviorProjectileThing=new int[n];
      o.behaviorState=new int[6][n];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select thing_type,"+
        "utl_raw.cast_from_number(speed),attack_kind,see_state_id,chase_state_id,melee_state_id,"+
        "missile_state_id,pain_state_id,death_state_id,coalesce(drop_thing_type,-1),pain_chance,"+
        "utl_raw.cast_from_number(melee_range),damage_base,damage_dice,coalesce(projectile_thing_type,-1) " +
        "from doom_monster_def order by thing_type")){int i=0;while(r.next()){
      o.behaviorThing[i]=r.getInt(1);o.behaviorSpeed[i]=new NUMBER(raw(r,2));o.behaviorAttack[i]=r.getString(3);
      for(int k=0;k<6;k++){String state=r.getString(4+k);Integer mapped=state==null?null:stateIndex.get(state);
        require(state==null||mapped!=null,"unified behavior state");o.behaviorState[k][i]=mapped==null?-1:mapped.intValue();}
      o.behaviorDeathState[i]=o.behaviorState[5][i];o.behaviorDropThing[i]=r.getInt(10);
      o.behaviorPainChance[i]=r.getInt(11);o.behaviorMeleeRange[i]=new NUMBER(raw(r,12));
      o.behaviorDamageBase[i]=r.getInt(13);o.behaviorDamageDice[i]=r.getInt(14);
      o.behaviorProjectileThing[i]=r.getInt(15);
      behavior.put(Integer.valueOf(o.behaviorThing[i]),Integer.valueOf(i++));}}

    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_thing_type_def")){
      r.next();int size=r.getInt(1);o.spawnThing=new int[size];o.spawnState=new int[size];
      o.spawnRadius=new NUMBER[size];o.spawnHeight=new NUMBER[size];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select thing_type,spawn_state_id,"+
        "utl_raw.cast_from_number(coalesce(radius,8)),utl_raw.cast_from_number(coalesce(height,8)) "+
        "from doom_thing_type_def order by thing_type")){int i=0;while(r.next()){
      o.spawnThing[i]=r.getInt(1);String state=r.getString(2);Integer si=state==null?null:stateIndex.get(state);
      require(state==null||si!=null,"unified spawn state");o.spawnState[i]=si==null?-1:si.intValue();
      o.spawnRadius[i]=new NUMBER(raw(r,3));o.spawnHeight[i]=new NUMBER(raw(r,4));i++;}}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_projectile_def")){
      r.next();int size=r.getInt(1);o.projectileThing=new int[size];o.projectileState=new int[size];
      o.projectileSpeed=new NUMBER[size];o.projectileRadius=new NUMBER[size];o.projectileHeight=new NUMBER[size];
      o.projectileKind=new String[size];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select thing_type,spawn_state_id,projectile_kind,"+
        "utl_raw.cast_from_number(speed),utl_raw.cast_from_number(radius),utl_raw.cast_from_number(height) "+
        "from doom_projectile_def order by thing_type")){int i=0;while(r.next()){
      o.projectileThing[i]=r.getInt(1);Integer si=stateIndex.get(r.getString(2));require(si!=null,"unified projectile state");
      o.projectileState[i]=si.intValue();o.projectileKind[i]=r.getString(3);
      o.projectileSpeed[i]=new NUMBER(raw(r,4));o.projectileRadius[i]=new NUMBER(raw(r,5));
      o.projectileHeight[i]=new NUMBER(raw(r,6));i++;}}
    try(PreparedStatement s=c.prepareStatement("select count(*) from mobjs m join doom_monster_def d " +
        "on d.thing_type=m.thing_type where m.session_token=?")){s.setString(1,session);
      try(ResultSet r=s.executeQuery()){r.next();o.count=r.getInt(1);}}
    int n=o.count;o.id=new int[n];o.thingType=new int[n];o.stateIndex=new int[n];o.stateTics=new int[n];
    o.health=new int[n];o.flags=new int[n];o.target=new int[n];o.sector=new int[n];o.direction=new int[n];
    o.awake=new int[n];o.cooldown=new int[n];o.healthSeen=new int[n];o.deathProcessed=new int[n];
    o.behaviorIndex=new int[n];o.x=new NUMBER[n];o.y=new NUMBER[n];o.z=new NUMBER[n];
    o.radius=new NUMBER[n];o.height=new NUMBER[n];o.worldSlot=new int[n];o.visibilityCache=new int[n];
    Arrays.fill(o.visibilityCache,-1);
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
        o.behaviorIndex[i]=bi.intValue();o.worldSlot[i]=o.world.slot(o.id[i]);
        require(o.worldSlot[i]>=0,"unified actor world slot");i++;}require(i==n,"unified actor rows");}}
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
      committed=candidate;spare=candidate.copy();int renderCapacity=4096;
      renderOp=new int[renderCapacity];renderId=new int[renderCapacity];renderState=new int[renderCapacity];
      renderX=new NUMBER[renderCapacity];renderY=new NUMBER[renderCapacity];renderZ=new NUMBER[renderCapacity];
      renderAngle=new NUMBER[renderCapacity];
      lastError="";return "OK|"+candidate.count+"|"+candidate.tic+"|"+
          candidate.seq+"|"+candidate.rng+"|"+candidate.nextMobj+"|"+candidate.nextEvent;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
  }

  private static void invalidateForRecovery(){
    pending=null;pendingRequest=null;pendingChild=null;pendingMode=0;committed=null;spare=null;
    lastRenderUpserts=lastRenderRemoves=0;DoomFreshDeathTickBench.invalidateForRecovery();
  }
  public static String forceLoad(String session,String lineage,long generation,String stateMapSha){
    long priorGeneration=committed==null?0:committed.generation;
    try{invalidateForRecovery();require(generation>priorGeneration,"owner recovery generation");
      String result=load(session,lineage,generation,stateMapSha);
      if(!result.startsWith("OK|")){invalidateForRecovery();return result;}
      lastError="";return result;
    }catch(Throwable e){invalidateForRecovery();lastError=e.getClass().getName()+":"+e.getMessage();
      return "ERR|"+lastError;}
  }
  public static String forceRestore(String session,String lineage,long generation,String stateMapSha,
      Blob checkpoint){
    long priorGeneration=committed==null?0:committed.generation;
    invalidateForRecovery();
    try{require(generation>priorGeneration&&checkpoint!=null&&checkpoint.length()<=1048576,
          "owner recovery checkpoint");
      String loaded=load(session,lineage,generation,stateMapSha);
      require(loaded.startsWith("OK|"),"owner recovery SQL "+loaded);
      byte[] packed=checkpoint.getBytes(1,(int)checkpoint.length());
      Owner restored=ownerBytes(committed,packed,true);
      committed=restored;spare=restored.copy();String parity=ownerSqlParity(session,lineage,generation);
      require(parity.startsWith("OK|"),"owner recovery checkpoint/SQL mismatch "+parity);
      String chase=DoomMonsterChaseBench.acceptWorld(session,lineage,generation,
          "00000000000000000000000000000000",chasePack(restored));
      require("OK".equals(chase),"owner recovery checkpoint chase "+chase);lastError="";
      return "OK|"+restored.count+"|"+restored.tic+"|"+restored.seq+"|"+generation;
    }catch(Throwable e){invalidateForRecovery();lastError=e.getClass().getName()+":"+e.getMessage();
      return "ERR|"+lastError;}
  }
  public static String recoveryStatus(String session,String lineage,long generation){
    try{require(committed!=null&&pending==null&&committed.session.equals(session)&&
          committed.lineage.equals(lineage)&&committed.generation==generation,
          "owner recovery status");return "OK|"+committed.tic+"|"+committed.seq+"|"+
          committed.generation+"|"+committed.stateMapSha;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
  }
  public static String recoverSqlAndRenderer(String session,String lineage,long generation,
      String stateMapSha,Blob rendererSnapshot){
    try{String owner=forceLoad(session,lineage,generation,stateMapSha);
      require(owner.startsWith("OK|"),"recovery owner SQL "+owner);
      String renderer=DoomRetainedRenderSceneBench.forceLoadFenced(session,generation,stateMapSha,
          committed.tic,committed.seq,rendererSnapshot);
      require(renderer.startsWith("OK|"),"recovery renderer "+renderer);
      lastError="";return "OK|"+committed.tic+"|"+committed.seq+"|"+generation;
    }catch(Throwable e){DoomRetainedRenderSceneBench.invalidateForRecovery();invalidateForRecovery();
      lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
  }
  public static String recoverCheckpointAndRenderer(String session,String lineage,long generation,
      String stateMapSha,Blob checkpoint,Blob rendererSnapshot){
    try{String owner=forceRestore(session,lineage,generation,stateMapSha,checkpoint);
      require(owner.startsWith("OK|"),"recovery owner checkpoint "+owner);
      String renderer=DoomRetainedRenderSceneBench.forceLoadFenced(session,generation,stateMapSha,
          committed.tic,committed.seq,rendererSnapshot);
      require(renderer.startsWith("OK|"),"recovery renderer "+renderer);
      lastError="";return "OK|"+committed.tic+"|"+committed.seq+"|"+generation;
    }catch(Throwable e){DoomRetainedRenderSceneBench.invalidateForRecovery();invalidateForRecovery();
      lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
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
    if(o.visibilityCache[i]>=0)return o.visibilityCache[i]==1;
    int value=DoomRetainedLosBench.visible(o.x[i],o.y[i],o.sector[i],
        o.playerX,o.playerY,o.playerSector);
    require(value>=0,"unified attack LOS "+DoomRetainedLosBench.lastError());o.visibilityCache[i]=value;
    return value==1;
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

  private static final class TicSpawn{
    int id,thing,state,tics,health=1,flags=0,target=-1,tracer=-1,reaction=0,spawnThing=-1;
    int owner,exploded=0,sector;NUMBER x,y,z,mx,my,mz,radius,height;String kind;
  }
  private static int find(int[] values,int value){
    int low=0,high=values.length-1;while(low<=high){int mid=(low+high)>>>1;
      if(values[mid]==value)return mid;if(values[mid]<value)low=mid+1;else high=mid-1;}return -1;
  }
  private static TicSpawn drop(Owner o,int actor,int thing)throws Exception{
    int d=find(o.spawnThing,thing);require(d>=0&&o.spawnState[d]>=0,"unified TIC drop def");TicSpawn s=new TicSpawn();
    s.id=o.nextMobj++;s.thing=thing;s.state=o.spawnState[d];s.tics=o.stateDefaultTics[s.state];
    s.x=o.x[actor];s.y=o.y[actor];s.z=o.z[actor];s.mx=NUMBER.zero();s.my=NUMBER.zero();s.mz=NUMBER.zero();
    s.radius=o.spawnRadius[d];s.height=o.spawnHeight[d];s.owner=o.id[actor];s.sector=o.sector[actor];return s;
  }
  private static TicSpawn projectile(Owner o,int actor,int thing)throws Exception{
    int p=find(o.projectileThing,thing);require(p>=0,"unified TIC projectile def");TicSpawn s=new TicSpawn();
    s.id=o.nextMobj++;s.thing=thing;s.state=o.projectileState[p];s.tics=o.stateDefaultTics[s.state];
    s.x=o.x[actor];s.y=o.y[actor];s.z=o.z[actor].add(new NUMBER(32));s.mz=NUMBER.zero();
    NUMBER dx=o.playerX.sub(o.x[actor]),dy=o.playerY.sub(o.y[actor]);
    NUMBER length=dx.mul(dx).add(dy.mul(dy)).sqroot();
    if(length.isZero()){s.mx=NUMBER.zero();s.my=NUMBER.zero();}
    else{s.mx=dx.mul(o.projectileSpeed[p]).div(length);s.my=dy.mul(o.projectileSpeed[p]).div(length);}
    s.radius=o.projectileRadius[p];s.height=o.projectileHeight[p];s.owner=o.id[actor];
    s.kind=o.projectileKind[p];s.sector=o.sector[actor];return s;
  }
  private static void ticAttack(Owner o,int actor,int bi,int[] draws,
      ArrayList<AttackEvent> events,ArrayList<TicSpawn> spawns)throws Exception{
    NUMBER range=distance(o,actor);String kind=o.behaviorAttack[bi];
    if("MELEE".equals(kind)&&range.compareTo(o.behaviorMeleeRange[bi])>0)return;
    if(!visible(o,actor))return;
    if("PROJECTILE".equals(kind)){
      TicSpawn spawn=projectile(o,actor,o.behaviorProjectileThing[bi]);spawns.add(spawn);
      int p=find(o.projectileThing,spawn.thing);
      events.add(new AttackEvent(o.nextEvent++,7,o.id[actor],spawn.id,o.projectileSpeed[p],spawn.kind));
    }else attack(o,actor,bi,draws,events);
  }
  private static byte[] chasePack(Owner o)throws Exception{
    byte[] out=new byte[8+o.count*58];out[0]='D';out[1]='M';out[2]='C';out[3]='H';out[4]=1;
    out[6]=(byte)(o.count>>>8);out[7]=(byte)o.count;
    for(int i=0;i<o.count;i++){int at=8+i*58;putInt(out,at,o.id[i]);byte[] xb=o.x[i].toBytes(),yb=o.y[i].toBytes();
      require(xb.length<=22&&yb.length<=22,"unified TIC chase NUMBER");out[at+4]=(byte)xb.length;
      System.arraycopy(xb,0,out,at+5,xb.length);out[at+27]=(byte)yb.length;
      System.arraycopy(yb,0,out,at+28,yb.length);putInt(out,at+50,o.sector[i]);putInt(out,at+54,o.direction[i]);}
    return out;
  }
  private static void putInt(byte[] b,int o,int v){b[o]=(byte)(v>>>24);b[o+1]=(byte)(v>>>16);b[o+2]=(byte)(v>>>8);b[o+3]=(byte)v;}
  private static void putLong(byte[] b,int o,long v){putInt(b,o,(int)(v>>>32));putInt(b,o+4,(int)v);}
  private static void putNumberFixed(byte[] b,int o,NUMBER value){byte[] raw=value.toBytes();
    require(raw.length>=1&&raw.length<=22,"command TIC NUMBER");b[o]=(byte)raw.length;
    System.arraycopy(raw,0,b,o+1,raw.length);Arrays.fill(b,o+1+raw.length,o+23,(byte)0);}
  private static int fastInt(int p,int v){putInt(ticOutput,p,v);return p+4;}
  private static int fastShort(int p,int v){ticOutput[p]=(byte)(v>>>8);ticOutput[p+1]=(byte)v;return p+2;}
  private static int fastLong(int p,long v){for(int i=7;i>=0;i--)ticOutput[p++]=(byte)(v>>>(i*8));return p;}
  private static int fastNumber(int p,NUMBER value){byte[] raw=value.toBytes();require(raw.length<=22,"TIC NUMBER");
    ticOutput[p++]=(byte)raw.length;System.arraycopy(raw,0,ticOutput,p,raw.length);
    Arrays.fill(ticOutput,p+raw.length,p+22,(byte)0);return p+22;}
  private static int fastText(int p,String value){if(value==null)return fastShort(p,65535);
    byte[] raw=value.getBytes(StandardCharsets.UTF_8);require(raw.length<=65534,"TIC text");p=fastShort(p,raw.length);
    System.arraycopy(raw,0,ticOutput,p,raw.length);return p+raw.length;}
  private static byte[] ticDelta(Owner o,String s,String l,long g,String request)throws Exception{
    long phase=System.nanoTime();
    if(priorHealthScratch.length!=o.count){priorHealthScratch=new int[o.count];moveMaskScratch=new int[o.count];}
    System.arraycopy(o.health,0,priorHealthScratch,0,o.count);Arrays.fill(moveMaskScratch,0);
    int[] priorHealth=priorHealthScratch,moveMask=moveMaskScratch;
    for(int i=0;i<o.count;i++)if(o.health[i]>0&&o.awake[i]==1){int state=o.stateIndex[i];
      if(o.stateTics[i]>1)continue;if(o.stateTics[i]==1)state=o.stateNext[state];
      if(state<0||!"CHASE".equals(o.stateAction[state]))continue;int bi=o.behaviorIndex[i];
      boolean attack=o.cooldown[i]==0&&("HITSCAN".equals(o.behaviorAttack[bi])||
          "PROJECTILE".equals(o.behaviorAttack[bi])||("MELEE".equals(o.behaviorAttack[bi])&&
          distance(o,i).compareTo(o.behaviorMeleeRange[bi])<=0));if(!attack)moveMask[i]=1;}
    byte[] moves=DoomMonsterChaseBench.prepareWorld(s,l,g,request,o.playerX,o.playerY,priorHealth,moveMask);
    require(moves.length>=8+o.count*58&&moves[5]==0,"unified TIC movement oracle");
    ticChaseNs+=System.nanoTime()-phase;phase=System.nanoTime();
    ArrayList<AttackEvent> events=new ArrayList<AttackEvent>();ArrayList<TicSpawn> spawns=new ArrayList<TicSpawn>();
    int[] draws=new int[]{0};
    for(int i=0;i<o.count;i++){
      int oldSeen=o.healthSeen[i]<0?o.health[i]:o.healthSeen[i],oldCooldown=o.cooldown[i];
      o.healthSeen[i]=o.health[i];o.cooldown[i]=Math.max(0,oldCooldown-1);int bi=o.behaviorIndex[i];
      if(o.health[i]==0){
        if(o.deathProcessed[i]==0){o.stateIndex[i]=o.behaviorState[5][bi];
          o.stateTics[i]=o.stateDefaultTics[o.stateIndex[i]];o.deathProcessed[i]=1;o.awake[i]=0;
          o.flags[i]=0;o.target[i]=-1;o.direction[i]=-1;o.killCount++;
          events.add(new AttackEvent(o.nextEvent++,4,o.id[i],-1,null,null));
          int thing=o.behaviorDropThing[bi];if(thing>=0){TicSpawn spawn=drop(o,i,thing);spawns.add(spawn);
            events.add(new AttackEvent(o.nextEvent++,5,o.id[i],spawn.id,new NUMBER(thing),null));}
        }else if(o.stateTics[i]>0){o.stateTics[i]--;if(o.stateTics[i]==0){int next=o.stateNext[o.stateIndex[i]];
          require(next>=0,"unified TIC corpse next");o.stateIndex[i]=next;o.stateTics[i]=o.stateDefaultTics[next];}}
        continue;
      }
      if(o.health[i]<oldSeen){int roll=draw(o,draws);if(roll<o.behaviorPainChance[bi]){
        o.stateIndex[i]=o.behaviorState[4][bi];o.stateTics[i]=o.stateDefaultTics[o.stateIndex[i]];
        o.awake[i]=1;events.add(new AttackEvent(o.nextEvent++,3,o.id[i],o.playerTarget,new NUMBER(roll),null));continue;}}
      if(o.awake[i]==0){boolean seen=visible(o,i),heard=o.playerSound==1&&
          DoomSimCatalogBench.soundReach(o.playerSector,o.sector[i])==1;
        if(heard||seen){o.awake[i]=1;o.target[i]=o.playerTarget;
          o.stateIndex[i]=o.behaviorState[0][bi];o.stateTics[i]=o.stateDefaultTics[o.stateIndex[i]];
          events.add(new AttackEvent(o.nextEvent++,6,o.id[i],o.playerTarget,null,seen?"SEEN":"HEARD"));
        }continue;
      }
      int state=o.stateIndex[i];String action;
      if(o.stateTics[i]>0){o.stateTics[i]--;if(o.stateTics[i]>0)continue;state=o.stateNext[state];
        require(state>=0,"unified TIC next");o.stateIndex[i]=state;o.stateTics[i]=o.stateDefaultTics[state];
        action=o.stateAction[state];}else action=o.stateAction[state];
      if("CHASE".equals(action)){
        boolean select=oldCooldown==0&&("HITSCAN".equals(o.behaviorAttack[bi])||
            "PROJECTILE".equals(o.behaviorAttack[bi])||("MELEE".equals(o.behaviorAttack[bi])&&
            distance(o,i).compareTo(o.behaviorMeleeRange[bi])<=0));
        if(select){state="MELEE".equals(o.behaviorAttack[bi])?o.behaviorState[2][bi]:o.behaviorState[3][bi];
          o.stateIndex[i]=state;o.stateTics[i]=o.stateDefaultTics[state];o.cooldown[i]=o.stateTics[i];
          ticAttack(o,i,bi,draws,events,spawns);
        }else{int at=8+i*58;o.x[i]=number(moves,at+4);o.y[i]=number(moves,at+27);
          o.sector[i]=int_(moves,at+50);o.direction[i]=int_(moves,at+54);o.visibilityCache[i]=-1;}
      }else if("MELEE".equals(action)||"HITSCAN".equals(action)||"PROJECTILE".equals(action))
        ticAttack(o,i,bi,draws,events,spawns);
    }
    for(int i=0;i<o.count;i++){int w=o.worldSlot[i];o.world.state[w]=o.stateIndex[i];
      o.world.tics[w]=o.stateTics[i];o.world.x[w]=o.x[i];o.world.y[w]=o.y[i];o.world.z[w]=o.z[i];
      o.world.health[w]=o.health[i];o.world.flags[w]=o.flags[i];o.world.target[w]=o.target[i];
      o.world.sector[w]=o.sector[i];o.world.direction[w]=o.direction[i];o.world.awake[w]=o.awake[i];
      o.world.cooldown[w]=o.cooldown[i];o.world.healthSeen[w]=o.healthSeen[i];
      o.world.deathProcessed[w]=o.deathProcessed[i];}
    for(TicSpawn spawn:spawns)o.world.append(spawn);
    ticLoopNs+=System.nanoTime()-phase;phase=System.nanoTime();
    int p=0;p=fastInt(p,0x44544943);ticOutput[p++]=1;ticOutput[p++]=0;p=fastShort(p,o.count);
    p=fastShort(p,spawns.size());p=fastShort(p,events.size());p=fastShort(p,draws[0]);p=fastShort(p,0);
    p=fastInt(p,o.rng);p=fastInt(p,o.playerHealth);p=fastInt(p,o.playerArmor);p=fastInt(p,o.playerAlive);
    p=fastInt(p,o.killCount);p=fastInt(p,o.nextMobj);p=fastInt(p,o.nextEvent);p=fastLong(p,o.tic+1);p=fastLong(p,o.seq+1);
    for(int i=0;i<o.count;i++){p=fastInt(p,o.id[i]);p=fastInt(p,o.healthSeen[i]);p=fastInt(p,o.cooldown[i]);
      p=fastInt(p,o.stateIndex[i]);p=fastInt(p,o.stateTics[i]);p=fastInt(p,o.deathProcessed[i]);
      p=fastInt(p,o.awake[i]);p=fastInt(p,o.flags[i]);p=fastInt(p,o.target[i]);p=fastInt(p,o.direction[i]);
      p=fastNumber(p,o.x[i]);p=fastNumber(p,o.y[i]);p=fastInt(p,o.sector[i]);}
    for(TicSpawn q:spawns){p=fastInt(p,q.id);p=fastInt(p,q.thing);p=fastInt(p,q.state);p=fastInt(p,q.tics);
      p=fastNumber(p,q.x);p=fastNumber(p,q.y);p=fastNumber(p,q.z);p=fastNumber(p,q.mx);p=fastNumber(p,q.my);
      p=fastNumber(p,q.mz);p=fastNumber(p,q.radius);p=fastNumber(p,q.height);p=fastInt(p,q.health);p=fastInt(p,q.flags);
      p=fastInt(p,q.target);p=fastInt(p,q.tracer);p=fastInt(p,q.reaction);p=fastInt(p,q.spawnThing);
      p=fastInt(p,q.owner);p=fastInt(p,q.exploded);p=fastInt(p,q.sector);p=fastText(p,q.kind);}
    for(AttackEvent e:events){p=fastInt(p,e.ordinal);p=fastInt(p,e.type);p=fastInt(p,e.actor);p=fastInt(p,e.target);
      ticOutput[p++]=(byte)(e.value==null?0:1);if(e.value!=null)p=fastNumber(p,e.value);
      else{Arrays.fill(ticOutput,p,p+23,(byte)0);p+=23;}p=fastText(p,e.text);}
    ticOutputLength=p;ticEncodeNs+=System.nanoTime()-phase;
    o.tic++;o.seq++;o.nextEvent=0;o.playerSound=0;return ticOutput;
  }

  /** One parity-locked DMSC/v2 movement command plus one ordered actor TIC. */
  public static byte[] prepareCommandTic(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command){
    try{
      fence(s,l,g,tic,seq,rng,nextMobj,nextEvent);require(pending==null&&request!=null&&
          request.matches("[0-9a-f]{32}"),"command TIC request");
      require(command!=null&&command.length==COMMAND_BYTES&&int_(command,0)==0x444d5343&&
          command[4]==2&&(command[5]&255)==1&&command[6]==0&&command[7]==0,"command TIC DMSC/v2 header");
      long commandSeq=long_(command,8);require(commandSeq==seq+1,"command TIC sequence gap");
      int turn=command[16],forward=command[17],strafe=command[18],run=command[19]&255;
      require(turn>=-1&&turn<=1&&forward>=-1&&forward<=1&&strafe>=-1&&strafe<=1&&run<=1,
          "command TIC movement domain");
      for(int i=20;i<24;i++)require(command[i]==0,"command TIC unsupported action/reserved");
      Owner candidate=spare;require(candidate!=null&&candidate!=committed,"command TIC spare");
      candidate.copyFrom(committed);candidate.playerAngleIndex=(candidate.playerAngleIndex+turn+64)&63;
      NUMBER oldX=candidate.playerX,oldY=candidate.playerY,oldZ=candidate.playerZ;
      String movement=DoomPlayerMovementBench.moveRetained(candidate.playerX,candidate.playerY,candidate.playerZ,
          candidate.playerAngleIndex,forward,strafe,run);
      require("OK".equals(movement),"command TIC movement "+DoomPlayerMovementBench.lastError());
      candidate.playerX=DoomPlayerMovementBench.resultX;candidate.playerY=DoomPlayerMovementBench.resultY;
      candidate.playerZ=DoomPlayerMovementBench.resultZ;
      candidate.playerEyeZ=candidate.playerEyeZ.add(candidate.playerZ.sub(oldZ));
      candidate.playerSector=DoomPlayerMovementBench.resultSector;
      if(oldX.compareTo(candidate.playerX)!=0||oldY.compareTo(candidate.playerY)!=0)
        Arrays.fill(candidate.visibilityCache,-1);
      long actorStarted=DoomPlayerMovementBench.traceEnabled?System.nanoTime():0;
      byte[] nested=ticDelta(candidate,s,l,g,request);
      if(DoomPlayerMovementBench.traceEnabled)lastActorTicNs=System.nanoTime()-actorStarted;
      int nestedLength=ticOutputLength;
      require(candidate.seq==commandSeq&&candidate.tic==tic+1,"command TIC resulting frontier");
      long encodeStarted=DoomPlayerMovementBench.traceEnabled?System.nanoTime():0;
      byte[] child=new byte[COMMAND_CHILD_HEADER+nestedLength];putInt(child,0,0x44435443);
      child[4]=1;child[5]=0;child[6]=0;child[7]=(byte)COMMAND_BYTES;
      putLong(child,8,candidate.seq);putLong(child,16,candidate.tic);putInt(child,24,candidate.playerAngleIndex);
      putNumberFixed(child,28,candidate.playerX);putNumberFixed(child,51,candidate.playerY);
      putNumberFixed(child,74,candidate.playerZ);putInt(child,97,candidate.playerSector);
      putInt(child,101,nestedLength);System.arraycopy(nested,0,child,COMMAND_CHILD_HEADER,nestedLength);
      byte[] result=wrap(MODE_COMMAND_TIC,child,child.length);pending=candidate;pendingRequest=request;
      if(DoomPlayerMovementBench.traceEnabled)lastCommandEncodeNs=System.nanoTime()-encodeStarted;
      pendingMode=MODE_COMMAND_TIC;
      pendingChild=null;lastError="";return result;
    }catch(Throwable e){return failure(e);}
  }
  private static void checkpointNumber(DataOutputStream out,NUMBER value)throws Exception{
    byte[] raw=value.toBytes();require(raw.length>=1&&raw.length<=22,"world checkpoint NUMBER");
    out.writeByte(raw.length);out.write(raw);
  }
  private static NUMBER checkpointNumber(DataInputStream in)throws Exception{
    int length=in.readUnsignedByte();require(length>=1&&length<=22,"world restore NUMBER");
    byte[] raw=new byte[length];in.readFully(raw);return new NUMBER(raw);
  }
  private static byte[] worldBytes(WorldMobjs w)throws Exception{
    ByteArrayOutputStream bytes=new ByteArrayOutputStream(32768);DataOutputStream out=new DataOutputStream(bytes);
    out.writeInt(0x44574d4a);out.writeInt(1);out.writeInt(w.count);
    for(int i=0;i<w.count;i++){
      int[] ints={w.id[i],w.thing[i],w.state[i],w.tics[i],w.health[i],w.flags[i],w.target[i],w.tracer[i],
        w.reaction[i],w.spawnThing[i],w.owner[i],w.exploded[i],w.sector[i],w.direction[i],w.awake[i],
        w.cooldown[i],w.healthSeen[i],w.deathProcessed[i]};for(int value:ints)out.writeInt(value);
      checkpointNumber(out,w.x[i]);checkpointNumber(out,w.y[i]);checkpointNumber(out,w.z[i]);
      checkpointNumber(out,w.mx[i]);checkpointNumber(out,w.my[i]);checkpointNumber(out,w.mz[i]);
      checkpointNumber(out,w.angle[i]);checkpointNumber(out,w.radius[i]);checkpointNumber(out,w.height[i]);
      out.writeBoolean(w.projectileKind[i]!=null);if(w.projectileKind[i]!=null)out.writeUTF(w.projectileKind[i]);
    }out.flush();return bytes.toByteArray();
  }
  private static WorldMobjs worldBytes(byte[] bytes)throws Exception{
    DataInputStream in=new DataInputStream(new ByteArrayInputStream(bytes));
    require(in.readInt()==0x44574d4a&&in.readInt()==1,"world restore header");int count=in.readInt();
    require(count>=0&&count<=65535,"world restore count");WorldMobjs w=new WorldMobjs(count);
    for(int i=0;i<count;i++){
      w.id[i]=in.readInt();w.thing[i]=in.readInt();w.state[i]=in.readInt();w.tics[i]=in.readInt();
      w.health[i]=in.readInt();w.flags[i]=in.readInt();w.target[i]=in.readInt();w.tracer[i]=in.readInt();
      w.reaction[i]=in.readInt();w.spawnThing[i]=in.readInt();w.owner[i]=in.readInt();w.exploded[i]=in.readInt();
      w.sector[i]=in.readInt();w.direction[i]=in.readInt();w.awake[i]=in.readInt();w.cooldown[i]=in.readInt();
      w.healthSeen[i]=in.readInt();w.deathProcessed[i]=in.readInt();w.x[i]=checkpointNumber(in);
      w.y[i]=checkpointNumber(in);w.z[i]=checkpointNumber(in);w.mx[i]=checkpointNumber(in);
      w.my[i]=checkpointNumber(in);w.mz[i]=checkpointNumber(in);w.angle[i]=checkpointNumber(in);
      w.radius[i]=checkpointNumber(in);w.height[i]=checkpointNumber(in);
      w.projectileKind[i]=in.readBoolean()?in.readUTF():null;
      require(w.slot.put(Integer.valueOf(w.id[i]),Integer.valueOf(i))==null,"world restore duplicate");
    }require(in.available()==0,"world restore trailing");return w;
  }
  private static void bindMonsters(Owner o){
    Arrays.fill(o.visibilityCache,-1);
    for(int i=0;i<o.count;i++){int slot=o.world.slot(o.id[i]);require(slot>=0,"world monster missing");
      o.worldSlot[i]=slot;o.stateIndex[i]=o.world.state[slot];o.stateTics[i]=o.world.tics[slot];
      o.x[i]=o.world.x[slot];o.y[i]=o.world.y[slot];o.z[i]=o.world.z[slot];o.radius[i]=o.world.radius[slot];
      o.height[i]=o.world.height[slot];o.health[i]=o.world.health[slot];o.flags[i]=o.world.flags[slot];
      o.target[i]=o.world.target[slot];o.sector[i]=o.world.sector[slot];o.direction[i]=o.world.direction[slot];
      o.awake[i]=o.world.awake[slot];o.cooldown[i]=o.world.cooldown[slot];
      o.healthSeen[i]=o.world.healthSeen[slot];o.deathProcessed[i]=o.world.deathProcessed[slot];}
  }
  private static void validateWorld(Owner o,WorldMobjs w){
    for(int i=0;i<w.count;i++){require(i==0||w.id[i]>w.id[i-1],"world id order");
      require(w.state[i]>=0&&w.state[i]<o.stateId.length,"world state bounds");
      require(w.x[i]!=null&&w.y[i]!=null&&w.z[i]!=null&&w.mx[i]!=null&&w.my[i]!=null&&w.mz[i]!=null&&
          w.angle[i]!=null&&w.radius[i]!=null&&w.height[i]!=null,"world NUMBER null");
      require(w.id[i]>=0&&w.thing[i]>=0&&w.tics[i]>=-1&&w.health[i]>=0&&w.flags[i]>=0&&
          w.reaction[i]>=0&&w.radius[i].compareTo(NUMBER.zero())>=0&&w.height[i].compareTo(NUMBER.zero())>=0&&
          w.angle[i].compareTo(NUMBER.zero())>=0&&w.angle[i].compareTo(new NUMBER(360))<0,
          "world scalar");
      require(w.direction[i]>=-1&&w.direction[i]<=7&&(w.awake[i]==0||w.awake[i]==1)&&w.cooldown[i]>=0&&
          w.healthSeen[i]>=-1&&(w.deathProcessed[i]==0||w.deathProcessed[i]==1)&&
          (w.exploded[i]==0||w.exploded[i]==1)&&w.sector[i]>=-1,"world runtime scalar");
      require((w.target[i]<0||w.slot(w.target[i])>=0)&&(w.tracer[i]<0||w.slot(w.tracer[i])>=0)&&
          (w.owner[i]<0||w.slot(w.owner[i])>=0),"world pointer");}
    for(int i=0;i<o.count;i++){int slot=w.slot(o.id[i]);require(slot>=0&&w.thing[slot]==o.thingType[i],
        "world monster identity");}
  }
  private static byte[] ownerBytes(Owner o)throws Exception{
    byte[] world=worldBytes(o.world);ByteArrayOutputStream bytes=new ByteArrayOutputStream(world.length+256);
    DataOutputStream out=new DataOutputStream(bytes);out.writeInt(0x44574350);out.writeInt(3);
    out.writeUTF(o.session);out.writeUTF(o.lineage);out.writeUTF(o.stateMapSha);out.writeLong(o.generation);
    out.writeLong(o.tic);out.writeLong(o.seq);out.writeInt(o.rng);out.writeInt(o.nextMobj);out.writeInt(o.nextEvent);
    out.writeInt(o.playerId);out.writeInt(o.playerTarget);out.writeInt(o.killCount);out.writeInt(o.playerHealth);
    out.writeInt(o.playerArmor);out.writeInt(o.playerArmorType);out.writeInt(o.playerAlive);out.writeInt(o.playerSector);
    out.writeInt(o.playerAngleIndex);
    out.writeInt(o.playerSound);checkpointNumber(out,o.playerX);checkpointNumber(out,o.playerY);
    checkpointNumber(out,o.playerZ);checkpointNumber(out,o.playerEyeZ);
    out.writeInt(world.length);out.write(world);out.flush();return bytes.toByteArray();
  }
  private static Owner ownerBytes(Owner base,byte[] packed)throws Exception{
    return ownerBytes(base,packed,false);
  }
  private static Owner ownerBytes(Owner base,byte[] packed,boolean recovery)throws Exception{
    DataInputStream in=new DataInputStream(new ByteArrayInputStream(packed));
    require(in.readInt()==0x44574350&&in.readInt()==3,"owner restore header");Owner o=base.copy();
    require(o.session.equals(in.readUTF())&&o.lineage.equals(in.readUTF())&&o.stateMapSha.equals(in.readUTF()),
        "owner restore identity");long packedGeneration=in.readLong();
    require(recovery?packedGeneration>0&&packedGeneration<o.generation:o.generation==packedGeneration,
        "owner restore generation");
    o.tic=in.readLong();o.seq=in.readLong();o.rng=in.readInt();o.nextMobj=in.readInt();o.nextEvent=in.readInt();
    require(o.nextEvent==0,"owner restore event frontier");
    o.playerId=in.readInt();o.playerTarget=in.readInt();o.killCount=in.readInt();o.playerHealth=in.readInt();
    o.playerArmor=in.readInt();o.playerArmorType=in.readInt();o.playerAlive=in.readInt();o.playerSector=in.readInt();
    o.playerAngleIndex=in.readInt();require(o.playerAngleIndex>=0&&o.playerAngleIndex<64,"owner restore angle");
    o.playerSound=in.readInt();o.playerX=checkpointNumber(in);o.playerY=checkpointNumber(in);o.playerZ=checkpointNumber(in);
    o.playerEyeZ=checkpointNumber(in);
    int length=in.readInt();require(length>=12&&length<=1048576,"owner world length");byte[] world=new byte[length];
    in.readFully(world);require(in.available()==0,"owner restore trailing");o.world=worldBytes(world);validateWorld(o,o.world);
    bindMonsters(o);return o;
  }
  public static String worldCheckpoint(String s,String l,long g,Blob output){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&output!=null,"world checkpoint fence");byte[] bytes=ownerBytes(committed);
      output.truncate(0);output.setBytes(1,bytes);return "OK|"+committed.world.count+"|"+bytes.length+"|"+
        hex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  public static String worldRestore(String s,String l,long g,Blob input){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&input!=null&&input.length()<=1048576,"world restore fence");
      byte[] packed=input.getBytes(1,(int)input.length());Owner restored=ownerBytes(committed,packed);
      require(Arrays.equals(packed,ownerBytes(restored)),"owner restore canonical");
      String chase=DoomMonsterChaseBench.acceptWorld(s,l,g,"00000000000000000000000000000000",chasePack(restored));
      require("OK".equals(chase),"world restore chase "+chase);committed=restored;lastError="";
      return "OK|"+restored.world.count+"|"+packed.length;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  public static String worldSqlParity(String s,String l,long g){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g,"world SQL parity fence");HashMap<String,Integer> states=new HashMap<String,Integer>();
      for(int i=0;i<committed.stateId.length;i++)states.put(committed.stateId[i],Integer.valueOf(i));
      WorldMobjs sql=loadWorld(DriverManager.getConnection("jdbc:default:connection:"),s,states);
      require(Arrays.equals(worldBytes(committed.world),worldBytes(sql)),"world SQL parity");
      return "OK|"+sql.count;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  public static String ownerSqlParity(String s,String l,long g){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&committed.nextEvent==0,"owner SQL parity fence");
      Connection c=DriverManager.getConnection("jdbc:default:connection:");
      try(PreparedStatement p=c.prepareStatement("select current_tic,last_command_seq,rng_cursor from game_sessions where session_token=?")){
        p.setString(1,s);try(ResultSet r=p.executeQuery()){require(r.next()&&r.getLong(1)==committed.tic&&
            r.getLong(2)==committed.seq&&r.getInt(3)==committed.rng,"owner SQL session");}}
      try(PreparedStatement p=c.prepareStatement("select utl_raw.cast_from_number(x),utl_raw.cast_from_number(y),"+
          "utl_raw.cast_from_number(z),utl_raw.cast_from_number(angle),"+
          "utl_raw.cast_from_number(z+view_height+view_bob),health,armor,armor_type,alive,kill_count " +
          ",(select sector_id from table(doom_bsp_locate(p.x,p.y)) where rownum=1) " +
          "from players p where session_token=? and player_id=?")){p.setString(1,s);p.setInt(2,committed.playerId);
        try(ResultSet r=p.executeQuery()){require(r.next(),"owner SQL player");NUMBER angle=new NUMBER((long)committed.playerAngleIndex*5625L).div(new NUMBER(1000));
          require(committed.playerX.compareTo(new NUMBER(raw(r,1)))==0&&committed.playerY.compareTo(new NUMBER(raw(r,2)))==0&&
              committed.playerZ.compareTo(new NUMBER(raw(r,3)))==0&&angle.compareTo(new NUMBER(raw(r,4)))==0&&
              committed.playerEyeZ.compareTo(new NUMBER(raw(r,5)))==0&&committed.playerHealth==r.getInt(6)&&
              committed.playerArmor==r.getInt(7)&&committed.playerArmorType==r.getInt(8)&&
              committed.playerAlive==r.getInt(9)&&committed.killCount==r.getInt(10)&&
              committed.playerSector==r.getInt(11),"owner SQL player state");}}
      HashMap<String,Integer> states=new HashMap<String,Integer>();for(int i=0;i<committed.stateId.length;i++)
        states.put(committed.stateId[i],Integer.valueOf(i));WorldMobjs sql=loadWorld(c,s,states);
      require(Arrays.equals(worldBytes(committed.world),worldBytes(sql)),"owner SQL world");
      try(PreparedStatement p=c.prepareStatement("select coalesce(max(mobj_id),0)+1 from mobjs where session_token=?")){
        p.setString(1,s);try(ResultSet r=p.executeQuery()){require(r.next()&&r.getInt(1)==committed.nextMobj,"owner SQL mobj frontier");}}
      return "OK|"+committed.tic+"|"+committed.seq+"|"+sql.count;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  public static String worldSpawnRemoveProbe(String s,String l,long g){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&committed.world.count>0,"world append fence");WorldMobjs w=committed.world.copy();
      byte[] before=worldBytes(w);int source=w.count-1;TicSpawn p=new TicSpawn();p.id=committed.nextMobj;
      p.thing=w.thing[source];p.state=w.state[source];p.tics=w.tics[source];p.health=w.health[source];
      p.flags=w.flags[source];p.target=w.target[source];p.tracer=w.tracer[source];p.reaction=w.reaction[source];
      p.spawnThing=w.spawnThing[source];p.owner=w.owner[source];p.exploded=w.exploded[source];p.sector=w.sector[source];
      p.x=w.x[source];p.y=w.y[source];p.z=w.z[source];p.mx=w.mx[source];p.my=w.my[source];p.mz=w.mz[source];
      p.radius=w.radius[source];p.height=w.height[source];p.kind=w.projectileKind[source];w.append(p);
      byte[] appended=worldBytes(w);WorldMobjs restored=worldBytes(appended);require(restored.count==w.count&&
          restored.slot(p.id)==w.count-1,"world append restore");int oldTarget=restored.target[0];
      int oldTracer=restored.tracer[0],oldOwner=restored.owner[0];restored.target[0]=p.id;
      restored.tracer[0]=p.id;restored.owner[0]=p.id;restored.remove(p.id);
      require(restored.target[0]==-1&&restored.tracer[0]==-1&&restored.owner[0]==-1,
          "world pointer detach");restored.target[0]=oldTarget;restored.tracer[0]=oldTracer;restored.owner[0]=oldOwner;
      require(Arrays.equals(before,worldBytes(restored)),"world remove roundtrip");return "OK|"+
          committed.world.count+"|"+w.count+"|"+before.length+"|"+appended.length;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}

  public static byte[] prepare(String s,String l,long g,String request,String mode,long tic,long seq,
      int rng,int nextMobj,int nextEvent){
    boolean deathPrepared=false;
    try{
      fence(s,l,g,tic,seq,rng,nextMobj,nextEvent);require(pending==null&&request!=null&&
          request.matches("[0-9a-f]{32}"),"unified request");Owner candidate=spare;
      require(candidate!=null&&candidate!=committed,"unified spare");candidate.copyFrom(committed);
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
      }else if("TIC".equals(mode)){
        selected=MODE_TIC;child=ticDelta(candidate,s,l,g,request);childLength=ticOutputLength;
      }else throw new IllegalStateException("unified mode");
      byte[] result=wrap(selected,child,childLength);pending=candidate;pendingRequest=request;
      pendingMode=selected;pendingChild=selected==MODE_TIC?null:Arrays.copyOf(child,childLength);
      lastError="";return result;
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
      else if(pendingMode==MODE_CHASE||pendingMode==MODE_TIC||pendingMode==MODE_COMMAND_TIC)
        child=DoomMonsterChaseBench.acceptWorld(s,l,g,request,
            pendingMode==MODE_CHASE?pendingChild:chasePack(pending));
      require("OK".equals(child)||child.startsWith("OK|"),"unified child accept "+child);
      if(DoomRetainedRenderSceneBench.ownerTicPending())require("OK".equals(
          DoomRetainedRenderSceneBench.acceptOwnerTic(s,g,request)),"unified renderer accept");
      Owner previous=committed;committed=pending;spare=previous;pending=null;pendingRequest=null;
      pendingChild=null;lastError="";return "OK";
    }catch(Throwable e){try{if(DoomRetainedRenderSceneBench.ownerTicPending())
        DoomRetainedRenderSceneBench.discardOwnerTic(s,g,request);}catch(Throwable ignored){}
      lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}

  public static String discard(String s,String l,long g,String request){
    try{require(committed!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&pending!=null&&request!=null&&request.equals(pendingRequest),
        "unified pending");if(pendingMode==MODE_DEATH){String child=DoomFreshDeathTickBench.discard(s,l,g,request);
        require("OK".equals(child),"unified child discard "+child);}
      if(DoomRetainedRenderSceneBench.ownerTicPending())require("OK".equals(
          DoomRetainedRenderSceneBench.discardOwnerTic(s,g,request)),"unified renderer discard");
      spare=pending;pending=null;pendingRequest=null;
      pendingChild=null;lastError="";return "OK";
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  public static String renderPending(String s,String l,long g,String request,String stateSha,Blob payload){
    try{require(committed!=null&&pending!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&request!=null&&request.equals(pendingRequest)&&
        (pendingMode==MODE_TIC||pendingMode==MODE_COMMAND_TIC),"unified render pending fence");
      int dirty=0,old=0,next=0;lastRenderUpserts=lastRenderRemoves=0;
      WorldMobjs before=committed.world,after=pending.world;
      while(old<before.count||next<after.count){int oldId=old<before.count?before.id[old]:Integer.MAX_VALUE;
        int nextId=next<after.count?after.id[next]:Integer.MAX_VALUE;
        if(oldId<nextId){require(dirty<renderId.length,"unified render diff capacity");renderOp[dirty]=0;
          renderId[dirty]=oldId;renderState[dirty]=0;renderX[dirty]=renderY[dirty]=renderZ[dirty]=renderAngle[dirty]=null;
          dirty++;lastRenderRemoves++;old++;continue;}
        if(nextId<oldId){require(dirty<renderId.length,"unified render diff capacity");renderOp[dirty]=1;
          renderId[dirty]=nextId;renderState[dirty]=after.state[next];renderX[dirty]=after.x[next];
          renderY[dirty]=after.y[next];renderZ[dirty]=after.z[next];renderAngle[dirty]=after.angle[next];
          dirty++;lastRenderUpserts++;next++;continue;}
        if(before.state[old]!=after.state[next]||before.x[old]!=after.x[next]||before.y[old]!=after.y[next]||
            before.z[old]!=after.z[next]||before.angle[old]!=after.angle[next]){
          require(dirty<renderId.length,"unified render diff capacity");renderOp[dirty]=1;renderId[dirty]=nextId;
          renderState[dirty]=after.state[next];renderX[dirty]=after.x[next];renderY[dirty]=after.y[next];
          renderZ[dirty]=after.z[next];renderAngle[dirty]=after.angle[next];dirty++;lastRenderUpserts++;}old++;next++;}
      String result=DoomRetainedRenderSceneBench.stageOwnerTic(s,g,request,pending.tic,pending.seq,
        pending.playerX,pending.playerY,pending.playerEyeZ,pending.playerAngleIndex,pending.playerHealth,
        pending.playerArmor,pending.playerAlive,dirty,renderOp,renderId,renderState,renderX,renderY,
        renderZ,renderAngle,stateSha,payload);
      require(result!=null&&!result.startsWith("ERROR:")&&!result.startsWith("ERR|"),
          "unified renderer stage "+DoomRetainedRenderSceneBench.lastError());lastError="";return result;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}return "ERR|"+lastError;}}
  public static int lastRenderUpserts(){return lastRenderUpserts;}
  public static int lastRenderRemoves(){return lastRenderRemoves;}
  public static String benchmark(String s,String l,long g,String mode,long tic,long seq,int rng,
      int nextMobj,int nextEvent,Clob targets,int iterations){
    NUMBER savedX=null,savedY=null;int savedSector=-1;String activeRequest=null;
    try{
      fence(s,l,g,tic,seq,rng,nextMobj,nextEvent);require(pending==null&&iterations==300&&
          ("CHASE".equals(mode)||"ATTACK".equals(mode)||"TIC".equals(mode)),"unified benchmark");
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
      if("TIC".equals(mode)){ticChaseNs=0;ticLoopNs=0;ticEncodeNs=0;}
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
      Arrays.sort(times);lastError="";String phases="TIC".equals(mode)?"|"+(ticChaseNs/320)+"|"+
          (ticLoopNs/320)+"|"+(ticEncodeNs/320):"";return "OK|"+mode+"|"+iterations+"|"+bytes+"|"+
          times[149]+"|"+times[284]+"|"+times[299]+phases;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
    finally{if(activeRequest!=null&&activeRequest.equals(pendingRequest)){
        pending=null;pendingRequest=null;pendingChild=null;}
      if(savedX!=null&&committed!=null){committed.playerX=savedX;committed.playerY=savedY;
      committed.playerSector=savedSector;}}
  }
  public static String benchmarkAcceptedTics(String s,String l,long g,int iterations){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&iterations==300,"accepted TIC benchmark");long[] times=new long[iterations];
      int bytes=0;for(int sample=-20;sample<iterations;sample++){String request=String.format("%032x",sample+21);
        long started=System.nanoTime();byte[] delta=prepare(s,l,g,request,"TIC",committed.tic,committed.seq,
          committed.rng,committed.nextMobj,committed.nextEvent);require(delta[5]==0,"accepted TIC prepare");
        String accepted=accept(s,l,g,request);require("OK".equals(accepted),"accepted TIC accept");
        long elapsed=System.nanoTime()-started;if(sample>=0){times[sample]=elapsed;bytes=delta.length;}}
      Arrays.sort(times);return "OK|TIC_ACCEPT|"+iterations+"|"+bytes+"|"+times[149]+"|"+
          times[284]+"|"+times[299]+"|"+committed.tic+"|"+committed.seq;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  private static byte[] movementCommand(long seq,int turn,int forward,int strafe,int run){
    byte[] command=new byte[COMMAND_BYTES];putInt(command,0,0x444d5343);command[4]=2;command[5]=1;
    putLong(command,8,seq);command[16]=(byte)turn;command[17]=(byte)forward;
    command[18]=(byte)strafe;command[19]=(byte)run;return command;
  }
  public static String benchmarkAcceptedCommandTics(String s,String l,long g,int iterations,int warmups){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&iterations==300&&(warmups==0||warmups==20),"accepted command TIC benchmark");
      long[] times=new long[iterations],candidateNs=new long[iterations],sideNs=new long[iterations];
      long[] interiorNs=new long[iterations],endpointNs=new long[iterations],portalNs=new long[iterations];
      long[] actorNs=new long[iterations],encodeNs=new long[iterations];long candidateCount=0,sideCount=0;
      long interiorCount=0,endpointCount=0;int bytes=0;
      for(int sample=-warmups;sample<iterations;sample++){long next=committed.seq+1;
        byte[] command=movementCommand(next,(sample%17==0)?1:(sample%11==0?-1:0),(sample&1)==0?1:-1,
            sample%19==0?1:0,sample%5==0?1:0);String request=String.format("%032x",sample+21);
        long started=System.nanoTime();byte[] delta=prepareCommandTic(s,l,g,request,committed.tic,committed.seq,
          committed.rng,committed.nextMobj,committed.nextEvent,command);require(delta[5]==0,"accepted command TIC prepare "+lastError);
        String accepted=accept(s,l,g,request);require("OK".equals(accepted),"accepted command TIC accept");
        long elapsed=System.nanoTime()-started;if(sample>=0){times[sample]=elapsed;bytes=delta.length;}}
      Arrays.sort(times);DoomPlayerMovementBench.traceEnabled=true;
      for(int sample=0;sample<iterations;sample++){long next=committed.seq+1;
        byte[] command=movementCommand(next,(sample%17==0)?1:(sample%11==0?-1:0),(sample&1)==0?1:-1,
            sample%19==0?1:0,sample%5==0?1:0);String request=String.format("%032x",sample+1001);
        byte[] delta=prepareCommandTic(s,l,g,request,committed.tic,committed.seq,committed.rng,
          committed.nextMobj,committed.nextEvent,command);require(delta[5]==0,"traced command TIC prepare "+lastError);
        String discarded=discard(s,l,g,request);require("OK".equals(discarded),"traced command TIC discard");
          candidateNs[sample]=DoomPlayerMovementBench.traceCandidateNs;sideNs[sample]=DoomPlayerMovementBench.traceSideNs;
          interiorNs[sample]=DoomPlayerMovementBench.traceInteriorNs;endpointNs[sample]=DoomPlayerMovementBench.traceEndpointNs;
          portalNs[sample]=DoomPlayerMovementBench.tracePortalNs;actorNs[sample]=lastActorTicNs;
          encodeNs[sample]=lastCommandEncodeNs;candidateCount+=DoomPlayerMovementBench.traceCandidates;
          sideCount+=DoomPlayerMovementBench.traceSideTests;interiorCount+=DoomPlayerMovementBench.traceInteriorTests;
          endpointCount+=DoomPlayerMovementBench.traceEndpointTests;}
      DoomPlayerMovementBench.traceEnabled=false;Arrays.sort(candidateNs);Arrays.sort(sideNs);Arrays.sort(interiorNs);
      Arrays.sort(endpointNs);Arrays.sort(portalNs);Arrays.sort(actorNs);Arrays.sort(encodeNs);
      return "OK|COMMAND_TIC_ACCEPT|"+iterations+"|"+warmups+"|"+bytes+"|"+times[149]+"|"+
          times[284]+"|"+times[299]+"|"+committed.tic+"|"+committed.seq+"|PHASES|"+
          candidateNs[149]+","+candidateNs[284]+"|"+sideNs[149]+","+sideNs[284]+"|"+
          interiorNs[149]+","+interiorNs[284]+"|"+endpointNs[149]+","+endpointNs[284]+"|"+
          portalNs[149]+","+portalNs[284]+"|"+actorNs[149]+","+actorNs[284]+"|"+
          encodeNs[149]+","+encodeNs[284]+"|COUNTS|"+(candidateCount/iterations)+","+
          (sideCount/iterations)+","+(interiorCount/iterations)+","+(endpointCount/iterations);
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
    finally{DoomPlayerMovementBench.traceEnabled=false;}}
  public static String lastError(){try{return lastError;}catch(Throwable e){return e.getClass().getName();}}
}
