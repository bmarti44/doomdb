import { commitAuthorityTransition } from './authority.js';
function hex(bytes) {
    return Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
}
async function canonicalSha(engine) {
    const record = engine.canonicalState();
    if (!/^canonicalBytes=[1-9][0-9]*\|canonicalThinkers=[0-9]+\|canonicalState=[0-9a-f]{32}$/
        .test(record)) {
        throw new TypeError('authority mirror canonical digest record is invalid');
    }
    return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(record))));
}
/**
 * Render-only replica of database-confirmed engine state.
 *
 * This class deliberately has no input or prediction API. Callers can only
 * apply an already validated database transition, in order, then render it.
 */
export class ConfirmedAuthorityMirror {
    #verifier;
    #presenter;
    #playerSlot;
    #state;
    #failed = false;
    constructor(verifier, presenter, playerSlot, initialState) {
        if (!Number.isInteger(playerSlot) || playerSlot < 0 || playerSlot > 3) {
            throw new TypeError('authority mirror player slot is invalid');
        }
        if (verifier === presenter) {
            throw new TypeError('authority verifier and presenter must be independent');
        }
        this.#verifier = verifier;
        this.#presenter = presenter;
        this.#playerSlot = playerSlot;
        this.#state = { ...initialState };
    }
    get frontier() { return { ...this.#state }; }
    async apply(transition) {
        if (this.#failed)
            throw new TypeError('authority mirror requires recovery');
        if (transition.tic !== this.#state.tic + 1 ||
            transition.previousChainSha !== this.#state.chainSha ||
            transition.membershipEpoch !== this.#state.membershipEpoch ||
            transition.generation < this.#state.generation) {
            throw new TypeError('authority mirror transition fence changed');
        }
        const tic = this.#verifier.stepMultiplayerAuthoritative(transition.activePlayers, transition.membershipBitmap, transition.commands);
        try {
            if (tic !== transition.tic) {
                throw new TypeError('authority mirror engine frontier changed');
            }
            if (transition.canonicalStateSha !== undefined &&
                await canonicalSha(this.#verifier) !== transition.canonicalStateSha) {
                throw new TypeError('authority mirror canonical state diverged');
            }
            const presentationTic = this.#presenter.stepMultiplayerAuthoritative(transition.activePlayers, transition.membershipBitmap, transition.commands);
            if (presentationTic !== transition.tic) {
                throw new TypeError('authority presentation frontier changed');
            }
            const frame = this.#presenter.renderPlayerFrame(this.#playerSlot);
            if (!(frame instanceof Uint8Array) || frame.length !== 320 * 200) {
                throw new TypeError('authority mirror frame is invalid');
            }
            commitAuthorityTransition(this.#state, transition);
            return { tic, chainSha: transition.chainSha,
                canonicalStateSha: transition.canonicalStateSha, frame };
        }
        catch (cause) {
            // The engine has advanced and cannot be retried from the old frontier.
            // Force checkpoint recovery rather than risking a half-committed mirror.
            this.#failed = true;
            throw cause;
        }
    }
}
