import java.sql.Blob;
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
      int playerHealth,int playerArmor,int playerAlive,int changeCount,int[] changeOp,int[] worldId,
      int[] worldState,NUMBER[] worldX,NUMBER[] worldY,NUMBER[] worldZ,NUMBER[] worldAngle,
      String stateSha,Blob payload){
    try{require(loaded&&stateMapFenced&&session.equals(owner)&&generation==ownerGeneration,
        "direct retained scene fence");String result=DoomBspKernelBench.stageRetainedOwnerAndRender(request,
          nextTic,nextSeq,playerX,playerY,playerEyeZ,playerAngleIndex,playerHealth,playerArmor,playerAlive,
          changeCount,changeOp,worldId,worldState,worldX,worldY,worldZ,worldAngle,stateSha,payload);
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
  public static boolean ownerTicPending(){return DoomBspKernelBench.retainedOwnerPending();}
  public static long lastUpdateNanos(){return DoomBspKernelBench.retainedUpdateNanos();}
  public static String lastError(){return lastError;}
}
