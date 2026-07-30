/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import defines.skill_t;
import data.Tables;
import doom.DoomMain;
import doom.player_t;
import doom.ticcmd_t;
import doomdb.mocha.DoomDbMochaAdapter;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.IdentityHashMap;
import mochadoom.Engine;
import m.fixed_t;
import org.teavm.jso.JSByRef;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;
import doom.thinker_t;
import rr.patch_t;
import savegame.IDoomSaveGame;
import savegame.IDoomSaveGameHeader;
import savegame.VanillaDSG;
import savegame.VanillaDSGHeader;
import utils.C2JUtils;
import v.renderers.DoomScreen;
import w.InputStreamSugar;

/** Resident authoritative Mocha Doom simulation adapter for MLE JavaScript. */
public final class SimulationEngineReachabilityProbe {
  private static final int MAX_IWAD_BYTES = 64 * 1024 * 1024;
  private static final int FIXED_MUL_RANDOM_PAIRS = 1_000_000;
  private static final int FIXED_DIV_RANDOM_PAIRS = 2_000_000;
  private static final int[] FIXED_MUL_BOUNDARIES = {
      Integer.MIN_VALUE, Integer.MIN_VALUE + 1,
      -0x40000001, -0x40000000, -0x10001, -0x10000, -0xffff,
      -0x8001, -0x8000, -2, -1, 0, 1, 2,
      0x7fff, 0x8000, 0xffff, 0x10000, 0x10001,
      0x3fffffff, 0x40000000, Integer.MAX_VALUE - 1, Integer.MAX_VALUE
  };
  private static final int[] FIXED_DIV_BOUNDARIES = {
      Integer.MIN_VALUE, Integer.MIN_VALUE + 1,
      -0x40000001, -0x40000000, -0x10001, -0x10000, -0xffff,
      -0x8001, -0x8000, -0x4001, -0x4000, -2, -1, 0, 1, 2,
      0x3fff, 0x4000, 0x7fff, 0x8000, 0xffff, 0x10000, 0x10001,
      0x3fffffff, 0x40000000, Integer.MAX_VALUE - 1, Integer.MAX_VALUE
  };
  private static final long[] LONG_FLAG_PROBE_VALUES = buildLongFlagProbeValues();
  private static byte[] iwad;
  private static byte[] tablePack;
  private static int tablePackBytesLoaded;
  private static DoomMain<?, ?> engine;
  private static byte[] canonicalStateCache;
  private static byte[] checkpointCache;
  private static int checkpointCacheBytes;
  private static ReusableByteArrayOutputStream vanillaCheckpointOutput;
  private static ReusableByteArrayOutputStream envelopeCheckpointOutput;
  private static ReusableByteArrayOutputStream playerCheckpointOutput;
  private static byte[] checkpointLoadBuffer;
  private static byte[][] presentationStatusBackgrounds;
  private static byte[] presentationWorldSnapshot;
  private static int presentationWorldSnapshotLength;
  private static int[] presentationSectorFloor;
  private static int[] presentationSectorCeiling;
  private static char[] presentationSectorLight;
  private static char[] presentationSectorFloorAsset;
  private static char[] presentationSectorCeilingAsset;
  private static char[] presentationSectorSpecial;
  private static int[] presentationDirtySectors;
  private static boolean presentationSectorStateInitialized;
  private static char[] presentationSideTop;
  private static char[] presentationSideBottom;
  private static char[] presentationSideMiddle;
  private static char[] presentationSideRawTop;
  private static char[] presentationSideRawBottom;
  private static char[] presentationSideRawMiddle;
  private static char[] presentationSideSpecial;
  private static int[] presentationSideTextureOffset;
  private static int[] presentationSideRowOffset;
  private static int[] presentationDirtySides;
  private static int[] presentationCandidateSides;
  private static boolean[] presentationCandidateSideFlags;
  private static int presentationCandidateSideCount;
  private static boolean presentationAnimatedSidesCataloged;
  private static boolean presentationSideStateInitialized;
  private static int checkpointBytesLoaded;
  private static short[][] multiplayerConsistency;

  private SimulationEngineReachabilityProbe() {}

  /** Cross-runtime checksum for the exact int-limb FixedMul implementation. */
  @JSExport
  public static int fixedMulChecksum() {
    int checksum = 0x13579bdf;
    for (int a : FIXED_MUL_BOUNDARIES) {
      for (int b : FIXED_MUL_BOUNDARIES) {
        checksum = mixFixedMul(checksum, a, b, fixed_t.FixedMul(a, b));
      }
    }
    int state = 0x6d2b79f5;
    for (int i = 0; i < FIXED_MUL_RANDOM_PAIRS; i++) {
      state = nextFixedMulValue(state);
      int a = state;
      state = nextFixedMulValue(state);
      int b = state;
      checksum = mixFixedMul(checksum, a, b, fixed_t.FixedMul(a, b));
    }
    return checksum;
  }

  /** Cross-runtime checksum for the allocation-free FixedDiv intrinsic. */
  @JSExport
  public static int fixedDivChecksum() {
    int checksum = 0x2468ace1;
    for (int a : FIXED_DIV_BOUNDARIES) {
      for (int b : FIXED_DIV_BOUNDARIES) {
        checksum = mixFixedMul(checksum, a, b, fixedDivChecksumValue(a, b));
      }
    }
    for (int b = -65536; b <= 65536; b++) {
      int magnitude = Math.abs(b) << 14;
      for (int delta = -3; delta <= 3; delta++) {
        int positive = magnitude + delta;
        int negative = -magnitude + delta;
        checksum = mixFixedMul(
            checksum, positive, b, fixedDivChecksumValue(positive, b));
        checksum = mixFixedMul(
            checksum, negative, b, fixedDivChecksumValue(negative, b));
      }
    }
    int state = 0x51ed270b;
    for (int i = 0; i < FIXED_DIV_RANDOM_PAIRS; i++) {
      state = nextFixedMulValue(state);
      int a = state;
      state = nextFixedMulValue(state);
      int b = state;
      checksum = mixFixedMul(checksum, a, b, fixedDivChecksumValue(a, b));
    }
    return checksum;
  }

  private static int fixedDivChecksumValue(int a, int b) {
    if (a == Integer.MIN_VALUE && b == 0) {
      // The JVM property test separately verifies the legacy exception. Avoid
      // invoking TeaVM's host BigInt divide-by-zero while computing a portable
      // checksum for every non-exceptional result.
      return 0x4d494e30;
    }
    return fixed_t.FixedDiv(a, b);
  }

  /** Baseline shape: repeat low-bit tests against a Java long field value. */
  @JSExport
  public static int longFlagRepeatedChecksum(int iterations) {
    int checksum = 0x10203040;
    for (int i = 0; i < iterations; i++) {
      long flags = LONG_FLAG_PROBE_VALUES[i & 255];
      if ((flags & 0x01000000L) != 0) checksum ^= i + 1;
      if ((flags & 0x00400000L) != 0) checksum += i ^ 0x55aa;
      if ((flags & 0x00004000L) != 0) checksum = checksum * 33 + i;
    }
    return checksum;
  }

  /** Candidate shape: cast once, then perform all low-word tests as ints. */
  @JSExport
  public static int longFlagHoistedChecksum(int iterations) {
    int checksum = 0x10203040;
    for (int i = 0; i < iterations; i++) {
      int flagsLow = (int) LONG_FLAG_PROBE_VALUES[i & 255];
      if ((flagsLow & 0x01000000) != 0) checksum ^= i + 1;
      if ((flagsLow & 0x00400000) != 0) checksum += i ^ 0x55aa;
      if ((flagsLow & 0x00004000) != 0) checksum = checksum * 33 + i;
    }
    return checksum;
  }

  /** Allocate the resident Java-side IWAD buffer before loading chunks. */
  @JSExport
  public static int allocateIwad(int length) {
    if (length < 12 || length > MAX_IWAD_BYTES) {
      throw new IllegalArgumentException("IWAD length " + length);
    }
    release();
    iwad = new byte[length];
    return length;
  }

  /** Copy one JavaScript Uint8Array into the resident IWAD buffer. */
  @JSExport
  public static int loadIwadChunk(int offset, Uint8Array chunk) {
    if (iwad == null) throw new IllegalStateException("allocate IWAD first");
    if (chunk == null || offset < 0 || offset > iwad.length - chunk.getLength()) {
      throw new IllegalArgumentException("IWAD chunk offset " + offset);
    }
    for (int i = 0; i < chunk.getLength(); i++) {
      iwad[offset + i] = (byte) chunk.get(i);
    }
    return offset + chunk.getLength();
  }

  /** Allocate the exact versioned canonical-table pack before initialization. */
  @JSExport
  public static int allocateTablePack(int length) {
    if (engine != null) throw new IllegalStateException("release engine first");
    if (length != Tables.CANONICAL_TABLE_PACK_BYTES) {
      throw new IllegalArgumentException("canonical table pack length " + length);
    }
    tablePack = new byte[length];
    tablePackBytesLoaded = 0;
    return length;
  }

  /** Copy the next bounded JavaScript chunk into the canonical-table pack. */
  @JSExport
  public static int loadTablePackChunk(int offset, Uint8Array chunk) {
    if (tablePack == null) throw new IllegalStateException("allocate table pack first");
    if (chunk == null || offset != tablePackBytesLoaded
        || offset < 0 || offset > tablePack.length - chunk.getLength()) {
      throw new IllegalArgumentException("canonical table pack chunk offset " + offset);
    }
    for (int i = 0; i < chunk.getLength(); i++) {
      tablePack[offset + i] = (byte) chunk.get(i);
    }
    tablePackBytesLoaded += chunk.getLength();
    return tablePackBytesLoaded;
  }

  /** Initialize exact sk_medium E1M1 from the fully loaded resident IWAD. */
  @JSExport
  public static String initialize() throws Exception {
    if (iwad == null) throw new IllegalStateException("IWAD is not loaded");
    if (tablePack == null || tablePackBytesLoaded != tablePack.length) {
      throw new IllegalStateException("canonical table pack is not loaded");
    }
    if (engine != null) return snapshot("already-initialized");
    Tables.installCanonicalTablePack(tablePack);
    InputStreamSugar.setInjectedResource(iwad);
    engine = Engine.createHeadlessAuthority(
        "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
        "-width", "320", "-height", "200");
    engine.singletics = true;
    engine.InitNew(skill_t.sk_medium, 1, 1);
    multiplayerConsistency = null;
    return snapshot("initialized");
  }

  /** Initialize a retained two-to-four-player cooperative E1M1 simulation. */
  @JSExport
  public static String initializeMultiplayer(int activePlayers) throws Exception {
    return initializeMultiplayerGame(activePlayers, 0, 3, 1, 1);
  }

  /** Initialize a retained cooperative E1M1 simulation at a vanilla skill. */
  @JSExport
  public static String initializeMultiplayerAtSkill(
      int activePlayers, int skill) throws Exception {
    return initializeMultiplayerGame(activePlayers, 0, skill, 1, 1);
  }

  /** Initialize a retained multiplayer game with the durable match settings. */
  @JSExport
  public static String initializeMultiplayerGame(
      int activePlayers, int deathmatch, int skill, int episode, int map)
      throws Exception {
    return initializeMultiplayerGameInternal(
        activePlayers, deathmatch, skill, episode, map, false);
  }

  static String initializePresentationGame(
      int activePlayers, int deathmatch, int skill, int episode, int map)
      throws Exception {
    return initializeMultiplayerGameInternal(
        activePlayers, deathmatch, skill, episode, map, true);
  }

  private static String initializeMultiplayerGameInternal(
      int activePlayers, int deathmatch, int skill, int episode, int map,
      boolean presentation) throws Exception {
    if (iwad == null) throw new IllegalStateException("IWAD is not loaded");
    if (tablePack == null || tablePackBytesLoaded != tablePack.length) {
      throw new IllegalStateException("canonical table pack is not loaded");
    }
    if (activePlayers < 2 || activePlayers > 4) {
      throw new IllegalArgumentException("active players " + activePlayers);
    }
    if (skill < 1 || skill > 5) {
      throw new IllegalArgumentException("skill " + skill);
    }
    if (deathmatch < 0 || deathmatch > 1) {
      throw new IllegalArgumentException("deathmatch " + deathmatch);
    }
    if (episode < 1 || episode > 4) {
      throw new IllegalArgumentException("episode " + episode);
    }
    if (map < 1 || map > 9) {
      throw new IllegalArgumentException("map " + map);
    }
    if (engine != null) throw new IllegalStateException("engine is already initialized");
    Tables.installCanonicalTablePack(tablePack);
    InputStreamSugar.setInjectedResource(iwad);
    String[] arguments = {
        "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
        "-width", "320", "-height", "200"
    };
    engine = presentation
        ? Engine.createHeadless(arguments)
        : Engine.createHeadlessAuthority(arguments);
    Arrays.fill(engine.playeringame, false);
    for (int player = 0; player < activePlayers; player++) {
      engine.playeringame[player] = true;
    }
    engine.consoleplayer = 0;
    engine.displayplayer = 0;
    engine.netgame = true;
    engine.deathmatch = deathmatch != 0;
    engine.InitNew(skill_t.values()[skill - 1], episode, map);
    engine.singletics = true;
    multiplayerConsistency = new short[engine.playeringame.length]
        [engine.netcmds[0].length];
    return snapshot("multiplayer-initialized");
  }

  /** Apply one packed eight-byte command per active player and tick once. */
  @JSExport
  public static int stepMultiplayerBare(
      int activePlayers, Uint8Array commandVector) {
    if (engine == null || multiplayerConsistency == null || !engine.netgame) {
      throw new IllegalStateException("multiplayer engine is not initialized");
    }
    if (activePlayers < 2 || activePlayers > 4 || commandVector == null
        || commandVector.getLength() != activePlayers * ticcmd_t.TICCMDLEN) {
      throw new IllegalArgumentException("multiplayer command vector");
    }
    int buffer = (engine.gametic / engine.getTicdup())
        % engine.netcmds[0].length;
    for (int player = 0; player < activePlayers; player++) {
      int offset = player * ticcmd_t.TICCMDLEN;
      ticcmd_t command = engine.netcmds[player][buffer];
      command.forwardmove = (byte) commandVector.get(offset);
      command.sidemove = (byte) commandVector.get(offset + 1);
      command.angleturn = (short) (((commandVector.get(offset + 2) & 0xff) << 8)
          | (commandVector.get(offset + 3) & 0xff));
      command.consistancy = multiplayerConsistency[player][buffer];
      command.chatchar = (char) (commandVector.get(offset + 6) & 0xff);
      command.buttons = (char) (commandVector.get(offset + 7) & 0xff);
      command.lookfly = 0;
    }
    canonicalStateCache = null;
    checkpointCacheBytes = 0;
    engine.Ticker();
    for (int player = 0; player < activePlayers; player++) {
      multiplayerConsistency[player][buffer] =
          engine.doomdbConsistency(player, buffer);
    }
    engine.gametic++;
    return engine.gametic;
  }

  /** Apply one authoritative four-slot vector under an exact membership mask. */
  @JSExport
  public static int stepMultiplayerAuthoritative(
      int activePlayers, int membershipMask, Uint8Array commandVector) {
    if (engine == null || multiplayerConsistency == null || !engine.netgame) {
      throw new IllegalStateException("multiplayer engine is not initialized");
    }
    int allowedMembership = (1 << activePlayers) - 1;
    if (activePlayers < 2 || activePlayers > 4 || commandVector == null
        || commandVector.getLength() != 4 * ticcmd_t.TICCMDLEN
        || (membershipMask & 1) == 0
        || (membershipMask & ~allowedMembership) != 0) {
      throw new IllegalArgumentException("multiplayer command vector");
    }
    for (int player = 0; player < engine.playeringame.length; player++) {
      engine.playeringame[player] = player < activePlayers
          && (membershipMask & (1 << player)) != 0;
    }
    int buffer = (engine.gametic / engine.getTicdup())
        % engine.netcmds[0].length;
    for (int player = 0; player < 4; player++) {
      int offset = player * ticcmd_t.TICCMDLEN;
      if (player >= activePlayers || !engine.playeringame[player]) {
        for (int index = 0; index < ticcmd_t.TICCMDLEN; index++) {
          if (commandVector.get(offset + index) != 0) {
            throw new IllegalArgumentException("inactive player command " + player);
          }
        }
        continue;
      }
      ticcmd_t command = engine.netcmds[player][buffer];
      command.forwardmove = (byte) commandVector.get(offset);
      command.sidemove = (byte) commandVector.get(offset + 1);
      command.angleturn = (short) (((commandVector.get(offset + 2) & 0xff) << 8)
          | (commandVector.get(offset + 3) & 0xff));
      command.consistancy = multiplayerConsistency[player][buffer];
      command.chatchar = (char) (commandVector.get(offset + 6) & 0xff);
      command.buttons = (char) (commandVector.get(offset + 7) & 0xff);
      command.lookfly = 0;
    }
    canonicalStateCache = null;
    checkpointCacheBytes = 0;
    engine.Ticker();
    for (int player = 0; player < activePlayers; player++) {
      if (!engine.playeringame[player]) continue;
      multiplayerConsistency[player][buffer] =
          engine.doomdbConsistency(player, buffer);
    }
    engine.gametic++;
    return engine.gametic;
  }

  /** Apply one caller-owned ticcmd and advance the resident simulation once. */
  @JSExport
  public static String step(
      int forwardMove, int sideMove, int angleTurn, int buttons) {
    stepCore(forwardMove, sideMove, angleTurn, buttons);
    return snapshot("stepped");
  }

  /** Advance exactly as {@link #step}, returning only the new gametic. */
  @JSExport
  public static int stepBare(
      int forwardMove, int sideMove, int angleTurn, int buttons) {
    return stepCore(forwardMove, sideMove, angleTurn, 0, buttons);
  }

  /** Apply one exact durable ticcmd including its consistency/control field. */
  @JSExport
  public static int stepCommandBare(
      int forwardMove, int sideMove, int angleTurn, int consistency,
      int buttons) {
    return stepCore(
        forwardMove, sideMove, angleTurn, consistency, buttons);
  }

  /** Shared command application and ticker path for all step exports. */
  private static int stepCore(
      int forwardMove, int sideMove, int angleTurn, int buttons) {
    return stepCore(forwardMove, sideMove, angleTurn, 0, buttons);
  }

  private static int stepCore(
      int forwardMove, int sideMove, int angleTurn, int consistency,
      int buttons) {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    canonicalStateCache = null;
    checkpointCacheBytes = 0;
    int buffer = (engine.gametic / engine.getTicdup())
        % engine.netcmds[engine.consoleplayer].length;
    ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
    command.forwardmove = (byte) clamp(forwardMove, -127, 127);
    command.sidemove = (byte) clamp(sideMove, -127, 127);
    command.angleturn = (short) clamp(angleTurn, Short.MIN_VALUE, Short.MAX_VALUE);
    command.consistancy = (short) clamp(
        consistency, Short.MIN_VALUE, Short.MAX_VALUE);
    command.chatchar = 0;
    command.buttons = (char) (buttons & 0xff);
    command.lookfly = 0;
    engine.Ticker();
    engine.gametic++;
    return engine.gametic;
  }

  /** Read a deterministic, renderer-independent state snapshot. */
  @JSExport
  public static String currentState() {
    if (engine == null) return "state=uninitialized";
    return snapshot("current");
  }

  /** Full save-semantic identity shared byte-for-byte with the OJVM oracle. */
  @JSExport
  public static String canonicalState() throws Exception {
    if (engine == null) return "state=uninitialized";
    return DoomDbMochaAdapter.canonicalStateDigest(engine);
  }

  /** Build and retain canonical bytes so PL/SQL can fetch them in RAW chunks. */
  @JSExport
  public static int canonicalStateLength() throws Exception {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    canonicalStateCache = DoomDbMochaAdapter.canonicalStateMaterial(engine);
    return canonicalStateCache.length;
  }

  /** Return one Oracle-RAW-sized slice of the retained canonical material. */
  @JSExport
  public static Uint8Array canonicalStateChunk(int offset, int length) {
    if (canonicalStateCache == null) {
      throw new IllegalStateException("canonical state length must be read first");
    }
    if (offset < 0 || length < 0 || length > 32767
        || offset > canonicalStateCache.length - length) {
      throw new IllegalArgumentException(
          "canonical state chunk offset=" + offset + " length=" + length);
    }
    Uint8Array result = Uint8Array.create(length);
    for (int index = 0; index < length; index++) {
      result.set(index, (short) (canonicalStateCache[offset + index] & 0xff));
    }
    return result;
  }

  /** Serialize a recoverable Mocha checkpoint and retain it for RAW export. */
  @JSExport
  public static int checkpointLength() throws Exception {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    IDoomSaveGameHeader header = new VanillaDSGHeader();
    header.setName("DoomDB MLE checkpoint");
    header.setVersion("version " + data.Defines.VERSION);
    header.setGameskill(engine.gameskill);
    header.setGameepisode(engine.gameepisode);
    header.setGamemap(engine.gamemap);
    header.setPlayeringame(engine.playeringame);
    header.setLeveltime(engine.leveltime);
    IDoomSaveGame save = new VanillaDSG<Object, Object>(
        (DoomMain<Object, Object>) engine);
    save.setHeader(header);
    if (vanillaCheckpointOutput == null) {
      vanillaCheckpointOutput = new ReusableByteArrayOutputStream(256 * 1024);
    } else {
      vanillaCheckpointOutput.reset();
    }
    boolean saved;
    C2JUtils.setCanonicalSavePointers(true);
    try (DataOutputStream data = new DataOutputStream(vanillaCheckpointOutput)) {
      saved = save.doSave(data);
    } finally {
      C2JUtils.setCanonicalSavePointers(false);
    }
    if (!saved) throw new IllegalStateException("Mocha checkpoint save failed");
    int vanillaLength = vanillaCheckpointOutput.size();
    ArrayList<thinker_t> thinkers = checkpointThinkers();
    IdentityHashMap<thinker_t, Integer> thinkerIndices =
        checkpointIdentityMap(thinkers);
    IdentityHashMap<Object, Integer> subsectorIndices =
        checkpointIdentityMap(engine.levelLoader.subsectors);
    int envelopeCapacity = vanillaLength + thinkers.size() * 80 + 8192;
    if (envelopeCheckpointOutput == null) {
      envelopeCheckpointOutput = new ReusableByteArrayOutputStream(envelopeCapacity);
    } else {
      envelopeCheckpointOutput.reset();
    }
    try (DataOutputStream envelope = new DataOutputStream(envelopeCheckpointOutput)) {
      envelope.writeInt(0x444d4331); // DMC1 DoomDB MLE checkpoint.
      envelope.writeInt(5);
      envelope.writeInt(engine.gametic);
      envelope.writeInt(engine.random.getIndex());
      envelope.writeInt(engine.netgame ? 1 : 0);
      envelope.writeInt(engine.deathmatch ? 1 : 0);
      envelope.writeInt(engine.consoleplayer);
      envelope.writeInt(engine.displayplayer);
      int consistencyRows = multiplayerConsistency == null
          ? 0 : multiplayerConsistency.length;
      int consistencyColumns = consistencyRows == 0
          ? 0 : multiplayerConsistency[0].length;
      envelope.writeInt(consistencyRows);
      envelope.writeInt(consistencyColumns);
      for (int row = 0; row < consistencyRows; row++) {
        for (int column = 0; column < consistencyColumns; column++) {
          envelope.writeShort(multiplayerConsistency[row][column]);
        }
      }
      envelope.writeInt(vanillaLength);
      envelope.write(vanillaCheckpointOutput.buffer(), 0, vanillaLength);
      // Vanilla savegames omit player_t records for players not currently in
      // playeringame.  Retain all four records so a recovered worker can make
      // an inactive member visible again without resurrecting fresh-init
      // state on rejoin.
      envelope.writeInt(engine.players.length);
      for (player_t player : engine.players) {
        if (player.readyweapon == null || player.pendingweapon == null) {
          envelope.writeInt(0);
          continue;
        }
        if (playerCheckpointOutput == null) {
          playerCheckpointOutput = new ReusableByteArrayOutputStream(280);
        } else {
          playerCheckpointOutput.reset();
        }
        C2JUtils.setCanonicalSavePointers(true);
        try (DataOutputStream playerData =
                 new DataOutputStream(playerCheckpointOutput)) {
          player.write(playerData);
        } finally {
          C2JUtils.setCanonicalSavePointers(false);
        }
        int playerBytes = playerCheckpointOutput.size();
        if (playerBytes != 280) {
          throw new IllegalStateException("checkpoint player bytes " + playerBytes);
        }
        envelope.writeInt(playerBytes);
        envelope.write(playerCheckpointOutput.buffer(), 0, playerBytes);
      }
      envelope.writeInt(thinkers.size());
      for (thinker_t thinker : thinkers) {
        envelope.writeInt(thinker.thinkerFunction.ordinal());
        if (thinker instanceof p.mobj_t) {
          p.mobj_t mobj = (p.mobj_t) thinker;
          envelope.writeInt(1);
          envelope.writeInt(checkpointIdentityIndex(thinkerIndices, mobj.snext));
          envelope.writeInt(checkpointIdentityIndex(thinkerIndices, mobj.sprev));
          envelope.writeInt(checkpointIdentityIndex(thinkerIndices, mobj.bnext));
          envelope.writeInt(checkpointIdentityIndex(thinkerIndices, mobj.bprev));
          envelope.writeInt(checkpointIdentityIndex(thinkerIndices, mobj.target));
          envelope.writeInt(checkpointIdentityIndex(thinkerIndices, mobj.tracer));
          envelope.writeInt(checkpointIdentityIndex(
              subsectorIndices, mobj.subsector));
          envelope.writeInt(checkpointIdentityIndex(engine.players, mobj.player));
          envelope.writeLong(mobj.angle);
          envelope.writeLong(mobj.mobj_tics);
          envelope.writeLong(mobj.flags);
          envelope.writeInt(mobj.floorz);
          envelope.writeInt(mobj.ceilingz);
        } else {
          envelope.writeInt(0);
        }
      }
      envelope.writeInt(engine.players.length);
      for (player_t player : engine.players) {
        envelope.writeInt(checkpointIdentityIndex(thinkerIndices, player.mo));
        envelope.writeInt(checkpointIdentityIndex(thinkerIndices, player.attacker));
      }
      envelope.writeInt(engine.levelLoader.sectors.length);
      for (rr.sector_t sector : engine.levelLoader.sectors) {
        envelope.writeInt(checkpointIdentityIndex(thinkerIndices, sector.thinglist));
      }
      envelope.writeInt(engine.levelLoader.blocklinks.length);
      for (p.mobj_t root : engine.levelLoader.blocklinks) {
        envelope.writeInt(checkpointIdentityIndex(thinkerIndices, root));
      }
    }
    checkpointCacheBytes = envelopeCheckpointOutput.size();
    if (checkpointCache == null || checkpointCache.length < checkpointCacheBytes) {
      checkpointCache = new byte[checkpointCacheBytes];
    }
    System.arraycopy(envelopeCheckpointOutput.buffer(), 0,
        checkpointCache, 0, checkpointCacheBytes);
    return checkpointCacheBytes;
  }

  /** Return one Oracle-RAW-sized checkpoint slice. */
  @JSExport
  public static Uint8Array checkpointChunk(int offset, int length) {
    if (checkpointCache == null || checkpointCacheBytes == 0) {
      throw new IllegalStateException("checkpoint length must be read first");
    }
    if (offset < 0 || length < 0 || length > 32767
        || offset > checkpointCacheBytes - length) {
      throw new IllegalArgumentException(
          "checkpoint chunk offset=" + offset + " length=" + length);
    }
    Uint8Array result = Uint8Array.create(length);
    for (int index = 0; index < length; index++) {
      result.set(index, (short) (checkpointCache[offset + index] & 0xff));
    }
    return result;
  }

  /** Allocate a bounded checkpoint buffer before database-to-MLE transfer. */
  @JSExport
  public static int allocateCheckpoint(int length) {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    if (length < 64 || length > 16 * 1024 * 1024) {
      throw new IllegalArgumentException("checkpoint length " + length);
    }
    checkpointLoadBuffer = new byte[length];
    checkpointBytesLoaded = 0;
    multiplayerConsistency = null;
    return length;
  }

  /** Copy the next bounded checkpoint chunk into retained MLE state. */
  @JSExport
  public static int loadCheckpointChunk(int offset, Uint8Array chunk) {
    if (checkpointLoadBuffer == null) {
      throw new IllegalStateException("allocate checkpoint first");
    }
    if (chunk == null || offset != checkpointBytesLoaded
        || offset > checkpointLoadBuffer.length - chunk.getLength()) {
      throw new IllegalArgumentException("checkpoint load offset " + offset);
    }
    for (int index = 0; index < chunk.getLength(); index++) {
      checkpointLoadBuffer[offset + index] = (byte) chunk.get(index);
    }
    checkpointBytesLoaded += chunk.getLength();
    return checkpointBytesLoaded;
  }

  /** Restore the resident engine from a fully transferred verified checkpoint. */
  @JSExport
  public static String restoreCheckpoint(int expectedTic) {
    return restoreCheckpointResult(expectedTic, false);
  }

  /**
   * Restore into a retained engine already at the checkpoint's exact origin.
   * Fail-closed origin checks guard the InitNew omission.
   */
  @JSExport
  public static String restoreCheckpointWarm(int expectedTic) {
    return restoreCheckpointResult(expectedTic, true);
  }

  private static String restoreCheckpointResult(
      int expectedTic, boolean requireWarmOrigin) {
    try {
      return restoreCheckpointCore(expectedTic, requireWarmOrigin);
    } catch (Throwable failure) {
      StringBuilder result = new StringBuilder("error|type=")
          .append(failure.getClass().getName()).append("|message=")
          .append(failure.getMessage());
      StackTraceElement[] trace = failure.getStackTrace();
      for (int index = 0; index < trace.length && index < 12; index++) {
        result.append("|at").append(index).append('=').append(trace[index]);
      }
      return result.toString();
    }
  }

  private static String restoreCheckpointCore(
      int expectedTic, boolean requireWarmOrigin) throws Exception {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    if (checkpointLoadBuffer == null
        || checkpointBytesLoaded != checkpointLoadBuffer.length) {
      throw new IllegalStateException("checkpoint is not fully loaded");
    }
    if (expectedTic < 0) throw new IllegalArgumentException("checkpoint tic " + expectedTic);
    byte[] vanilla;
    int checkpointTic;
    int randomIndex;
    boolean checkpointNetgame;
    boolean checkpointDeathmatch;
    int checkpointConsolePlayer;
    int checkpointDisplayPlayer;
    short[][] checkpointConsistency;
    byte[][] checkpointPlayers;
    int[][] topology;
    long[][] topologyLongs;
    int[][] playerReferences;
    int[] sectorRoots;
    int[] blockRoots;
    try (DataInputStream envelope = new DataInputStream(
        new ByteArrayInputStream(checkpointLoadBuffer))) {
      if (envelope.readInt() != 0x444d4331 || envelope.readInt() != 5) {
        throw new IllegalArgumentException("checkpoint envelope mismatch");
      }
      checkpointTic = envelope.readInt();
      randomIndex = envelope.readInt();
      checkpointNetgame = envelope.readInt() != 0;
      checkpointDeathmatch = envelope.readInt() != 0;
      checkpointConsolePlayer = envelope.readInt();
      checkpointDisplayPlayer = envelope.readInt();
      int consistencyRows = envelope.readInt();
      int consistencyColumns = envelope.readInt();
      if (consistencyRows < 0 || consistencyRows > 4
          || consistencyColumns < 0 || consistencyColumns > 1024
          || (consistencyRows == 0) != (consistencyColumns == 0)) {
        throw new IllegalArgumentException("checkpoint consistency shape");
      }
      checkpointConsistency = consistencyRows == 0
          ? null : new short[consistencyRows][consistencyColumns];
      for (int row = 0; row < consistencyRows; row++) {
        for (int column = 0; column < consistencyColumns; column++) {
          checkpointConsistency[row][column] = envelope.readShort();
        }
      }
      int vanillaLength = envelope.readInt();
      if (vanillaLength < 64 || vanillaLength > checkpointLoadBuffer.length - 44) {
        throw new IllegalArgumentException("checkpoint payload length " + vanillaLength);
      }
      vanilla = new byte[vanillaLength];
      envelope.readFully(vanilla);
      int checkpointPlayerCount = envelope.readInt();
      if (checkpointPlayerCount != engine.players.length) {
        throw new IllegalArgumentException(
            "checkpoint player snapshot count " + checkpointPlayerCount);
      }
      checkpointPlayers = new byte[checkpointPlayerCount][];
      for (int player = 0; player < checkpointPlayerCount; player++) {
        int playerLength = envelope.readInt();
        if (playerLength != 0 && playerLength != 280) {
          throw new IllegalArgumentException(
              "checkpoint player snapshot bytes " + playerLength);
        }
        if (playerLength != 0) {
          checkpointPlayers[player] = new byte[playerLength];
          envelope.readFully(checkpointPlayers[player]);
        }
      }
      int thinkerCount = envelope.readInt();
      if (thinkerCount < 0 || thinkerCount > 1000000) {
        throw new IllegalArgumentException("checkpoint thinker count " + thinkerCount);
      }
      topology = new int[thinkerCount][12];
      topologyLongs = new long[thinkerCount][3];
      for (int index = 0; index < thinkerCount; index++) {
        topology[index][0] = envelope.readInt();
        topology[index][1] = envelope.readInt();
        if (topology[index][1] != 0) {
          for (int field = 2; field < 10; field++) {
            topology[index][field] = envelope.readInt();
          }
          topologyLongs[index][0] = envelope.readLong();
          topologyLongs[index][1] = envelope.readLong();
          topologyLongs[index][2] = envelope.readLong();
          topology[index][10] = envelope.readInt();
          topology[index][11] = envelope.readInt();
        }
      }
      int playerCount = envelope.readInt();
      if (playerCount != engine.players.length) {
        throw new IllegalArgumentException("checkpoint player count " + playerCount);
      }
      playerReferences = new int[playerCount][2];
      for (int index = 0; index < playerCount; index++) {
        playerReferences[index][0] = envelope.readInt();
        playerReferences[index][1] = envelope.readInt();
      }
      int sectorCount = envelope.readInt();
      if (sectorCount != engine.levelLoader.sectors.length) {
        throw new IllegalArgumentException("checkpoint sector count " + sectorCount);
      }
      sectorRoots = new int[sectorCount];
      for (int index = 0; index < sectorCount; index++) {
        sectorRoots[index] = envelope.readInt();
      }
      int blockCount = envelope.readInt();
      if (blockCount != engine.levelLoader.blocklinks.length) {
        throw new IllegalArgumentException("checkpoint block count " + blockCount);
      }
      blockRoots = new int[blockCount];
      for (int index = 0; index < blockCount; index++) {
        blockRoots[index] = envelope.readInt();
      }
      if (envelope.available() != 0) {
        throw new IllegalArgumentException("checkpoint trailing bytes " + envelope.available());
      }
    }
    if (checkpointTic != expectedTic || randomIndex < 0 || randomIndex > 255) {
      throw new IllegalArgumentException("checkpoint frontier mismatch");
    }
    VanillaDSGHeader header = new VanillaDSGHeader();
    try (DataInputStream data = new DataInputStream(
        new ByteArrayInputStream(vanilla))) {
      header.read(data);
    }
    if (!("version " + data.Defines.VERSION).equals(header.getVersion())) {
      throw new IllegalArgumentException("checkpoint version mismatch");
    }
    if (requireWarmOrigin) {
      if (engine.gametic != 0
          || engine.gameskill != header.getGameskill()
          || engine.gameepisode != header.getGameepisode()
          || engine.gamemap != header.getGamemap()
          || !Arrays.equals(engine.playeringame, header.getPlayeringame())
          || engine.netgame != checkpointNetgame
          || engine.deathmatch != checkpointDeathmatch
          || engine.consoleplayer != checkpointConsolePlayer
          || engine.displayplayer != checkpointDisplayPlayer) {
        throw new IllegalStateException(
            "warm checkpoint origin does not match retained engine");
      }
    }
    engine.gameskill = header.getGameskill();
    engine.gameepisode = header.getGameepisode();
    engine.gamemap = header.getGamemap();
    System.arraycopy(header.getPlayeringame(), 0, engine.playeringame, 0,
        engine.playeringame.length);
    engine.netgame = checkpointNetgame;
    engine.deathmatch = checkpointDeathmatch;
    engine.consoleplayer = checkpointConsolePlayer;
    engine.displayplayer = checkpointDisplayPlayer;
    if (!requireWarmOrigin) {
      engine.InitNew(engine.gameskill, engine.gameepisode, engine.gamemap);
    }
    engine.singletics = true;
    engine.leveltime = header.getLeveltime();
    IDoomSaveGame save = new VanillaDSG<Object, Object>(
        (DoomMain<Object, Object>) engine);
    boolean loaded;
    try (DataInputStream data = new DataInputStream(
        new ByteArrayInputStream(vanilla))) {
      loaded = save.doLoad(data);
    }
    if (!loaded) throw new IllegalStateException("Mocha checkpoint load failed");
    for (int player = 0; player < engine.players.length; player++) {
      if (checkpointPlayers[player] == null) continue;
      try (DataInputStream playerData = new DataInputStream(
          new ByteArrayInputStream(checkpointPlayers[player]))) {
        engine.players[player].read(playerData);
        if (playerData.available() != 0) {
          throw new IllegalStateException(
              "checkpoint player trailing bytes " + playerData.available());
        }
      }
    }
    // VanillaDSG reads the numeric psprite state into readstate, but its
    // fix-up tests the pre-load object reference.  A fresh multiplayer engine
    // can have a null reference there and silently lose a non-null saved
    // weapon state.  Reconstruct from the serialized ID unconditionally.
    for (int player = 0; player < engine.players.length; player++) {
      if (checkpointPlayers[player] == null) continue;
      for (p.pspdef_t psprite : engine.players[player].psprites) {
        psprite.state = psprite.readstate == 0
            ? null : data.info.states[psprite.readstate];
      }
    }
    ArrayList<thinker_t> loadedThinkers = checkpointThinkers();
    if (loadedThinkers.size() != topology.length) {
      throw new IllegalStateException("checkpoint restored thinker count "
          + loadedThinkers.size());
    }
    ArrayList<thinker_t> loadedMobjs = new ArrayList<thinker_t>();
    ArrayList<thinker_t> loadedSpecials = new ArrayList<thinker_t>();
    for (thinker_t thinker : loadedThinkers) {
      if (thinker instanceof p.mobj_t) loadedMobjs.add(thinker);
      else loadedSpecials.add(thinker);
    }
    ArrayList<thinker_t> restoredThinkers = new ArrayList<thinker_t>();
    int mobjIndex = 0;
    int specialIndex = 0;
    for (int index = 0; index < topology.length; index++) {
      thinker_t thinker = topology[index][1] != 0
          ? loadedMobjs.get(mobjIndex++) : loadedSpecials.get(specialIndex++);
      if (thinker.thinkerFunction.ordinal() != topology[index][0]) {
        throw new IllegalStateException("checkpoint thinker shape " + index);
      }
      restoredThinkers.add(thinker);
    }
    thinker_t cap = engine.actions.getThinkerCap();
    cap.next = restoredThinkers.isEmpty() ? cap : restoredThinkers.get(0);
    cap.prev = restoredThinkers.isEmpty()
        ? cap : restoredThinkers.get(restoredThinkers.size() - 1);
    for (int index = 0; index < restoredThinkers.size(); index++) {
      thinker_t thinker = restoredThinkers.get(index);
      thinker.prev = index == 0 ? cap : restoredThinkers.get(index - 1);
      thinker.next = index + 1 == restoredThinkers.size()
          ? cap : restoredThinkers.get(index + 1);
      if (thinker instanceof p.mobj_t) {
        p.mobj_t mobj = (p.mobj_t) thinker;
        mobj.snext = checkpointThinker(restoredThinkers, topology[index][2]);
        mobj.sprev = checkpointThinker(restoredThinkers, topology[index][3]);
        mobj.bnext = checkpointThinker(restoredThinkers, topology[index][4]);
        mobj.bprev = checkpointThinker(restoredThinkers, topology[index][5]);
        mobj.target = (p.mobj_t) checkpointThinker(restoredThinkers, topology[index][6]);
        mobj.tracer = (p.mobj_t) checkpointThinker(restoredThinkers, topology[index][7]);
        mobj.subsector = topology[index][8] < 0 ? null
            : engine.levelLoader.subsectors[topology[index][8]];
        mobj.player = topology[index][9] < 0 ? null
            : engine.players[topology[index][9]];
        mobj.angle = topologyLongs[index][0];
        mobj.mobj_tics = topologyLongs[index][1];
        mobj.flags = topologyLongs[index][2];
        mobj.floorz = topology[index][10];
        mobj.ceilingz = topology[index][11];
      }
    }
    for (int index = 0; index < engine.players.length; index++) {
      engine.players[index].mo = (p.mobj_t) checkpointThinker(
          restoredThinkers, playerReferences[index][0]);
      engine.players[index].attacker = (p.mobj_t) checkpointThinker(
          restoredThinkers, playerReferences[index][1]);
    }
    for (int index = 0; index < sectorRoots.length; index++) {
      engine.levelLoader.sectors[index].thinglist = (p.mobj_t) checkpointThinker(
          restoredThinkers, sectorRoots[index]);
    }
    for (int index = 0; index < blockRoots.length; index++) {
      engine.levelLoader.blocklinks[index] = (p.mobj_t) checkpointThinker(
          restoredThinkers, blockRoots[index]);
    }
    engine.gametic = expectedTic;
    for (int advances = 0;
         engine.random.getIndex() != randomIndex && advances < 256;
         advances++) {
      engine.random.P_Random();
    }
    if (engine.random.getIndex() != randomIndex) {
      throw new IllegalStateException("checkpoint RNG restore failed");
    }
    if (checkpointConsistency != null) {
      if (checkpointConsistency.length != engine.playeringame.length
          || checkpointConsistency[0].length != engine.netcmds[0].length) {
        throw new IllegalStateException("checkpoint consistency dimensions");
      }
      for (int player = 0; player < checkpointConsistency.length; player++) {
        for (int buffer = 0; buffer < checkpointConsistency[player].length; buffer++) {
          engine.doomdbSetConsistency(
              player, buffer, checkpointConsistency[player][buffer]);
        }
      }
    }
    multiplayerConsistency = checkpointConsistency;
    canonicalStateCache = null;
    checkpointCacheBytes = 0;
    return snapshot("restored");
  }

  /** Cheap retained-state inventory without relying on a JVM heap API. */
  @JSExport
  public static String memoryDiagnostic() {
    if (engine == null) return "state=uninitialized";
    int thinkers = 0;
    int mobjs = 0;
    int killMonsters = 0;
    int livingMonsters = 0;
    int awakeMonsters = 0;
    int movingMonsters = 0;
    final long mfCountKill = 0x00400000L;
    thinker_t cap = engine.actions.getThinkerCap();
    for (thinker_t thinker = cap.next;
        thinker != null && thinker != cap && thinkers < 1000000;
        thinker = thinker.next) {
      thinkers++;
      if (thinker instanceof p.mobj_t) {
        p.mobj_t mobj = (p.mobj_t) thinker;
        mobjs++;
        if ((mobj.flags & mfCountKill) != 0) {
          killMonsters++;
          if (mobj.health > 0) livingMonsters++;
          if (mobj.health > 0 && mobj.target != null) awakeMonsters++;
          if (mobj.health > 0
              && (mobj.momx != 0 || mobj.momy != 0 || mobj.momz != 0)) {
            movingMonsters++;
          }
        }
      }
    }
    Object foreground = engine.graphicSystem.getScreen(
        v.renderers.DoomScreen.FG);
    int frameBytes = foreground instanceof byte[] ? ((byte[]) foreground).length : -1;
    return "iwadBytes=" + (iwad == null ? 0 : iwad.length)
        + "|frameBytes=" + frameBytes
        + "|thinkers=" + thinkers
        + "|mobjs=" + mobjs
        + "|killMonsters=" + killMonsters
        + "|livingMonsters=" + livingMonsters
        + "|awakeMonsters=" + awakeMonsters
        + "|movingMonsters=" + movingMonsters
        + "|vertexes=" + engine.levelLoader.numvertexes
        + "|segs=" + engine.levelLoader.numsegs
        + "|sectors=" + engine.levelLoader.numsectors
        + "|subsectors=" + engine.levelLoader.numsubsectors
        + "|nodes=" + engine.levelLoader.numnodes
        + "|lines=" + engine.levelLoader.numlines
        + "|sides=" + engine.levelLoader.numsides
        + "|blockmapInts=" + length(engine.levelLoader.blockmap)
        + "|blocklinks=" + length(engine.levelLoader.blocklinks)
        + "|rejectBytes=" + length(engine.levelLoader.rejectmatrix);
  }

  /**
   * Render one confirmed player POV for the presentation-only TeaVM root.
   *
   * This method deliberately is not a JS export from the authoritative root.
   * TeaVM can prune the Display graph from that artifact while the separate
   * presentation root calls it from the same simulation adapter bytecode.
   */
  static byte[] renderPlayerFrameBytes(int playerSlot) throws Exception {
    if (engine == null || multiplayerConsistency == null || !engine.netgame) {
      throw new IllegalStateException("multiplayer engine is not initialized");
    }
    if (playerSlot < 0 || playerSlot >= engine.playeringame.length
        || !engine.playeringame[playerSlot]) {
      throw new IllegalArgumentException("inactive display player " + playerSlot);
    }
    int savedConsole = engine.consoleplayer;
    int savedDisplay = engine.displayplayer;
    try {
      engine.consoleplayer = playerSlot;
      engine.displayplayer = playerSlot;
      engine.statusBar.doomdbDisplayPlayer(playerSlot);
      if (engine.headsUp != null) engine.headsUp.doomdbDisplayPlayer(playerSlot);
      engine.Display();
      Object foreground = engine.graphicSystem.getScreen(DoomScreen.FG);
      if (!(foreground instanceof byte[]) || ((byte[]) foreground).length != 320 * 200) {
        throw new IllegalStateException("indexed framebuffer unavailable");
      }
      byte[] pixels = (byte[]) foreground;
      // Mocha's desktop status lifecycle never populates its off-screen SB
      // buffer in the TeaVM headless engine. Compose the two immutable
      // backgrounds once per player, then restore that exact indexed region
      // with a bulk copy before applying Mocha's dynamic widget rules.
      // This is presentation-only state and the canonical before/after guard
      // proves it cannot mutate authority.
      if (presentationStatusBackgrounds == null) {
        presentationStatusBackgrounds = new byte[engine.playeringame.length][];
      }
      byte[] statusBackground = presentationStatusBackgrounds[playerSlot];
      if (statusBackground == null) {
        drawIndexedPatch(engine.wadLoader.CachePatchName("STBAR"), 0, 168);
        drawIndexedPatch(engine.wadLoader.CachePatchName("STFB" + playerSlot), 143, 168);
        statusBackground = new byte[320 * 32];
        for (int index = 0; index < statusBackground.length; index++) {
          statusBackground[index] = pixels[320 * 168 + index];
        }
        presentationStatusBackgrounds[playerSlot] = statusBackground;
      } else {
        for (int index = 0; index < statusBackground.length; index++) {
          pixels[320 * 168 + index] = statusBackground[index];
        }
      }
      engine.statusBar.doomdbDrawWidgets(true);
      return pixels;
    } finally {
      engine.statusBar.doomdbDisplayPlayer(savedConsole);
      if (engine.headsUp != null) engine.headsUp.doomdbDisplayPlayer(savedConsole);
      engine.consoleplayer = savedConsole;
      engine.displayplayer = savedDisplay;
    }
  }

  static Uint8Array renderPlayerFrame(int playerSlot) throws Exception {
    byte[] pixels = renderPlayerFrameBytes(playerSlot);
    Uint8Array result = Uint8Array.create(pixels.length);
    for (int index = 0; index < pixels.length; index++) {
      result.set(index, (short) (pixels[index] & 0xff));
    }
    return result;
  }

  private static void drawIndexedPatch(patch_t patch, int x, int y) {
    byte[] destination = (byte[]) engine.graphicSystem.getScreen(DoomScreen.FG);
    int originX = x - patch.leftoffset;
    int originY = y - patch.topoffset;
    for (int columnIndex = 0; columnIndex < patch.width; columnIndex++) {
      int targetX = originX + columnIndex;
      if (targetX < 0 || targetX >= 320) continue;
      rr.column_t column = patch.columns[columnIndex];
      for (int post = 0;
          post < column.posts && column.postdeltas[post] != 0xff;
          post++) {
        int targetY = originY + column.postdeltas[post];
        for (int pixel = 0; pixel < column.postlen[post]; pixel++) {
          int screenY = targetY + pixel;
          if (screenY >= 0 && screenY < 200) {
            destination[screenY * 320 + targetX] =
                column.data[column.postofs[post] + pixel];
          }
        }
      }
    }
  }

  /**
   * Select Doom's full-width gameplay view with the canonical 32-pixel status
   * bar. Screenblocks 11 hid the HUD and made the presentation artifact an
   * incomplete world-only renderer; screenblocks 10 retains the exact Mocha
   * status-bar composition while preserving the 320x200 indexed framebuffer.
   */
  static void initializePresentationView() {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    engine.sceneRenderer.SetViewSize(10, 0);
  }

  /**
   * Candidate-only diagnostic access for the exact raster stage harness.
   * This method is not exported and is unreachable from production roots.
   */
  static DoomMain<?, ?> presentationEngineForDiagnostic() {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    return engine;
  }

  /** Presentation caches are derived state and must full-refresh after restore. */
  static void resetPresentationStatusAfterRestore() {
    presentationStatusBackgrounds = null;
  }

  /** Palette selected by the exact Mocha status-bar presentation pass. */
  static int presentationPaletteIndex() {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    return engine.graphicSystem.getPalette();
  }

  /** Expose presentation geometry without adding it to the authority root. */
  static String presentationDiagnostic() {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    Object foreground = engine.graphicSystem.getScreen(DoomScreen.FG);
    Object status = engine.graphicSystem.getScreen(DoomScreen.SB);
    patch_t statusPatch = engine.wadLoader.CachePatchName("STBAR");
    int statusPosts = 0;
    int statusPixels = 0;
    int statusData = 0;
    if (statusPatch.columns != null) {
      for (int index = 0; index < statusPatch.columns.length; index++) {
        if (statusPatch.columns[index] != null) {
          statusPosts += statusPatch.columns[index].posts;
          for (int post = 0; post < statusPatch.columns[index].posts; post++) {
            statusPixels += statusPatch.columns[index].postlen[post];
          }
          statusData += nonzero(statusPatch.columns[index].data, 0,
              statusPatch.columns[index].data.length);
        }
      }
    }
    return "fullHeight=" + engine.sceneRenderer.isFullHeight()
        + "|fullScreen=" + engine.sceneRenderer.isFullScreen()
        + "|setSizeNeeded=" + engine.sceneRenderer.getSetSizeNeeded()
        + "|statusHeight=" + engine.statusBar.getHeight()
        + "|fgHud=" + nonzero((byte[]) foreground, 320 * 168, 320 * 32)
        + "|statusBuffer=" + nonzero((byte[]) status, 0, 320 * 32)
        + "|statusPatch=" + statusPatch.width + "x" + statusPatch.height
        + "|statusColumns=" + (statusPatch.columns == null ? -1
            : statusPatch.columns.length)
        + "|statusPosts=" + statusPosts
        + "|statusPixels=" + statusPixels
        + "|statusData=" + statusData;
  }

  /**
   * Export the bounded live player view consumed by the specialized MLE
   * rasterizer.  This is presentation input only: the authoritative engine
   * continues to own and advance all of these values.
   */
  @JSExport
  public static Uint8Array presentationPlayerSnapshot(int playerSlot) {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    if (playerSlot < 0 || playerSlot >= engine.players.length
        || !engine.playeringame[playerSlot]) {
      throw new IllegalArgumentException("inactive player slot " + playerSlot);
    }
    player_t player = engine.players[playerSlot];
    if (player.mo == null) {
      throw new IllegalStateException("player has no mobj " + playerSlot);
    }
    Uint8Array snapshot = Uint8Array.create(32);
    putSnapshotI32(snapshot, 0, player.mo.x);
    putSnapshotI32(snapshot, 4, player.mo.y);
    putSnapshotI32(snapshot, 8, (int) player.mo.angle >>> 16);
    putSnapshotI32(snapshot, 12, player.viewz);
    putSnapshotI32(snapshot, 16, player.health[0]);
    putSnapshotI32(snapshot, 20, player.armorpoints[0]);
    putSnapshotI32(snapshot, 24, player.readyweapon.ordinal());
    putSnapshotI32(snapshot, 28, player.ammo[0]);
    return snapshot;
  }

  /**
   * Build the bounded binary world snapshot consumed by the live MLE
   * framebuffer renderer. The format is presentation-only and contains no
   * authority: it is regenerated from the canonical Mocha world after each
   * confirmed tic.
   *
   * <pre>
   * DVL2 header/player: 208 bytes
   * sector records:      16 bytes each
   * sidedef records:      8 bytes each
   * visible mobj records:24 bytes each for DVC4, 32 bytes for DVL2
   * </pre>
   */
  @JSExport
  public static int presentationWorldSnapshotLength(int playerSlot) {
    return buildPresentationWorldSnapshot(playerSlot, true, true, true, false);
  }

  /**
   * Build the retained-renderer update payload without sidedef changes.
   * This compatibility entry point remains useful for isolated measurements;
   * the live renderer uses the exact dirty-sidedef entry point below.
   */
  @JSExport
  public static int presentationWorldCompactSnapshotLength(int playerSlot) {
    return buildPresentationWorldSnapshot(playerSlot, false, true, true, false);
  }

  /** Camera plus sectors for the isolated world-raster module. */
  @JSExport
  public static int presentationWorldGeometrySnapshotLength(int playerSlot) {
    return buildPresentationWorldSnapshot(playerSlot, false, true, false, false);
  }

  /**
   * Camera, sectors, and sidedefs for the retained live world raster.
   *
   * <p>The framebuffer compositor owns the independently culled mobj stream,
   * so this export deliberately omits mobjs. It carries the current sector
   * heights, light levels, translated flat ids, and (when requested) sidedef
   * texture ids without making the rasterizer pay for a duplicate actor list.
   * Animated wall translation and sidedef mutations after the retained
   * full-side snapshot still require separate dirty-state propagation.
   */
  @JSExport
  public static int presentationWorldGeometryAndSidesSnapshotLength(
      int playerSlot) {
    return buildPresentationWorldSnapshot(playerSlot, true, true, false, false);
  }

  /**
   * Camera plus exact indexed sector and sidedef changes since the prior call.
   * DVL6 records only dirty indexes, so moving floors/ceilings, light and flat
   * changes, switches, animated walls, and scrolling texture offsets remain
   * current without serializing every sector and sidedef on every tic.
   */
  @JSExport
  public static int presentationWorldGeometryDeltaSnapshotLength(
      int playerSlot) {
    return buildPresentationWorldSnapshot(
        playerSlot, false, false, false, true);
  }

  /** Full HUD header plus visible mobjs for the isolated compositor. */
  @JSExport
  public static int presentationCompositorSnapshotLength(int playerSlot) {
    return buildPresentationWorldSnapshot(playerSlot, false, false, true, false);
  }

  private static int buildPresentationWorldSnapshot(
      int playerSlot, boolean includeSides, boolean includeSectors,
      boolean includeMobjs, boolean includeDirtySides) {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    if (playerSlot < 0 || playerSlot >= engine.players.length
        || !engine.playeringame[playerSlot]) {
      throw new IllegalArgumentException("inactive player slot " + playerSlot);
    }
    player_t player = engine.players[playerSlot];
    if (player.mo == null) {
      throw new IllegalStateException("player has no mobj " + playerSlot);
    }
    int mobjCount = 0;
    thinker_t cap = engine.actions.getThinkerCap();
    if (includeSides && includeMobjs) {
      for (thinker_t current = cap.next;
           current != null && current != cap;
           current = current.next) {
        if (!(current instanceof p.mobj_t)) continue;
        p.mobj_t mobj = (p.mobj_t) current;
        if (((int) mobj.flags & p.mobj_t.MF_NOSECTOR) != 0) continue;
        mobjCount++;
      }
    }
    int dirtySectorCount = 0;
    if (includeDirtySides) {
      rr.sector_t[] sectors = engine.levelLoader.sectors;
      if (presentationSectorFloor == null
          || presentationSectorFloor.length != sectors.length) {
        presentationSectorFloor = new int[sectors.length];
        presentationSectorCeiling = new int[sectors.length];
        presentationSectorLight = new char[sectors.length];
        presentationSectorFloorAsset = new char[sectors.length];
        presentationSectorCeilingAsset = new char[sectors.length];
        presentationSectorSpecial = new char[sectors.length];
        presentationDirtySectors = new int[sectors.length];
        presentationSectorStateInitialized = false;
      }
      for (int sectorIndex = 0;
           sectorIndex < sectors.length; sectorIndex++) {
        rr.sector_t sector = sectors[sectorIndex];
        int floor = sector.floorheight;
        int ceiling = sector.ceilingheight;
        char light = (char) sector.lightlevel;
        char floorAsset = (char)
            engine.textureManager.getFlatTranslation(sector.floorpic);
        char ceilingAsset = (char)
            engine.textureManager.getFlatTranslation(sector.ceilingpic);
        char special = (char) sector.special;
        if (!presentationSectorStateInitialized
            || floor != presentationSectorFloor[sectorIndex]
            || ceiling != presentationSectorCeiling[sectorIndex]
            || light != presentationSectorLight[sectorIndex]
            || floorAsset != presentationSectorFloorAsset[sectorIndex]
            || ceilingAsset != presentationSectorCeilingAsset[sectorIndex]
            || special != presentationSectorSpecial[sectorIndex]) {
          presentationDirtySectors[dirtySectorCount++] = sectorIndex;
          presentationSectorFloor[sectorIndex] = floor;
          presentationSectorCeiling[sectorIndex] = ceiling;
          presentationSectorLight[sectorIndex] = light;
          presentationSectorFloorAsset[sectorIndex] = floorAsset;
          presentationSectorCeilingAsset[sectorIndex] = ceilingAsset;
          presentationSectorSpecial[sectorIndex] = special;
        }
      }
      presentationSectorStateInitialized = true;
    }
    int dirtySideCount = 0;
    if (includeDirtySides) {
      rr.side_t[] sides = engine.levelLoader.sides;
      if (presentationSideTop == null
          || presentationSideTop.length != sides.length) {
        presentationSideTop = new char[sides.length];
        presentationSideBottom = new char[sides.length];
        presentationSideMiddle = new char[sides.length];
        presentationSideRawTop = new char[sides.length];
        presentationSideRawBottom = new char[sides.length];
        presentationSideRawMiddle = new char[sides.length];
        presentationSideSpecial = new char[sides.length];
        presentationSideTextureOffset = new int[sides.length];
        presentationSideRowOffset = new int[sides.length];
        presentationDirtySides = new int[sides.length];
        presentationCandidateSides = new int[sides.length];
        presentationCandidateSideFlags = new boolean[sides.length];
        presentationCandidateSideCount = 0;
        for (rr.line_t line : engine.levelLoader.lines) {
          if (line.special == 0) continue;
          for (int side = 0; side < line.sidenum.length; side++) {
            int sideIndex = line.sidenum[side];
            if (sideIndex == 0xffff
                || presentationCandidateSideFlags[sideIndex]) continue;
            presentationCandidateSideFlags[sideIndex] = true;
            presentationCandidateSides[presentationCandidateSideCount++] =
                sideIndex;
          }
        }
        presentationAnimatedSidesCataloged = false;
        presentationSideStateInitialized = false;
      }
      boolean animationBoundary = engine.leveltime % 8 == 0;
      boolean scanAll = !presentationSideStateInitialized
          || (!presentationAnimatedSidesCataloged
              && animationBoundary && engine.leveltime >= 8);
      int scanCount = scanAll
          ? sides.length : presentationCandidateSideCount;
      for (int scan = 0; scan < scanCount; scan++) {
        int sideIndex = scanAll ? scan : presentationCandidateSides[scan];
        rr.side_t side = sides[sideIndex];
        char rawTop = (char) side.toptexture;
        char rawBottom = (char) side.bottomtexture;
        char rawMiddle = (char) side.midtexture;
        boolean rawChanged = !presentationSideStateInitialized
            || rawTop != presentationSideRawTop[sideIndex]
            || rawBottom != presentationSideRawBottom[sideIndex]
            || rawMiddle != presentationSideRawMiddle[sideIndex];
        char top = presentationSideTop[sideIndex];
        char bottom = presentationSideBottom[sideIndex];
        char middle = presentationSideMiddle[sideIndex];
        if (rawChanged || animationBoundary) {
          top = (char) (side.toptexture == 0 ? 0
              : engine.textureManager.getTextureTranslation(side.toptexture));
          bottom = (char) (side.bottomtexture == 0 ? 0
              : engine.textureManager.getTextureTranslation(side.bottomtexture));
          middle = (char) (side.midtexture == 0 ? 0
              : engine.textureManager.getTextureTranslation(side.midtexture));
        }
        char special = (char) side.special;
        int textureOffset = side.textureoffset;
        int rowOffset = side.rowoffset;
        if (!presentationSideStateInitialized
            || rawChanged
            || top != presentationSideTop[sideIndex]
            || bottom != presentationSideBottom[sideIndex]
            || middle != presentationSideMiddle[sideIndex]
            || special != presentationSideSpecial[sideIndex]
            || textureOffset != presentationSideTextureOffset[sideIndex]
            || rowOffset != presentationSideRowOffset[sideIndex]) {
          presentationDirtySides[dirtySideCount++] = sideIndex;
          presentationSideTop[sideIndex] = top;
          presentationSideBottom[sideIndex] = bottom;
          presentationSideMiddle[sideIndex] = middle;
          presentationSideRawTop[sideIndex] = rawTop;
          presentationSideRawBottom[sideIndex] = rawBottom;
          presentationSideRawMiddle[sideIndex] = rawMiddle;
          presentationSideSpecial[sideIndex] = special;
          presentationSideTextureOffset[sideIndex] = textureOffset;
          presentationSideRowOffset[sideIndex] = rowOffset;
        }
        if (presentationSideStateInitialized
            && !presentationCandidateSideFlags[sideIndex]
            && (top != (char) (side.toptexture == 0 ? 0 : side.toptexture)
                || bottom != (char) (side.bottomtexture == 0
                    ? 0 : side.bottomtexture)
                || middle != (char) (side.midtexture == 0
                    ? 0 : side.midtexture))) {
          presentationCandidateSideFlags[sideIndex] = true;
          presentationCandidateSides[presentationCandidateSideCount++] =
              sideIndex;
        }
      }
      if (scanAll && presentationSideStateInitialized
          && animationBoundary && engine.leveltime >= 8) {
        presentationAnimatedSidesCataloged = true;
      }
      presentationSideStateInitialized = true;
    }
    int sectorOffset = 208;
    int sectorCount = includeSectors
        ? engine.levelLoader.sectors.length
        : includeDirtySides ? dirtySectorCount : 0;
    int sectorRecordBytes = includeDirtySides ? 18 : 16;
    int sideOffset = sectorOffset + sectorCount * sectorRecordBytes;
    int sideCount = includeSides
        ? engine.levelLoader.sides.length
        : includeDirtySides ? dirtySideCount : 0;
    int sideRecordBytes = includeDirtySides ? 18 : 8;
    int mobjOffset = sideOffset + sideCount * sideRecordBytes;
    boolean compactCompositorMobjs =
        !includeSides && !includeDirtySides && !includeSectors && includeMobjs;
    int mobjRecordBytes = compactCompositorMobjs ? 24 : 32;
    int length = includeSides || includeDirtySides
        ? mobjOffset + mobjCount * mobjRecordBytes : mobjOffset;
    // DVL6's one-time all-sector/all-side seed includes fixed-point X/Y
    // offsets and is intentionally larger than RAW's 32,767-byte boundary.
    // The retained coordinator consumes it as a same-session native
    // Uint8Array; steady indexed dirty updates remain only a few KB.
    if (length > 16 * 1024 * 1024) {
      throw new IllegalStateException("presentation world snapshot too large " + length);
    }
    int requiredCapacity = includeSides || includeDirtySides
        ? Math.max(length, 16384)
        : 8192;
    if (presentationWorldSnapshot == null
        || presentationWorldSnapshot.length < requiredCapacity
        || (!includeSides && !includeDirtySides
            && presentationWorldSnapshot.length > 16384)) {
      presentationWorldSnapshot = new byte[requiredCapacity];
    }
    putPresentationI32(0,
        includeDirtySides ? 0x364c5644
            : includeSides ? 0x324c5644
            : includeSectors ? 0x334c5644 : 0x344c5644);
    putPresentationI32(4, includeDirtySides ? 6
        : includeSides ? 2 : includeSectors ? 3 : 4);
    putPresentationI32(8, engine.gametic);
    putPresentationI32(12, playerSlot);
    putPresentationI32(16, sectorCount);
    putPresentationI32(20, mobjCount);
    putPresentationI32(24, sectorOffset);
    putPresentationI32(28, mobjOffset);
    putPresentationI32(32, length);
    putPresentationI32(36, player.mo.x);
    putPresentationI32(40, player.mo.y);
    putPresentationI32(44, player.mo.z);
    putPresentationI32(48, (int) player.mo.angle >>> 16);
    putPresentationI32(52, player.viewz);
    putPresentationI32(56, player.health[0]);
    putPresentationI32(60, player.armorpoints[0]);
    putPresentationI32(64, player.readyweapon.ordinal());
    putPresentationI32(68, player.pendingweapon.ordinal());
    for (int ammo = 0; ammo < 4; ammo++) {
      putPresentationI32(72 + ammo * 4, player.ammo[ammo]);
    }
    for (int psprite = 0; psprite < 2; psprite++) {
      p.pspdef_t value = player.psprites[psprite];
      int offset = 88 + psprite * 20;
      putPresentationI32(offset, value.state == null ? -1 : value.state.id);
      putPresentationI32(offset + 4, value.sx);
      putPresentationI32(offset + 8, value.sy);
      putPresentationI32(offset + 12,
          value.state == null || value.state.sprite == null
              ? -1 : value.state.sprite.ordinal());
      putPresentationI32(offset + 16,
          value.state == null ? -1 : value.state.frame);
    }
    putPresentationI32(128, player.damagecount);
    putPresentationI32(132, player.bonuscount);
    putPresentationI32(136, player.extralight);
    putPresentationI32(140, player.fixedcolormap);
    int cards = 0;
    for (int card = 0; card < player.cards.length; card++) {
      if (player.cards[card]) cards |= 1 << card;
    }
    // DVL presentation metadata uses the otherwise-empty high bits of the
    // key mask. This preserves the fixed 208-byte hot snapshot while giving
    // the database renderer enough information for Doom's ARMS/max-ammo and
    // deathmatch-frag widgets. Bits 0..5 remain the exact card/skull mask.
    for (int weapon = 0; weapon < player.weaponowned.length; weapon++) {
      if (player.weaponowned[weapon]) cards |= 1 << (8 + weapon);
    }
    if (player.backpack) cards |= 1 << 17;
    if (engine.deathmatch) cards |= 1 << 18;
    putPresentationI32(144, cards);
    int frags = 0;
    for (int frag : player.frags) frags += frag;
    putPresentationI32(148, frags);
    putPresentationI32(152, player.killcount);
    putPresentationI32(156, player.itemcount);
    putPresentationI32(160, player.secretcount);
    putPresentationI32(164, player.playerstate);
    putPresentationI32(168, player.cheats);
    putPresentationI32(172, player.armortype);
    putPresentationI32(176, player.colormap);
    putPresentationI32(180, player.refire);
    putPresentationI32(184, player.attackdown ? 1 : 0);
    putPresentationI32(188, player.usedown ? 1 : 0);
    putPresentationI32(192, sideCount);
    putPresentationI32(196, sideOffset);
    putPresentationI32(200, sideRecordBytes);
    putPresentationI32(204,
        includeDirtySides ? sectorRecordBytes : sectorOffset);

    int offset = sectorOffset;
    if (includeSectors) {
      for (rr.sector_t sector : engine.levelLoader.sectors) {
        putPresentationI32(offset, sector.floorheight);
        putPresentationI32(offset + 4, sector.ceilingheight);
        putPresentationI16(offset + 8, sector.lightlevel);
        putPresentationI16(offset + 10,
            engine.textureManager.getFlatTranslation(sector.floorpic));
        putPresentationI16(offset + 12,
            engine.textureManager.getFlatTranslation(sector.ceilingpic));
        putPresentationI16(offset + 14, sector.special);
        offset += 16;
      }
    } else if (includeDirtySides) {
      for (int dirty = 0; dirty < dirtySectorCount; dirty++) {
        int sectorIndex = presentationDirtySectors[dirty];
        putPresentationI16(offset, sectorIndex);
        putPresentationI32(
            offset + 2, presentationSectorFloor[sectorIndex]);
        putPresentationI32(
            offset + 6, presentationSectorCeiling[sectorIndex]);
        putPresentationI16(
            offset + 10, presentationSectorLight[sectorIndex]);
        putPresentationI16(
            offset + 12, presentationSectorFloorAsset[sectorIndex]);
        putPresentationI16(
            offset + 14, presentationSectorCeilingAsset[sectorIndex]);
        putPresentationI16(
            offset + 16, presentationSectorSpecial[sectorIndex]);
        offset += 18;
      }
    }
    if (includeSides) {
      for (rr.side_t side : engine.levelLoader.sides) {
        putPresentationI16(offset,
            side.toptexture == 0 ? 0
                : engine.textureManager.getTextureTranslation(side.toptexture));
        putPresentationI16(offset + 2,
            side.bottomtexture == 0 ? 0
                : engine.textureManager.getTextureTranslation(side.bottomtexture));
        putPresentationI16(offset + 4,
            side.midtexture == 0 ? 0
                : engine.textureManager.getTextureTranslation(side.midtexture));
        putPresentationI16(offset + 6, side.special);
        offset += 8;
      }
    } else if (includeDirtySides) {
      for (int dirty = 0; dirty < dirtySideCount; dirty++) {
        int sideIndex = presentationDirtySides[dirty];
        putPresentationI16(offset, sideIndex);
        putPresentationI16(offset + 2, presentationSideTop[sideIndex]);
        putPresentationI16(offset + 4, presentationSideBottom[sideIndex]);
        putPresentationI16(offset + 6, presentationSideMiddle[sideIndex]);
        putPresentationI16(offset + 8, presentationSideSpecial[sideIndex]);
        putPresentationI32(
            offset + 10, presentationSideTextureOffset[sideIndex]);
        putPresentationI32(offset + 14, presentationSideRowOffset[sideIndex]);
        offset += 18;
      }
    }
    int writtenMobjs = 0;
    int presentationDirectionX = 0;
    int presentationDirectionY = 0;
    if (includeMobjs && !includeSides) {
      int angle = ((int) player.mo.angle >>> Tables.ANGLETOFINESHIFT)
          & Tables.FINEMASK;
      presentationDirectionX = Tables.finecosine[angle] >> 8;
      presentationDirectionY = Tables.finesine[angle] >> 8;
    }
    if (includeMobjs) {
      for (thinker_t current = cap.next;
           current != null && current != cap;
           current = current.next) {
        if (!(current instanceof p.mobj_t)) continue;
        p.mobj_t mobj = (p.mobj_t) current;
        if (((int) mobj.flags & p.mobj_t.MF_NOSECTOR) != 0) continue;
        if (!includeSides
            && !presentationMobjCandidate(
                player.mo, mobj,
                presentationDirectionX, presentationDirectionY)) {
          continue;
        }
        if (offset > 32767 - mobjRecordBytes) {
          throw new IllegalStateException("presentation mobj payload too large");
        }
        if (offset > presentationWorldSnapshot.length - mobjRecordBytes) {
          growPresentationCompactSnapshot(offset + mobjRecordBytes);
        }
        putPresentationI32(offset, mobj.x);
        putPresentationI32(offset + 4, mobj.y);
        putPresentationI32(offset + 8, mobj.z);
        putPresentationI32(offset + 12, (int) mobj.angle >>> 16);
        putPresentationI16(offset + 16,
            mobj.mobj_sprite == null ? -1 : mobj.mobj_sprite.ordinal());
        putPresentationI16(offset + 18, mobj.mobj_frame);
        if (compactCompositorMobjs) {
          putPresentationI16(offset + 20,
              mobj.subsector == null ? -1 : mobj.subsector.sector.id);
          putPresentationI16(offset + 22, 0);
        } else {
          putPresentationI32(offset + 20,
              mobj.mobj_state == null ? -1 : mobj.mobj_state.id);
          putPresentationI32(offset + 24, (int) mobj.flags);
          putPresentationI16(offset + 28,
              mobj.type == null ? -1 : mobj.type.ordinal());
          putPresentationI16(offset + 30,
              mobj.subsector == null ? -1 : mobj.subsector.sector.id);
        }
        offset += mobjRecordBytes;
        writtenMobjs++;
        if (!includeSides) mobjCount++;
      }
    }
    if (!includeSides && !includeDirtySides) {
      length = offset;
      putPresentationI32(20, mobjCount);
      putPresentationI32(32, length);
    }
    if (writtenMobjs != mobjCount || offset != length) {
      throw new IllegalStateException(
          "presentation snapshot cardinality changed during serialization"
              + " offset=" + offset + " length=" + length
              + " sectors=" + sectorCount
              + " dirtySectors=" + dirtySectorCount
              + " sides=" + sideCount + " dirtySides=" + dirtySideCount);
    }
    presentationWorldSnapshotLength = length;
    return length;
  }

  /**
   * Keep the cross-module DVC4 export near its useful payload size.  TeaVM's
   * {@code @JSByRef} bridge exposes the complete Java backing array, not only
   * {@link #presentationWorldSnapshotLength}; the former fixed 32,767-byte
   * allocation therefore paid a multi-millisecond boundary cost for padding
   * on every frame.  Power-of-two growth avoids a per-frame allocation when
   * the visible thinker population changes.
   */
  private static void growPresentationCompactSnapshot(int required) {
    int capacity = presentationWorldSnapshot.length;
    while (capacity < required && capacity < 16384) capacity <<= 1;
    if (capacity < required) capacity = 32767;
    byte[] grown = new byte[capacity];
    for (int index = 0; index < presentationWorldSnapshot.length; index++) {
      grown[index] = presentationWorldSnapshot[index];
    }
    presentationWorldSnapshot = grown;
  }

  /**
   * Conservative first-person frustum rejection before serializing a mobj.
   * The compositor performs the final projection and occlusion tests.  A
   * two-to-one lateral margin is wider than its 1.5-to-one projection gate,
   * so this removes records that cannot contribute pixels without clipping
   * sprites at either edge of the view.
   */
  private static boolean presentationMobjCandidate(
      p.mobj_t viewer, p.mobj_t candidate,
      int directionX, int directionY) {
    int dx = (candidate.x - viewer.x) >> 16;
    int dy = (candidate.y - viewer.y) >> 16;
    int depth = dx * directionX + dy * directionY;
    if (depth <= 0) return false;
    int lateral = -dx * directionY + dy * directionX;
    if (lateral == Integer.MIN_VALUE || depth > Integer.MAX_VALUE / 2) {
      return true;
    }
    return Math.abs(lateral) <= depth * 2;
  }

  @JSExport
  public static Uint8Array presentationWorldSnapshotChunk(
      int offset, int length) {
    if (presentationWorldSnapshot == null
        || presentationWorldSnapshotLength == 0) {
      throw new IllegalStateException("presentation snapshot length must run first");
    }
    if (offset < 0 || length < 0 || length > 32767
        || offset > presentationWorldSnapshotLength - length) {
      throw new IllegalArgumentException("presentation snapshot chunk");
    }
    Uint8Array result = Uint8Array.create(length);
    for (int index = 0; index < length; index++) {
      result.set(index,
          (short) (presentationWorldSnapshot[offset + index] & 255));
    }
    return result;
  }

  /**
   * Zero-copy view for a coordinator module running in the same MLE context.
   * Call {@link #presentationWorldSnapshotLength(int)} first and consume only
   * that many leading bytes; the retained backing array may be larger after a
   * higher-mobj frame.
   */
  @JSExport
  @JSByRef
  public static byte[] presentationWorldSnapshotByRef() {
    if (presentationWorldSnapshot == null
        || presentationWorldSnapshotLength == 0) {
      throw new IllegalStateException("presentation snapshot length must run first");
    }
    return presentationWorldSnapshot;
  }

  /**
   * Same-isolate view of the retained presentation payload without the
   * defensive primitive-array clone performed by {@link JSByRef}. Consumers
   * must finish reading it before the next snapshot build mutates the array.
   */
  @JSExport
  public static Uint8Array presentationWorldSnapshotNativeByRef() {
    if (presentationWorldSnapshot == null
        || presentationWorldSnapshotLength == 0) {
      throw new IllegalStateException("presentation snapshot length must run first");
    }
    return nativeByteArrayView(presentationWorldSnapshot);
  }

  @JSBody(params = {"array"}, script =
      "return new Uint8Array(array.buffer,"
          + "array.byteOffset,array.byteLength);")
  private static native Uint8Array nativeByteArrayView(
      @JSByRef byte[] array);

  @JSExport
  public static int presentationWorldSnapshotCurrentLength() {
    return presentationWorldSnapshotLength;
  }

  private static void putPresentationI16(int offset, int value) {
    presentationWorldSnapshot[offset] = (byte) value;
    presentationWorldSnapshot[offset + 1] = (byte) (value >>> 8);
  }

  private static void putPresentationI32(int offset, int value) {
    putPresentationI16(offset, value);
    putPresentationI16(offset + 2, value >>> 16);
  }

  private static void putSnapshotI32(
      Uint8Array snapshot, int offset, int value) {
    snapshot.set(offset, (short) (value & 255));
    snapshot.set(offset + 1, (short) ((value >>> 8) & 255));
    snapshot.set(offset + 2, (short) ((value >>> 16) & 255));
    snapshot.set(offset + 3, (short) ((value >>> 24) & 255));
  }

  private static int nonzero(byte[] bytes, int offset, int length) {
    int count = 0;
    int end = Math.min(bytes.length, offset + length);
    for (int index = offset; index < end; index++) {
      if (bytes[index] != 0) count++;
    }
    return count;
  }

  /** Describe a DMS1 byte offset for presentation-residue diagnostics. */
  static String canonicalOffsetDescription(int materialOffset) {
    if (engine == null) throw new IllegalStateException("engine is not initialized");
    int saveOffset = materialOffset - 8; // DMS1 magic and save-length prefix.
    if (saveOffset < 0) return "dms1.header+" + materialOffset;
    int cursor = 50; // VanillaDSGHeader serialized bytes.
    for (int player = 0; player < engine.playeringame.length; player++) {
      if (!engine.playeringame[player]) continue;
      cursor = (cursor + 3) & ~3;
      if (saveOffset < cursor + 280) {
        return "save.player[" + player + "]+" + (saveOffset - cursor);
      }
      cursor += 280;
    }
    int sectorBytes = engine.levelLoader.numsectors * 14;
    if (saveOffset < cursor + sectorBytes) {
      int local = saveOffset - cursor;
      return "save.sector[" + (local / 14) + "]+" + (local % 14);
    }
    cursor += sectorBytes;
    String[] lineFields = {"flags", "special", "tag"};
    String[] sideFields = {
        "textureoffset", "rowoffset", "toptexture", "bottomtexture", "midtexture"};
    for (int line = 0; line < engine.levelLoader.numlines; line++) {
      if (saveOffset < cursor + 6) {
        int local = saveOffset - cursor;
        return "save.line[" + line + "]." + lineFields[local / 2]
            + "+byte" + (local % 2);
      }
      cursor += 6;
      rr.line_t value = engine.levelLoader.lines[line];
      for (int side = 0; side < 2; side++) {
        if (value.sidenum[side] == rr.line_t.NO_INDEX) continue;
        if (saveOffset < cursor + 10) {
          int local = saveOffset - cursor;
          return "save.line[" + line + "].side[" + side + "="
              + value.sidenum[side] + "]." + sideFields[local / 2]
              + "+byte" + (local % 2);
        }
        cursor += 10;
      }
    }
    return "save.after-world+" + (saveOffset - cursor);
  }

  /** Release all module-scope session state. */
  @JSExport
  public static void release() {
    engine = null;
    canonicalStateCache = null;
    checkpointCache = null;
    checkpointCacheBytes = 0;
    vanillaCheckpointOutput = null;
    envelopeCheckpointOutput = null;
    playerCheckpointOutput = null;
    checkpointLoadBuffer = null;
    checkpointBytesLoaded = 0;
    iwad = null;
    presentationStatusBackgrounds = null;
    presentationWorldSnapshot = null;
    presentationWorldSnapshotLength = 0;
    presentationSectorFloor = null;
    presentationSectorCeiling = null;
    presentationSectorLight = null;
    presentationSectorFloorAsset = null;
    presentationSectorCeilingAsset = null;
    presentationSectorSpecial = null;
    presentationDirtySectors = null;
    presentationSectorStateInitialized = false;
    presentationSideTop = null;
    presentationSideBottom = null;
    presentationSideMiddle = null;
    presentationSideRawTop = null;
    presentationSideRawBottom = null;
    presentationSideRawMiddle = null;
    presentationSideSpecial = null;
    presentationSideTextureOffset = null;
    presentationSideRowOffset = null;
    presentationDirtySides = null;
    presentationCandidateSides = null;
    presentationCandidateSideFlags = null;
    presentationCandidateSideCount = 0;
    presentationAnimatedSidesCataloged = false;
    presentationSideStateInitialized = false;
    tablePack = null;
    tablePackBytesLoaded = 0;
    Tables.clearCanonicalTablePack();
    Engine.releaseHeadless();
    InputStreamSugar.clearInjectedResource();
  }

  private static final class ReusableByteArrayOutputStream
      extends ByteArrayOutputStream {
    ReusableByteArrayOutputStream(int capacity) {
      super(capacity);
    }

    byte[] buffer() {
      return buf;
    }
  }


  public static void main(String[] args) {
    // MLE and Node drive the explicit exported lifecycle above.
  }

  private static String snapshot(String state) {
    player_t player = engine.players[engine.consoleplayer];
    String position = player.mo == null
        ? "|player=missing"
        : "|playerX=" + player.mo.x
            + "|playerY=" + player.mo.y
            + "|playerZ=" + player.mo.z
            + "|playerAngle=" + Long.toUnsignedString(player.mo.angle);
    return "state=" + state
        + "|gametic=" + engine.gametic
        + "|leveltime=" + engine.leveltime
        + "|randomIndex=" + engine.random.getIndex()
        + "|gamestate=" + engine.gamestate.name()
        + "|episode=" + engine.gameepisode
        + "|map=" + engine.gamemap
        + "|playerState=" + player.playerstate
        + position
        + "|playerHealth=" + player.health[0]
        + "|viewZ=" + player.viewz
        + "|armor=" + player.armorpoints[0]
        + "|readyWeapon=" + player.readyweapon.name()
        + "|kills=" + player.killcount + '/' + engine.totalkills
        + "|items=" + player.itemcount + '/' + engine.totalitems
        + "|secrets=" + player.secretcount + '/' + engine.totalsecret;
  }

  private static int clamp(int value, int minimum, int maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private static int nextFixedMulValue(int value) {
    value ^= value << 13;
    value ^= value >>> 17;
    value ^= value << 5;
    return value;
  }

  private static long[] buildLongFlagProbeValues() {
    long[] values = new long[256];
    int state = 0x7f4a7c15;
    for (int i = 0; i < values.length; i++) {
      state = nextFixedMulValue(state);
      long low = state & 0xffffffffL;
      state = nextFixedMulValue(state);
      long high = ((long) state & 0x7fL) << 32;
      values[i] = high | low;
    }
    return values;
  }

  private static int mixFixedMul(int checksum, int a, int b, int result) {
    checksum = checksum * 16777619 ^ a;
    checksum = checksum * 16777619 ^ b;
    return checksum * 16777619 ^ result;
  }

  private static int length(Object[] values) {
    return values == null ? 0 : values.length;
  }

  private static int length(int[] values) {
    return values == null ? 0 : values.length;
  }

  private static int length(byte[] values) {
    return values == null ? 0 : values.length;
  }

  private static ArrayList<thinker_t> checkpointThinkers() {
    ArrayList<thinker_t> thinkers = new ArrayList<thinker_t>();
    thinker_t cap = engine.actions.getThinkerCap();
    for (thinker_t current = cap.next;
         current != null && current != cap && thinkers.size() < 1000000;
         current = current.next) {
      thinkers.add(current);
    }
    return thinkers;
  }

  private static int checkpointThinkerIndex(
      ArrayList<thinker_t> thinkers, thinker_t target) {
    if (target == null) return -1;
    for (int index = 0; index < thinkers.size(); index++) {
      if (thinkers.get(index) == target) return index;
    }
    return -2;
  }

  private static IdentityHashMap<thinker_t, Integer> checkpointIdentityMap(
      ArrayList<thinker_t> values) {
    IdentityHashMap<thinker_t, Integer> result =
        new IdentityHashMap<thinker_t, Integer>(values.size() * 2);
    for (int index = 0; index < values.size(); index++) {
      result.put(values.get(index), index);
    }
    return result;
  }

  private static IdentityHashMap<Object, Integer> checkpointIdentityMap(
      Object[] values) {
    IdentityHashMap<Object, Integer> result =
        new IdentityHashMap<Object, Integer>(values.length * 2);
    for (int index = 0; index < values.length; index++) {
      result.put(values[index], index);
    }
    return result;
  }

  private static int checkpointIdentityIndex(
      IdentityHashMap<?, Integer> values, Object target) {
    if (target == null) return -1;
    Integer index = values.get(target);
    return index == null ? -2 : index.intValue();
  }

  private static int checkpointIdentityIndex(Object[] values, Object target) {
    if (target == null) return -1;
    for (int index = 0; index < values.length; index++) {
      if (values[index] == target) return index;
    }
    return -2;
  }

  private static thinker_t checkpointThinker(
      ArrayList<thinker_t> thinkers, int index) {
    if (index == -1) return null;
    if (index < 0 || index >= thinkers.size()) {
      throw new IllegalArgumentException("checkpoint thinker reference " + index);
    }
    return thinkers.get(index);
  }
}
