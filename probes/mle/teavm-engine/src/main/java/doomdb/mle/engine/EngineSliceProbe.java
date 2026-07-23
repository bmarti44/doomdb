/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import data.Tables;
import data.info;
import data.mobjinfo_t;
import data.state_t;
import doom.ticcmd_t;
import m.BBox;
import m.DelegateRandom;
import m.fixed_t;
import org.teavm.jso.JSExport;
import p.MapUtils;
import p.divline_t;
import rr.drawfuns.ColVars;
import rr.drawfuns.R_DrawColumnBoomOpt;
import rr.drawfuns.R_DrawSpan;
import rr.drawfuns.SpanVars;

/**
 * A reachable, executable subset of the real engine chosen along the planned
 * MLE/native boundary.  It includes deterministic game inputs and state LUTs,
 * fixed-point/BSP math, and Mocha Doom's exact indexed column/span consumers.
 */
public final class EngineSliceProbe {
  private static final int WIDTH = 320;
  private static final int HEIGHT = 200;
  private static final int COLUMN_COMMANDS = 1416;
  private static final int SPAN_COMMANDS = 667;

  private EngineSliceProbe() {}

  /** Exercise the inputs and immutable data used by the authoritative ticker. */
  @JSExport
  public static int simulationChecksum() {
    Tables.InitTables();
    int hash = 0x6d2b79f5;

    DelegateRandom random = new DelegateRandom();
    random.ClearRandom();
    for (int i = 0; i < 256; i++) {
      hash = mix(hash, random.P_Random());
    }

    ticcmd_t command = new ticcmd_t();
    command.forwardmove = 25;
    command.sidemove = -24;
    command.angleturn = (short) -640;
    command.consistancy = (short) 0x2a55;
    command.chatchar = 0;
    command.buttons = 3;
    byte[] packed = command.pack();
    for (int i = 0; i < packed.length; i++) {
      hash = mix(hash, packed[i] & 0xff);
    }

    BBox box = new BBox();
    box.ClearBox();
    for (int i = 0; i < 64; i++) {
      int x = Tables.finecosine[(i * 71) & Tables.FINEMASK];
      int y = Tables.finesine[(i * 113) & Tables.FINEMASK];
      box.AddToBox(x, y);
    }
    for (int value : box.bbox) hash = mix(hash, value);

    divline_t first = new divline_t();
    first.x = -2 * fixed_t.FRACUNIT;
    first.y = fixed_t.FRACUNIT;
    first.dx = 7 * fixed_t.FRACUNIT;
    first.dy = 3 * fixed_t.FRACUNIT;
    divline_t second = new divline_t();
    second.x = fixed_t.FRACUNIT;
    second.y = -3 * fixed_t.FRACUNIT;
    second.dx = -2 * fixed_t.FRACUNIT;
    second.dy = 9 * fixed_t.FRACUNIT;
    hash = mix(hash, MapUtils.P_InterceptVector(first, second));
    hash = mix(hash, MapUtils.AproxDistance(first.dx, second.dy));

    // Retain the complete vanilla actor/state metadata used by P_SetMobjState
    // and the action dispatcher. The local TeaVM patch removes only its
    // ConsoleHandler side effect; these data and action IDs remain upstream.
    for (state_t state : info.states) {
      hash = mix(hash, state.sprite.ordinal());
      hash = mix(hash, state.frame);
      hash = mix(hash, state.tics);
      hash = mix(hash, state.action.ordinal());
      hash = mix(hash, state.nextstate.ordinal());
    }
    for (mobjinfo_t actor : info.mobjinfo) {
      hash = mix(hash, actor.doomednum);
      hash = mix(hash, actor.spawnhealth);
      hash = mix(hash, actor.speed);
      hash = mix(hash, actor.radius);
      hash = mix(hash, actor.height);
      hash = mix(hash, (int) actor.flags);
      hash = mix(hash, (int) (actor.flags >>> 32));
    }

    return hash;
  }

  /**
   * Generate a production-cardinality draw tape and execute it through the
   * actual indexed Mocha Doom raster primitives.  The data is synthetic, but
   * command shape, fixed-point stepping, lookup semantics and destination
   * layout are the production implementations.
   */
  @JSExport
  public static int renderCommandChecksum() {
    int[] ylookup = new int[HEIGHT];
    int[] columnofs = new int[WIDTH];
    for (int y = 0; y < HEIGHT; y++) ylookup[y] = y * WIDTH;
    for (int x = 0; x < WIDTH; x++) columnofs[x] = x;

    byte[] screen = new byte[WIDTH * HEIGHT];
    byte[] columnSource = new byte[128];
    byte[] flatSource = new byte[64 * 64];
    byte[] colormap = new byte[256];
    for (int i = 0; i < columnSource.length; i++) {
      columnSource[i] = (byte) ((i * 29 + 17) & 0xff);
    }
    for (int i = 0; i < flatSource.length; i++) {
      flatSource[i] = (byte) ((i * 13 + (i >>> 6) * 7) & 0xff);
    }
    for (int i = 0; i < colormap.length; i++) {
      colormap[i] = (byte) ((i * 5 + 11) & 0xff);
    }

    ColVars<byte[], byte[]> column = new ColVars<byte[], byte[]>();
    column.dc_source = columnSource;
    column.dc_colormap = colormap;
    column.dc_texheight = columnSource.length;
    column.centery = HEIGHT / 2;
    R_DrawColumnBoomOpt.Indexed drawColumn =
        new R_DrawColumnBoomOpt.Indexed(WIDTH, HEIGHT, ylookup, columnofs,
            column, screen, null);
    for (int command = 0; command < COLUMN_COMMANDS; command++) {
      int x = (command * 73 + 19) % WIDTH;
      int top = (command * 7) % 91;
      int count = 8 + ((command * 11) % (HEIGHT - top - 7));
      column.dc_x = x;
      column.dc_yl = top;
      column.dc_yh = top + count - 1;
      column.dc_iscale = (fixed_t.FRACUNIT / 2) + ((command & 31) << 10);
      column.dc_texturemid = ((command * 37) & 127) << fixed_t.FRACBITS;
      drawColumn.invoke();
    }

    SpanVars<byte[], byte[]> span = new SpanVars<byte[], byte[]>();
    span.ds_source = flatSource;
    span.ds_colormap = colormap;
    R_DrawSpan.Indexed drawSpan = new R_DrawSpan.Indexed(
        WIDTH, HEIGHT, ylookup, columnofs, span, screen, null);
    for (int command = 0; command < SPAN_COMMANDS; command++) {
      int x1 = (command * 31) % 200;
      int width = 1 + ((command * 17) % (WIDTH - x1));
      span.ds_y = (command * 47 + 3) % HEIGHT;
      span.ds_x1 = x1;
      span.ds_x2 = x1 + width - 1;
      span.ds_xfrac = command * 0x0012345;
      span.ds_yfrac = command * 0x0034567;
      span.ds_xstep = 0x00018000 + ((command & 15) << 11);
      span.ds_ystep = 0x0000c000 + ((command & 7) << 12);
      drawSpan.invoke();
    }

    int hash = 0x811c9dc5;
    for (int i = 0; i < screen.length; i++) {
      hash ^= screen[i] & 0xff;
      hash *= 0x01000193;
    }
    return hash;
  }

  @JSExport
  public static int combinedChecksum() {
    return mix(simulationChecksum(), renderCommandChecksum());
  }

  public static void main(String[] args) {
    combinedChecksum();
  }

  private static int mix(int hash, int value) {
    hash ^= value + 0x9e3779b9 + (hash << 6) + (hash >>> 2);
    return hash;
  }
}
