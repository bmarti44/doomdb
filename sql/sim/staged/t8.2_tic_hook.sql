-- Ordered T8.2 integration seam (documentation/source-audit artifact only).
-- In each command iteration, before any RNG/gameplay package advances:
doom_workflow.apply_control(
  p_session,command_row.tic,command_row.pause_toggle,command_row.menu_action,
  command_row.automap_toggle,command_row.cheat_code,l_gameplay_enabled,
  l_branch_kind,l_branch_tic);

-- Only invoke movement/world/combat/monster/audio packages when this is one.
-- Paused, menu, DEAD, and INTERMISSION commands still append their exact
-- TIC_COMMANDS/history row and advance the global command sequence.
if l_gameplay_enabled=1 then
  -- Damage application joins GAME_SESSIONS.GOD_MODE and clamps incoming
  -- damage to zero when it is one; health, armor, and inventory are not
  -- rewritten by the GOD control itself. NOCLIP bypasses blocking collision
  -- only, so crossing triggers and pickup processing remain in this path.
  null; -- existing ordered gameplay calls remain here
end if;

-- REWIND/RESTART are resolved by the owning transaction through
-- DOOM_HISTORY.REWIND_TO_TIC before canonical hashing. The submitted command
-- remains in the old lineage, the new branch keeps LAST_COMMAND_SEQ, and no
-- old command/event/history row is deleted.

-- After gameplay but before canonical state serialization/rendering, establish
-- DEAD/INTERMISSION so this command's payload already carries the terminal mode.
doom_workflow.finish_gameplay(p_session,command_row.tic);

-- After canonical state and frame hashes exist, attach the derived terminal
-- evidence. These two seals are excluded from their own canonical hash inputs.
doom_workflow.seal_terminal(p_session,l_state_sha,l_frame_sha);
