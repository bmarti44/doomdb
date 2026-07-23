import {
  combinedChecksum,
  renderCommandChecksum,
  simulationChecksum,
} from './target/javascript/doom-mle-engine-slice.js';

const first = {
  simulation: simulationChecksum(),
  renderCommands: renderCommandChecksum(),
  combined: combinedChecksum(),
};
const second = {
  simulation: simulationChecksum(),
  renderCommands: renderCommandChecksum(),
  combined: combinedChecksum(),
};
if (JSON.stringify(first) !== JSON.stringify(second)) {
  throw new Error(`non-deterministic TeaVM engine slice: ${JSON.stringify({first, second})}`);
}
if (Object.values(first).some(value => !Number.isInteger(value) || value === 0)) {
  throw new Error(`invalid TeaVM engine slice result: ${JSON.stringify(first)}`);
}
console.log(`PASS PMLE-TEAVM-ENGINE-SLICE ${JSON.stringify(first)}`);
