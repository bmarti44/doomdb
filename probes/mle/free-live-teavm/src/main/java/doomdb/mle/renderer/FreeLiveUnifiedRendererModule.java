package doomdb.mle.renderer;

import org.teavm.jso.JSByRef;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;

/**
 * A single generated module for the retained world raster and final overlay.
 *
 * Both cores remain independently reproducible, but Java-to-Java array
 * binding lets the compositor draw directly into the world framebuffer
 * without crossing an MLE module boundary or converting Java arrays to
 * typed-array element writes.
 */
public final class FreeLiveUnifiedRendererModule {
  private FreeLiveUnifiedRendererModule() {}

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
  public static int loadCompactSnapshot(Uint8Array snapshot) {
    return FreeLiveWorldRasterCore.loadCompactSnapshot(snapshot);
  }

  @JSExport
  public static int renderLoadedCompactFrameCoarse(Uint8Array snapshot) {
    return FreeLiveWorldRasterCore.renderLoadedCompactFrameCoarse(snapshot);
  }

  @JSExport
  public static int allocateCompositorPack(int length) {
    return FreeLiveCompositorCore.allocatePack(length);
  }

  @JSExport
  public static int loadCompositorPackChunk(int offset, Uint8Array chunk) {
    return FreeLiveCompositorCore.loadPackChunk(offset, chunk);
  }

  @JSExport
  public static int finalizeCompositorPack() {
    return FreeLiveCompositorCore.finalizePack();
  }

  @JSExport
  public static int allocateCompositorSprites(int length) {
    return FreeLiveCompositorCore.allocateSpriteTextures(length);
  }

  @JSExport
  public static int loadCompositorSpriteChunk(
      int offset, Uint8Array chunk) {
    return FreeLiveCompositorCore.loadSpriteTextureChunk(offset, chunk);
  }

  @JSExport
  public static int finalizeCompositorSprites() {
    return FreeLiveCompositorCore.finalizeSpriteTextures();
  }

  @JSExport
  public static int allocateCompositorUi(int length) {
    return FreeLiveCompositorCore.allocateUiTextures(length);
  }

  @JSExport
  public static int loadCompositorUiChunk(int offset, Uint8Array chunk) {
    return FreeLiveCompositorCore.loadUiTextureChunk(offset, chunk);
  }

  @JSExport
  public static int finalizeCompositorUi() {
    return FreeLiveCompositorCore.finalizeUiTextures();
  }

  private static void bindCompositionTargets() {
    FreeLiveCompositorCore.bindJavaTargets(
        FreeLiveWorldRasterCore.frameByRef(),
        FreeLiveWorldRasterCore.solidDepthByRef(),
        FreeLiveWorldRasterCore.wallDepthByRef());
  }

  @JSExport
  public static int composeCompactSnapshot(Uint8Array snapshot) {
    bindCompositionTargets();
    return FreeLiveCompositorCore.composeCompactSnapshot(snapshot);
  }

  @JSExport
  public static int composeWorldSpritesStage(Uint8Array snapshot) {
    bindCompositionTargets();
    return FreeLiveCompositorCore.composeWorldSpritesStage(snapshot);
  }

  @JSExport
  public static int composeWeaponStage(Uint8Array snapshot) {
    bindCompositionTargets();
    return FreeLiveCompositorCore.composeWeaponStage(snapshot);
  }

  @JSExport
  public static int composeStatusStage(Uint8Array snapshot) {
    bindCompositionTargets();
    return FreeLiveCompositorCore.composeStatusStage(snapshot);
  }

  @JSExport
  public static int resetPresentationState() {
    return FreeLiveCompositorCore.resetPresentationState();
  }

  @JSExport
  public static int resetWorldState() {
    return FreeLiveWorldRasterCore.resetDynamicWorldState();
  }

  @JSExport
  @JSByRef
  public static byte[] frameByRef() {
    return FreeLiveWorldRasterCore.frameByRef();
  }

  /**
   * Same-isolate zero-copy framebuffer view. TeaVM stores primitive byte
   * arrays in an Int8Array-backed JavaArray; the ordinary {@link JSByRef}
   * export deliberately clones it. The coordinator treats this view as
   * immutable and publishes it before the next raster call mutates the frame.
   */
  @JSExport
  public static Uint8Array frameNativeByRef() {
    return nativeByteArrayView(FreeLiveWorldRasterCore.frameByRef());
  }

  @JSBody(params = {"array"}, script =
      "return new Uint8Array(array.buffer,"
          + "array.byteOffset,array.byteLength);")
  private static native Uint8Array nativeByteArrayView(
      @JSByRef byte[] array);

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
}
