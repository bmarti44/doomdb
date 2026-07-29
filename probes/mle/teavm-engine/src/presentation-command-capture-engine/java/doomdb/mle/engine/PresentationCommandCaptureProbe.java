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
  private static byte[] retainedNormalFrame;
  private static byte[] retainedCapturedOriginal;

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
  public static int renderPlayerFrameLength(int playerSlot) throws Exception {
    retainedNormalFrame =
        PresentationEngineReachabilityProbe.renderPlayerFrameByRef(playerSlot);
    return retainedNormalFrame.length;
  }

  @JSExport
  @JSByRef
  public static byte[] renderPlayerFrameChunk(int offset, int length) {
    if (retainedNormalFrame == null || offset < 0 || length < 0
        || length > 32767 || offset + length > retainedNormalFrame.length) {
      throw new IllegalArgumentException(
          "normal frame chunk outside framebuffer");
    }
    byte[] result = new byte[length];
    System.arraycopy(retainedNormalFrame, offset, result, 0, length);
    return result;
  }

  /**
   * Render from the current authoritative state through the compact command
   * raster. The viewport writers are intercepted, while Mocha still renders
   * the authentic status bar into the same retained foreground screen.
   *
   * Wire layout: 320x168 column-major viewport followed by the 320x32
   * row-major HUD. The client only transposes/copies these database-produced
   * indexed pixels; it performs no game or rendering decisions.
   */
  @JSExport
  @JSByRef
  public static byte[] renderCapturedPlayerFrameByRef(int playerSlot)
      throws Exception {
    capturePlayerFrameCommands(playerSlot);
    return rasterCapturedPlayerFrameByRef();
  }

  @JSExport
  public static int capturePlayerFrameCommands(int playerSlot)
      throws Exception {
    if (!FrameCommandMetrics.isEnabled()) FrameCommandMetrics.enable();
    FrameCommandMetrics.beginLiveFrame();
    FrameCommandMetrics.setCaptureOnly(true);
    try {
      retainedCapturedOriginal =
          PresentationEngineReachabilityProbe.renderPlayerFrameByRef(playerSlot);
      return FrameCommandMetrics.liveCommandCount();
    } finally {
      FrameCommandMetrics.setCaptureOnly(false);
    }
  }

  @JSExport
  @JSByRef
  public static byte[] rasterCapturedPlayerFrameByRef() {
    if (retainedCapturedOriginal == null) {
      throw new IllegalStateException("captured commands are unavailable");
    }
    return FrameCommandMetrics.renderCapturedFrame(retainedCapturedOriginal);
  }

  @JSExport
  public static int rasterCapturedPlayerFrameLength() {
    rasterCapturedPlayerFrameByRef();
    return 320 * 200;
  }

  @JSExport
  public static int renderPlayerFrameCountOnly(int playerSlot)
      throws Exception {
    if (!FrameCommandMetrics.isEnabled()) FrameCommandMetrics.enable();
    FrameCommandMetrics.beginLiveFrame();
    FrameCommandMetrics.setCountOnly(true);
    FrameCommandMetrics.setCaptureOnly(true);
    try {
      retainedCapturedOriginal =
          PresentationEngineReachabilityProbe.renderPlayerFrameByRef(playerSlot);
      return retainedCapturedOriginal.length;
    } finally {
      FrameCommandMetrics.setCaptureOnly(false);
      FrameCommandMetrics.setCountOnly(false);
    }
  }

  @JSExport
  public static int renderCapturedPlayerFrameLength(int playerSlot)
      throws Exception {
    renderCapturedPlayerFrameByRef(playerSlot);
    return 320 * 200;
  }

  @JSExport
  @JSByRef
  public static byte[] capturedPlayerFrameChunk(int offset, int length) {
    return FrameCommandMetrics.capturedFrameChunk(offset, length);
  }

  @JSExport
  public static int prepareCapturedPlayerFrameRowMajor() {
    return FrameCommandMetrics.prepareCapturedFrameRowMajor();
  }

  @JSExport
  @JSByRef
  public static byte[] capturedPlayerFrameRowMajorChunk(
      int offset, int length) {
    return FrameCommandMetrics.capturedFrameRowMajorChunk(offset, length);
  }

  @JSExport
  public static int capturedFrameCommandCount() {
    return FrameCommandMetrics.liveCommandCount();
  }

  @JSExport
  public static int capturedFrameAssetResetCount() {
    return FrameCommandMetrics.liveAssetResetCount();
  }

  @JSExport
  public static String presentationDiagnostic() {
    return PresentationEngineReachabilityProbe.presentationDiagnostic();
  }

  @JSExport
  public static Uint8Array presentationPlayerSnapshot(int playerSlot) {
    return PresentationEngineReachabilityProbe.presentationPlayerSnapshot(
        playerSlot);
  }

  @JSExport
  public static int presentationWorldSnapshotLength(int playerSlot) {
    return PresentationEngineReachabilityProbe.presentationWorldSnapshotLength(
        playerSlot);
  }

  @JSExport
  public static Uint8Array presentationWorldSnapshotChunk(
      int offset, int length) {
    return PresentationEngineReachabilityProbe.presentationWorldSnapshotChunk(
        offset, length);
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
