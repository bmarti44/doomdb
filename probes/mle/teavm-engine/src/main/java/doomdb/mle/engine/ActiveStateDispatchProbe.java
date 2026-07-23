package doomdb.mle.engine;

import org.teavm.jso.JSExport;
import p.ActiveStates;
import p.ActiveStates.ThinkerConsumer;

/** TeaVM-emitted lookup shape used by ActionsThinkers.Ticker. */
public final class ActiveStateDispatchProbe {
  private static final Class<ThinkerConsumer> TYPE = ThinkerConsumer.class;
  private static final ActiveStates STATE = ActiveStates.NOP;
  private static final ThinkerConsumer CACHED = STATE.fun(TYPE);
  private static final ThinkerConsumer[] TABLE = {CACHED};

  private ActiveStateDispatchProbe() {}

  /** Per-thinker enum type check plus generic fun() lookup. */
  @JSExport
  public static int stateLookup(int iterations) {
    int checksum = 0;
    for (int i = 0; i < iterations; i++) {
      if (STATE.isParamType(TYPE) && STATE.fun(TYPE) == CACHED) {
        checksum = checksum * 31 + i;
      }
    }
    return checksum;
  }

  /** Static dispatch table built once, retaining the same consumer object. */
  @JSExport
  public static int tableLookup(int iterations) {
    int checksum = 0;
    for (int i = 0; i < iterations; i++) {
      if (TABLE[0] == CACHED) checksum = checksum * 31 + i;
    }
    return checksum;
  }

  public static void main(String[] args) {}
}
