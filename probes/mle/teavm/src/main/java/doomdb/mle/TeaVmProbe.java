/* GPLv3-or-later: links with pinned Mocha Doom for a disposable MLE probe. */
package doomdb.mle;

import data.Tables;
import org.teavm.jso.JSExport;

/** Smallest real Mocha bytecode slice used to validate TeaVM -> MLE modules. */
public final class TeaVmProbe {
  private TeaVmProbe() {}

  @JSExport
  public static int tablesChecksum() {
    Tables.InitTables();
    int value = 0;
    for (int index = 0; index < Tables.finesine.length; index += 257) {
      value = value * 31 + Tables.finesine[index];
    }
    return value;
  }

  public static void main(String[] args) {
    tablesChecksum();
  }
}
