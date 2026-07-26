#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const [nodePath, ociPath] = process.argv.slice(2);
assert.ok(nodePath && ociPath,
  'usage: evaluate-command-stream-digest-binding.mjs NODE_LOG OCI_LOG');

const parse = (file, venue) => {
  const text = fs.readFileSync(file, 'utf8');
  const progress = [...text.matchAll(
    new RegExp(`^PMLE_COMMAND_DIGEST_PROGRESS\\\\|venue=${venue}` +
      String.raw`\|tic=(\d+)\|cumulative_sha256=([0-9a-f]{64})$`, 'gm'))]
    .map(match => ({tic: Number(match[1]), cumulativeSha256: match[2]}));
  const terminal = [...text.matchAll(
    new RegExp(`^PMLE_COMMAND_DIGEST\\\\|PASS\\\\|venue=${venue}` +
      String.raw`\|tics=(\d+)\|authority_sha256=([0-9a-f]{64})` +
      String.raw`\|stream_sha256=([0-9a-f]{64})` +
      String.raw`\|canonical_sha256=([0-9a-f]{64})` +
      String.raw`\|cumulative_sha256=([0-9a-f]{64})$`, 'gm'))];
  assert.equal(terminal.length, 1, `${venue} terminal marker count`);
  const [, tics, authority, stream, canonical, cumulative] = terminal[0];
  return {
    progress,
    terminal: {
      tics: Number(tics), authority, stream, canonical, cumulative
    }
  };
};

const node = parse(nodePath, 'NODE');
const oci = parse(ociPath, 'OCI_ADB');
assert.deepEqual(oci, node, 'OCI digest chain differs from Node');
assert.equal(node.terminal.tics, 5250);
assert.equal(node.progress.length, 10);
assert.deepEqual(node.progress.map(value => value.tic),
  [500,1000,1500,2000,2500,3000,3500,4000,4500,5000]);
console.log(
  `PMLE_COMMAND_DIGEST_BINDING|PASS|tics=${node.terminal.tics}` +
  `|progress_points=${node.progress.length}` +
  `|authority_sha256=${node.terminal.authority}` +
  `|stream_sha256=${node.terminal.stream}` +
  `|canonical_sha256=${node.terminal.canonical}` +
  `|cumulative_sha256=${node.terminal.cumulative}`);
