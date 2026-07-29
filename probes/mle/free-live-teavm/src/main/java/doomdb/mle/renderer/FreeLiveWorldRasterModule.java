package doomdb.mle.renderer;

import org.teavm.jso.JSByRef;
import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;

/**
 * Small TeaVM entry point for the hot world-raster isolate.
 *
 * Keeping UI, sprite and live-snapshot exports out of this entry point lets
 * TeaVM eliminate those graphs so Autonomous can compile the remaining BSP,
 * wall and visplane shape. A second retained MLE module owns composition.
 */
public final class FreeLiveWorldRasterModule {
  private FreeLiveWorldRasterModule() {}

  @JSExport
  public static int allocatePack(int length) {
    return FreeLiveWorldRasterCore.allocatePack(length);
  }

  @JSExport
  public static int loadPackChunk(int offset, Uint8Array chunk) {
    return FreeLiveWorldRasterCore.loadPackChunk(offset, chunk);
  }

  @JSExport
  public static int finalizePack() {
    return FreeLiveWorldRasterCore.finalizePack();
  }

  @JSExport
  public static int allocateWallTextures(int length) {
    return FreeLiveWorldRasterCore.allocateWallTextures(length);
  }

  @JSExport
  public static int loadWallTextureChunk(int offset, Uint8Array chunk) {
    return FreeLiveWorldRasterCore.loadWallTextureChunk(offset, chunk);
  }

  @JSExport
  public static int finalizeWallTextures() {
    return FreeLiveWorldRasterCore.finalizeWallTextures();
  }

  @JSExport
  public static int allocateFlatTextures(int length) {
    return FreeLiveWorldRasterCore.allocateFlatTextures(length);
  }

  @JSExport
  public static int loadFlatTextureChunk(int offset, Uint8Array chunk) {
    return FreeLiveWorldRasterCore.loadFlatTextureChunk(offset, chunk);
  }

  @JSExport
  public static int finalizeFlatTextures() {
    return FreeLiveWorldRasterCore.finalizeFlatTextures();
  }

  @JSExport
  public static int renderFrame(int pose) {
    return FreeLiveWorldRasterCore.renderFrame(pose);
  }

  @JSExport
  public static int renderFrameCoarseVertical(int pose) {
    return FreeLiveWorldRasterCore.renderFrameCoarseVertical(pose);
  }

  @JSExport
  public static int loadCompactSnapshot(Uint8Array snapshot) {
    return FreeLiveWorldRasterCore.loadCompactSnapshot(snapshot);
  }

  @JSExport
  public static int renderLoadedCompactFrameCoarse(Uint8Array snapshot) {
    return FreeLiveWorldRasterCore.renderLoadedCompactFrameCoarse(snapshot);
  }

  @JSExport
  public static int renderWallsOnly(int pose) {
    return FreeLiveWorldRasterCore.renderWallsOnly(pose);
  }

  @JSExport
  public static int renderPlanesOnly(int pose) {
    return FreeLiveWorldRasterCore.renderPlanesOnly(pose);
  }

  @JSExport
  @JSByRef
  public static byte[] frameChunk(int offset, int length) {
    return FreeLiveWorldRasterCore.frameChunk(offset, length);
  }

  @JSExport
  @JSByRef
  public static byte[] frameByRef() {
    return FreeLiveWorldRasterCore.frameByRef();
  }

  @JSExport
  @JSByRef
  public static double[] solidDepthByRef() {
    return FreeLiveWorldRasterCore.solidDepthByRef();
  }

  @JSExport
  @JSByRef
  public static double[] wallDepthByRef() {
    return FreeLiveWorldRasterCore.wallDepthByRef();
  }

  @JSExport
  public static int rasterPixelWrites() {
    return FreeLiveWorldRasterCore.rasterPixelWrites();
  }
}
