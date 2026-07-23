/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import defines.skill_t;
import doom.DoomMain;
import mochadoom.Engine;

/** Forces TeaVM to analyze the patched, real headless bootstrap and one tic. */
public final class FullEngineReachabilityProbe {
  private FullEngineReachabilityProbe() {}

  public static void main(String[] args) throws Exception {
    DoomMain<?, ?> engine = Engine.createHeadless(
        "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
        "-width", "320", "-height", "200");
    engine.singletics = true;
    engine.InitNew(skill_t.sk_medium, 1, 1);
    engine.Ticker();
    engine.gametic++;
    engine.Display();
  }
}
