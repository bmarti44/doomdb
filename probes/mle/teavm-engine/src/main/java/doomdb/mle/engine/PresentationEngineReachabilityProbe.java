/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;

/**
 * Browser/audit presentation root over the exact authoritative adapter.
 *
 * Keeping this as a separate TeaVM main class prevents renderer reachability
 * from entering the retained database ticker artifact. Both outputs are still
 * derived from the same adapter bytecode and pinned Mocha bytecode.
 */
public final class PresentationEngineReachabilityProbe {
  private static boolean viewInitialized;

  private PresentationEngineReachabilityProbe() {}

  @JSExport
  public static int allocateIwad(int length) {
    return SimulationEngineReachabilityProbe.allocateIwad(length);
  }

  @JSExport
  public static int loadIwadChunk(int offset, Uint8Array chunk) {
    return SimulationEngineReachabilityProbe.loadIwadChunk(offset, chunk);
  }

  @JSExport
  public static int allocateTablePack(int length) {
    return SimulationEngineReachabilityProbe.allocateTablePack(length);
  }

  @JSExport
  public static int loadTablePackChunk(int offset, Uint8Array chunk) {
    return SimulationEngineReachabilityProbe.loadTablePackChunk(offset, chunk);
  }

  @JSExport
  public static String initializeMultiplayerGame(
      int activePlayers, int deathmatch, int skill, int episode, int map)
      throws Exception {
    return SimulationEngineReachabilityProbe.initializeMultiplayerGame(
        activePlayers, deathmatch, skill, episode, map);
  }

  @JSExport
  public static int stepMultiplayerAuthoritative(
      int activePlayers, int membershipMask, Uint8Array commandVector) {
    return SimulationEngineReachabilityProbe.stepMultiplayerAuthoritative(
        activePlayers, membershipMask, commandVector);
  }

  @JSExport
  public static int canonicalStateLength() throws Exception {
    return SimulationEngineReachabilityProbe.canonicalStateLength();
  }

  @JSExport
  public static Uint8Array canonicalStateChunk(int offset, int length) {
    return SimulationEngineReachabilityProbe.canonicalStateChunk(offset, length);
  }

  @JSExport
  public static int allocateCheckpoint(int length) {
    return SimulationEngineReachabilityProbe.allocateCheckpoint(length);
  }

  @JSExport
  public static int loadCheckpointChunk(int offset, Uint8Array chunk) {
    return SimulationEngineReachabilityProbe.loadCheckpointChunk(offset, chunk);
  }

  @JSExport
  public static String restoreCheckpoint(int expectedTic) {
    return SimulationEngineReachabilityProbe.restoreCheckpoint(expectedTic);
  }

  @JSExport
  public static Uint8Array renderPlayerFrame(int playerSlot) throws Exception {
    if (!viewInitialized) {
      SimulationEngineReachabilityProbe.initializePresentationView();
      viewInitialized = true;
    }
    return SimulationEngineReachabilityProbe.renderPlayerFrame(playerSlot);
  }

  @JSExport
  public static String presentationDiagnostic() {
    return SimulationEngineReachabilityProbe.presentationDiagnostic();
  }

  @JSExport
  public static String canonicalOffsetDescription(int materialOffset) {
    return SimulationEngineReachabilityProbe.canonicalOffsetDescription(materialOffset);
  }

  @JSExport
  public static String currentState() {
    return SimulationEngineReachabilityProbe.currentState();
  }

  @JSExport
  public static String memoryDiagnostic() {
    return SimulationEngineReachabilityProbe.memoryDiagnostic();
  }

  @JSExport
  public static void release() {
    SimulationEngineReachabilityProbe.release();
    viewInitialized = false;
  }

  public static void main(String[] args) {
    // Browser and asynchronous audit code drive the explicit exports above.
  }
}
