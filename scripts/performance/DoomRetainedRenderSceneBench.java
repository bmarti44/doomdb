import java.sql.Blob;
import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import oracle.sql.NUMBER;

/** Fenced owner for one renderer scene retained across compact frame updates. */
public final class DoomRetainedRenderSceneBench {
  private static boolean loaded;
  private static boolean stateMapFenced;
  private static String session,lastError="";
  private static long generation;
  private DoomRetainedRenderSceneBench() {}
  private static void require(boolean value,String message){
    if(!value)throw new IllegalStateException(message);
  }
  private static boolean hex(String value,int length){
    if(value==null||value.length()!=length)return false;
    for(int index=0;index<length;index++){char c=value.charAt(index);
      if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;}return true;
  }
  public static String load(String owner,long ownerGeneration,Blob snapshot){
    try{require(!DoomBspKernelBench.retainedOwnerPending()&&hex(owner,32)&&ownerGeneration>0&&snapshot!=null,"retained scene load");
      DoomBspKernelBench.loadRetainedScene(owner,snapshot);session=owner;
      generation=ownerGeneration;loaded=true;stateMapFenced=false;lastError="";return "OK";
    }catch(Throwable failure){loaded=false;stateMapFenced=false;lastError=failure.getClass().getName()+":"+
        failure.getMessage();return "ERR|"+lastError;}
  }
  public static String loadFenced(String owner,long ownerGeneration,String stateMapSha,Blob snapshot){
    try{require(!DoomBspKernelBench.retainedOwnerPending()&&hex(owner,32)&&ownerGeneration>0&&hex(stateMapSha,64)&&snapshot!=null,
        "retained fenced scene load");DoomBspKernelBench.loadRetainedScene(owner,stateMapSha,snapshot);
      session=owner;generation=ownerGeneration;loaded=true;stateMapFenced=true;lastError="";return "OK";
    }catch(Throwable failure){loaded=false;stateMapFenced=false;lastError=failure.getClass().getName()+":"+
        failure.getMessage();return "ERR|"+lastError;}
  }
  public static String forceLoadFenced(String owner,long ownerGeneration,String stateMapSha,
      long expectedTic,long expectedSeq,Blob snapshot){
    long priorGeneration=loaded?generation:0;
    invalidateForRecovery();
    try{require(hex(owner,32)&&ownerGeneration>priorGeneration&&hex(stateMapSha,64)&&snapshot!=null,
        "retained recovery load");DoomBspKernelBench.forceLoadRetainedScene(owner,stateMapSha,
          expectedTic,expectedSeq,snapshot);session=owner;generation=ownerGeneration;
      loaded=true;stateMapFenced=true;lastError="";
      return "OK|"+expectedTic+"|"+expectedSeq+"|"+ownerGeneration;
    }catch(Throwable failure){loaded=false;stateMapFenced=false;session=null;generation=0;
      lastError=failure.getClass().getName()+":"+failure.getMessage();return "ERR|"+lastError;}
  }
  static void invalidateForRecovery(){
    DoomBspKernelBench.invalidateRetainedForRecovery();loaded=false;stateMapFenced=false;
    session=null;generation=0;
  }
  public static String recoveryStatus(String owner,long ownerGeneration){
    try{require(loaded&&stateMapFenced&&session.equals(owner)&&generation==ownerGeneration&&
          !DoomBspKernelBench.retainedOwnerPending(),"retained recovery status");
      return "OK|"+DoomBspKernelBench.retainedLiveTic()+"|"+
          DoomBspKernelBench.retainedSequence()+"|"+generation;
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      return "ERR|"+lastError;}
  }
  public static String updateRender(String owner,long ownerGeneration,Blob delta,
      String stateSha,Blob payload){
    try{require(loaded&&!DoomBspKernelBench.retainedOwnerPending()&&session.equals(owner)&&generation==ownerGeneration,
        "retained scene fence");String result=DoomBspKernelBench.updateRetainedSceneAndRender(
          owner,delta,stateSha,payload);lastError="";return result;
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}
      return "ERROR:"+failure.getClass().getName();}
  }
  public static String updateTicRender(String owner,long ownerGeneration,Blob delta,
      String stateSha,Blob payload){
    try{require(loaded&&stateMapFenced&&!DoomBspKernelBench.retainedOwnerPending()&&
        session.equals(owner)&&generation==ownerGeneration,
        "retained DTIC scene fence");String result=DoomBspKernelBench.updateRetainedTicAndRender(
          owner,delta,stateSha,payload);lastError="";return result;
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}
      return "ERROR:"+failure.getClass().getName();}
  }
  public static String stageOwnerTic(String owner,long ownerGeneration,String request,long nextTic,
      long nextSeq,NUMBER playerX,NUMBER playerY,NUMBER playerEyeZ,int playerAngleIndex,
      int playerHealth,int playerArmor,int playerAlive,String selectedWeapon,String weaponState,int selectedAmmo,
      int changeCount,int[] changeOp,int[] worldId,
      int[] worldState,NUMBER[] worldX,NUMBER[] worldY,NUMBER[] worldZ,NUMBER[] worldAngle,
      int sectorChangeCount,int[] sectorIds,int[] sectorLights,
      String stateSha,Blob payload){
    try{require(loaded&&stateMapFenced&&session.equals(owner)&&generation==ownerGeneration,
        "direct retained scene fence");String result=DoomBspKernelBench.stageRetainedOwnerAndRender(request,
          nextTic,nextSeq,playerX,playerY,playerEyeZ,playerAngleIndex,playerHealth,playerArmor,playerAlive,
          selectedWeapon,weaponState,selectedAmmo,
          changeCount,changeOp,worldId,worldState,worldX,worldY,worldZ,worldAngle,
          sectorChangeCount,sectorIds,sectorLights,stateSha,payload);
      lastError="";return result;
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}
      return "ERROR:"+failure.getClass().getName();}
  }
  public static String stageOwnerTicWorld(String owner,long ownerGeneration,String request,long nextTic,
      long nextSeq,NUMBER playerX,NUMBER playerY,NUMBER playerEyeZ,int playerAngleIndex,
      int playerHealth,int playerArmor,int playerAlive,String selectedWeapon,String weaponState,int selectedAmmo,
      int changeCount,int[] changeOp,int[] worldId,
      int[] worldState,NUMBER[] worldX,NUMBER[] worldY,NUMBER[] worldZ,NUMBER[] worldAngle,
      int sectorChangeCount,int[] sectorIds,int[] sectorLights,byte[] geometryPack,
      String stateSha,Blob payload){
    try{require(loaded&&stateMapFenced&&session.equals(owner)&&generation==ownerGeneration,
        "direct retained world scene fence");String result=DoomBspKernelBench.stageRetainedOwnerAndRender(request,
          nextTic,nextSeq,playerX,playerY,playerEyeZ,playerAngleIndex,playerHealth,playerArmor,playerAlive,
          selectedWeapon,weaponState,selectedAmmo,changeCount,changeOp,worldId,worldState,worldX,worldY,worldZ,worldAngle,
          sectorChangeCount,sectorIds,sectorLights,geometryPack,stateSha,payload);
      lastError="";return result;
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}
      return "ERROR:"+failure.getClass().getName();}
  }
  public static String acceptOwnerTic(String owner,long ownerGeneration,String request){
    try{require(loaded&&stateMapFenced&&session.equals(owner)&&generation==ownerGeneration,
        "direct retained accept scene fence");DoomBspKernelBench.acceptRetainedOwner(request);
      lastError="";return "OK";
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      return "ERR|"+lastError;}
  }
  public static String discardOwnerTic(String owner,long ownerGeneration,String request){
    try{require(loaded&&stateMapFenced&&session.equals(owner)&&generation==ownerGeneration,
        "direct retained discard scene fence");DoomBspKernelBench.discardRetainedOwner(request);
      lastError="";return "OK";
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      return "ERR|"+lastError;}
  }
  private static NUMBER readNumber(DataInputStream in)throws Exception{
    int length=in.readUnsignedByte();require(length>=1&&length<=22,"render pack NUMBER");
    byte[] raw=new byte[length];in.readFully(raw);return new NUMBER(raw);
  }
  public static String stageOwnerPack(String owner,long ownerGeneration,String request,
      byte[] pack,String stateSha,Blob payload){
    try{require(loaded&&stateMapFenced&&session.equals(owner)&&generation==ownerGeneration&&
        pack!=null&&pack.length>0&&pack.length<=32767,"render pack scene fence");
      DataInputStream in=new DataInputStream(new ByteArrayInputStream(pack));
      require(in.readInt()==0x4452504b&&in.readUnsignedByte()==1,"render pack header");
      int flags=in.readUnsignedByte();require((flags&~1)==0&&in.readUnsignedShort()==0,"render pack flags");
      long tic=in.readLong(),seq=in.readLong();NUMBER x=readNumber(in),y=readNumber(in),eyeZ=readNumber(in);
      int angle=in.readInt(),health=in.readInt(),armor=in.readInt(),alive=in.readInt(),ammo=in.readInt();
      String weapon=in.readUTF(),weaponState=in.readUTF();int changes=in.readUnsignedShort();
      int sectors=in.readUnsignedShort(),geometryLength=in.readInt();
      require(changes<=4096&&sectors<=4096&&geometryLength>=0&&geometryLength<=32767&&
          ((flags&1)==0)==(geometryLength==0),"render pack counts");
      int[] op=new int[changes],id=new int[changes],state=new int[changes];
      NUMBER[] wx=new NUMBER[changes],wy=new NUMBER[changes],wz=new NUMBER[changes],wa=new NUMBER[changes];
      for(int change=0;change<changes;change++){op[change]=in.readUnsignedByte();id[change]=in.readInt();
        state[change]=in.readInt();require(op[change]==0||op[change]==1,"render pack operation");
        if(op[change]==1){wx[change]=readNumber(in);wy[change]=readNumber(in);
          wz[change]=readNumber(in);wa[change]=readNumber(in);}}
      int[] sectorId=new int[sectors],sectorLight=new int[sectors];
      for(int change=0;change<sectors;change++){sectorId[change]=in.readInt();sectorLight[change]=in.readInt();}
      byte[] geometry=null;if(geometryLength>0){geometry=new byte[geometryLength];in.readFully(geometry);}
      require(in.available()==0,"render pack trailing bytes");
      String result=geometry==null?DoomBspKernelBench.stageRetainedOwnerAndRender(request,tic,seq,
        x,y,eyeZ,angle,health,armor,alive,weapon,weaponState,ammo,changes,op,id,state,wx,wy,wz,wa,
        sectors,sectorId,sectorLight,stateSha,payload):
        DoomBspKernelBench.stageRetainedOwnerAndRender(request,tic,seq,x,y,eyeZ,angle,health,armor,
        alive,weapon,weaponState,ammo,changes,op,id,state,wx,wy,wz,wa,sectors,sectorId,sectorLight,
        geometry,stateSha,payload);lastError="";return result;
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}return "ERR|"+lastError;}
  }
  public static boolean ownerTicPending(){return DoomBspKernelBench.retainedOwnerPending();}
  public static long lastUpdateNanos(){return DoomBspKernelBench.retainedUpdateNanos();}
  public static String lastError(){return lastError;}
}
