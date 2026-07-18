import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Blob;
import java.sql.Clob;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import oracle.sql.NUMBER;

/** Structural Gate 0: one fenced committed/pending retained world-state owner. */
public final class DoomRetainedWorldStateBench {
  private static final int MAGIC = 0x44575330; // DWS0
  private static final int VERSION = 1;
  private static State committed, pending;
  private static String pendingRequest, lastError = "";

  private DoomRetainedWorldStateBench() {}

  private static final class Column {
    final String name;
    final boolean number;
    Column(String name, boolean number) { this.name = name; this.number = number; }
  }

  private static final class Cell {
    final NUMBER number;
    final String text;
    Cell(NUMBER number, String text) { this.number = number; this.text = text; }
  }

  private static final class TableState {
    final String name;
    final Column[] columns;
    final Cell[][] rows;
    TableState(String name, Column[] columns, Cell[][] rows) {
      this.name = name; this.columns = columns; this.rows = rows;
    }
  }

  private static final class State {
    final String session, lineage, stateMapSha;
    final long generation, tic, commandSeq;
    final int rng, currentPlayer, nextMobj, nextEvent;
    final TableState player, actors, states, monsters;
    State(String session, String lineage, String stateMapSha, long generation,
        long tic, long commandSeq, int rng, int currentPlayer, int nextMobj, int nextEvent,
        TableState player, TableState actors, TableState states, TableState monsters) {
      this.session=session;this.lineage=lineage;this.stateMapSha=stateMapSha;
      this.generation=generation;this.tic=tic;this.commandSeq=commandSeq;this.rng=rng;
      this.currentPlayer=currentPlayer;this.nextMobj=nextMobj;this.nextEvent=nextEvent;
      this.player=player;this.actors=actors;this.states=states;this.monsters=monsters;
    }
    State copy() {
      // Cells and NUMBER instances are immutable; separate State instances are the
      // committed/pending ownership boundary for this no-behavior structural gate.
      return new State(session,lineage,stateMapSha,generation,tic,commandSeq,rng,
          currentPlayer,nextMobj,nextEvent,player,actors,states,monsters);
    }
  }

  private static void require(boolean value, String message) {
    if (!value) throw new IllegalStateException(message);
  }

  private static String hex(byte[] bytes) {
    char[] out = new char[bytes.length * 2];
    final char[] digits = "0123456789abcdef".toCharArray();
    for (int index=0;index<bytes.length;index++) {
      out[index*2]=digits[(bytes[index]>>>4)&15];out[index*2+1]=digits[bytes[index]&15];
    }
    return new String(out);
  }

  private static String sha(byte[] bytes) throws Exception {
    return hex(MessageDigest.getInstance("SHA-256").digest(bytes));
  }

  private static Column[] columns(Connection connection,String table) throws Exception {
    List<Column> result=new ArrayList<Column>();
    try(PreparedStatement statement=connection.prepareStatement(
        "select column_name,data_type from user_tab_columns where table_name=? order by column_id")) {
      statement.setString(1,table);
      try(ResultSet rows=statement.executeQuery()) {
        while(rows.next()) {
          String type=rows.getString(2);
          require("NUMBER".equals(type)||"VARCHAR2".equals(type),"unsupported column "+table+"."+rows.getString(1));
          result.add(new Column(rows.getString(1),"NUMBER".equals(type)));
        }
      }
    }
    require(!result.isEmpty(),"missing table "+table);
    return result.toArray(new Column[result.size()]);
  }

  private static TableState loadTable(Connection connection,String table,String where,
      String order,String session) throws Exception {
    Column[] columns=columns(connection,table);
    StringBuilder sql=new StringBuilder("select ");
    for(int index=0;index<columns.length;index++) {
      if(index>0)sql.append(',');
      if(columns[index].number)sql.append("utl_raw.cast_from_number(").append(columns[index].name).append(')');
      else sql.append(columns[index].name);
    }
    sql.append(" from ").append(table);
    if(where!=null)sql.append(" where ").append(where);
    if(order!=null)sql.append(" order by ").append(order);
    List<Cell[]> values=new ArrayList<Cell[]>();
    try(PreparedStatement statement=connection.prepareStatement(sql.toString())) {
      if(where!=null&&where.indexOf('?')>=0)statement.setString(1,session);
      try(ResultSet rows=statement.executeQuery()) {
        while(rows.next()) {
          Cell[] row=new Cell[columns.length];
          for(int column=0;column<columns.length;column++) {
            if(columns[column].number) {
              byte[] bytes=rows.getBytes(column+1);
              row[column]=new Cell(bytes==null?null:new NUMBER(bytes),null);
            } else row[column]=new Cell(null,rows.getString(column+1));
          }
          values.add(row);
        }
      }
    }
    return new TableState(table,columns,values.toArray(new Cell[values.size()][]));
  }

  private static String stateMapSha(Connection connection) throws Exception {
    try(Statement statement=connection.createStatement();ResultSet row=statement.executeQuery(
        "select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,"+
        "sprite_prefix,sprite_frame,rotations null on null returning varchar2) " +
        "order by state_id returning clob) from doom_state_def")) {
      require(row.next(),"state map");Clob clob=row.getClob(1);
      String text=clob.getSubString(1,(int)clob.length());clob.free();
      return sha(text.getBytes(StandardCharsets.UTF_8));
    }
  }

  private static int column(TableState table,String name) {
    for(int index=0;index<table.columns.length;index++)if(name.equals(table.columns[index].name))return index;
    throw new IllegalStateException("missing column "+table.name+"."+name);
  }

  private static String string(Cell cell) { return cell==null?null:cell.text; }

  private static void validateMappings(State state) {
    int stateId=column(state.states,"STATE_ID");
    HashMap<String,Integer> index=new HashMap<String,Integer>();
    for(int row=0;row<state.states.rows.length;row++) {
      String id=string(state.states.rows[row][stateId]);
      require(id!=null&&index.put(id,Integer.valueOf(row))==null,"state index order");
    }
    int actorState=column(state.actors,"STATE_ID");
    for(Cell[] row:state.actors.rows)require(index.containsKey(string(row[actorState])),"actor state mapping");
    for(String field:new String[]{"SEE_STATE_ID","CHASE_STATE_ID","MELEE_STATE_ID",
        "MISSILE_STATE_ID","PAIN_STATE_ID","DEATH_STATE_ID"}) {
      int fieldIndex=column(state.monsters,field);
      for(Cell[] row:state.monsters.rows)require(index.containsKey(string(row[fieldIndex])),"behavior state mapping");
    }
  }

  private static State loadState(Connection connection,String session,String lineage,
      long generation,String expectedMapSha) throws Exception {
    long tic,seq;int rng,player,nextMobj,nextEvent;
    try(PreparedStatement statement=connection.prepareStatement(
        "select current_tic,last_command_seq,rng_cursor,current_player_id,save_lineage " +
        "from game_sessions where session_token=?")) {
      statement.setString(1,session);try(ResultSet row=statement.executeQuery()) {
        require(row.next(),"session missing");tic=row.getLong(1);seq=row.getLong(2);rng=row.getInt(3);
        player=row.getInt(4);require(!row.wasNull(),"player missing");
        require(lineage.equals(row.getString(5))&&!row.next(),"lineage changed");
      }
    }
    try(PreparedStatement statement=connection.prepareStatement(
        "select coalesce(max(mobj_id),0)+1 from mobjs where session_token=?")) {
      statement.setString(1,session);try(ResultSet row=statement.executeQuery()){row.next();nextMobj=row.getInt(1);}
    }
    try(PreparedStatement statement=connection.prepareStatement(
        "select coalesce(max(event_ordinal)+1,0) from game_events " +
        "where session_token=? and lineage=? and tic=?")) {
      statement.setString(1,session);statement.setString(2,lineage);statement.setLong(3,tic);
      try(ResultSet row=statement.executeQuery()){row.next();nextEvent=row.getInt(1);}
    }
    String actualMapSha=stateMapSha(connection);
    require(actualMapSha.equals(expectedMapSha),"state map SHA fence");
    State state=new State(session,lineage,actualMapSha,generation,tic,seq,rng,player,nextMobj,nextEvent,
        loadTable(connection,"PLAYERS","SESSION_TOKEN=? AND PLAYER_ID="+player,"PLAYER_ID",session),
        loadTable(connection,"MOBJS","SESSION_TOKEN=?","MOBJ_ID",session),
        loadTable(connection,"DOOM_STATE_DEF",null,"STATE_ID",session),
        loadTable(connection,"DOOM_MONSTER_DEF",null,"THING_TYPE",session));
    require(state.player.rows.length==1&&state.actors.rows.length>0&&state.states.rows.length>0&&
        state.monsters.rows.length>0,"world row counts");
    validateMappings(state);return state;
  }

  private static void writeString(DataOutputStream out,String value) throws Exception {
    if(value==null){out.writeInt(-1);return;}byte[] bytes=value.getBytes(StandardCharsets.UTF_8);
    out.writeInt(bytes.length);out.write(bytes);
  }

  private static void writeTable(DataOutputStream out,TableState table) throws Exception {
    writeString(out,table.name);out.writeInt(table.columns.length);out.writeInt(table.rows.length);
    for(Column column:table.columns){writeString(out,column.name);out.writeByte(column.number?1:2);}
    for(Cell[] row:table.rows)for(int index=0;index<row.length;index++) {
      if(table.columns[index].number) {
        byte[] bytes=row[index].number==null?null:row[index].number.toBytes();
        if(bytes==null)out.writeInt(-1);else{out.writeInt(bytes.length);out.write(bytes);}
      } else writeString(out,row[index].text);
    }
  }

  private static byte[] pack(State state) throws Exception {
    ByteArrayOutputStream bytes=new ByteArrayOutputStream(131072);
    DataOutputStream out=new DataOutputStream(bytes);out.writeInt(MAGIC);out.writeInt(VERSION);
    writeString(out,state.session);writeString(out,state.lineage);writeString(out,state.stateMapSha);
    out.writeLong(state.generation);out.writeLong(state.tic);out.writeLong(state.commandSeq);
    out.writeInt(state.rng);out.writeInt(state.currentPlayer);out.writeInt(state.nextMobj);out.writeInt(state.nextEvent);
    writeTable(out,state.player);writeTable(out,state.actors);writeTable(out,state.states);writeTable(out,state.monsters);
    out.flush();return bytes.toByteArray();
  }

  private static String write(State state,Blob output) throws Exception {
    require(output!=null,"output BLOB");byte[] bytes=pack(state);output.truncate(0);
    for(int offset=0;offset<bytes.length;) {
      int count=Math.min(32767,bytes.length-offset);
      require(output.setBytes(offset+1L,bytes,offset,count)==count,"short world BLOB write");offset+=count;
    }
    return sha(bytes)+"|"+bytes.length;
  }

  public static String load(String session,String lineage,long generation,String expectedMapSha,
      Blob output) {
    try {
      require(pending==null,"pending world load");
      require(session!=null&&session.matches("[0-9a-f]{32}")&&lineage!=null&&
          lineage.matches("[0-9a-f]{64}")&&generation>0&&expectedMapSha!=null&&
          expectedMapSha.matches("[0-9a-f]{64}"),"world load fence");
      Connection connection=DriverManager.getConnection("jdbc:default:connection:");
      State loaded=loadState(connection,session,lineage,generation,expectedMapSha);
      String result=write(loaded,output);committed=loaded;lastError="";
      return "OK|"+loaded.tic+"|"+loaded.commandSeq+"|"+loaded.rng+"|"+
          loaded.nextMobj+"|"+loaded.nextEvent+"|"+loaded.actors.rows.length+"|"+result;
    } catch(Throwable error) {lastError=error.getClass().getName()+":"+error.getMessage();return "ERR|"+lastError;}
  }

  private static void fence(String session,String lineage,long generation) {
    require(committed!=null,"world not loaded");
    require(committed.session.equals(session)&&committed.lineage.equals(lineage)&&
        committed.generation==generation,"world fence");
  }

  public static String prepare(String session,String lineage,long generation,String request,
      long expectedTic,long expectedSeq,int expectedRng,int expectedNextMobj,int expectedNextEvent,
      Blob output) {
    try {
      fence(session,lineage,generation);require(pending==null&&request!=null&&
          request.matches("[0-9a-f]{32}"),"world request");
      require(committed.tic==expectedTic&&committed.commandSeq==expectedSeq&&
          committed.rng==expectedRng&&committed.nextMobj==expectedNextMobj&&
          committed.nextEvent==expectedNextEvent,"world frontier");
      State candidate=committed.copy();
      String result=write(candidate,output);
      pending=candidate;pendingRequest=request;lastError="";
      return "OK|"+result;
    } catch(Throwable error){lastError=error.getClass().getName()+":"+error.getMessage();return "ERR|"+lastError;}
  }

  public static String accept(String session,String lineage,long generation,String request) {
    try {fence(session,lineage,generation);require(pending!=null&&request!=null&&
        request.equals(pendingRequest),"world pending request");committed=pending;pending=null;
      pendingRequest=null;lastError="";return "OK";
    } catch(Throwable error){lastError=error.getClass().getName()+":"+error.getMessage();return "ERR|"+lastError;}
  }

  public static String discard(String session,String lineage,long generation,String request) {
    try {fence(session,lineage,generation);require(pending!=null&&request!=null&&
        request.equals(pendingRequest),"world pending request");pending=null;pendingRequest=null;
      lastError="";return "OK";
    } catch(Throwable error){lastError=error.getClass().getName()+":"+error.getMessage();return "ERR|"+lastError;}
  }

  public static String lastError(){try{return lastError;}catch(Throwable error){return error.getClass().getName();}}
}
