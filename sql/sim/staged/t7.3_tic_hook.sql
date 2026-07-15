-- Ordered-integration hook. Invoke exactly once after authoritative gameplay
-- transitions for a logical tic and before state/history hashes are captured.
doom_audio.emit(p_session,l_tic+command_row.ord);

