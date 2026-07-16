import java.sql.Blob;

/** Fenced owner for one renderer scene retained across compact frame updates. */
public final class DoomRetainedRenderSceneBench {
  private static boolean loaded;
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
    try{require(hex(owner,32)&&ownerGeneration>0&&snapshot!=null,"retained scene load");
      DoomBspKernelBench.loadRetainedScene(owner,snapshot);session=owner;
      generation=ownerGeneration;loaded=true;lastError="";return "OK";
    }catch(Throwable failure){loaded=false;lastError=failure.getClass().getName()+":"+
        failure.getMessage();return "ERR|"+lastError;}
  }
  public static String updateRender(String owner,long ownerGeneration,Blob delta,
      String stateSha,Blob payload){
    try{require(loaded&&session.equals(owner)&&generation==ownerGeneration,
        "retained scene fence");String result=DoomBspKernelBench.updateRetainedSceneAndRender(
          owner,delta,stateSha,payload);lastError="";return result;
    }catch(Throwable failure){lastError=failure.getClass().getName()+":"+failure.getMessage();
      try{if(payload!=null)payload.truncate(0);}catch(Throwable ignored){}
      return "ERROR:"+failure.getClass().getName();}
  }
  public static long lastUpdateNanos(){return DoomBspKernelBench.retainedUpdateNanos();}
  public static String lastError(){return lastError;}
}
