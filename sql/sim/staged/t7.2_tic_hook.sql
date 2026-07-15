-- Ordered-integration hook. Insert exactly once after DOOM_COMBAT.ADVANCE in
-- the owning logical-tic transaction.
doom_monsters.advance(p_session,l_tic);

