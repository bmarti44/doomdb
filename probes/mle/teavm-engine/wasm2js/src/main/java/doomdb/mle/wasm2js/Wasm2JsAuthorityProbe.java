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

  private Wasm2JsAuthorityProbe() {}

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
    if (iwad == null || tablePack == null) return -2;
    if (activePlayers < 1 || activePlayers > 4) return -3;
    Tables.installCanonicalTablePack(tablePack);
    InputStreamSugar.setInjectedResource(iwad);
    engine = Engine.createHeadlessAuthority(
        "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
        "-width", "320", "-height", "200");
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
    return engine.gametic;
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

  @Export(name = "doom_release")
  public static int release() {
    engine = null;
    canonical = null;
    tablePack = null;
    iwad = null;
    commandVector = null;
    multiplayerConsistency = null;
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
}
