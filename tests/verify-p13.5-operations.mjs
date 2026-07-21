import assert from 'node:assert/strict';
import fs from 'node:fs';

const report=fs.readFileSync(new URL('../scripts/multiplayer-status.sql',import.meta.url),'utf8');
for (const required of ['MULTIPLAYER_LIFECYCLE','MULTIPLAYER_ACTIVE',
  'MULTIPLAYER_ACTIVE_PLAYERS','average_hz','command_lead','recoveries',
  'tic_p95_ms','frame_rows','frame_bytes','checkpoints','input_revisions',
  'applied_commands','neutral_commands','average_response_bytes',
  'TRANSPORT_LATENCY_AND_HTTP_REJECTS']) assert.match(report,new RegExp(required,'i'));
assert.doesNotMatch(report,/select[^;]*(capability_(?:hash|salt)|display_name)/is,
  'operator report must not expose capabilities or player names');
assert.match(report,/standard_hash\(m\.match_id,'SHA256'\)/i,
  'operator report must pseudonymize match identifiers');
process.stdout.write('PASS P13.5-OPERATIONS bounded pseudonymous database report\n');
