-- Ordered-integration hook.  Insert exactly once after movement/world/history
-- advancement in DOOM_TIC_TX's per-command logical-tic path.
doom_combat.advance(p_session,l_tic);
