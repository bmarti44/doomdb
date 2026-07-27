package doomdb.mle.engine;

import org.teavm.jso.JSByRef;
import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;
import rr.drawfuns.FrameCommandMetrics;

/**
 * Diagnostic-only export root for the authentic presentation command stream.
 *
 * The accompanying Mocha candidate patch installs transparent delegates
 * during renderer initialization.  Keeping these exports in a candidate
 * source root prevents the pinned authority and presentation artifacts from
 * reaching capture state or its retained asset registry.
 */
public final class PresentationCommandCaptureProbe {
  private PresentationCommandCaptureProbe() {}

  @JSExport
  public static int allocateIwad(int length) {
    return PresentationEngineReachabilityProbe.allocateIwad(length);
  }

  @JSExport
  public static int loadIwadChunk(int offset, Uint8Array chunk) {
    return PresentationEngineReachabilityProbe.loadIwadChunk(offset, chunk);
  }

  @JSExport
  public static int allocateTablePack(int length) {
    return PresentationEngineReachabilityProbe.allocateTablePack(length);
  }

  @JSExport
  public static int loadTablePackChunk(int offset, Uint8Array chunk) {
    return PresentationEngineReachabilityProbe.loadTablePackChunk(offset, chunk);
  }

  @JSExport
  public static String initializeMultiplayerGame(
      int activePlayers, int deathmatch, int skill, int episode, int map)
      throws Exception {
    return PresentationEngineReachabilityProbe.initializeMultiplayerGame(
        activePlayers, deathmatch, skill, episode, map);
  }

  @JSExport
  public static int stepMultiplayerAuthoritative(
      int activePlayers, int membershipMask, Uint8Array commandVector) {
    return PresentationEngineReachabilityProbe.stepMultiplayerAuthoritative(
        activePlayers, membershipMask, commandVector);
  }

  @JSExport
  public static int canonicalStateLength() throws Exception {
    return PresentationEngineReachabilityProbe.canonicalStateLength();
  }

  @JSExport
  public static Uint8Array canonicalStateChunk(int offset, int length) {
    return PresentationEngineReachabilityProbe.canonicalStateChunk(offset, length);
  }

  @JSExport
  public static int allocateCheckpoint(int length) {
    return PresentationEngineReachabilityProbe.allocateCheckpoint(length);
  }

  @JSExport
  public static int loadCheckpointChunk(int offset, Uint8Array chunk) {
    return PresentationEngineReachabilityProbe.loadCheckpointChunk(offset, chunk);
  }

  @JSExport
  public static String restoreCheckpoint(int expectedTic) {
    return PresentationEngineReachabilityProbe.restoreCheckpoint(expectedTic);
  }

  @JSExport
  public static Uint8Array renderPlayerFrame(int playerSlot) throws Exception {
    return PresentationEngineReachabilityProbe.renderPlayerFrame(playerSlot);
  }

  @JSExport
  @JSByRef
  public static byte[] renderPlayerFrameByRef(int playerSlot) throws Exception {
    return PresentationEngineReachabilityProbe.renderPlayerFrameByRef(playerSlot);
  }

  @JSExport
  public static String presentationDiagnostic() {
    return PresentationEngineReachabilityProbe.presentationDiagnostic();
  }

  @JSExport
  public static String canonicalOffsetDescription(int materialOffset) {
    return PresentationEngineReachabilityProbe.canonicalOffsetDescription(
        materialOffset);
  }

  @JSExport
  public static String currentState() {
    return PresentationEngineReachabilityProbe.currentState();
  }

  @JSExport
  public static String memoryDiagnostic() {
    return PresentationEngineReachabilityProbe.memoryDiagnostic();
  }

  @JSExport
  public static void release() {
    PresentationEngineReachabilityProbe.release();
  }

  @JSExport
  public static void enableFrameCommandMetrics() {
    FrameCommandMetrics.enable();
  }

  @JSExport
  public static String frameCommandMetrics(int reset) {
    String result = FrameCommandMetrics.snapshot();
    if (reset != 0) FrameCommandMetrics.reset();
    return result;
  }

  @JSExport
  public static int frameCommandLength() {
    return FrameCommandMetrics.commandLength();
  }

  @JSExport
  @JSByRef
  public static byte[] frameCommandChunk(int offset, int length) {
    return FrameCommandMetrics.commandChunk(offset, length);
  }

  @JSExport
  public static int frameAssetCount() {
    return FrameCommandMetrics.assetCount();
  }

  @JSExport
  public static int frameAssetPackLength() {
    return FrameCommandMetrics.assetPackLength();
  }

  @JSExport
  @JSByRef
  public static byte[] frameAssetPackChunk(int offset, int length) {
    return FrameCommandMetrics.assetPackChunk(offset, length);
  }

  public static void main(String[] args) {
    // Explicit exports above keep the diagnostic surface isolated.
  }
}
