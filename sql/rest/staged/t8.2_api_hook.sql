-- T8.2 ordered DOOM_API body integration seam. This file is not a new public
-- endpoint and is deliberately parked outside 010_doom_api.sql until the T7.3,
-- T8.1, and T10.1 live stack is ready.

-- NEW_GAME: after all authoritative E1M1 rows exist and before tic-zero state
-- serialization/rendering:
doom_workflow.initialize_session(p_session);

-- STEP remains the only public control entry point. DOOM_TIC_TX validates the
-- exact command grammar and invokes DOOM_WORKFLOW in the owning transaction.
-- A REWIND:<tic> or DEAD/RESTART branch is resolved inside that transaction via
-- DOOM_HISTORY.REWIND_TO_TIC; the REST body only renders the resulting state.
-- SAVE_GAME, LOAD_GAME, START_REPLAY, and STEP_REPLAY retain their fixed public
-- signatures and continue delegating to verified DOOM_HISTORY operations.

