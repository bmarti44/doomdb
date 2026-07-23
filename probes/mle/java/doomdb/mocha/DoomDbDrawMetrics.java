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
  private static long maxCommands, maxPixels, frameColumns, frameSpans, framePixels;
  private static final long[] frameColumnKeys = new long[4096];
  private static final long[] frameSpanKeys = new long[2048];
  private static int frameUniqueColumns, frameUniqueSpans;

  private DoomDbDrawMetrics() {}

  public static void beginRun() {
    frames = columns = spans = pixels = uniqueColumns = uniqueSpans = 0;
    maxCommands = maxPixels = 0;enabled = true;
  }
  public static void beginFrame() {
    if (!enabled) return;
    frameColumns = frameSpans = framePixels = 0;
    frameUniqueColumns=frameUniqueSpans=0;
    Arrays.fill(frameColumnKeys,0L);Arrays.fill(frameSpanKeys,0L);
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
    frameColumns++;framePixels += count;
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
    frameSpans++;framePixels += count;
  }
  public static void endFrame() {
    if(!enabled)return;frames++;columns+=frameColumns;spans+=frameSpans;
    pixels+=framePixels;uniqueColumns+=frameUniqueColumns;
    uniqueSpans+=frameUniqueSpans;maxCommands=Math.max(maxCommands,frameColumns+frameSpans);
    maxPixels=Math.max(maxPixels,framePixels);
  }
  public static String finish() {
    enabled=false;long divisor=Math.max(1,frames);
    return "drawFrames="+frames+"|columnsPerFrame="+columns/divisor
      +"|spansPerFrame="+spans/divisor+"|pixelsPerFrame="+pixels/divisor
      +"|uniqueColumnsPerFrame="+uniqueColumns/divisor
      +"|uniqueSpansPerFrame="+uniqueSpans/divisor
      +"|maxDrawCommands="+maxCommands+"|maxDrawPixels="+maxPixels;
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
