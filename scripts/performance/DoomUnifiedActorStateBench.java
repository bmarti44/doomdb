import java.io.ByteArrayOutputStream;
import java.io.ByteArrayInputStream;
import java.io.DataOutputStream;
import java.io.DataInputStream;
import java.sql.Clob;
import java.sql.Blob;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Collections;
import java.util.Comparator;
import oracle.sql.NUMBER;

/** Typed retained owner coordinating the accepted fresh-death and CHASE kernels. */
public final class DoomUnifiedActorStateBench {
  private static final int HEADER_BYTES=12,MODE_DEATH=1,MODE_CHASE=2,MODE_ATTACK=3,MODE_TIC=4,
      MODE_COMMAND_TIC=5,COMMAND_BYTES=24,COMMAND_CHILD_HEADER=105;
  private static Owner committed,pending,spare;
  private static String pendingRequest,lastError="";
  private static int pendingMode;
  private static boolean pendingStateEncoded;
  private static String pendingStateSha;
  private static byte[] pendingChild;
  private static byte[] pendingCommand;
  private static long ticChaseNs,ticLoopNs,ticEncodeNs;
  private static long lastActorTicNs,lastCommandEncodeNs;
  private static final byte[] ticOutput=new byte[32767];
  private static int ticOutputLength;
  private static int[] priorHealthScratch=new int[0],moveMaskScratch=new int[0];
  private static int[] renderOp=new int[0],renderId=new int[0],renderState=new int[0];
  private static int[] renderSectorId=new int[0],renderSectorLight=new int[0];
  private static NUMBER[] renderX=new NUMBER[0],renderY=new NUMBER[0],renderZ=new NUMBER[0],renderAngle=new NUMBER[0];
  private static int lastRenderUpserts,lastRenderRemoves;
  private static byte[] stateOutput=new byte[262144];
  private static int stateOutputLength;
  private static MessageDigest stateDigest;
  private static long lastStateEncodeNs,lastStateBlobNs,lastStateTotalNs;
  private static long lastStateCompareNs,lastStateObjectEncodeNs;
  private static int lastStateChanged,lastStateReused,lastStateRemoved;
  private static byte[] historyOutput=new byte[524288];
  private static int historyOutputLength;
  private static long lastHistoryEncodeNs,lastHistoryBlobNs,lastHistoryTotalNs;

  private DoomUnifiedActorStateBench() {}

  private static NUMBER canonicalNumber(NUMBER value){
    try{return new NUMBER(value.toBytes());}
    catch(Exception failure){throw new IllegalStateException("canonical NUMBER",failure);}
  }

  private static final class Owner {
    String session,lineage,stateMapSha;long generation,tic,seq;
    int rng,nextMobj,nextEvent,playerId,playerTarget,killCount,count;
    int playerHealth,playerArmor,playerArmorType,playerAlive,playerSector,playerAngleIndex;
    int playerSound,ammoBullets,ammoShells,ammoRockets,ammoCells,weaponMask;
    int selectedWeapon,pendingWeapon,weaponState,weaponStateTics,flashState,flashStateTics,refire;
    NUMBER playerX,playerY,playerZ,playerEyeZ;
    int[] sectorLight,sectorLightTimer;
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
    int[] spawnThing,spawnState;NUMBER[] spawnRadius,spawnHeight;String[] spawnCategory;
    int[] projectileThing,projectileState;NUMBER[] projectileSpeed,projectileRadius,projectileHeight;
    int[] projectileDamage,projectileSplashDamage;NUMBER[] projectileSplashRadius;String[] projectileKind;
    String[] weaponId,weaponAmmo,weaponAttack,weaponProjectile;NUMBER[] weaponSpread;
    int[] weaponSlot,weaponAmmoCost,weaponPellets,weaponDamage,weaponReadyState,weaponFireState;
    int[] weaponRefireState,weaponFlashState,weaponLowerState,weaponRaiseState;
    byte[][] stateFragments,stateMobjFragments;
    WorldMobjs world;int[] worldSlot;
    Owner copy(){
      Owner o=new Owner();o.session=session;o.lineage=lineage;o.stateMapSha=stateMapSha;
      o.generation=generation;o.tic=tic;o.seq=seq;o.rng=rng;o.nextMobj=nextMobj;
      o.nextEvent=nextEvent;o.playerId=playerId;o.playerTarget=playerTarget;o.killCount=killCount;o.count=count;
      o.playerX=playerX;o.playerY=playerY;o.playerZ=playerZ;o.playerEyeZ=playerEyeZ;o.playerHealth=playerHealth;
      o.playerArmor=playerArmor;o.playerArmorType=playerArmorType;o.playerAlive=playerAlive;
      o.playerSector=playerSector;o.playerAngleIndex=playerAngleIndex;
      o.sectorLight=sectorLight.clone();o.sectorLightTimer=sectorLightTimer.clone();
      o.playerSound=playerSound;o.ammoBullets=ammoBullets;o.ammoShells=ammoShells;
      o.ammoRockets=ammoRockets;o.ammoCells=ammoCells;o.weaponMask=weaponMask;
      o.selectedWeapon=selectedWeapon;o.pendingWeapon=pendingWeapon;o.weaponState=weaponState;
      o.weaponStateTics=weaponStateTics;o.flashState=flashState;o.flashStateTics=flashStateTics;o.refire=refire;
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
      o.spawnRadius=spawnRadius;o.spawnHeight=spawnHeight;o.spawnCategory=spawnCategory;o.projectileThing=projectileThing;
      o.projectileState=projectileState;o.projectileSpeed=projectileSpeed;
      o.projectileRadius=projectileRadius;o.projectileHeight=projectileHeight;
      o.projectileDamage=projectileDamage;o.projectileSplashDamage=projectileSplashDamage;
      o.projectileSplashRadius=projectileSplashRadius;o.projectileKind=projectileKind;o.stateFragments=stateFragments;
      o.weaponId=weaponId;o.weaponAmmo=weaponAmmo;o.weaponAttack=weaponAttack;o.weaponProjectile=weaponProjectile;
      o.weaponSpread=weaponSpread;o.weaponSlot=weaponSlot;o.weaponAmmoCost=weaponAmmoCost;
      o.weaponPellets=weaponPellets;o.weaponDamage=weaponDamage;
      o.weaponReadyState=weaponReadyState;o.weaponFireState=weaponFireState;o.weaponRefireState=weaponRefireState;
      o.weaponFlashState=weaponFlashState;o.weaponLowerState=weaponLowerState;o.weaponRaiseState=weaponRaiseState;
      o.stateMobjFragments=stateMobjFragments==null?null:stateMobjFragments.clone();
      o.world=world.copy();o.worldSlot=worldSlot.clone();return o;
    }
    void copyFrom(Owner s){session=s.session;lineage=s.lineage;stateMapSha=s.stateMapSha;generation=s.generation;
      tic=s.tic;seq=s.seq;rng=s.rng;nextMobj=s.nextMobj;nextEvent=s.nextEvent;playerId=s.playerId;
      playerTarget=s.playerTarget;killCount=s.killCount;count=s.count;playerHealth=s.playerHealth;
      playerArmor=s.playerArmor;playerArmorType=s.playerArmorType;playerAlive=s.playerAlive;
      playerSector=s.playerSector;playerAngleIndex=s.playerAngleIndex;playerSound=s.playerSound;
      ammoBullets=s.ammoBullets;ammoShells=s.ammoShells;ammoRockets=s.ammoRockets;ammoCells=s.ammoCells;
      weaponMask=s.weaponMask;selectedWeapon=s.selectedWeapon;pendingWeapon=s.pendingWeapon;
      weaponState=s.weaponState;weaponStateTics=s.weaponStateTics;flashState=s.flashState;
      flashStateTics=s.flashStateTics;refire=s.refire;
      playerX=s.playerX;playerY=s.playerY;playerZ=s.playerZ;playerEyeZ=s.playerEyeZ;
      System.arraycopy(s.sectorLight,0,sectorLight,0,sectorLight.length);
      System.arraycopy(s.sectorLightTimer,0,sectorLightTimer,0,sectorLightTimer.length);
      stateFragments=s.stateFragments;
      stateMobjFragments=s.stateMobjFragments==null?null:s.stateMobjFragments.clone();
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
      deathProcessed[i]=0;x[i]=canonicalNumber(p.x);y[i]=canonicalNumber(p.y);z[i]=canonicalNumber(p.z);
      mx[i]=canonicalNumber(p.mx);my[i]=canonicalNumber(p.my);mz[i]=canonicalNumber(p.mz);
      angle[i]=NUMBER.zero();radius[i]=canonicalNumber(p.radius);height[i]=canonicalNumber(p.height);
      projectileKind[i]=p.kind;
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
  private static int jsonSpace(byte[] value,int p){while(p<value.length&&(value[p]==' '||value[p]=='\n'||
      value[p]=='\r'||value[p]=='\t'))p++;return p;}
  private static int jsonStringEnd(byte[] value,int p){
    require(p<value.length&&value[p]=='"',"state seed string");p++;
    while(p<value.length){int b=value[p++]&255;if(b=='"')return p;if(b=='\\'){
        require(p<value.length,"state seed escape");p++;}}
    throw new IllegalStateException("state seed unterminated string");
  }
  private static int jsonValueEnd(byte[] value,int p){
    p=jsonSpace(value,p);require(p<value.length,"state seed value");
    if(value[p]=='"')return jsonStringEnd(value,p);
    if(value[p]=='{'||value[p]=='['){int depth=0;
      while(p<value.length){int b=value[p]&255;if(b=='"'){p=jsonStringEnd(value,p);continue;}
        if(b=='{'||b=='[')depth++;else if(b=='}'||b==']'){depth--;if(depth==0)return p+1;}p++;}
      throw new IllegalStateException("state seed unterminated container");
    }
    int start=p;while(p<value.length&&value[p]!=','&&value[p]!='}'&&value[p]!=']'&&
        value[p]!=' '&&value[p]!='\n'&&value[p]!='\r'&&value[p]!='\t')p++;
    require(p>start,"state seed primitive");return p;
  }
  private static boolean asciiEquals(byte[] value,int start,int end,String expected){
    if(end-start!=expected.length())return false;
    for(int i=0;i<expected.length();i++)if((value[start+i]&255)!=expected.charAt(i))return false;
    return true;
  }
  private static int[] jsonObjectValue(byte[] value,int objectStart,String expected){
    int p=jsonSpace(value,objectStart);require(p<value.length&&value[p]=='{',"state seed object");p++;
    for(;;){p=jsonSpace(value,p);require(p<value.length,"state seed object end");
      if(value[p]=='}')break;int keyStart=p+1,keyEnd=jsonStringEnd(value,p)-1;
      p=jsonSpace(value,keyEnd+1);require(p<value.length&&value[p]==':',"state seed colon");
      int start=jsonSpace(value,p+1),end=jsonValueEnd(value,start);
      if(asciiEquals(value,keyStart,keyEnd,expected))return new int[]{start,end};
      p=jsonSpace(value,end);require(p<value.length&&(value[p]==','||value[p]=='}'),"state seed delimiter");
      if(value[p]=='}')break;p++;
    }
    throw new IllegalStateException("state seed missing "+expected);
  }
  private static byte[] slice(byte[] value,int start,int end){return Arrays.copyOfRange(value,start,end);}
  private static void ensureState(int bytes){if(stateOutputLength+bytes<=stateOutput.length)return;
    stateOutput=Arrays.copyOf(stateOutput,Math.max(stateOutput.length*2,stateOutputLength+bytes));}
  private static void stateBytes(byte[] value){ensureState(value.length);
    System.arraycopy(value,0,stateOutput,stateOutputLength,value.length);stateOutputLength+=value.length;}
  private static void stateAscii(String value){ensureState(value.length());
    for(int i=0;i<value.length();i++)stateOutput[stateOutputLength++]=(byte)value.charAt(i);}
  private static void stateQuoted(String value){
    if(value==null){stateAscii("null");return;}ensureState(value.length()*3+2);stateOutput[stateOutputLength++]='"';
    final char[] hex="0123456789abcdef".toCharArray();
    for(int offset=0;offset<value.length();){int cp=value.codePointAt(offset);offset+=Character.charCount(cp);
      if(cp=='"'||cp=='\\'){stateOutput[stateOutputLength++]='\\';stateOutput[stateOutputLength++]=(byte)cp;}
      else if(cp=='\b')stateAscii("\\b");else if(cp=='\f')stateAscii("\\f");
      else if(cp=='\n')stateAscii("\\n");else if(cp=='\r')stateAscii("\\r");else if(cp=='\t')stateAscii("\\t");
      else if(cp<32){stateAscii("\\u00");stateOutput[stateOutputLength++]=(byte)hex[(cp>>>4)&15];
        stateOutput[stateOutputLength++]=(byte)hex[cp&15];}
      else{byte[] bytes=new String(Character.toChars(cp)).getBytes(StandardCharsets.UTF_8);stateBytes(bytes);}}
    stateOutput[stateOutputLength++]='"';
  }
  private static void stateNumber(BigDecimal value){value=value.stripTrailingZeros();
    if(value.signum()==0){stateAscii("0");return;}
    int integerDigits=value.precision()-value.scale();
    if(value.scale()>40||integerDigits>40){String digits=value.unscaledValue().abs().toString();
      if(value.signum()<0)stateAscii("-");stateOutput[stateOutputLength++]=(byte)digits.charAt(0);
      if(digits.length()>1){stateOutput[stateOutputLength++]='.';stateAscii(digits.substring(1));}
      stateAscii("E"+Integer.toString(integerDigits-1));
    }else stateAscii(value.toPlainString());}
  private static void stateNumber(NUMBER value)throws Exception{stateNumber(value.bigDecimalValue());}
  private static void stateInt(int value){stateAscii(Integer.toString(value));}
  private static void stateLong(long value){stateAscii(Long.toString(value));}
  private static void stateNullable(int value){if(value<0)stateAscii("null");else stateInt(value);}
  private static void stateKey(String key,boolean first){if(!first)stateOutput[stateOutputLength++]=',';
    stateQuoted(key);stateOutput[stateOutputLength++]=':';}
  private static boolean sameStateNumber(NUMBER a,NUMBER b)throws Exception{
    return a==b||(a!=null&&b!=null&&a.compareTo(b)==0);
  }
  private static boolean sameStateText(String a,String b){return a==b||(a!=null&&a.equals(b));}
  private static boolean sameStateMobj(WorldMobjs a,int ai,WorldMobjs b,int bi)throws Exception{
    long started=System.nanoTime();boolean same=
      a.id[ai]==b.id[bi]&&a.thing[ai]==b.thing[bi]&&a.state[ai]==b.state[bi]&&a.tics[ai]==b.tics[bi]&&
      sameStateNumber(a.x[ai],b.x[bi])&&sameStateNumber(a.y[ai],b.y[bi])&&sameStateNumber(a.z[ai],b.z[bi])&&
      sameStateNumber(a.mx[ai],b.mx[bi])&&sameStateNumber(a.my[ai],b.my[bi])&&sameStateNumber(a.mz[ai],b.mz[bi])&&
      sameStateNumber(a.angle[ai],b.angle[bi])&&sameStateNumber(a.radius[ai],b.radius[bi])&&
      sameStateNumber(a.height[ai],b.height[bi])&&a.health[ai]==b.health[bi]&&a.flags[ai]==b.flags[bi]&&
      a.target[ai]==b.target[bi]&&a.tracer[ai]==b.tracer[bi]&&a.reaction[ai]==b.reaction[bi]&&
      a.spawnThing[ai]==b.spawnThing[bi]&&a.owner[ai]==b.owner[bi]&&
      sameStateText(a.projectileKind[ai],b.projectileKind[bi])&&a.exploded[ai]==b.exploded[bi]&&
      a.sector[ai]==b.sector[bi]&&a.direction[ai]==b.direction[bi]&&a.awake[ai]==b.awake[bi]&&
      a.cooldown[ai]==b.cooldown[bi]&&a.healthSeen[ai]==b.healthSeen[bi]&&
      a.deathProcessed[ai]==b.deathProcessed[bi];
    lastStateCompareNs+=System.nanoTime()-started;return same;
  }
  private static void stateMobj(Owner o,int i)throws Exception{
    WorldMobjs w=o.world;stateOutput[stateOutputLength++]='{';
      stateKey("mobj_id",true);stateInt(w.id[i]);stateKey("thing_type",false);stateInt(w.thing[i]);
      stateKey("state_id",false);stateQuoted(o.stateId[w.state[i]]);stateKey("state_tics",false);stateInt(w.tics[i]);
      stateKey("x",false);stateNumber(w.x[i]);stateKey("y",false);stateNumber(w.y[i]);
      stateKey("z",false);stateNumber(w.z[i]);stateKey("momentum_x",false);stateNumber(w.mx[i]);
      stateKey("momentum_y",false);stateNumber(w.my[i]);stateKey("momentum_z",false);stateNumber(w.mz[i]);
      stateKey("angle",false);stateNumber(w.angle[i]);stateKey("radius",false);stateNumber(w.radius[i]);
      stateKey("height",false);stateNumber(w.height[i]);stateKey("health",false);stateInt(w.health[i]);
      stateKey("flags",false);stateInt(w.flags[i]);stateKey("target_mobj_id",false);stateNullable(w.target[i]);
      stateKey("tracer_mobj_id",false);stateNullable(w.tracer[i]);stateKey("reaction_time",false);stateInt(w.reaction[i]);
      stateKey("spawn_thing_id",false);stateNullable(w.spawnThing[i]);stateKey("owner_mobj_id",false);stateNullable(w.owner[i]);
      stateKey("projectile_kind",false);stateQuoted(w.projectileKind[i]);stateKey("exploded",false);stateInt(w.exploded[i]);
      stateKey("sector_id",false);stateNullable(w.sector[i]);stateKey("move_direction",false);stateInt(w.direction[i]);
      stateKey("awake",false);stateInt(w.awake[i]);stateKey("attack_cooldown",false);stateInt(w.cooldown[i]);
      stateKey("monster_health_seen",false);stateNullable(w.healthSeen[i]);
      stateKey("death_processed",false);stateInt(w.deathProcessed[i]);stateOutput[stateOutputLength++]='}';
  }
  private static void stateWorld(Owner before,Owner after)throws Exception{
    WorldMobjs old=before.world,next=after.world;byte[][] fragments=new byte[next.count][];
    lastStateChanged=lastStateReused=lastStateRemoved=0;lastStateCompareNs=lastStateObjectEncodeNs=0;
    stateOutput[stateOutputLength++]='[';int oi=0;
    for(int ni=0;ni<next.count;ni++){require(ni==0||next.id[ni]>next.id[ni-1],"state pending mobj order");
      while(oi<old.count&&old.id[oi]<next.id[ni]){lastStateRemoved++;oi++;}
      if(ni>0)stateOutput[stateOutputLength++]=',';byte[] fragment=null;
      if(oi<old.count&&old.id[oi]==next.id[ni]&&before.stateMobjFragments!=null&&
          oi<before.stateMobjFragments.length&&before.stateMobjFragments[oi]!=null&&
          sameStateMobj(old,oi,next,ni)){
        fragment=before.stateMobjFragments[oi];
        stateBytes(fragment);lastStateReused++;oi++;
      }else{long started=System.nanoTime();int start=stateOutputLength;stateMobj(after,ni);
        fragment=slice(stateOutput,start,stateOutputLength);lastStateObjectEncodeNs+=System.nanoTime()-started;
        lastStateChanged++;if(oi<old.count&&old.id[oi]==next.id[ni])oi++;}
      fragments[ni]=fragment;
    }
    lastStateRemoved+=old.count-oi;after.stateMobjFragments=fragments;stateOutput[stateOutputLength++]=']';
  }
  private static void encodeState(Owner before,Owner after)throws Exception{
    require(after.stateFragments!=null&&after.stateFragments.length==25,"state template");stateOutputLength=0;
    stateBytes(after.stateFragments[0]);stateLong(after.tic);stateBytes(after.stateFragments[1]);stateInt(after.rng);
    stateBytes(after.stateFragments[2]);stateNumber(after.playerX);stateBytes(after.stateFragments[3]);stateNumber(after.playerY);
    stateBytes(after.stateFragments[4]);stateNumber(after.playerZ);stateBytes(after.stateFragments[5]);
    stateNumber(BigDecimal.valueOf(after.playerAngleIndex).multiply(new BigDecimal("5.625")));
    stateBytes(after.stateFragments[6]);stateInt(after.playerHealth);stateBytes(after.stateFragments[7]);stateInt(after.playerArmor);
    stateBytes(after.stateFragments[8]);stateInt(after.playerArmorType);
    stateBytes(after.stateFragments[9]);stateInt(after.ammoBullets);
    stateBytes(after.stateFragments[10]);stateInt(after.ammoShells);
    stateBytes(after.stateFragments[11]);stateInt(after.ammoRockets);
    stateBytes(after.stateFragments[12]);stateInt(after.ammoCells);
    stateBytes(after.stateFragments[13]);stateInt(after.weaponMask);
    stateBytes(after.stateFragments[14]);stateQuoted(after.weaponId[after.selectedWeapon]);
    stateBytes(after.stateFragments[15]);stateQuoted(after.pendingWeapon<0?null:after.weaponId[after.pendingWeapon]);
    stateBytes(after.stateFragments[16]);stateQuoted(after.stateId[after.weaponState]);
    stateBytes(after.stateFragments[17]);stateInt(after.weaponStateTics);
    stateBytes(after.stateFragments[18]);stateQuoted(after.flashState<0?null:after.stateId[after.flashState]);
    stateBytes(after.stateFragments[19]);stateInt(after.flashStateTics);
    stateBytes(after.stateFragments[20]);stateInt(after.refire);
    stateBytes(after.stateFragments[21]);stateInt(after.killCount);
    stateBytes(after.stateFragments[22]);stateInt(after.playerAlive);
    stateBytes(after.stateFragments[23]);stateWorld(before,after);stateBytes(after.stateFragments[24]);
  }
  private static String stateSha()throws Exception{if(stateDigest==null)stateDigest=MessageDigest.getInstance("SHA-256");
    stateDigest.reset();stateDigest.update(stateOutput,0,stateOutputLength);return hex(stateDigest.digest());}
  private static boolean lowerHex(String value,int length){if(value==null||value.length()!=length)return false;
    for(int i=0;i<length;i++){char c=value.charAt(i);if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;}
    return true;}
  private static void ensureHistory(int bytes){if(historyOutputLength+bytes<=historyOutput.length)return;
    historyOutput=Arrays.copyOf(historyOutput,Math.max(historyOutput.length*2,historyOutputLength+bytes));}
  private static void historyAscii(String value){ensureHistory(value.length());
    for(int i=0;i<value.length();i++)historyOutput[historyOutputLength++]=(byte)value.charAt(i);}
  private static String historySha()throws Exception{if(stateDigest==null)stateDigest=MessageDigest.getInstance("SHA-256");
    stateDigest.reset();stateDigest.update(historyOutput,0,historyOutputLength);return hex(stateDigest.digest());}
  private static void loadStateTemplate(Connection c,String session,Owner o)throws Exception{
    byte[] seed;String expectedSha;
    try(CallableStatement call=c.prepareCall("begin doom_canonical_state.build(?,0,?,?); end;")){
      call.setString(1,session);call.registerOutParameter(2,Types.BLOB);call.registerOutParameter(3,Types.VARCHAR);
      call.execute();Blob blob=call.getBlob(2);expectedSha=call.getString(3);
      require(blob!=null&&blob.length()<=1048576,"state seed BLOB");seed=blob.getBytes(1,(int)blob.length());blob.free();}
    int[] tic=jsonObjectValue(seed,0,"tic"),rng=jsonObjectValue(seed,0,"rng_cursor");
    int[] player=jsonObjectValue(seed,0,"player"),mobjs=jsonObjectValue(seed,0,"mobjs");
    String[] playerKeys={"x","y","z","angle","health","armor","armor_type","ammo_bullets",
      "ammo_shells","ammo_rockets","ammo_cells","weapon_mask","selected_weapon","pending_weapon",
      "weapon_state","weapon_state_tics","flash_state","flash_state_tics","refire","kill_count","alive"};
    int[][] spans=new int[24][];spans[0]=tic;spans[1]=rng;
    for(int i=0;i<playerKeys.length;i++)spans[i+2]=jsonObjectValue(seed,player[0],playerKeys[i]);
    spans[23]=mobjs;o.stateFragments=new byte[25][];int p=0;
    for(int i=0;i<spans.length;i++){require(spans[i][0]>=p&&spans[i][1]>=spans[i][0],"state seed order");
      o.stateFragments[i]=slice(seed,p,spans[i][0]);p=spans[i][1];}
    o.stateFragments[24]=slice(seed,p,seed.length);
    o.stateMobjFragments=new byte[o.world.count][];p=jsonSpace(seed,mobjs[0]);
    require(seed[p++]=='[',"state seed mobj array");
    for(int i=0;i<o.world.count;i++){p=jsonSpace(seed,p);if(i>0){require(seed[p++]==',',"state seed mobj comma");
        p=jsonSpace(seed,p);}int end=jsonValueEnd(seed,p);require(seed[p]=='{',"state seed mobj object");
      int[] id=jsonObjectValue(seed,p,"mobj_id");int parsed=Integer.parseInt(
        new String(seed,id[0],id[1]-id[0],StandardCharsets.US_ASCII));
      require(parsed==o.world.id[i],"state seed mobj ID");o.stateMobjFragments[i]=slice(seed,p,end);p=end;}
    p=jsonSpace(seed,p);require(seed[p++]==']'&&p==mobjs[1],"state seed mobj count");
    encodeState(o,o);
    require(stateOutputLength==seed.length&&Arrays.equals(seed,Arrays.copyOf(stateOutput,stateOutputLength)),
        "state template initial bytes");require(expectedSha.equals(stateSha()),"state template initial SHA");
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
    String selectedWeaponId,pendingWeaponId,weaponStateId,flashStateId;
    try(PreparedStatement s=c.prepareStatement("select current_tic,last_command_seq,rng_cursor,"+
        "current_player_id,save_lineage from game_sessions where session_token=?")){
      s.setString(1,session);try(ResultSet r=s.executeQuery()){require(r.next(),"unified session");
        o.tic=r.getLong(1);o.seq=r.getLong(2);o.rng=r.getInt(3);o.playerId=r.getInt(4);
        require(lineage.equals(r.getString(5)),"unified lineage");}}
    try(PreparedStatement s=c.prepareStatement("select utl_raw.cast_from_number(x),"+
        "utl_raw.cast_from_number(y),utl_raw.cast_from_number(z),utl_raw.cast_from_number(angle),"+
        "utl_raw.cast_from_number(z+view_height+view_bob),"+
        "kill_count,health,armor,armor_type,alive,"+
        "ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,pending_weapon,"+
        "weapon_state,weapon_state_tics,flash_state,flash_state_tics,refire,"+
        "(select sector_id from table(doom_bsp_locate(p.x,p.y)) where rownum=1) "+
        "from players p where session_token=? and player_id=?")){
      s.setString(1,session);s.setInt(2,o.playerId);try(ResultSet r=s.executeQuery()){require(r.next(),"unified player");
        o.playerX=new NUMBER(raw(r,1));o.playerY=new NUMBER(raw(r,2));o.playerZ=new NUMBER(raw(r,3));
        NUMBER angle=new NUMBER(raw(r,4));o.playerEyeZ=new NUMBER(raw(r,5));double degrees=angle.doubleValue();
        require(degrees>=0&&degrees<360,"unified player angle");o.playerAngleIndex=((int)Math.round(degrees/5.625d))&63;
        require(Math.abs(o.playerAngleIndex*5.625d-degrees)<1e-9,"unified player angle quantum");
        o.killCount=r.getInt(6);o.playerHealth=r.getInt(7);o.playerArmor=r.getInt(8);
        o.playerArmorType=r.getInt(9);o.playerAlive=r.getInt(10);o.ammoBullets=r.getInt(11);
        o.ammoShells=r.getInt(12);o.ammoRockets=r.getInt(13);o.ammoCells=r.getInt(14);
        o.weaponMask=r.getInt(15);selectedWeaponId=r.getString(16);pendingWeaponId=r.getString(17);
        weaponStateId=r.getString(18);o.weaponStateTics=r.getInt(19);flashStateId=r.getString(20);
        o.flashStateTics=r.getInt(21);o.refire=r.getInt(22);o.playerSector=r.getInt(23);}}
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
    HashMap<String,Integer> weaponIndex=new HashMap<String,Integer>();int weapons=0;
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_weapon_def")){
      r.next();weapons=r.getInt(1);o.weaponId=new String[weapons];o.weaponAmmo=new String[weapons];
      o.weaponAttack=new String[weapons];o.weaponProjectile=new String[weapons];o.weaponSpread=new NUMBER[weapons];
      o.weaponSlot=new int[weapons];o.weaponAmmoCost=new int[weapons];o.weaponPellets=new int[weapons];
      o.weaponDamage=new int[weapons];o.weaponReadyState=new int[weapons];
      o.weaponFireState=new int[weapons];o.weaponRefireState=new int[weapons];o.weaponFlashState=new int[weapons];
      o.weaponLowerState=new int[weapons];o.weaponRaiseState=new int[weapons];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery(
        "select weapon_id,slot_number,ammo_type,ammo_cost,ready_state_id,fire_state_id,"+
        "refire_state_id,flash_state_id,attack_kind,pellet_count,damage_multiplier,"+
        "utl_raw.cast_from_number(spread_scale),projectile_kind from doom_weapon_def order by slot_number")){
      int i=0;while(r.next()){String id=r.getString(1);o.weaponId[i]=id;weaponIndex.put(id,Integer.valueOf(i));
        o.weaponSlot[i]=r.getInt(2);o.weaponAmmo[i]=r.getString(3);o.weaponAmmoCost[i]=r.getInt(4);
        o.weaponAttack[i]=r.getString(9);o.weaponPellets[i]=r.getInt(10);o.weaponDamage[i]=r.getInt(11);
        o.weaponSpread[i]=new NUMBER(raw(r,12));o.weaponProjectile[i]=r.getString(13);
        String[] ids={r.getString(5),r.getString(6),r.getString(7),r.getString(8),
          "WEAPON_"+id+"_LOWER","WEAPON_"+id+"_RAISE"};int[] mapped=new int[ids.length];
        for(int k=0;k<ids.length;k++){Integer value=stateIndex.get(ids[k]);require(value!=null,"unified weapon state "+ids[k]);
          mapped[k]=value.intValue();}
        o.weaponReadyState[i]=mapped[0];o.weaponFireState[i]=mapped[1];o.weaponRefireState[i]=mapped[2];
        o.weaponFlashState[i]=mapped[3];o.weaponLowerState[i]=mapped[4];o.weaponRaiseState[i]=mapped[5];i++;}
      require(i==weapons,"unified weapon rows");}
    Integer selected=weaponIndex.get(selectedWeaponId),pending=pendingWeaponId==null?null:weaponIndex.get(pendingWeaponId);
    Integer weaponState=stateIndex.get(weaponStateId),flashState=flashStateId==null?null:stateIndex.get(flashStateId);
    require(selected!=null&&weaponState!=null&&(pendingWeaponId==null||pending!=null)&&
        (flashStateId==null||flashState!=null),"unified player weapon state");
    o.selectedWeapon=selected.intValue();o.pendingWeapon=pending==null?-1:pending.intValue();
    o.weaponState=weaponState.intValue();o.flashState=flashState==null?-1:flashState.intValue();
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_map_sector")){
      r.next();int sectors=r.getInt(1);o.sectorLight=new int[sectors];o.sectorLightTimer=new int[sectors];
      Arrays.fill(o.sectorLightTimer,-1);}
    try(PreparedStatement s=c.prepareStatement("select sector_id,light_level,coalesce(light_timer,-1) "+
        "from sector_state where session_token=? order by sector_id")){s.setString(1,session);
      try(ResultSet r=s.executeQuery()){int count=0;while(r.next()){int id=r.getInt(1);
        require(id==count&&id<o.sectorLight.length,"unified sector runtime order");
        o.sectorLight[id]=r.getInt(2);o.sectorLightTimer[id]=r.getInt(3);count++;}
        require(count==o.sectorLight.length,"unified sector runtime rows");}}
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
      o.spawnRadius=new NUMBER[size];o.spawnHeight=new NUMBER[size];o.spawnCategory=new String[size];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select thing_type,spawn_state_id,"+
        "utl_raw.cast_from_number(coalesce(radius,8)),utl_raw.cast_from_number(coalesce(height,8)),category "+
        "from doom_thing_type_def order by thing_type")){int i=0;while(r.next()){
      o.spawnThing[i]=r.getInt(1);String state=r.getString(2);Integer si=state==null?null:stateIndex.get(state);
      require(state==null||si!=null,"unified spawn state");o.spawnState[i]=si==null?-1:si.intValue();
      o.spawnRadius[i]=new NUMBER(raw(r,3));o.spawnHeight[i]=new NUMBER(raw(r,4));o.spawnCategory[i]=r.getString(5);i++;}}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select count(*) from doom_projectile_def")){
      r.next();int size=r.getInt(1);o.projectileThing=new int[size];o.projectileState=new int[size];
      o.projectileSpeed=new NUMBER[size];o.projectileRadius=new NUMBER[size];o.projectileHeight=new NUMBER[size];
      o.projectileDamage=new int[size];o.projectileSplashDamage=new int[size];
      o.projectileSplashRadius=new NUMBER[size];o.projectileKind=new String[size];}
    try(Statement s=c.createStatement();ResultSet r=s.executeQuery("select thing_type,spawn_state_id,projectile_kind,"+
        "utl_raw.cast_from_number(speed),utl_raw.cast_from_number(radius),utl_raw.cast_from_number(height),"+
        "damage,utl_raw.cast_from_number(splash_radius),splash_damage "+
        "from doom_projectile_def order by thing_type")){int i=0;while(r.next()){
      o.projectileThing[i]=r.getInt(1);Integer si=stateIndex.get(r.getString(2));require(si!=null,"unified projectile state");
      o.projectileState[i]=si.intValue();o.projectileKind[i]=r.getString(3);
      o.projectileSpeed[i]=new NUMBER(raw(r,4));o.projectileRadius[i]=new NUMBER(raw(r,5));
      o.projectileHeight[i]=new NUMBER(raw(r,6));o.projectileDamage[i]=r.getInt(7);
      o.projectileSplashRadius[i]=new NUMBER(raw(r,8));o.projectileSplashDamage[i]=r.getInt(9);i++;}}
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
    loadStateTemplate(c,session,o);
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
      String movement=DoomPlayerMovementBench.loadDynamicSectors(sectors);
      sectors.free();chaseActors.free();require(chase.startsWith("OK|"),"unified chase load "+chase);
      require(los.startsWith("OK|"),"unified LOS load "+los);
      require(movement.startsWith("OK|"),"unified movement load "+movement);
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
      renderSectorId=new int[candidate.sectorLight.length];
      renderSectorLight=new int[candidate.sectorLight.length];
      lastError="";return "OK|"+candidate.count+"|"+candidate.tic+"|"+
          candidate.seq+"|"+candidate.rng+"|"+candidate.nextMobj+"|"+candidate.nextEvent;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
  }

  private static void invalidateForRecovery(){
    pending=null;pendingRequest=null;pendingChild=null;pendingMode=0;pendingStateEncoded=false;
    pendingStateSha=null;committed=null;spare=null;
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
  private static final class WorldOp{
    int op,mask,id,health,exploded;NUMBER x,y;
    WorldOp(int operation,int fields,int mobj){op=operation;mask=fields;id=mobj;}
  }
  private static int find(int[] values,int value){
    int low=0,high=values.length-1;while(low<=high){int mid=(low+high)>>>1;
      if(values[mid]==value)return mid;if(values[mid]<value)low=mid+1;else high=mid-1;}return -1;
  }
  private static int find(String[] values,String value){
    for(int i=0;i<values.length;i++)if(values[i].equals(value))return i;return -1;
  }
  private static boolean advanceOwnerProjectiles(Owner o,ArrayList<WorldOp> ops,
      ArrayList<AttackEvent> events)throws Exception{
    ArrayList<Integer> ids=new ArrayList<Integer>();HashSet<Integer> owners=new HashSet<Integer>();
    for(int i=0;i<o.world.count;i++)if(o.world.projectileKind[i]!=null){
      int owner=o.world.owner[i],actor=find(o.id,owner),def=find(o.projectileKind,o.world.projectileKind[i]);
      if(actor<0||def<0||o.health[actor]<=0||!o.projectileSplashRadius[def].isZero()||
          !owners.add(Integer.valueOf(owner)))return false;
      ids.add(Integer.valueOf(o.world.id[i]));
    }
    for(Integer boxed:ids){int projectileId=boxed.intValue(),slot=o.world.slot(projectileId);
      require(slot>=0,"retained projectile slot");int owner=o.world.owner[slot],actor=find(o.id,owner);
      int def=find(o.projectileKind,o.world.projectileKind[slot]),damage=o.projectileDamage[def];
      int ownerSlot=o.world.slot(owner);require(ownerSlot>=0&&actor>=0,"retained projectile owner");
      o.world.health[ownerSlot]=Math.max(0,o.world.health[ownerSlot]-damage);o.health[actor]=o.world.health[ownerSlot];
      String kind=o.world.projectileKind[slot];o.world.remove(projectileId);ops.add(new WorldOp(2,0,projectileId));
      events.add(new AttackEvent(o.nextEvent++,10,projectileId,owner,new NUMBER(damage),kind));
    }
    Collections.sort(ops,new Comparator<WorldOp>(){public int compare(WorldOp a,WorldOp b){
      return a.id<b.id?-1:a.id==b.id?0:1;}});
    for(int i=1;i<ops.size();i++)require(ops.get(i-1).id<ops.get(i).id,"retained projectile op order");
    o.nextMobj=o.world.count==0?1:o.world.id[o.world.count-1]+1;return true;
  }
  private static boolean ownerProjectilesEligible(Owner o)throws Exception{
    HashSet<Integer> owners=new HashSet<Integer>();
    for(int i=0;i<o.world.count;i++)if(o.world.projectileKind[i]!=null){
      int owner=o.world.owner[i],actor=find(o.id,owner),def=find(o.projectileKind,o.world.projectileKind[i]);
      if(actor<0||def<0||o.health[actor]<=0||!o.projectileSplashRadius[def].isZero()||
          !owners.add(Integer.valueOf(owner)))return false;
    }
    return true;
  }
  public static int ownerProjectilesReady(String s,String l,long g){
    try{require(committed!=null&&pending==null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g,"projectile readiness fence");lastError="";
      return ownerProjectilesEligible(committed)?1:0;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return -1;}
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
  private static boolean sameActorDelta(Owner a,Owner b,int i)throws Exception{
    return a.id[i]==b.id[i]&&a.healthSeen[i]==b.healthSeen[i]&&a.cooldown[i]==b.cooldown[i]&&
      a.stateIndex[i]==b.stateIndex[i]&&a.stateTics[i]==b.stateTics[i]&&
      a.deathProcessed[i]==b.deathProcessed[i]&&a.awake[i]==b.awake[i]&&a.flags[i]==b.flags[i]&&
      a.target[i]==b.target[i]&&a.direction[i]==b.direction[i]&&a.sector[i]==b.sector[i]&&
      a.x[i].compareTo(b.x[i])==0&&a.y[i].compareTo(b.y[i])==0;
  }
  private static int weaponAmmo(Owner o,String type){
    if("NONE".equals(type))return 0;
    if("BULLET".equals(type))return o.ammoBullets;if("SHELL".equals(type))return o.ammoShells;
    if("ROCKET".equals(type))return o.ammoRockets;if("CELL".equals(type))return o.ammoCells;
    throw new IllegalStateException("unified weapon ammo "+type);
  }
  /** SQL-oracle order: choose_weapon, then advance_weapon_state. */
  private static void advanceWeapon(Owner o,int slot,ArrayList<AttackEvent> events){
    if(slot!=0){int selected=-1;for(int i=0;i<o.weaponSlot.length;i++)if(o.weaponSlot[i]==slot){selected=i;break;}
      if(selected>=0&&(o.weaponMask&(1<<(slot-1)))!=0&&
          weaponAmmo(o,o.weaponAmmo[selected])>=o.weaponAmmoCost[selected]&&selected!=o.selectedWeapon){
        o.pendingWeapon=selected;o.weaponState=o.weaponLowerState[o.selectedWeapon];o.weaponStateTics=3;
        events.add(new AttackEvent(o.nextEvent++,12,-1,-1,new NUMBER(slot),o.weaponId[selected]));}}
    int oldState=o.weaponState,oldPending=o.pendingWeapon,oldTics=o.weaponStateTics;
    o.flashStateTics=Math.max(0,o.flashStateTics-1);if(o.flashStateTics==0)o.flashState=-1;
    if(oldTics>1)o.weaponStateTics=oldTics-1;
    else if(oldTics==1){int next=o.stateNext[oldState];require(next>=0,"unified weapon next state");
      if(o.stateId[oldState].endsWith("_LOWER")&&oldPending>=0){
        o.selectedWeapon=oldPending;o.pendingWeapon=-1;o.weaponState=o.weaponRaiseState[oldPending];
        o.weaponStateTics=3;events.add(new AttackEvent(o.nextEvent++,13,-1,-1,null,o.weaponId[oldPending]));
      }else{o.weaponState=next;o.weaponStateTics=Math.max(o.stateDefaultTics[oldState],0);}}
  }
  private static void consumeWeaponAmmo(Owner o,int weapon){
    int cost=o.weaponAmmoCost[weapon];String type=o.weaponAmmo[weapon];
    if("BULLET".equals(type))o.ammoBullets-=cost;else if("SHELL".equals(type))o.ammoShells-=cost;
    else if("ROCKET".equals(type))o.ammoRockets-=cost;else if("CELL".equals(type))o.ammoCells-=cost;
    else require("NONE".equals(type)&&cost==0,"retained fire ammo type");
  }
  private static String oracleDefaultNumberText(NUMBER value)throws Exception{
    String text=value.stringValue();
    if(text.startsWith("0."))return text.substring(1);
    if(text.startsWith("-0."))return "-"+text.substring(2);
    return text;
  }
  private static double firstCombatBlock(double x0,double y0,double x1,double y1){
    double dx=x1-x0,dy=y1-y0,best=Double.POSITIVE_INFINITY;
    for(int line=0;line<DoomSimCatalogBench.lineId.length;line++){
      int left=DoomSimCatalogBench.lineLeftSector[line],right=DoomSimCatalogBench.lineRightSector[line];
      boolean blocking=left<0||Math.min(DoomSimCatalogBench.baseCeiling[right],
          DoomSimCatalogBench.baseCeiling[left])<=Math.max(DoomSimCatalogBench.baseFloor[right],
          DoomSimCatalogBench.baseFloor[left]);
      if(!blocking)continue;
      double sx=DoomSimCatalogBench.lineX2[line]-DoomSimCatalogBench.lineX1[line];
      double sy=DoomSimCatalogBench.lineY2[line]-DoomSimCatalogBench.lineY1[line];
      double determinant=dx*sy-dy*sx;if(determinant==0.0)continue;
      double rx=DoomSimCatalogBench.lineX1[line]-x0,ry=DoomSimCatalogBench.lineY1[line]-y0;
      double u=(rx*dy-ry*dx)/determinant,t=(rx*sy-ry*sx)/determinant;
      if(t>0.0&&t<1.0&&u>=0.0&&u<=1.0&&t<best)best=t;
    }
    return best;
  }
  private static void fireWeapon(Owner o,int fire,int[] draws,ArrayList<AttackEvent> events)throws Exception{
    if(fire==0){o.refire=0;return;}
    String state=o.stateId[o.weaponState];
    if(!state.endsWith("_READY")&&!state.endsWith("_REFIRE"))return;
    int weapon=o.selectedWeapon;
    if(weaponAmmo(o,o.weaponAmmo[weapon])<o.weaponAmmoCost[weapon]){
      events.add(new AttackEvent(o.nextEvent++,16,-1,-1,null,null));o.playerSound=1;return;
    }
    require("HITSCAN".equals(o.weaponAttack[weapon])||"MELEE".equals(o.weaponAttack[weapon]),
        "retained fire projectile fallback");
    consumeWeaponAmmo(o,weapon);o.weaponState=o.weaponFireState[weapon];o.weaponStateTics=4;
    o.flashState=o.weaponFlashState[weapon];o.flashStateTics=2;o.refire++;
    double far=DoomBspKernelBench.combatFarDistance(),px=o.playerX.doubleValue(),py=o.playerY.doubleValue();
    for(int pellet=0;pellet<o.weaponPellets[weapon];pellet++){
      int difference=draw(o,draws)-draw(o,draws);NUMBER spread=new NUMBER(difference).mul(o.weaponSpread[weapon]);
      int damage=(draw(o,draws)%3+1)*o.weaponDamage[weapon];
      int column=Math.max(0,Math.min(319,(int)Math.floor((Math.tan(spread.doubleValue())+1.0)*160.0)));
      double rayX=DoomBspKernelBench.combatRayX(o.playerAngleIndex,column);
      double rayY=DoomBspKernelBench.combatRayY(o.playerAngleIndex,column);
      double length=Math.sqrt(rayX*rayX+rayY*rayY);rayX/=length;rayY/=length;
      double wallFraction=firstCombatBlock(px,py,px+rayX*far,py+rayY*far);
      double wall=Double.isInfinite(wallFraction)?Double.POSITIVE_INFINITY:wallFraction*far;
      int target=-1,targetSlot=-1;double targetDepth=Double.POSITIVE_INFINITY;
      for(int i=0;i<o.world.count;i++)if(o.world.health[i]>0){
        int type=find(o.spawnThing,o.world.thing[i]);require(type>=0,"retained fire thing type");
        String category=o.spawnCategory[type];if(!"monster".equals(category)&&!"barrel".equals(category))continue;
        double dx=o.world.x[i].doubleValue()-px,dy=o.world.y[i].doubleValue()-py;
        double depth=dx*rayX+dy*rayY,miss=Math.abs(dx*rayY-dy*rayX);
        if(depth>0.0&&miss<=o.world.radius[i].doubleValue()&&depth<wall&&
            (depth<targetDepth||(depth==targetDepth&&o.world.id[i]<target))){
          target=o.world.id[i];targetSlot=i;targetDepth=depth;}
      }
      String spreadText=oracleDefaultNumberText(spread);
      if(targetSlot<0)events.add(new AttackEvent(o.nextEvent++,15,-1,-1,null,spreadText));
      else{
        require("monster".equals(o.spawnCategory[find(o.spawnThing,o.world.thing[targetSlot])]),
            "retained fire barrel fallback");
        o.world.health[targetSlot]=Math.max(0,o.world.health[targetSlot]-damage);
        int actor=find(o.id,target);require(actor>=0,"retained fire monster actor");o.health[actor]=o.world.health[targetSlot];
        events.add(new AttackEvent(o.nextEvent++,8,-1,target,new NUMBER(damage),null));
        events.add(new AttackEvent(o.nextEvent++,14,-1,target,new NUMBER(damage),spreadText));o.playerSound=1;
      }
    }
  }
  private static byte[] ticDelta(Owner o,String s,String l,long g,String request)throws Exception{
    return ticDelta(o,s,l,g,request,false,null,false);
  }
  private static byte[] ticDelta(Owner o,String s,String l,long g,String request,
      boolean advanceProjectiles)throws Exception{
    return ticDelta(o,s,l,g,request,advanceProjectiles,null,false);
  }
  private static byte[] ticDelta(Owner o,String s,String l,long g,String request,
      boolean advanceProjectiles,ArrayList<AttackEvent> prefixEvents,boolean weaponBlock)throws Exception{
    return ticDelta(o,s,l,g,request,advanceProjectiles,prefixEvents,weaponBlock,0);
  }
  private static byte[] ticDelta(Owner o,String s,String l,long g,String request,
      boolean advanceProjectiles,ArrayList<AttackEvent> prefixEvents,boolean weaponBlock,
      int prefixDraws)throws Exception{
    long phase=System.nanoTime();
    ArrayList<AttackEvent> events=prefixEvents==null?new ArrayList<AttackEvent>():prefixEvents;
    ArrayList<WorldOp> worldOps=new ArrayList<WorldOp>();
    if(advanceProjectiles)require(advanceOwnerProjectiles(o,worldOps,events),"retained projectile fallback");
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
    ArrayList<TicSpawn> spawns=new ArrayList<TicSpawn>();
    int[] draws=new int[]{prefixDraws};
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
    int changedActors=0;for(int i=0;i<o.count;i++)if(!sameActorDelta(o,committed,i))changedActors++;
    int p=0;p=fastInt(p,0x44544943);ticOutput[p++]=(byte)(weaponBlock?2:1);ticOutput[p++]=0;p=fastShort(p,changedActors);
    p=fastShort(p,spawns.size());p=fastShort(p,events.size());p=fastShort(p,draws[0]);p=fastShort(p,worldOps.size());
    p=fastInt(p,o.rng);p=fastInt(p,o.playerHealth);p=fastInt(p,o.playerArmor);p=fastInt(p,o.playerAlive);
    p=fastInt(p,o.killCount);p=fastInt(p,o.nextMobj);p=fastInt(p,o.nextEvent);p=fastLong(p,o.tic+1);p=fastLong(p,o.seq+1);
    if(weaponBlock){p=fastInt(p,o.ammoBullets);p=fastInt(p,o.ammoShells);p=fastInt(p,o.ammoRockets);
      p=fastInt(p,o.ammoCells);p=fastInt(p,o.weaponMask);p=fastInt(p,o.selectedWeapon);
      p=fastInt(p,o.pendingWeapon);p=fastInt(p,o.weaponState);p=fastInt(p,o.weaponStateTics);
      p=fastInt(p,o.flashState);p=fastInt(p,o.flashStateTics);p=fastInt(p,o.refire);}
    for(int i=0;i<o.count;i++)if(!sameActorDelta(o,committed,i)){p=fastInt(p,o.id[i]);p=fastInt(p,o.healthSeen[i]);p=fastInt(p,o.cooldown[i]);
      p=fastInt(p,o.stateIndex[i]);p=fastInt(p,o.stateTics[i]);p=fastInt(p,o.deathProcessed[i]);
      p=fastInt(p,o.awake[i]);p=fastInt(p,o.flags[i]);p=fastInt(p,o.target[i]);p=fastInt(p,o.direction[i]);
      p=fastNumber(p,o.x[i]);p=fastNumber(p,o.y[i]);p=fastInt(p,o.sector[i]);}
    for(WorldOp q:worldOps){ticOutput[p++]=(byte)q.op;ticOutput[p++]=(byte)q.mask;p=fastShort(p,0);p=fastInt(p,q.id);
      if((q.mask&1)!=0)p=fastNumber(p,q.x);else{Arrays.fill(ticOutput,p,p+23,(byte)0);p+=23;}
      if((q.mask&2)!=0)p=fastNumber(p,q.y);else{Arrays.fill(ticOutput,p,p+23,(byte)0);p+=23;}
      p=fastInt(p,q.health);p=fastInt(p,q.exploded);}
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

  /** Reconcile authoritative SQL projectile movement/damage without JDBC row walking. */
  private static boolean applyProjectilePack(Owner o,byte[] pack)throws Exception{
    require(pack!=null&&pack.length>=32&&int_(pack,0)==0x4450524a&&pack[4]==1&&
        (pack[5]==0||pack[5]==1),
        "projectile pack header");
    int damaged=ushort(pack,6),projectiles=ushort(pack,8);require(ushort(pack,10)==0,
        "projectile pack reserved");
    require(pack.length==32+damaged*9+projectiles*50,"projectile pack length");
    o.playerHealth=int_(pack,12);o.playerArmor=int_(pack,16);o.playerAlive=int_(pack,20);
    o.nextMobj=int_(pack,24);o.nextEvent=int_(pack,28);
    require(o.playerHealth>=0&&o.playerArmor>=0&&(o.playerAlive==0||o.playerAlive==1)&&
        o.nextMobj>=1&&o.nextEvent>=0,"projectile pack frontier");
    int p=32,prior=-1;
    for(int i=0;i<damaged;i++,p+=9){int id=int_(pack,p);require(id>prior,"projectile damage order");prior=id;
      int slot=o.world.slot(id);require(slot>=0,"projectile damage target");
      o.world.health[slot]=int_(pack,p+4);o.world.exploded[slot]=pack[p+8]&255;
      require(o.world.health[slot]>=0&&o.world.exploded[slot]<=1,"projectile damage value");
    }
    int[] surviving=new int[projectiles];NUMBER[] xs=new NUMBER[projectiles],ys=new NUMBER[projectiles];prior=-1;
    for(int i=0;i<projectiles;i++,p+=50){int id=int_(pack,p);require(id>prior,"projectile order");prior=id;
      surviving[i]=id;xs[i]=number(pack,p+4);ys[i]=number(pack,p+27);
    }
    for(int i=o.world.count-1;i>=0;i--)if(o.world.projectileKind[i]!=null&&
        Arrays.binarySearch(surviving,o.world.id[i])<0)o.world.remove(o.world.id[i]);
    for(int i=0;i<projectiles;i++){int slot=o.world.slot(surviving[i]);
      require(slot>=0&&o.world.projectileKind[slot]!=null,"projectile retained id");
      o.world.x[slot]=xs[i];o.world.y[slot]=ys[i];
    }
    for(int i=0;i<o.count;i++){int slot=o.world.slot(o.id[i]);require(slot>=0,"projectile actor retained");
      o.worldSlot[i]=slot;o.health[i]=o.world.health[slot];o.flags[i]=o.world.flags[slot];
      o.target[i]=o.world.target[slot];
    }
    return pack[5]==1;
  }

  private static int applyPassiveWorldPack(Owner o,byte[] pack)throws Exception{
    require(pack!=null&&pack.length>=12&&int_(pack,0)==0x444d5750&&pack[4]==1&&pack[5]==0,
        "passive world pack header");
    int count=ushort(pack,6),start=ushort(pack,8),draws=ushort(pack,10);
    require(start==o.rng&&pack.length==12+count*12&&draws<=256,
        "passive world pack frontier/length");
    int prior=-1,p=12;
    for(int i=0;i<count;i++,p+=12){int sector=int_(pack,p),light=int_(pack,p+4),timer=int_(pack,p+8);
      require(sector>prior&&sector>=0&&sector<o.sectorLight.length&&light>=0&&light<=255&&timer>=-1,
          "passive world pack sector");prior=sector;o.sectorLight[sector]=light;o.sectorLightTimer[sector]=timer;}
    o.rng=(o.rng+draws)&255;return draws;
  }

  /** Canonical split phase 1: validate DMSC and apply only player movement. */
  public static byte[] prepareCommandPreWorld(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command){
    try{fence(s,l,g,tic,seq,rng,nextMobj,nextEvent);require(pending==null&&request!=null&&
        request.matches("[0-9a-f]{32}")&&command!=null&&command.length==COMMAND_BYTES&&
        int_(command,0)==0x444d5343&&(command[4]==2||command[4]==3)&&(command[5]&255)==1&&
        command[6]==0&&command[7]==0&&long_(command,8)==seq+1,"pre-world command fence/header");
      int turn=command[16],forward=command[17],strafe=command[18],run=command[19]&255;
      int fire=command[20]&255,use=command[21]&255,weapon=command[22]&255,reserved=command[23]&255;
      require(turn>=-1&&turn<=1&&forward>=-1&&forward<=1&&strafe>=-1&&strafe<=1&&run<=1&&reserved==0&&
          (command[4]==2?(fire==0&&use==0&&weapon==0):(fire<=1&&use<=1&&weapon<=9)),
          "pre-world command domain");Owner candidate=spare;candidate.copyFrom(committed);
      candidate.playerAngleIndex=(candidate.playerAngleIndex+turn+64)&63;NUMBER oldZ=candidate.playerZ;
      String movement=DoomPlayerMovementBench.moveRetained(candidate.playerX,candidate.playerY,candidate.playerZ,
          candidate.playerAngleIndex,forward,strafe,run);require("OK".equals(movement),"pre-world movement "+
          DoomPlayerMovementBench.lastError());candidate.playerX=DoomPlayerMovementBench.resultX;
      candidate.playerY=DoomPlayerMovementBench.resultY;candidate.playerZ=DoomPlayerMovementBench.resultZ;
      candidate.playerEyeZ=candidate.playerEyeZ.add(candidate.playerZ.sub(oldZ));
      candidate.playerSector=DoomPlayerMovementBench.resultSector;
      if(committed.playerX.compareTo(candidate.playerX)!=0||committed.playerY.compareTo(candidate.playerY)!=0)
        Arrays.fill(candidate.visibilityCache,-1);
      pending=candidate;pendingRequest=request;pendingMode=MODE_COMMAND_TIC;pendingCommand=command.clone();
      pendingStateEncoded=false;pendingStateSha=null;pendingChild=null;
      byte[] out=new byte[101];putInt(out,0,0x4450574d);out[4]=1;putLong(out,8,seq+1);
      putLong(out,16,tic+1);putInt(out,24,candidate.playerAngleIndex);putNumberFixed(out,28,candidate.playerX);
      putNumberFixed(out,51,candidate.playerY);putNumberFixed(out,74,candidate.playerZ);
      putInt(out,97,candidate.playerSector);lastError="";return out;
    }catch(Throwable e){pending=null;pendingRequest=null;pendingCommand=null;return failure(e);}
  }

  public static int preWorldRequiresAdvance(String s,String l,long g,String request){
    try{require(committed!=null&&pending!=null&&pendingCommand!=null&&committed.session.equals(s)&&
        committed.lineage.equals(l)&&committed.generation==g&&request!=null&&request.equals(pendingRequest),
        "pre-world decision fence");lastError="";
      return DoomPlayerMovementBench.requiresWorldAdvance()?1:0;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return -1;}
  }

  /** Canonical split phase 2: world state is already synchronized; now run combat/actors. */
  public static byte[] finishCommandPostWorld(String s,String l,long g,String request,
      byte[] projectilePack,int retainedProjectiles){
    return finishCommandPostWorldInternal(s,l,g,request,projectilePack,null,retainedProjectiles);
  }
  /** Fast split completion when retained movement crossed no active/special world boundary. */
  public static byte[] finishCommandPostWorldPassive(String s,String l,long g,String request,
      byte[] projectilePack,byte[] worldPack,int retainedProjectiles){
    return finishCommandPostWorldInternal(s,l,g,request,projectilePack,worldPack,retainedProjectiles);
  }
  private static byte[] finishCommandPostWorldInternal(String s,String l,long g,String request,
      byte[] projectilePack,byte[] worldPack,int retainedProjectiles){
    try{require(committed!=null&&pending!=null&&pendingCommand!=null&&committed.session.equals(s)&&
        committed.lineage.equals(l)&&committed.generation==g&&request.equals(pendingRequest)&&
        (retainedProjectiles==0||retainedProjectiles==1),"post-world command fence");Owner candidate=pending;
      int commandDraws=worldPack==null?0:applyPassiveWorldPack(candidate,worldPack);
      boolean advanceProjectiles=retainedProjectiles==1||
        (projectilePack!=null&&applyProjectilePack(candidate,projectilePack));
      if(retainedProjectiles==1)require(ownerProjectilesEligible(candidate),"retained projectile eligibility");
      boolean actions=pendingCommand[4]==3;ArrayList<AttackEvent> events=null;
      if(actions){events=new ArrayList<AttackEvent>();advanceWeapon(candidate,pendingCommand[22]&255,events);
        int[] draws=new int[]{commandDraws};fireWeapon(candidate,pendingCommand[20]&255,draws,events);
        require(draws[0]>=0,"post-world weapon draws");commandDraws=draws[0];}
      byte[] nested=ticDelta(candidate,s,l,g,request,advanceProjectiles,events,actions,commandDraws);
      int nestedLength=ticOutputLength;require(candidate.seq==committed.seq+1&&candidate.tic==committed.tic+1,
          "post-world resulting frontier");byte[] child=new byte[COMMAND_CHILD_HEADER+nestedLength];
      putInt(child,0,0x44435443);child[4]=1;child[5]=0;child[6]=0;child[7]=(byte)COMMAND_BYTES;
      putLong(child,8,candidate.seq);putLong(child,16,candidate.tic);putInt(child,24,candidate.playerAngleIndex);
      putNumberFixed(child,28,candidate.playerX);putNumberFixed(child,51,candidate.playerY);
      putNumberFixed(child,74,candidate.playerZ);putInt(child,97,candidate.playerSector);
      putInt(child,101,nestedLength);System.arraycopy(nested,0,child,COMMAND_CHILD_HEADER,nestedLength);
      byte[] result=wrap(MODE_COMMAND_TIC,child,child.length);pendingStateEncoded=false;pendingStateSha=null;
      pendingChild=null;lastError="";return result;
    }catch(Throwable e){return failure(e);}
  }

  /** One parity-locked DMSC/v2 movement command plus one ordered actor TIC. */
  public static byte[] prepareCommandTic(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,null,false,false);
  }
  /** Production entry point with a compact authoritative projectile mutation pack. */
  public static byte[] prepareCommandTicWithProjectiles(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command,byte[] projectilePack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,projectilePack,null,false,false);
  }
  public static byte[] prepareCommandTicRetainedProjectiles(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,null,true,false);
  }
  /** One DMSC/v3 movement/weapon command. USE remains rejected until split-phase selection. */
  public static byte[] prepareCommandTicActions(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,null,false,true);
  }
  public static byte[] prepareCommandTicActionsWithProjectiles(String s,String l,long g,String request,long tic,
      long seq,int rng,int nextMobj,int nextEvent,byte[] command,byte[] projectilePack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,projectilePack,null,false,true);
  }
  public static byte[] prepareCommandTicActionsRetainedProjectiles(String s,String l,long g,String request,
      long tic,long seq,int rng,int nextMobj,int nextEvent,byte[] command){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,null,true,true);
  }
  public static byte[] prepareCommandTicWorld(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command,byte[] worldPack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,worldPack,false,false);}
  public static byte[] prepareCommandTicWorldProjectiles(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command,byte[] projectilePack,byte[] worldPack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,projectilePack,worldPack,false,false);}
  public static byte[] prepareCommandTicWorldRetained(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command,byte[] worldPack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,worldPack,true,false);}
  public static byte[] prepareCommandTicActionsWorld(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command,byte[] worldPack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,worldPack,false,true);}
  public static byte[] prepareCommandTicActionsWorldProjectiles(String s,String l,long g,String request,long tic,
      long seq,int rng,int nextMobj,int nextEvent,byte[] command,byte[] projectilePack,byte[] worldPack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,projectilePack,worldPack,false,true);}
  public static byte[] prepareCommandTicActionsWorldRetained(String s,String l,long g,String request,long tic,
      long seq,int rng,int nextMobj,int nextEvent,byte[] command,byte[] worldPack){
    return prepareCommandTicInternal(s,l,g,request,tic,seq,rng,nextMobj,nextEvent,command,null,worldPack,true,true);}
  private static byte[] prepareCommandTicInternal(String s,String l,long g,String request,long tic,long seq,
      int rng,int nextMobj,int nextEvent,byte[] command,byte[] projectilePack,byte[] worldPack,boolean retainedProjectiles,
      boolean weaponActions){
    try{
      fence(s,l,g,tic,seq,rng,nextMobj,nextEvent);require(pending==null&&request!=null&&
          request.matches("[0-9a-f]{32}"),"command TIC request");
      require(command!=null&&command.length==COMMAND_BYTES&&int_(command,0)==0x444d5343&&
          command[4]==(byte)(weaponActions?3:2)&&(command[5]&255)==1&&command[6]==0&&command[7]==0,
          "command TIC DMSC header");
      long commandSeq=long_(command,8);require(commandSeq==seq+1,"command TIC sequence gap");
      int turn=command[16],forward=command[17],strafe=command[18],run=command[19]&255;
      require(turn>=-1&&turn<=1&&forward>=-1&&forward<=1&&strafe>=-1&&strafe<=1&&run<=1,
          "command TIC movement domain");
      int fire=command[20]&255,use=command[21]&255,weapon=command[22]&255,reserved=command[23]&255;
      if(weaponActions)require(fire<=1&&use==0&&weapon<=9&&reserved==0,
          "command TIC unsupported use/action domain");
      else require(fire==0&&use==0&&weapon==0&&reserved==0,"command TIC unsupported action/reserved");
      Owner candidate=spare;require(candidate!=null&&candidate!=committed,"command TIC spare");
      candidate.copyFrom(committed);candidate.playerAngleIndex=(candidate.playerAngleIndex+turn+64)&63;
      boolean advanceProjectiles=retainedProjectiles||
        (projectilePack!=null&&applyProjectilePack(candidate,projectilePack));
      if(retainedProjectiles)require(ownerProjectilesEligible(candidate),"retained projectile eligibility");
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
      ArrayList<AttackEvent> commandEvents=null;
      int commandDraws=worldPack==null?0:applyPassiveWorldPack(candidate,worldPack);
      if(weaponActions){commandEvents=new ArrayList<AttackEvent>();advanceWeapon(candidate,weapon,commandEvents);
        int[] draws=new int[]{commandDraws};fireWeapon(candidate,fire,draws,commandEvents);commandDraws=draws[0];}
      long actorStarted=DoomPlayerMovementBench.traceEnabled?System.nanoTime():0;
      byte[] nested=ticDelta(candidate,s,l,g,request,advanceProjectiles,commandEvents,weaponActions,commandDraws);
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
      pendingStateEncoded=false;pendingStateSha=null;
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
    DataOutputStream out=new DataOutputStream(bytes);out.writeInt(0x44574350);out.writeInt(5);
    out.writeUTF(o.session);out.writeUTF(o.lineage);out.writeUTF(o.stateMapSha);out.writeLong(o.generation);
    out.writeLong(o.tic);out.writeLong(o.seq);out.writeInt(o.rng);out.writeInt(o.nextMobj);out.writeInt(o.nextEvent);
    out.writeInt(o.playerId);out.writeInt(o.playerTarget);out.writeInt(o.killCount);out.writeInt(o.playerHealth);
    out.writeInt(o.playerArmor);out.writeInt(o.playerArmorType);out.writeInt(o.playerAlive);out.writeInt(o.playerSector);
    out.writeInt(o.playerAngleIndex);
    out.writeInt(o.playerSound);out.writeInt(o.ammoBullets);out.writeInt(o.ammoShells);
    out.writeInt(o.ammoRockets);out.writeInt(o.ammoCells);out.writeInt(o.weaponMask);
    out.writeInt(o.selectedWeapon);out.writeInt(o.pendingWeapon);out.writeInt(o.weaponState);
    out.writeInt(o.weaponStateTics);out.writeInt(o.flashState);out.writeInt(o.flashStateTics);out.writeInt(o.refire);
    out.writeInt(o.sectorLight.length);for(int i=0;i<o.sectorLight.length;i++){
      out.writeInt(o.sectorLight[i]);out.writeInt(o.sectorLightTimer[i]);}
    checkpointNumber(out,o.playerX);checkpointNumber(out,o.playerY);
    checkpointNumber(out,o.playerZ);checkpointNumber(out,o.playerEyeZ);
    out.writeInt(world.length);out.write(world);out.flush();return bytes.toByteArray();
  }
  private static String worldDifference(WorldMobjs a,WorldMobjs b){
    if(a.count!=b.count)return "count "+a.count+"/"+b.count;
    for(int i=0;i<a.count;i++){
      if(a.id[i]!=b.id[i])return "id slot="+i+" "+a.id[i]+"/"+b.id[i];
      if(a.thing[i]!=b.thing[i])return "thing id="+a.id[i]+" "+a.thing[i]+"/"+b.thing[i];
      if(a.health[i]!=b.health[i])return "health id="+a.id[i]+" "+a.health[i]+"/"+b.health[i];
      if(a.healthSeen[i]!=b.healthSeen[i])return "healthSeen id="+a.id[i]+" "+a.healthSeen[i]+"/"+b.healthSeen[i];
      if(a.state[i]!=b.state[i])return "state id="+a.id[i]+" "+a.state[i]+"/"+b.state[i];
      if(a.tics[i]!=b.tics[i])return "tics id="+a.id[i]+" "+a.tics[i]+"/"+b.tics[i];
      if(a.awake[i]!=b.awake[i])return "awake id="+a.id[i]+" "+a.awake[i]+"/"+b.awake[i];
      if(a.cooldown[i]!=b.cooldown[i])return "cooldown id="+a.id[i]+" "+a.cooldown[i]+"/"+b.cooldown[i];
      if(a.deathProcessed[i]!=b.deathProcessed[i])return "death id="+a.id[i]+" "+a.deathProcessed[i]+"/"+b.deathProcessed[i];
      if(a.flags[i]!=b.flags[i])return "flags id="+a.id[i]+" "+a.flags[i]+"/"+b.flags[i];
      if(a.target[i]!=b.target[i])return "target id="+a.id[i]+" "+a.target[i]+"/"+b.target[i];
      if(a.tracer[i]!=b.tracer[i])return "tracer id="+a.id[i]+" "+a.tracer[i]+"/"+b.tracer[i];
      if(a.reaction[i]!=b.reaction[i])return "reaction id="+a.id[i]+" "+a.reaction[i]+"/"+b.reaction[i];
      if(a.spawnThing[i]!=b.spawnThing[i])return "spawnThing id="+a.id[i]+" "+a.spawnThing[i]+"/"+b.spawnThing[i];
      if(a.owner[i]!=b.owner[i])return "owner id="+a.id[i]+" "+a.owner[i]+"/"+b.owner[i];
      if(a.exploded[i]!=b.exploded[i])return "exploded id="+a.id[i]+" "+a.exploded[i]+"/"+b.exploded[i];
      if(a.sector[i]!=b.sector[i])return "sector id="+a.id[i]+" "+a.sector[i]+"/"+b.sector[i];
      if(a.direction[i]!=b.direction[i])return "direction id="+a.id[i]+" "+a.direction[i]+"/"+b.direction[i];
      if(a.x[i].compareTo(b.x[i])!=0)return "x id="+a.id[i]+" "+a.x[i]+"/"+b.x[i];
      if(a.y[i].compareTo(b.y[i])!=0)return "y id="+a.id[i]+" "+a.y[i]+"/"+b.y[i];
      if(a.z[i].compareTo(b.z[i])!=0)return "z id="+a.id[i]+" "+a.z[i]+"/"+b.z[i];
      if(a.mx[i].compareTo(b.mx[i])!=0)return "mx id="+a.id[i]+" "+a.mx[i]+"/"+b.mx[i];
      if(a.my[i].compareTo(b.my[i])!=0)return "my id="+a.id[i]+" "+a.my[i]+"/"+b.my[i];
      if(a.mz[i].compareTo(b.mz[i])!=0)return "mz id="+a.id[i]+" "+a.mz[i]+"/"+b.mz[i];
      if(a.angle[i].compareTo(b.angle[i])!=0)return "angle id="+a.id[i]+" "+a.angle[i]+"/"+b.angle[i];
      if(a.radius[i].compareTo(b.radius[i])!=0)return "radius id="+a.id[i]+" "+a.radius[i]+"/"+b.radius[i];
      if(a.height[i].compareTo(b.height[i])!=0)return "height id="+a.id[i]+" "+a.height[i]+"/"+b.height[i];
      if(a.projectileKind[i]==null?b.projectileKind[i]!=null:!a.projectileKind[i].equals(b.projectileKind[i]))
        return "projectile id="+a.id[i];
    }
    return "unlisted bytes";
  }
  private static Owner ownerBytes(Owner base,byte[] packed)throws Exception{
    return ownerBytes(base,packed,false);
  }
  private static Owner ownerBytes(Owner base,byte[] packed,boolean recovery)throws Exception{
    DataInputStream in=new DataInputStream(new ByteArrayInputStream(packed));
    require(in.readInt()==0x44574350,"owner restore magic");int version=in.readInt();
    require(version==4||version==5,"owner restore version");Owner o=base.copy();
    require(o.session.equals(in.readUTF())&&o.lineage.equals(in.readUTF())&&o.stateMapSha.equals(in.readUTF()),
        "owner restore identity");long packedGeneration=in.readLong();
    require(recovery?packedGeneration>0&&packedGeneration<o.generation:o.generation==packedGeneration,
        "owner restore generation");
    o.tic=in.readLong();o.seq=in.readLong();o.rng=in.readInt();o.nextMobj=in.readInt();o.nextEvent=in.readInt();
    require(o.nextEvent==0,"owner restore event frontier");
    o.playerId=in.readInt();o.playerTarget=in.readInt();o.killCount=in.readInt();o.playerHealth=in.readInt();
    o.playerArmor=in.readInt();o.playerArmorType=in.readInt();o.playerAlive=in.readInt();o.playerSector=in.readInt();
    o.playerAngleIndex=in.readInt();require(o.playerAngleIndex>=0&&o.playerAngleIndex<64,"owner restore angle");
    o.playerSound=in.readInt();o.ammoBullets=in.readInt();o.ammoShells=in.readInt();o.ammoRockets=in.readInt();
    o.ammoCells=in.readInt();o.weaponMask=in.readInt();o.selectedWeapon=in.readInt();o.pendingWeapon=in.readInt();
    o.weaponState=in.readInt();o.weaponStateTics=in.readInt();o.flashState=in.readInt();
    o.flashStateTics=in.readInt();o.refire=in.readInt();
    require(o.ammoBullets>=0&&o.ammoShells>=0&&o.ammoRockets>=0&&o.ammoCells>=0&&o.weaponMask>=0&&
        o.selectedWeapon>=0&&o.selectedWeapon<o.weaponId.length&&o.pendingWeapon>=-1&&
        o.pendingWeapon<o.weaponId.length&&o.weaponState>=0&&o.weaponState<o.stateId.length&&
        o.weaponStateTics>=0&&o.flashState>=-1&&o.flashState<o.stateId.length&&o.flashStateTics>=0&&o.refire>=0,
        "owner restore weapon state");
    if(version>=5){int sectors=in.readInt();require(sectors==o.sectorLight.length,"owner restore sectors");
      for(int i=0;i<sectors;i++){o.sectorLight[i]=in.readInt();o.sectorLightTimer[i]=in.readInt();
        require(o.sectorLight[i]>=0&&o.sectorLight[i]<=255&&o.sectorLightTimer[i]>=-1,
          "owner restore sector runtime");}}
    o.playerX=checkpointNumber(in);o.playerY=checkpointNumber(in);o.playerZ=checkpointNumber(in);
    o.playerEyeZ=checkpointNumber(in);
    int length=in.readInt();require(length>=12&&length<=1048576,"owner world length");byte[] world=new byte[length];
    in.readFully(world);require(in.available()==0,"owner restore trailing");o.world=worldBytes(world);
    o.stateMobjFragments=null;validateWorld(o,o.world);
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
          ",ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,pending_weapon,"+
          "weapon_state,weapon_state_tics,flash_state,flash_state_tics,refire "+
          ",(select sector_id from table(doom_bsp_locate(p.x,p.y)) where rownum=1) " +
          "from players p where session_token=? and player_id=?")){p.setString(1,s);p.setInt(2,committed.playerId);
        try(ResultSet r=p.executeQuery()){require(r.next(),"owner SQL player");NUMBER angle=new NUMBER((long)committed.playerAngleIndex*5625L).div(new NUMBER(1000));
          require(committed.playerX.compareTo(new NUMBER(raw(r,1)))==0&&committed.playerY.compareTo(new NUMBER(raw(r,2)))==0&&
              committed.playerZ.compareTo(new NUMBER(raw(r,3)))==0&&angle.compareTo(new NUMBER(raw(r,4)))==0&&
              committed.playerEyeZ.compareTo(new NUMBER(raw(r,5)))==0&&committed.playerHealth==r.getInt(6)&&
              committed.playerArmor==r.getInt(7)&&committed.playerArmorType==r.getInt(8)&&
              committed.playerAlive==r.getInt(9)&&committed.killCount==r.getInt(10)&&
              committed.ammoBullets==r.getInt(11)&&committed.ammoShells==r.getInt(12)&&
              committed.ammoRockets==r.getInt(13)&&committed.ammoCells==r.getInt(14)&&
              committed.weaponMask==r.getInt(15)&&committed.weaponId[committed.selectedWeapon].equals(r.getString(16))&&
              sameStateText(committed.pendingWeapon<0?null:committed.weaponId[committed.pendingWeapon],r.getString(17))&&
              committed.stateId[committed.weaponState].equals(r.getString(18))&&committed.weaponStateTics==r.getInt(19)&&
              sameStateText(committed.flashState<0?null:committed.stateId[committed.flashState],r.getString(20))&&
              committed.flashStateTics==r.getInt(21)&&committed.refire==r.getInt(22)&&
              committed.playerSector==r.getInt(23),"owner SQL player state");}}
      HashMap<String,Integer> states=new HashMap<String,Integer>();for(int i=0;i<committed.stateId.length;i++)
        states.put(committed.stateId[i],Integer.valueOf(i));WorldMobjs sql=loadWorld(c,s,states);
      require(Arrays.equals(worldBytes(committed.world),worldBytes(sql)),
          "owner SQL world "+worldDifference(committed.world,sql));
      try(PreparedStatement p=c.prepareStatement("select sector_id,light_level,coalesce(light_timer,-1) "+
          "from sector_state where session_token=? order by sector_id")){p.setString(1,s);
        try(ResultSet r=p.executeQuery()){int sector=0;while(r.next()){
          require(r.getInt(1)==sector&&committed.sectorLight[sector]==r.getInt(2)&&
              committed.sectorLightTimer[sector]==r.getInt(3),"owner SQL sector runtime "+sector);sector++;}
          require(sector==committed.sectorLight.length,"owner SQL sector count");}}
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
      pendingStateEncoded=false;pendingStateSha=null;
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
      DoomPlayerMovementBench.acceptWorldGeometry();
      DoomMonsterChaseBench.acceptWorldGeometry();DoomRetainedLosBench.acceptWorldGeometry();
      if(!pendingStateEncoded)pending.stateMobjFragments=null;
      Owner previous=committed;committed=pending;spare=previous;pending=null;pendingRequest=null;
      pendingStateEncoded=false;pendingStateSha=null;
      pendingChild=null;pendingCommand=null;lastError="";return "OK";
    }catch(Throwable e){try{if(DoomRetainedRenderSceneBench.ownerTicPending())
        DoomRetainedRenderSceneBench.discardOwnerTic(s,g,request);}catch(Throwable ignored){}
      DoomPlayerMovementBench.discardWorldGeometry();
      DoomMonsterChaseBench.discardWorldGeometry();DoomRetainedLosBench.discardWorldGeometry();
      lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}

  public static String discard(String s,String l,long g,String request){
    try{require(committed!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&pending!=null&&request!=null&&request.equals(pendingRequest),
        "unified pending");if(pendingMode==MODE_DEATH){String child=DoomFreshDeathTickBench.discard(s,l,g,request);
        require("OK".equals(child),"unified child discard "+child);}
      if(DoomRetainedRenderSceneBench.ownerTicPending())require("OK".equals(
          DoomRetainedRenderSceneBench.discardOwnerTic(s,g,request)),"unified renderer discard");
      DoomPlayerMovementBench.discardWorldGeometry();
      DoomMonsterChaseBench.discardWorldGeometry();DoomRetainedLosBench.discardWorldGeometry();
      spare=pending;pending=null;pendingRequest=null;pendingStateEncoded=false;pendingStateSha=null;
      pendingChild=null;pendingCommand=null;lastError="";return "OK";
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}}
  public static String fillPendingState(String s,String l,long g,String request,Blob payload){
    long totalStarted=System.nanoTime();
    try{require(committed!=null&&pending!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&request!=null&&request.equals(pendingRequest)&&payload!=null&&
        (pendingMode==MODE_TIC||pendingMode==MODE_COMMAND_TIC),"unified state pending fence");
      long phase=System.nanoTime();encodeState(committed,pending);String sha=stateSha();lastStateEncodeNs=System.nanoTime()-phase;
      phase=System.nanoTime();payload.truncate(0);int offset=0;
      while(offset<stateOutputLength){int count=Math.min(32767,stateOutputLength-offset);
        int written=payload.setBytes(offset+1L,stateOutput,offset,count);
        require(written==count,"unified state short BLOB write");offset+=count;}
      lastStateBlobNs=System.nanoTime()-phase;lastStateTotalNs=System.nanoTime()-totalStarted;
      pendingStateEncoded=true;pendingStateSha=sha;lastError="";return sha;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}return "ERR|"+lastError;}}
  public static long lastStateEncodeNanos(){return lastStateEncodeNs;}
  public static long lastStateBlobNanos(){return lastStateBlobNs;}
  public static long lastStateTotalNanos(){return lastStateTotalNs;}
  public static long lastStateCompareNanos(){return lastStateCompareNs;}
  public static long lastStateObjectEncodeNanos(){return lastStateObjectEncodeNs;}
  public static int lastStateChanged(){return lastStateChanged;}
  public static int lastStateReused(){return lastStateReused;}
  public static int lastStateRemoved(){return lastStateRemoved;}
  public static String fillPendingHistory(String s,String l,long g,String request,long tic,long frontier,
      String commandSha,String eventSha,String stateSha,String frameSha,Blob payload){
    long totalStarted=System.nanoTime();
    try{require(committed!=null&&pending!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&request!=null&&request.equals(pendingRequest)&&pendingStateEncoded&&
        tic==pending.tic&&frontier==pending.seq&&lowerHex(l,64)&&lowerHex(commandSha,64)&&lowerHex(eventSha,64)&&
        lowerHex(stateSha,64)&&stateSha.equals(pendingStateSha)&&lowerHex(frameSha,64)&&payload!=null,
        "unified history pending fence");long phase=System.nanoTime();
      historyOutputLength=0;historyAscii("{\"schema\":1,\"lineage\":\""+l+
        "\",\"frontier\":"+frontier+",\"command_sha\":\""+commandSha+
        "\",\"event_sha\":\""+eventSha+"\",\"state_sha\":\""+stateSha+
        "\",\"frame_sha\":\""+frameSha+"\",\"state\":");
      ensureHistory(stateOutputLength+1);
      System.arraycopy(stateOutput,0,historyOutput,historyOutputLength,stateOutputLength);
      historyOutputLength+=stateOutputLength;historyOutput[historyOutputLength++]='}';
      String sha=historySha();
      lastHistoryEncodeNs=System.nanoTime()-phase;phase=System.nanoTime();
      payload.truncate(0);int offset=0;while(offset<historyOutputLength){int count=Math.min(32767,
          historyOutputLength-offset);int written=payload.setBytes(offset+1L,historyOutput,offset,count);
        require(written==count,"unified history short BLOB write");offset+=count;}
      lastHistoryBlobNs=System.nanoTime()-phase;lastHistoryTotalNs=System.nanoTime()-totalStarted;
      lastError="";return sha;
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}return "ERR|"+lastError;}}
  public static long lastHistoryEncodeNanos(){return lastHistoryEncodeNs;}
  public static long lastHistoryBlobNanos(){return lastHistoryBlobNs;}
  public static long lastHistoryTotalNanos(){return lastHistoryTotalNs;}
  public static String renderPending(String s,String l,long g,String request,String stateSha,Blob payload){
    return renderPendingInternal(s,l,g,request,null,stateSha,payload);
  }
  public static String syncPendingWorld(String s,String l,long g,String request,byte[] pack){
    try{require(committed!=null&&pending!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&request!=null&&request.equals(pendingRequest)&&pack!=null&&pack.length>=55&&
        int_(pack,0)==0x444d5747&&(pack[4]&255)==3&&pack[5]==0,"world sync fence/header");
      int sectors=ushort(pack,6),mobjs=ushort(pack,8),complete=pack[10]&255;
      int baseLength=55+20*sectors+27*mobjs;
      require(pack[11]==0&&complete<=1&&sectors==pending.sectorLight.length&&
          pack.length>=baseLength,"world sync length/status");
      NUMBER oldZ=pending.playerZ;pending.playerZ=number(pack,12);
      pending.playerEyeZ=pending.playerEyeZ.add(pending.playerZ.sub(oldZ));
      pending.playerHealth=int_(pack,35);pending.playerAlive=int_(pack,39);
      int secrets=int_(pack,43);require(pending.playerHealth>=0&&(pending.playerAlive==0||pending.playerAlive==1)&&
          secrets>=0,"world sync player values");
      pending.rng=int_(pack,47);pending.nextEvent=int_(pack,51);require(pending.rng>=0&&pending.rng<=255&&
          pending.nextEvent>=0,"world sync frontier values");
      int p=55,prior=-1;for(int i=0;i<sectors;i++,p+=20){int id=int_(pack,p),floor=int_(pack,p+4),ceiling=int_(pack,p+8);
        int light=int_(pack,p+12),timer=int_(pack,p+16);require(id==i&&id>prior&&ceiling>=floor&&
          light>=0&&light<=255&&timer>=-1,"world sync sector image");prior=id;
        pending.sectorLight[id]=light;pending.sectorLightTimer[id]=timer;}
      prior=-1;for(int i=0;i<mobjs;i++,p+=27){int id=int_(pack,p),slot=pending.world.slot(id);
        require(id>prior&&slot>=0,"world sync mobj image");prior=id;pending.world.z[slot]=number(pack,p+4);}
      if(p<pack.length){require(pack.length-p>=8&&int_(pack,p)==0x444d5356&&pack[p+4]==1&&
          pack[p+5]==1,"world sync switch header");int switches=ushort(pack,p+6);p+=8;prior=-1;
        for(int i=0;i<switches;i++){require(pack.length-p>=10,"world sync switch row");int line=int_(pack,p);
          int on=pack[p+4]&255,timer=int_(pack,p+5),name=pack[p+9]&255;p+=10;
          require(line>prior&&(on==0||on==1)&&((on==1&&timer>=0)||(on==0&&timer==-1))&&
              name<=32&&pack.length-p>=name,"world sync switch values");prior=line;p+=name;}
        require(p==pack.length,"world sync switch trailing");}
      for(int i=0;i<pending.count;i++){int slot=pending.world.slot(pending.id[i]);
        require(slot>=0,"world sync actor slot");pending.worldSlot[i]=slot;pending.z[i]=pending.world.z[slot];}
      DoomPlayerMovementBench.stageWorldGeometry(pack);
      DoomMonsterChaseBench.stageWorldGeometry(pack);DoomRetainedLosBench.stageWorldGeometry(pack);
      lastError="";return "OK|"+sectors+"|"+mobjs+"|"+complete+"|"+secrets;
    }catch(Throwable e){DoomPlayerMovementBench.discardWorldGeometry();
      DoomMonsterChaseBench.discardWorldGeometry();DoomRetainedLosBench.discardWorldGeometry();
      lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
  }

  public static String refreshPendingStateTemplate(String s,String l,long g,String request){
    try{require(committed!=null&&pending!=null&&committed.session.equals(s)&&committed.lineage.equals(l)&&
        committed.generation==g&&request!=null&&request.equals(pendingRequest),"state refresh fence");
      Connection c=DriverManager.getConnection("jdbc:default:connection:");loadStateTemplate(c,s,pending);
      lastError="";return "OK";
    }catch(Throwable e){lastError=e.getClass().getName()+":"+e.getMessage();return "ERR|"+lastError;}
  }
  public static String renderPendingWorld(String s,String l,long g,String request,byte[] geometryPack,
      String stateSha,Blob payload){return renderPendingInternal(s,l,g,request,geometryPack,stateSha,payload);}
  private static String renderPendingInternal(String s,String l,long g,String request,byte[] geometryPack,
      String stateSha,Blob payload){
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
      int dirtySectors=0;for(int sector=0;sector<pending.sectorLight.length;sector++)
        if(committed.sectorLight[sector]!=pending.sectorLight[sector]){
          renderSectorId[dirtySectors]=sector;renderSectorLight[dirtySectors]=pending.sectorLight[sector];dirtySectors++;}
      String result=geometryPack==null?DoomRetainedRenderSceneBench.stageOwnerTic(s,g,request,pending.tic,pending.seq,
        pending.playerX,pending.playerY,pending.playerEyeZ,pending.playerAngleIndex,pending.playerHealth,
        pending.playerArmor,pending.playerAlive,pending.weaponId[pending.selectedWeapon],
        weaponAmmo(pending,pending.weaponAmmo[pending.selectedWeapon]),dirty,renderOp,renderId,renderState,renderX,renderY,
        renderZ,renderAngle,dirtySectors,renderSectorId,renderSectorLight,stateSha,payload):
        DoomRetainedRenderSceneBench.stageOwnerTicWorld(s,g,request,pending.tic,pending.seq,
        pending.playerX,pending.playerY,pending.playerEyeZ,pending.playerAngleIndex,pending.playerHealth,
        pending.playerArmor,pending.playerAlive,pending.weaponId[pending.selectedWeapon],
        weaponAmmo(pending,pending.weaponAmmo[pending.selectedWeapon]),dirty,renderOp,renderId,renderState,renderX,renderY,
        renderZ,renderAngle,dirtySectors,renderSectorId,renderSectorLight,geometryPack,stateSha,payload);
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
        pending=null;pendingRequest=null;pendingChild=null;pendingStateEncoded=false;pendingStateSha=null;}
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
