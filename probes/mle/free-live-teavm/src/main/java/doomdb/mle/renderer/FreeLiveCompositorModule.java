package doomdb.mle.renderer;

import org.teavm.jso.JSByRef;
import org.teavm.jso.JSExport;
import org.teavm.jso.typedarrays.Uint8Array;

/** Isolated sprite, weapon, HUD, title, and menu compositor. */
public final class FreeLiveCompositorModule {
  private FreeLiveCompositorModule() {}

  @JSExport
  public static int allocatePack(int length) {
    return FreeLiveCompositorCore.allocatePack(length);
  }

  @JSExport
  public static int loadPackChunk(int offset, Uint8Array chunk) {
    return FreeLiveCompositorCore.loadPackChunk(offset, chunk);
  }

  @JSExport
  public static int finalizePack() {
    return FreeLiveCompositorCore.finalizePack();
  }

  @JSExport
  public static int allocateSpriteTextures(int length) {
    return FreeLiveCompositorCore.allocateSpriteTextures(length);
  }

  @JSExport
  public static int loadSpriteTextureChunk(int offset, Uint8Array chunk) {
    return FreeLiveCompositorCore.loadSpriteTextureChunk(offset, chunk);
  }

  @JSExport
  public static int finalizeSpriteTextures() {
    return FreeLiveCompositorCore.finalizeSpriteTextures();
  }

  @JSExport
  public static int allocateUiTextures(int length) {
    return FreeLiveCompositorCore.allocateUiTextures(length);
  }

  @JSExport
  public static int loadUiTextureChunk(int offset, Uint8Array chunk) {
    return FreeLiveCompositorCore.loadUiTextureChunk(offset, chunk);
  }

  @JSExport
  public static int finalizeUiTextures() {
    return FreeLiveCompositorCore.finalizeUiTextures();
  }

  @JSExport
  public static int composeCompactSnapshot(Uint8Array snapshot) {
    return FreeLiveCompositorCore.composeCompactSnapshot(snapshot);
  }

  @JSExport
  public static int composeWorldSpritesStage(Uint8Array snapshot) {
    return FreeLiveCompositorCore.composeWorldSpritesStage(snapshot);
  }

  @JSExport
  public static int composeWeaponStage(Uint8Array snapshot) {
    return FreeLiveCompositorCore.composeWeaponStage(snapshot);
  }

  @JSExport
  public static int composeStatusStage(Uint8Array snapshot) {
    return FreeLiveCompositorCore.composeStatusStage(snapshot);
  }

  @JSExport
  public static int resetPresentationState() {
    return FreeLiveCompositorCore.resetPresentationState();
  }

  @JSExport
  @JSByRef
  public static byte[] frameByRef() {
    return FreeLiveCompositorCore.frameByRef();
  }

  @JSExport
  @JSByRef
  public static double[] solidDepthByRef() {
    return FreeLiveCompositorCore.solidDepthByRef();
  }

  @JSExport
  @JSByRef
  public static double[] wallDepthByRef() {
    return FreeLiveCompositorCore.wallDepthByRef();
  }
}
