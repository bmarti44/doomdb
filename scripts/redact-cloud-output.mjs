#!/usr/bin/env node
import process from 'node:process';

const secretNames = [
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_SESSION_TOKEN',
  'ADB_PASSWORD',
  'ADB_WALLET_PASSWORD',
  'ADB_CLIENT_SECRET',
];

let input = '';
for await (const chunk of process.stdin) input += chunk;

for (const name of secretNames) {
  const value = process.env[name];
  if (value) input = input.split(value).join('<redacted>');
}

const names = secretNames.join('|');
input = input.replace(
  new RegExp(`((?:"|')?(?:${names})(?:"|')?\\s*[:=]\\s*)("[^"]*"|'[^']*'|[^\\s,]+)`, 'gi'),
  (_match, prefix, value) => `${prefix}${value.startsWith('"') ? '"<redacted>"' : value.startsWith("'") ? "'<redacted>'" : '<redacted>'}`,
);
input = input.replace(/(connect\s+[^/\s]+\/)[^@\s]+(@)/gi, '$1<redacted>$2');

process.stdout.write(input);
