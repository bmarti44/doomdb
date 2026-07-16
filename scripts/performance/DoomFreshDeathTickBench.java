import java.sql.Clob;

/** Atomic retained fresh-death phase, including resolved relational drop spawns. */
public final class DoomFreshDeathTickBench {
  private static final int MAGIC = 0x44444654; // DDFT
  private static final int VERSION = 1;
  private static final int HEADER_BYTES = 24;
  private static final int ACTOR_BYTES = 40;
  private static final int DROP_BYTES = 92;
  private static final int EVENT_BYTES = 20;
  private static final int EVENT_MONSTER_DEATH = 1;
  private static final int EVENT_MONSTER_DROP = 2;
  private static final int MAX_ACTORS = 128;
  private static final int NULL = -1;
  private static final byte[] delta = new byte[HEADER_BYTES +
      MAX_ACTORS * ACTOR_BYTES + MAX_ACTORS * DROP_BYTES + MAX_ACTORS * 2 * EVENT_BYTES];

  private static boolean loaded, pending;
  private static String session, lineage, pendingRequest, lastError = "";
  private static long generation;
  private static int count, killCount, pendingKillCount;
  private static int[] mobjId, health, healthSeen, cooldown, awake, stateTics;
  private static int[] deathProcessed, flags, targetMobjId, moveDirection;
  private static int[] deathStateIndex, deathStateTics, x, y, z, sectorId;
  private static int[] dropThingType, dropStateIndex, dropStateTics, dropRadius, dropHeight;
  private static int[] pendingHealthSeen, pendingCooldown, pendingAwake, pendingStateTics;
  private static int[] pendingDeathProcessed, pendingFlags, pendingTargetMobjId;
  private static int[] pendingMoveDirection, pendingStateIndex;

  private DoomFreshDeathTickBench() {}

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static final class Parser {
    final String text;
    int offset;
    Parser(String text) { this.text = text; }
    void whitespace() { while (offset < text.length() && text.charAt(offset) <= ' ') offset++; }
    void expect(char value) {
      whitespace();
      require(offset < text.length() && text.charAt(offset++) == value, "death JSON syntax");
    }
    boolean take(char value) {
      whitespace();
      if (offset < text.length() && text.charAt(offset) == value) { offset++; return true; }
      return false;
    }
    int integer(boolean nullable) {
      whitespace();
      if (nullable && text.startsWith("null", offset)) { offset += 4; return NULL; }
      require(offset < text.length(), "death JSON integer");
      int sign = 1, value = 0;
      if (text.charAt(offset) == '-') { sign = -1; offset++; }
      int start = offset;
      while (offset < text.length() && Character.isDigit(text.charAt(offset)))
        value = value * 10 + text.charAt(offset++) - '0';
      require(offset > start, "death JSON integer");
      return sign * value;
    }
  }

  private static void putShort(int offset, int value) {
    delta[offset] = (byte) (value >>> 8); delta[offset + 1] = (byte) value;
  }

  private static void putInt(int offset, int value) {
    delta[offset] = (byte) (value >>> 24); delta[offset + 1] = (byte) (value >>> 16);
    delta[offset + 2] = (byte) (value >>> 8); delta[offset + 3] = (byte) value;
  }

  private static byte[] failBytes(Throwable error) {
    lastError = error.getClass().getName() + ":" + error.getMessage();
    for (int index = 0; index < HEADER_BYTES; index++) delta[index] = 0;
    putInt(0, MAGIC); delta[4] = VERSION; delta[5] = 1;
    return delta;
  }

  private static String failString(Throwable error) {
    lastError = error.getClass().getName() + ":" + error.getMessage();
    return "ERR|" + lastError;
  }

  /** Coordinator-only hard fence used before reconstructing a new worker generation. */
  static void invalidateForRecovery() {
    pending=false;pendingRequest=null;loaded=false;session=null;lineage=null;generation=0;
  }

  /**
   * Rows contain 21 integers:
   * id,health,seen,cooldown,awake,stateTics,deathProcessed,flags,target,moveDirection,
   * deathStateIndex,deathStateTics,x,y,z,sector,dropThingType,dropStateIndex,
   * dropStateTics,dropRadius,dropHeight. Nullable fields use JSON null -> -1.
   */
  public static String load(String loadedSession, String loadedLineage, long loadedGeneration,
      int loadedKillCount, Clob snapshot) {
    try {
      require(!pending, "pending death load");
      require(loadedSession != null && loadedSession.matches("[0-9a-f]{32}"), "session");
      require(loadedLineage != null && loadedLineage.matches("[0-9a-f]{64}"), "lineage");
      require(loadedGeneration > 0 && loadedKillCount >= 0 && snapshot != null &&
          snapshot.length() <= 1048576, "load");
      String text = snapshot.getSubString(1, (int) snapshot.length());
      Parser parser = new Parser(text); parser.expect('[');
      int rows = 0;
      if (!parser.take(']')) {
        do {
          parser.expect('[');
          for (int field = 0; field < 21; field++) {
            parser.integer(field == 2 || field == 8 || field >= 16);
            if (field < 20) parser.expect(',');
          }
          parser.expect(']'); rows++;
        } while (parser.take(','));
        parser.expect(']');
      }
      parser.whitespace();
      require(parser.offset == text.length() && rows >= 1 && rows <= MAX_ACTORS, "death rows");
      int[][] value = new int[21][rows];
      parser = new Parser(text); parser.expect('[');
      int row = 0;
      do {
        parser.expect('[');
        for (int field = 0; field < 21; field++) {
          value[field][row] = parser.integer(field == 2 || field == 8 || field >= 16);
          if (field < 20) parser.expect(',');
        }
        parser.expect(']');
        require(value[0][row] >= 0 && (row == 0 || value[0][row] > value[0][row - 1]),
            "death actor order");
        require(value[1][row] >= 0 && (value[2][row] == NULL || value[2][row] >= 0) &&
            value[3][row] >= 0 && (value[4][row] == 0 || value[4][row] == 1) &&
            value[5][row] >= -1 && (value[6][row] == 0 || value[6][row] == 1) &&
            value[7][row] >= 0 && (value[8][row] == NULL || value[8][row] >= 0) &&
            value[9][row] >= -1 && value[9][row] <= 7 && value[10][row] >= 0 &&
            value[11][row] >= -1 && value[15][row] >= 0, "death actor value");
        if (value[16][row] == NULL) {
          require(value[17][row] == NULL && value[18][row] == NULL &&
              value[19][row] == NULL && value[20][row] == NULL, "unresolved no-drop fields");
        } else {
          require(value[16][row] >= 0 && value[17][row] >= 0 && value[18][row] >= -1 &&
              value[19][row] >= 0 && value[20][row] >= 0, "unresolved drop definition");
        }
        row++;
      } while (parser.take(','));
      parser.expect(']'); parser.whitespace();
      require(row == rows && parser.offset == text.length(), "death trailing bytes");

      mobjId=value[0];health=value[1];healthSeen=value[2];cooldown=value[3];awake=value[4];
      stateTics=value[5];deathProcessed=value[6];flags=value[7];targetMobjId=value[8];
      moveDirection=value[9];deathStateIndex=value[10];deathStateTics=value[11];
      x=value[12];y=value[13];z=value[14];sectorId=value[15];dropThingType=value[16];
      dropStateIndex=value[17];dropStateTics=value[18];dropRadius=value[19];dropHeight=value[20];
      pendingHealthSeen=new int[rows];pendingCooldown=new int[rows];pendingAwake=new int[rows];
      pendingStateTics=new int[rows];pendingDeathProcessed=new int[rows];pendingFlags=new int[rows];
      pendingTargetMobjId=new int[rows];pendingMoveDirection=new int[rows];
      pendingStateIndex=new int[rows];
      session=loadedSession;lineage=loadedLineage;generation=loadedGeneration;
      killCount=loadedKillCount;count=rows;pending=false;pendingRequest=null;loaded=true;lastError="";
      return "OK|" + count + "|" + killCount;
    } catch (Throwable error) { return failString(error); }
  }

  private static void fence(String expectedSession, String expectedLineage, long expectedGeneration) {
    require(loaded, "deaths not loaded");
    require(session.equals(expectedSession) && lineage.equals(expectedLineage) &&
        generation == expectedGeneration, "death fence");
  }

  public static byte[] prepare(String expectedSession, String expectedLineage,
      long expectedGeneration, String request, int nextEventOrdinal, int nextMobjId) {
    try {
      fence(expectedSession, expectedLineage, expectedGeneration);
      require(!pending && request != null && request.matches("[0-9a-f]{32}"), "death request");
      require(nextEventOrdinal >= 0 && nextMobjId >= 0, "death frontier");
      int drops = 0;
      for (int index = 0; index < count; index++) {
        require(health[index] == 0 && deathProcessed[index] == 0,
            "unsupported non-fresh death mobj=" + mobjId[index]);
        if (dropThingType[index] != NULL) drops++;
      }
      int events = count + drops;
      require(nextEventOrdinal <= Integer.MAX_VALUE - events && nextMobjId <= Integer.MAX_VALUE - drops,
          "death frontier overflow");

      for (int index = 0; index < HEADER_BYTES; index++) delta[index] = 0;
      putInt(0,MAGIC);delta[4]=VERSION;putShort(6,count);putShort(8,drops);putShort(10,events);
      putInt(12,count);putInt(16,nextMobjId+drops);putInt(20,nextEventOrdinal+events);
      int actorOffset=HEADER_BYTES;
      int dropOffset=actorOffset+count*ACTOR_BYTES;
      int eventOffset=dropOffset+drops*DROP_BYTES;
      int drop=0,event=0;
      for (int index=0;index<count;index++) {
        pendingHealthSeen[index]=0;pendingCooldown[index]=Math.max(0,cooldown[index]-1);
        pendingStateIndex[index]=deathStateIndex[index];pendingStateTics[index]=deathStateTics[index];
        pendingDeathProcessed[index]=1;pendingAwake[index]=0;pendingFlags[index]=0;
        pendingTargetMobjId[index]=NULL;pendingMoveDirection[index]=-1;
        int offset=actorOffset+index*ACTOR_BYTES;
        putInt(offset,mobjId[index]);putInt(offset+4,pendingHealthSeen[index]);
        putInt(offset+8,pendingCooldown[index]);putInt(offset+12,pendingStateIndex[index]);
        putInt(offset+16,pendingStateTics[index]);putInt(offset+20,1);putInt(offset+24,0);
        putInt(offset+28,0);putInt(offset+32,NULL);putInt(offset+36,-1);

        offset=eventOffset+event++*EVENT_BYTES;
        putInt(offset,nextEventOrdinal+event-1);putInt(offset+4,EVENT_MONSTER_DEATH);
        putInt(offset+8,mobjId[index]);putInt(offset+12,NULL);putInt(offset+16,NULL);
        if (dropThingType[index] != NULL) {
          int dropId=nextMobjId+drop;
          offset=dropOffset+drop++*DROP_BYTES;
          int[] record={dropId,dropThingType[index],dropStateIndex[index],dropStateTics[index],
              x[index],y[index],z[index],0,0,0,0,dropRadius[index],dropHeight[index],1,0,
              NULL,NULL,0,NULL,mobjId[index],NULL,0,sectorId[index]};
          for (int field=0;field<record.length;field++) putInt(offset+field*4,record[field]);
          offset=eventOffset+event++*EVENT_BYTES;
          putInt(offset,nextEventOrdinal+event-1);putInt(offset+4,EVENT_MONSTER_DROP);
          putInt(offset+8,mobjId[index]);putInt(offset+12,dropId);
          putInt(offset+16,dropThingType[index]);
        }
      }
      require(drop==drops && event==events,"death packed counts");
      pendingKillCount=killCount+count;pendingRequest=request;pending=true;lastError="";
      return delta;
    } catch (Throwable error) { return failBytes(error); }
  }

  public static String accept(String expectedSession,String expectedLineage,long expectedGeneration,
      String request) {
    try {
      fence(expectedSession,expectedLineage,expectedGeneration);
      require(pending && request!=null && request.equals(pendingRequest),"death pending request");
      for(int index=0;index<count;index++){
        healthSeen[index]=pendingHealthSeen[index];cooldown[index]=pendingCooldown[index];
        stateTics[index]=pendingStateTics[index];deathProcessed[index]=pendingDeathProcessed[index];
        awake[index]=pendingAwake[index];flags[index]=pendingFlags[index];
        targetMobjId[index]=pendingTargetMobjId[index];moveDirection[index]=pendingMoveDirection[index];
      }
      killCount=pendingKillCount;pending=false;pendingRequest=null;lastError="";
      return "OK|"+killCount;
    } catch(Throwable error){return failString(error);}
  }

  public static String discard(String expectedSession,String expectedLineage,long expectedGeneration,
      String request) {
    try {
      fence(expectedSession,expectedLineage,expectedGeneration);
      require(pending && request!=null && request.equals(pendingRequest),"death pending request");
      pending=false;pendingRequest=null;lastError="";return "OK";
    } catch(Throwable error){return failString(error);}
  }

  public static String lastError(){
    try{return lastError;}catch(Throwable error){return error.getClass().getName();}
  }
}
