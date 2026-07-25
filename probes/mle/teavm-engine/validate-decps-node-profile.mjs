#!/usr/bin/env node
import {createHash} from 'node:crypto';
import fs from 'node:fs';

const authoritySha =
  '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3';
const streamSha =
  'fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

function one(text, prefix, label) {
  const rows = text.split(/\r?\n/).filter(line => line.startsWith(prefix));
  if (rows.length !== 1) {
    throw new Error(`${label}: expected one ${prefix}, found ${rows.length}`);
  }
  return rows[0];
}

function fields(line, prefix, expected, label) {
  const entries = line.slice(prefix.length).split('|').map(token => {
    const separator = token.indexOf('=');
    if (separator < 1) throw new Error(`${label}: malformed field`);
    return [token.slice(0, separator), token.slice(separator + 1)];
  });
  const names = entries.map(([name]) => name);
  if (new Set(names).size !== names.length
      || names.toSorted().join(',') !== expected.toSorted().join(',')) {
    throw new Error(`${label}: fields are not exact and unique`);
  }
  return Object.fromEntries(entries);
}

function validate(text, profileBytes) {
  const startPrefix = 'PMLE_DECPS_NODE_PROFILE|START|';
  const rankPrefix = 'PMLE_DECPS_NODE_PROFILE_RANK|PASS|';
  const passPrefix = 'PMLE_DECPS_NODE_PROFILE|PASS|';
  const startLine = one(text, startPrefix, 'profile start');
  const rankLine = one(text, rankPrefix, 'profile rank');
  const passLine = one(text, passPrefix, 'profile terminal');
  const start = fields(startLine, startPrefix, [
    'authority_sha256',
    'profile_artifact_sha256',
    'stream_sha256',
    'tics',
    'host_quiet',
  ], 'profile start');
  const rank = fields(rankLine, rankPrefix, [
    'samples',
    'sampled_ms',
    'sight_bsp_pct',
    'sight_bsp_eligible',
    'movement_ai_pct',
    'mobj_flag_long_pct',
  ], 'profile rank');
  const pass = fields(passLine, passPrefix, [
    'authority_sha256',
    'profile_sha256',
  ], 'profile terminal');
  if (start.authority_sha256 !== authoritySha
      || pass.authority_sha256 !== authoritySha
      || start.tics !== '5250'
      || start.host_quiet !== 'YES'
      || !/^[0-9a-f]{64}$/.test(start.profile_artifact_sha256)
      || start.stream_sha256 !== streamSha
      || pass.profile_sha256 !== sha(profileBytes)
      || !/^[1-9][0-9]*$/.test(rank.samples)
      || !(Number(rank.sampled_ms) > 0)
      || !['YES', 'NO'].includes(rank.sight_bsp_eligible)
      || !['sight_bsp_pct', 'movement_ai_pct', 'mobj_flag_long_pct']
        .every(name => Number.isFinite(Number(rank[name]))
          && Number(rank[name]) >= 0 && Number(rank[name]) <= 100)) {
    throw new Error('profile evidence values are invalid or unbound');
  }
  const positions = [startLine, rankLine, passLine].map(line =>
    text.indexOf(line));
  if (!(positions[0] >= 0
      && positions[0] < positions[1]
      && positions[1] < positions[2])) {
    throw new Error('profile start, rank, and terminal are out of order');
  }
  return {profileSha: pass.profile_sha256, samples: rank.samples};
}

if (process.argv[2] === '--self-test') {
  const bytes = Buffer.from('profile fixture');
  const digest = sha(bytes);
  const start =
    `PMLE_DECPS_NODE_PROFILE|START|authority_sha256=${authoritySha}`
    + `|profile_artifact_sha256=${'ab'.repeat(32)}`
    + `|stream_sha256=${streamSha}|tics=5250|host_quiet=YES`;
  const rank =
    'PMLE_DECPS_NODE_PROFILE_RANK|PASS|samples=100|sampled_ms=1.000'
    + '|sight_bsp_pct=25.000|sight_bsp_eligible=YES'
    + '|movement_ai_pct=20.000|mobj_flag_long_pct=5.000';
  const pass =
    `PMLE_DECPS_NODE_PROFILE|PASS|authority_sha256=${authoritySha}`
    + `|profile_sha256=${digest}`;
  const valid = `${start}\n${rank}\n${pass}\n`;
  validate(valid, bytes);
  for (const invalid of [
    `${rank}\n${start}\n${pass}\n`,
    valid.replace(`profile_sha256=${digest}`, `profile_sha256=${'0'.repeat(64)}`),
    valid.replace('|samples=100|', '|samples=100|samples=1|'),
  ]) {
    let rejected = false;
    try {
      validate(invalid, bytes);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('invalid Node profile evidence was accepted');
  }
  console.log('PASS PMLE-DECPS-NODE-PROFILE-VALIDATOR-SELF-TEST');
} else {
  const [logPath, profilePath] = process.argv.slice(2);
  if (!logPath || !profilePath) {
    throw new Error(
      'usage: validate-decps-node-profile.mjs LOG PROFILE.cpuprofile',
    );
  }
  const result = validate(
    fs.readFileSync(logPath, 'utf8'),
    fs.readFileSync(profilePath),
  );
  console.log(
    `PMLE_DECPS_NODE_PROFILE_VALIDATED|PASS|authority_sha256=${authoritySha}`
    + `|samples=${result.samples}|profile_sha256=${result.profileSha}`,
  );
}
