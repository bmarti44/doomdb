/*
 * Copyright (C) 2026 DoomDB contributors
 * GPLv3-or-later. Disposable renderer-port instrumentation.
 */
package doomdb.mocha;

import java.util.Arrays;
import rr.drawfuns.ColVars;
import rr.drawfuns.SpanVars;

/** Counts production Mocha raster commands without retaining framebuffer data. */
public final class DoomDbDrawMetrics {
  private static boolean enabled;
  private static long frames, columns, spans, pixels, uniqueColumns, uniqueSpans;
  private static long columnPixels, spanPixels, sourceSets, colormapSets;
  private static long translationSets, lengthLe8, lengthLe16, lengthLe32;
  private static long lengthLe64, lengthLe128, lengthLe200, lengthOver200;
  private static long maxCommands, maxPixels, frameColumns, frameSpans, framePixels;
  private static long maxColumnPixels, maxSpanPixels, maxSourceSets;
  private static long maxColormapSets, maxTranslationSets;
  private static int maxColumnLength, maxSpanLength;
  private static final long[] columnKinds = new long[8];
  private static final long[] spanKinds = new long[8];
  private static final long[] frameColumnKeys = new long[4096];
  private static final long[] frameSpanKeys = new long[2048];
  private static final long[] frameSourceKeys = new long[4096];
  private static final long[] frameColormapKeys = new long[256];
  private static final long[] frameTranslationKeys = new long[128];
  private static int frameUniqueColumns, frameUniqueSpans;
  private static int frameSourceSets, frameColormapSets, frameTranslationSets;
  private static long frameColumnPixels, frameSpanPixels;

  private DoomDbDrawMetrics() {}

  public static void beginRun() {
    frames = columns = spans = pixels = uniqueColumns = uniqueSpans = 0;
    columnPixels = spanPixels = sourceSets = colormapSets = translationSets = 0;
    lengthLe8 = lengthLe16 = lengthLe32 = lengthLe64 = 0;
    lengthLe128 = lengthLe200 = lengthOver200 = 0;
    maxCommands = maxPixels = 0;enabled = true;
    maxColumnPixels = maxSpanPixels = maxSourceSets = maxColormapSets = 0;
    maxTranslationSets = 0;maxColumnLength=maxSpanLength=0;
    Arrays.fill(columnKinds,0L);Arrays.fill(spanKinds,0L);
  }
  public static void beginFrame() {
    if (!enabled) return;
    frameColumns = frameSpans = framePixels = 0;
    frameUniqueColumns=frameUniqueSpans=0;
    frameSourceSets=frameColormapSets=frameTranslationSets=0;
    frameColumnPixels=frameSpanPixels=0;
    Arrays.fill(frameColumnKeys,0L);Arrays.fill(frameSpanKeys,0L);
    Arrays.fill(frameSourceKeys,0L);Arrays.fill(frameColormapKeys,0L);
    Arrays.fill(frameTranslationKeys,0L);
  }
  public static void column(ColVars<byte[], byte[]> vars, int kind) {
    if (!enabled || vars == null) return;
    int count = vars.dc_yh - vars.dc_yl + 1;if (count <= 0) return;
    long key = 1469598103934665603L;
    key=mix(key,kind);key=mix(key,vars.dc_yl);key=mix(key,vars.dc_yh);
    key=mix(key,vars.dc_iscale);key=mix(key,vars.dc_texturemid);
    key=mix(key,vars.dc_texheight);key=mix(key,vars.dc_source_ofs);
    key=mix(key,System.identityHashCode(vars.dc_source));
    key=mix(key,System.identityHashCode(vars.dc_colormap));
    key=mix(key,System.identityHashCode(vars.dc_translation));
    if(insert(frameColumnKeys,key))frameUniqueColumns++;
    if(insert(frameSourceKeys,identity(vars.dc_source)))frameSourceSets++;
    if(insert(frameColormapKeys,identity(vars.dc_colormap)))frameColormapSets++;
    if(vars.dc_translation != null
        && insert(frameTranslationKeys,identity(vars.dc_translation))) {
      frameTranslationSets++;
    }
    frameColumns++;framePixels += count;frameColumnPixels += count;
    if(kind>=0&&kind<columnKinds.length)columnKinds[kind]++;
    maxColumnLength=Math.max(maxColumnLength,count);recordLength(count);
  }
  public static void span(SpanVars<byte[], byte[]> vars, int kind) {
    if (!enabled || vars == null) return;
    int count=vars.ds_x2-vars.ds_x1+1;if(count<=0)return;
    long key=1469598103934665603L;
    key=mix(key,kind);key=mix(key,vars.ds_y);key=mix(key,vars.ds_x1);
    key=mix(key,vars.ds_x2);key=mix(key,vars.ds_xfrac);key=mix(key,vars.ds_yfrac);
    key=mix(key,vars.ds_xstep);key=mix(key,vars.ds_ystep);
    key=mix(key,System.identityHashCode(vars.ds_source));
    key=mix(key,System.identityHashCode(vars.ds_colormap));
    if(insert(frameSpanKeys,key))frameUniqueSpans++;
    if(insert(frameSourceKeys,identity(vars.ds_source)))frameSourceSets++;
    if(insert(frameColormapKeys,identity(vars.ds_colormap)))frameColormapSets++;
    frameSpans++;framePixels += count;frameSpanPixels += count;
    if(kind>=0&&kind<spanKinds.length)spanKinds[kind]++;
    maxSpanLength=Math.max(maxSpanLength,count);recordLength(count);
  }
  public static void endFrame() {
    if(!enabled)return;frames++;columns+=frameColumns;spans+=frameSpans;
    pixels+=framePixels;uniqueColumns+=frameUniqueColumns;
    uniqueSpans+=frameUniqueSpans;columnPixels+=frameColumnPixels;
    spanPixels+=frameSpanPixels;sourceSets+=frameSourceSets;
    colormapSets+=frameColormapSets;translationSets+=frameTranslationSets;
    maxCommands=Math.max(maxCommands,frameColumns+frameSpans);
    maxPixels=Math.max(maxPixels,framePixels);
    maxColumnPixels=Math.max(maxColumnPixels,frameColumnPixels);
    maxSpanPixels=Math.max(maxSpanPixels,frameSpanPixels);
    maxSourceSets=Math.max(maxSourceSets,frameSourceSets);
    maxColormapSets=Math.max(maxColormapSets,frameColormapSets);
    maxTranslationSets=Math.max(maxTranslationSets,frameTranslationSets);
  }
  public static String finish() {
    enabled=false;long divisor=Math.max(1,frames);
    return "drawFrames="+frames+"|columnsPerFrame="+columns/divisor
      +"|spansPerFrame="+spans/divisor+"|pixelsPerFrame="+pixels/divisor
      +"|uniqueColumnsPerFrame="+uniqueColumns/divisor
      +"|uniqueSpansPerFrame="+uniqueSpans/divisor
      +"|columnPixelsPerFrame="+columnPixels/divisor
      +"|spanPixelsPerFrame="+spanPixels/divisor
      +"|sourceSetsPerFrame="+sourceSets/divisor
      +"|colormapSetsPerFrame="+colormapSets/divisor
      +"|translationSetsPerFrame="+translationSets/divisor
      +"|maxDrawCommands="+maxCommands+"|maxDrawPixels="+maxPixels
      +"|maxColumnPixels="+maxColumnPixels+"|maxSpanPixels="+maxSpanPixels
      +"|maxSourceSets="+maxSourceSets+"|maxColormapSets="+maxColormapSets
      +"|maxTranslationSets="+maxTranslationSets
      +"|maxColumnLength="+maxColumnLength+"|maxSpanLength="+maxSpanLength
      +"|lengthLe8="+lengthLe8+"|lengthLe16="+lengthLe16
      +"|lengthLe32="+lengthLe32+"|lengthLe64="+lengthLe64
      +"|lengthLe128="+lengthLe128+"|lengthLe200="+lengthLe200
      +"|lengthOver200="+lengthOver200
      +"|columnKind1="+columnKinds[1]+"|columnKind2="+columnKinds[2]
      +"|columnKind3="+columnKinds[3]+"|spanKind1="+spanKinds[1];
  }
  private static long identity(Object value) {
    return value == null ? 1L : (System.identityHashCode(value)&0xffffffffL)+2L;
  }
  private static void recordLength(int count) {
    if(count<=8)lengthLe8++;
    else if(count<=16)lengthLe16++;
    else if(count<=32)lengthLe32++;
    else if(count<=64)lengthLe64++;
    else if(count<=128)lengthLe128++;
    else if(count<=200)lengthLe200++;
    else lengthOver200++;
  }
  private static long mix(long value,int field){
    return(value^(field&0xffffffffL))*1099511628211L;
  }
  private static boolean insert(long[] table,long key){
    if(key==0)key=1;int mask=table.length-1;
    int slot=(int)(key^(key>>>32))&mask;
    for(int probe=0;probe<table.length;probe++){
      long existing=table[slot];if(existing==key)return false;
      if(existing==0){table[slot]=key;return true;}slot=(slot+1)&mask;
    }
    return false;
  }
}
