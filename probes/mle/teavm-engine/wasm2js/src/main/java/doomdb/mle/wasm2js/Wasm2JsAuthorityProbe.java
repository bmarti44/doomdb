/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.wasm2js;

import data.Tables;
import defines.skill_t;
import doom.DoomMain;
import doom.ticcmd_t;
import doomdb.mocha.DoomDbMochaAdapter;
import java.util.Arrays;
import mochadoom.Engine;
import org.teavm.interop.Export;
import rr.column_t;
import rr.patch_t;
import utils.Throwers;
import v.renderers.DoomScreen;
import w.InputStreamSugar;

/**
 * Low-level, linear-memory bridge for the isolated TeaVM 0.13 -> wasm2js
 * feasibility spike.
 *
 * <p>The production adapter uses JSO typed arrays, which the legacy TeaVM
 * WebAssembly backend cannot expose. These methods deliberately use only
 * primitive values and raw Java array references. In legacy TeaVM Wasm an
 * object/array reference and the associated teavm_*ArrayData helper are i32
 * linear-memory addresses; wasm2js preserves that ABI.</p>
 */
public final class Wasm2JsAuthorityProbe {
  private static final int MAX_IWAD_BYTES = 64 * 1024 * 1024;
  private static byte[] iwad;
  private static byte[] tablePack;
  private static DoomMain<?, ?> engine;
  private static byte[] canonical;
  private static byte[] commandVector;
  private static short[][] multiplayerConsistency;
  private static byte[] frame;
  private static byte[][] statusBackgrounds;
  private static boolean presentationViewInitialized;
  private static byte[] initFailure;
  private static byte[] renderCostTexture;
  private static byte[] renderCostColormap;
  private static byte[] renderCostFrame;

  private static final class LongHolder {
    long value;
  }

  private Wasm2JsAuthorityProbe() {}

  /*
   * Reduced i64 lowering diagnostics. These exports are spike-only and keep
   * every JS-facing signature i32. The full native-Wasm authority already
   * proves the source semantics; wasm2js must return the stated high words
   * before Doom initialization or the translator is rejected.
   */
  @Export(name = "doom_i64_constant_high")
  public static int i64ConstantHigh() {
    return (int) (0x0000000f12345678L >>> 32);
  }

  @Export(name = "doom_i64_field_high")
  public static int i64FieldHigh() {
    LongHolder holder = new LongHolder();
    holder.value = 0x0000000f12345678L;
    return (int) (holder.value >>> 32);
  }

  @Export(name = "doom_i64_field_copy_high")
  public static int i64FieldCopyHigh() {
    LongHolder source = new LongHolder();
    LongHolder destination = new LongHolder();
    source.value = 0x0000001712345678L;
    destination.value = source.value;
    return (int) (destination.value >>> 32);
  }

  @Export(name = "doom_i64_array_high")
  public static int i64ArrayHigh() {
    long[] values = new long[] {0L, 0x0000000712345678L};
    return (int) (values[1] >>> 32);
  }

  @Export(name = "doom_i64_call_high")
  public static int i64CallHigh() {
    return highWord(0x0000000f12345678L);
  }

  @Export(name = "doom_i64_flag_or_high")
  public static int i64FlagOrHigh() {
    long flags = 0x12345678L;
    flags |= 1L << 32;
    flags |= 1L << 33;
    flags |= 1L << 34;
    flags |= 1L << 35;
    return (int) (flags >>> 32);
  }

  @Export(name = "doom_allocate_iwad")
  public static int allocateIwad(int length) {
    if (length < 12 || length > MAX_IWAD_BYTES) return -1;
    iwad = new byte[length];
    return length;
  }

  @Export(name = "doom_iwad_ref")
  public static byte[] iwadReference() {
    return iwad;
  }

  @Export(name = "doom_allocate_tables")
  public static int allocateTables(int length) {
    if (length != Tables.CANONICAL_TABLE_PACK_BYTES) return -1;
    tablePack = new byte[length];
    return length;
  }

  @Export(name = "doom_tables_ref")
  public static byte[] tableReference() {
    return tablePack;
  }

  @Export(name = "doom_initialize")
  public static int initialize(
      int activePlayers, int deathmatch, int skill, int episode, int map)
      throws Exception {
    return initializeGame(
        activePlayers, deathmatch, skill, episode, map, false);
  }

  @Export(name = "doom_initialize_presentation")
  public static int initializePresentation(
      int activePlayers, int deathmatch, int skill, int episode, int map)
      throws Exception {
    return initializeGame(
        activePlayers, deathmatch, skill, episode, map, true);
  }

  private static int initializeGame(
      int activePlayers, int deathmatch, int skill, int episode, int map,
      boolean presentation) throws Exception {
    if (iwad == null || tablePack == null) return -2;
    if (activePlayers < 1 || activePlayers > 4) return -3;
    Tables.installCanonicalTablePack(tablePack);
    InputStreamSugar.setInjectedResource(iwad);
    String[] arguments = {
        "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
        "-width", "320", "-height", "200"
    };
    try {
      if (presentation) {
        engine = Engine.createHeadless(arguments);
      } else {
        engine = Engine.createHeadlessAuthority(arguments);
      }
    } catch (Throwable failure) {
      if (failure instanceof Throwers.Throwed
          && ((Throwers.Throwed) failure).t != null) {
        failure = ((Throwers.Throwed) failure).t;
      }
      String message = failure.getClass().getName() + ":"
          + (failure.getMessage() == null ? "" : failure.getMessage());
      Throwable cause = failure.getCause();
      if (cause != null && cause != failure) {
        message += "|cause=" + cause.getClass().getName() + ":"
            + (cause.getMessage() == null ? "" : cause.getMessage());
      }
      initFailure = new byte[message.length()];
      for (int index = 0; index < message.length(); index++) {
        initFailure[index] = (byte) message.charAt(index);
      }
      if (DoomMain.doomdbInitStage != 0) {
        return -100 - DoomMain.doomdbInitStage;
      }
      if (failure instanceof NullPointerException) return -11;
      if (failure instanceof ArrayIndexOutOfBoundsException) return -12;
      if (failure instanceof ClassCastException) return -13;
      if (failure instanceof IllegalArgumentException) return -14;
      if (failure instanceof IllegalStateException) return -15;
      if (failure instanceof java.io.IOException) return -16;
      if (failure instanceof RuntimeException) return -17;
      if (failure instanceof Error) return -18;
      return -10;
    }
    Arrays.fill(engine.playeringame, false);
    for (int player = 0; player < activePlayers; player++) {
      engine.playeringame[player] = true;
    }
    engine.consoleplayer = 0;
    engine.displayplayer = 0;
    engine.netgame = activePlayers > 1;
    engine.deathmatch = deathmatch != 0;
    engine.InitNew(skill_t.values()[skill - 1], episode, map);
    engine.singletics = true;
    commandVector = new byte[4 * ticcmd_t.TICCMDLEN];
    multiplayerConsistency = new short[engine.playeringame.length]
        [engine.netcmds[0].length];
    canonical = null;
    frame = null;
    statusBackgrounds = null;
    presentationViewInitialized = false;
    return engine.gametic;
  }

  @Export(name = "doom_init_failure_length")
  public static int initFailureLength() {
    return initFailure == null ? 0 : initFailure.length;
  }

  @Export(name = "doom_init_failure_ref")
  public static byte[] initFailureReference() {
    return initFailure;
  }

  @Export(name = "doom_command_ref")
  public static byte[] commandReference() {
    return commandVector;
  }

  /** Exact four-slot DMD1 command shape used by the production authority. */
  @Export(name = "doom_step_authority")
  public static int stepAuthority(int activePlayers, int membershipMask) {
    if (engine == null || commandVector == null
        || multiplayerConsistency == null || !engine.netgame) {
      return -1;
    }
    int allowedMembership = (1 << activePlayers) - 1;
    if (activePlayers < 2 || activePlayers > 4
        || (membershipMask & 1) == 0
        || (membershipMask & ~allowedMembership) != 0) {
      return -2;
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
          if (commandVector[offset + index] != 0) return -3;
        }
        continue;
      }
      ticcmd_t command = engine.netcmds[player][buffer];
      command.forwardmove = commandVector[offset];
      command.sidemove = commandVector[offset + 1];
      command.angleturn = (short) (((commandVector[offset + 2] & 0xff) << 8)
          | (commandVector[offset + 3] & 0xff));
      command.consistancy = multiplayerConsistency[player][buffer];
      command.chatchar = (char) (commandVector[offset + 6] & 0xff);
      command.buttons = (char) (commandVector[offset + 7] & 0xff);
      command.lookfly = 0;
    }
    canonical = null;
    engine.Ticker();
    for (int player = 0; player < activePlayers; player++) {
      if (!engine.playeringame[player]) continue;
      multiplayerConsistency[player][buffer] =
          engine.doomdbConsistency(player, buffer);
    }
    engine.gametic++;
    return engine.gametic;
  }

  @Export(name = "doom_step")
  public static int step(
      int forwardMove, int sideMove, int angleTurn, int consistency,
      int buttons) {
    if (engine == null) return -1;
    int buffer = (engine.gametic / engine.getTicdup())
        % engine.netcmds[engine.consoleplayer].length;
    ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
    command.forwardmove = (byte) clamp(forwardMove, -127, 127);
    command.sidemove = (byte) clamp(sideMove, -127, 127);
    command.angleturn = (short) clamp(angleTurn, Short.MIN_VALUE, Short.MAX_VALUE);
    command.consistancy =
        (short) clamp(consistency, Short.MIN_VALUE, Short.MAX_VALUE);
    command.chatchar = 0;
    command.buttons = (char) (buttons & 0xff);
    command.lookfly = 0;
    canonical = null;
    engine.Ticker();
    engine.gametic++;
    return engine.gametic;
  }

  @Export(name = "doom_canonical_length")
  public static int canonicalLength() throws Exception {
    if (engine == null) return -1;
    canonical = DoomDbMochaAdapter.canonicalStateMaterial(engine);
    return canonical.length;
  }

  @Export(name = "doom_canonical_ref")
  public static byte[] canonicalReference() {
    return canonical;
  }

  /**
   * Render one exact confirmed 320x200 indexed frame inside the engine.
   *
   * The returned value is a length/status code. doom_frame_ref exposes the
   * retained Java byte array directly through TeaVM's linear-memory ABI.
   */
  @Export(name = "doom_render_player")
  public static int renderPlayer(int playerSlot) {
    int stage = 0;
    try {
      if (engine == null || multiplayerConsistency == null || !engine.netgame) {
        return -1;
      }
      if (playerSlot < 0 || playerSlot >= engine.playeringame.length
          || !engine.playeringame[playerSlot]) {
        return -2;
      }
      if (!presentationViewInitialized) {
        engine.sceneRenderer.SetViewSize(10, 0);
        presentationViewInitialized = true;
      }
      stage = 1;
      int savedConsole = engine.consoleplayer;
      int savedDisplay = engine.displayplayer;
      try {
        engine.consoleplayer = playerSlot;
        engine.displayplayer = playerSlot;
        engine.statusBar.doomdbDisplayPlayer(playerSlot);
        if (engine.headsUp != null) engine.headsUp.doomdbDisplayPlayer(playerSlot);
        stage = 2;
        engine.Display();
        stage = 3;
        Object foreground = engine.graphicSystem.getScreen(DoomScreen.FG);
        if (!(foreground instanceof byte[])
            || ((byte[]) foreground).length != 320 * 200) {
          return -3;
        }
        frame = (byte[]) foreground;
        stage = 4;
        composeStatusBar(playerSlot);
        stage = 5;
        return frame.length;
      } finally {
        engine.statusBar.doomdbDisplayPlayer(savedConsole);
        if (engine.headsUp != null) {
          engine.headsUp.doomdbDisplayPlayer(savedConsole);
        }
        engine.consoleplayer = savedConsole;
        engine.displayplayer = savedDisplay;
      }
    } catch (Throwable failure) {
      if (DoomMain.doomdbDisplayStage != 0) {
        return -200 - DoomMain.doomdbDisplayStage;
      }
      return -100 - stage;
    }
  }

  @Export(name = "doom_frame_ref")
  public static byte[] frameReference() {
    return frame;
  }

  /**
   * Cost-only Doom-shaped indexed raster kernel.
   *
   * <p>This is deliberately independent of Display() and engine
   * initialization so the generated linear-memory shape can be rejected on
   * cost before more parity debugging. It performs two byte gathers, integer
   * coordinate work, and one framebuffer store for every 320x200 pixel. It
   * is a lower bound, not an exact Doom frame and never a release artifact.</p>
   */
  @Export(name = "doom_render_cost_kernel")
  public static int renderCostKernel(int frames) {
    if (frames < 1 || frames > 1000) return -1;
    if (renderCostTexture == null) {
      renderCostTexture = new byte[65536];
      renderCostColormap = new byte[256];
      renderCostFrame = new byte[320 * 200];
      for (int index = 0; index < renderCostTexture.length; index++) {
        renderCostTexture[index] = (byte) (index * 73 + 19);
      }
      for (int index = 0; index < renderCostColormap.length; index++) {
        renderCostColormap[index] = (byte) (index * 29 + 7);
      }
    }
    int checksum = 0x13579bdf;
    for (int frameIndex = 0; frameIndex < frames; frameIndex++) {
      int phase = frameIndex * 17 + checksum;
      for (int y = 0; y < 200; y++) {
        int row = y * 320;
        int v = y * 97 + (phase << 2);
        for (int x = 0; x < 320; x++) {
          int u = x * 257 + phase + (y << 3);
          int textureIndex = (u + (v & 0xff00)) & 0xffff;
          int sample = renderCostTexture[textureIndex] & 0xff;
          int mapped = renderCostColormap[
              (sample + ((x ^ y) & 31)) & 0xff] & 0xff;
          renderCostFrame[row + x] = (byte) mapped;
        }
      }
      checksum = checksum * 31
          + (renderCostFrame[(frameIndex * 997) % renderCostFrame.length] & 0xff);
    }
    return checksum;
  }

  @Export(name = "doom_release")
  public static int release() {
    engine = null;
    canonical = null;
    tablePack = null;
    iwad = null;
    commandVector = null;
    multiplayerConsistency = null;
    frame = null;
    statusBackgrounds = null;
    presentationViewInitialized = false;
    renderCostTexture = null;
    renderCostColormap = null;
    renderCostFrame = null;
    InputStreamSugar.clearInjectedResource();
    Engine.releaseHeadless();
    return 0;
  }

  public static void main(String[] args) {
    // The MLE/Node probe drives the exported lifecycle directly.
  }

  private static int clamp(int value, int minimum, int maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private static int highWord(long value) {
    return (int) (value >>> 32);
  }

  private static void composeStatusBar(int playerSlot) {
    if (statusBackgrounds == null) {
      statusBackgrounds = new byte[engine.playeringame.length][];
    }
    byte[] background = statusBackgrounds[playerSlot];
    if (background == null) {
      drawIndexedPatch(engine.wadLoader.CachePatchName("STBAR"), 0, 168);
      drawIndexedPatch(
          engine.wadLoader.CachePatchName("STFB" + playerSlot), 143, 168);
      background = new byte[320 * 32];
      System.arraycopy(frame, 320 * 168, background, 0, background.length);
      statusBackgrounds[playerSlot] = background;
    } else {
      System.arraycopy(background, 0, frame, 320 * 168, background.length);
    }
    engine.statusBar.doomdbDrawWidgets(true);
  }

  private static void drawIndexedPatch(patch_t patch, int x, int y) {
    int originX = x - patch.leftoffset;
    int originY = y - patch.topoffset;
    for (int columnIndex = 0; columnIndex < patch.width; columnIndex++) {
      int targetX = originX + columnIndex;
      if (targetX < 0 || targetX >= 320) continue;
      column_t column = patch.columns[columnIndex];
      for (int post = 0;
          post < column.posts && column.postdeltas[post] != 0xff;
          post++) {
        int targetY = originY + column.postdeltas[post];
        for (int pixel = 0; pixel < column.postlen[post]; pixel++) {
          int screenY = targetY + pixel;
          if (screenY >= 0 && screenY < 200) {
            frame[screenY * 320 + targetX] =
                column.data[column.postofs[post] + pixel];
          }
        }
      }
    }
  }
}
