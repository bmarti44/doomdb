/* GPLv3-or-later: links with the pinned Mocha Doom engine. */
package doomdb.mle.engine;

import data.info;
import data.mobjinfo_t;
import data.state_t;

/** Forces reachability of every vanilla actor, state and action identifier. */
public final class ActorMetadataReachabilityProbe {
  private ActorMetadataReachabilityProbe() {}

  public static void main(String[] args) {
    int hash = 1;
    for (state_t state : info.states) {
      hash = 31 * hash + state.sprite.ordinal();
      hash = 31 * hash + state.action.ordinal();
      hash = 31 * hash + state.nextstate.ordinal();
      hash = 31 * hash + state.tics;
    }
    for (mobjinfo_t actor : info.mobjinfo) {
      hash = 31 * hash + actor.doomednum;
      hash = 31 * hash + actor.spawnhealth;
      hash = 31 * hash + actor.speed;
      hash = 31 * hash + (int) actor.flags;
    }
    if (hash == 0) throw new IllegalStateException("actor metadata checksum");
  }
}
