const TIC_MS = 1000 / 35;
const MIN_INPUT_LEAD = 2;
const MAX_INPUT_LEAD = 12;
const MIN_PLAYOUT_TICS = 1;
const MAX_PLAYOUT_TICS = 6;
const MAX_SAMPLES = 64;
const LEAD_HYSTERESIS_MS = 10_000;
function clamp(value, minimum, maximum) {
    return Math.min(maximum, Math.max(minimum, value));
}
function percentile(values, fraction) {
    if (values.length === 0)
        return 0;
    const sorted = [...values].sort((left, right) => left - right);
    return sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];
}
function addSample(samples, value) {
    if (!Number.isFinite(value) || value < 0) {
        throw new TypeError('WAN timing sample is invalid');
    }
    samples.push(value);
    if (samples.length > MAX_SAMPLES)
        samples.shift();
}
/**
 * Schedules input and presentation around confirmed database frontiers.
 *
 * This policy never predicts or applies a transition. Its outputs are target
 * tic numbers consumed by the input poster and confirmed mirror respectively.
 */
export class ConfirmedWanPolicy {
    rttSamples = [];
    deliveryIntervals = [];
    inputLead = MIN_INPUT_LEAD;
    playoutTics = MIN_PLAYOUT_TICS;
    lastLeadAdjustmentMs = Number.NEGATIVE_INFINITY;
    lastDeliveryMs;
    substituted = 0;
    scheduled = 0;
    get inputLeadTics() { return this.inputLead; }
    get playoutBufferTics() { return this.playoutTics; }
    get neutralSubstitutionRate() {
        return this.scheduled === 0 ? 0 : this.substituted / this.scheduled;
    }
    observeRoundTrip(roundTripMs, nowMs) {
        addSample(this.rttSamples, roundTripMs);
        if (!Number.isFinite(nowMs))
            throw new TypeError('WAN clock is invalid');
        const desired = clamp(Math.ceil(percentile(this.rttSamples, 0.90) / TIC_MS) + 1, MIN_INPUT_LEAD, MAX_INPUT_LEAD);
        if (desired === this.inputLead ||
            nowMs - this.lastLeadAdjustmentMs < LEAD_HYSTERESIS_MS)
            return;
        // One-tic adjustments avoid oscillating the command horizon.
        this.inputLead += Math.sign(desired - this.inputLead);
        this.lastLeadAdjustmentMs = nowMs;
    }
    observeConfirmedDelivery(nowMs) {
        if (!Number.isFinite(nowMs))
            throw new TypeError('WAN clock is invalid');
        if (this.lastDeliveryMs !== undefined) {
            addSample(this.deliveryIntervals, Math.abs(nowMs - this.lastDeliveryMs - TIC_MS));
            this.playoutTics = clamp(Math.ceil(percentile(this.deliveryIntervals, 0.90) / TIC_MS) + 1, MIN_PLAYOUT_TICS, MAX_PLAYOUT_TICS);
        }
        this.lastDeliveryMs = nowMs;
    }
    inputTargetTic(confirmedFrontierTic) {
        if (!Number.isInteger(confirmedFrontierTic) || confirmedFrontierTic < 0) {
            throw new TypeError('confirmed frontier is invalid');
        }
        return confirmedFrontierTic + this.inputLead;
    }
    presentationTargetTic(confirmedFrontierTic) {
        if (!Number.isInteger(confirmedFrontierTic) || confirmedFrontierTic < 0) {
            throw new TypeError('confirmed frontier is invalid');
        }
        return Math.max(0, confirmedFrontierTic - this.playoutTics);
    }
    recordScheduledTic(neutralSubstituted) {
        this.scheduled += 1;
        if (neutralSubstituted)
            this.substituted += 1;
    }
}
