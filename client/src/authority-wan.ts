const TIC_MS = 1000 / 35;
const MIN_INPUT_LEAD = 2;
const MAX_INPUT_LEAD = 12;
const MIN_PLAYOUT_TICS = 1;
const MAX_PLAYOUT_TICS = 6;
const PLAYOUT_ACCELERATION_MARGIN_TICS = 2;
const PLAYOUT_DECELERATION_MARGIN_TICS = 2;
const MAX_DECELERATED_PLAYOUT_INTERVAL_MS = 31.4;
const MAX_SAMPLES = 64;
const LEAD_HYSTERESIS_MS = 10_000;

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

function percentile(values: readonly number[], fraction: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)]!;
}

function addSample(samples: number[], value: number): void {
  if (!Number.isFinite(value) || value < 0) {
    throw new TypeError('WAN timing sample is invalid');
  }
  samples.push(value);
  if (samples.length > MAX_SAMPLES) samples.shift();
}

/**
 * Presentation cadence for an already-confirmed queue.
 *
 * A consumer locked permanently to the simulation's 35 Hz rate can never
 * remove backlog introduced by startup or a WAN burst. Confirmed frames may be
 * time-compressed, but never reordered or skipped, until the requested
 * one-frame playout horizon is restored.
 */
export function confirmedPlayoutIntervalMs(backlogTics: number): number {
  if (!Number.isInteger(backlogTics) || backlogTics < 0) {
    throw new TypeError('confirmed playout backlog is invalid');
  }
  // Preserve the exact maximum/maximum+1 boundary as a standalone primitive.
  // The production controller below adds hysteresis around its selected-depth
  // occupancy setpoint.
  return backlogTics > MAX_PLAYOUT_TICS ? TIC_MS / 2 : TIC_MS;
}

export function confirmedPlayoutDecision(
    bufferedFrames: number, selectedDepth: number,
    priorMode: 'ACCELERATE'|'FREE'|'DECELERATE'):
    {intervalMs: number; mode: 'ACCELERATE'|'FREE'|'DECELERATE'} {
  if (!Number.isInteger(bufferedFrames) || bufferedFrames < 0 ||
      !Number.isInteger(selectedDepth) || selectedDepth < MIN_PLAYOUT_TICS ||
      selectedDepth > MAX_PLAYOUT_TICS ||
      !['ACCELERATE','FREE','DECELERATE'].includes(priorMode)) {
    throw new TypeError('confirmed playout occupancy is invalid');
  }
  const accelerationEntry =
    selectedDepth + PLAYOUT_ACCELERATION_MARGIN_TICS;
  const decelerationEntry = Math.max(0,
    selectedDepth - PLAYOUT_DECELERATION_MARGIN_TICS);
  let mode=priorMode;
  if (mode==='ACCELERATE' && bufferedFrames<=selectedDepth) mode='FREE';
  if (mode==='DECELERATE' && bufferedFrames>=selectedDepth) mode='FREE';
  if (mode==='FREE' && bufferedFrames>accelerationEntry) mode='ACCELERATE';
  if (mode==='FREE' && bufferedFrames<decelerationEntry) mode='DECELERATE';
  let intervalMs=TIC_MS;
  if (mode==='ACCELERATE') {
    intervalMs=TIC_MS/2;
  } else if (mode==='DECELERATE') {
    // Spend confirmed state no more than ten percent below native cadence
    // while occupancy is below the selected-depth setpoint.
    intervalMs=MAX_DECELERATED_PLAYOUT_INTERVAL_MS;
  }
  return {intervalMs,mode};
}

/**
 * Schedules input and presentation around confirmed database frontiers.
 *
 * This policy never predicts or applies a transition. Its outputs are target
 * tic numbers consumed by the input poster and confirmed mirror respectively.
 */
export class ConfirmedWanPolicy {
  private readonly rttSamples: number[] = [];
  private readonly deliveryIntervals: number[] = [];
  private inputLead = MIN_INPUT_LEAD;
  private playoutTics = MIN_PLAYOUT_TICS;
  private desiredPlayoutTics = MIN_PLAYOUT_TICS;
  private lastLeadAdjustmentMs = Number.NEGATIVE_INFINITY;
  private lastDeliveryMs: number | undefined;
  private substituted = 0;
  private scheduled = 0;

  get inputLeadTics(): number { return this.inputLead; }
  get playoutBufferTics(): number { return this.playoutTics; }
  get preClampPlayoutBufferTics(): number { return this.desiredPlayoutTics; }
  get neutralSubstitutionRate(): number {
    return this.scheduled === 0 ? 0 : this.substituted / this.scheduled;
  }

  observeRoundTrip(roundTripMs: number, nowMs: number,
                   minimumLeadTics = MIN_INPUT_LEAD): void {
    addSample(this.rttSamples, roundTripMs);
    if (!Number.isFinite(nowMs) || !Number.isInteger(minimumLeadTics) ||
        minimumLeadTics < MIN_INPUT_LEAD) {
      throw new TypeError('WAN clock/lead sample is invalid');
    }
    const desired = clamp(Math.max(
      Math.ceil(percentile(this.rttSamples, 0.90) / TIC_MS) + 1,
      minimumLeadTics),
      MIN_INPUT_LEAD, MAX_INPUT_LEAD);
    if (desired === this.inputLead ||
        nowMs - this.lastLeadAdjustmentMs < LEAD_HYSTERESIS_MS) return;
    // One-tic adjustments avoid oscillating the command horizon.
    this.inputLead += Math.sign(desired - this.inputLead);
    this.lastLeadAdjustmentMs = nowMs;
  }

  observeConfirmedDelivery(nowMs: number): void {
    if (!Number.isFinite(nowMs)) throw new TypeError('WAN clock is invalid');
    if (this.lastDeliveryMs !== undefined) {
      addSample(this.deliveryIntervals, Math.abs(nowMs - this.lastDeliveryMs - TIC_MS));
      this.desiredPlayoutTics =
        Math.ceil(percentile(this.deliveryIntervals, 0.90) / TIC_MS) + 1;
      this.playoutTics = clamp(
        this.desiredPlayoutTics,
        MIN_PLAYOUT_TICS, MAX_PLAYOUT_TICS);
    }
    this.lastDeliveryMs = nowMs;
  }

  inputTargetTic(confirmedFrontierTic: number): number {
    if (!Number.isInteger(confirmedFrontierTic) || confirmedFrontierTic < 0) {
      throw new TypeError('confirmed frontier is invalid');
    }
    return confirmedFrontierTic + this.inputLead;
  }

  presentationTargetTic(confirmedFrontierTic: number): number {
    if (!Number.isInteger(confirmedFrontierTic) || confirmedFrontierTic < 0) {
      throw new TypeError('confirmed frontier is invalid');
    }
    return Math.max(0, confirmedFrontierTic - this.playoutTics);
  }

  recordScheduledTic(neutralSubstituted: boolean): void {
    this.scheduled += 1;
    if (neutralSubstituted) this.substituted += 1;
  }
}
