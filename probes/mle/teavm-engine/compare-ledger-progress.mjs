#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const progressPattern=
  /^PMLE_LEDGER_PROGRESS\|tic=([0-9]+)\|cumulative_sha256=([0-9a-f]{64})$/;
const terminalPattern=
  /^PMLE_TEAVM_LEDGER_DIFFERENTIAL\|PASS\|tics=13272\|deep_every=1\|route_runs=1152\|vector_runs=1246\|cumulative_sha256=([0-9a-f]{64})$/;

function parse(file,text) {
  const progress=new Map();
  for(const line of text.split(/\r?\n/)) {
    if(!line.startsWith('PMLE_LEDGER_PROGRESS|'))continue;
    const match=line.match(progressPattern);
    assert.ok(match,`${file}: malformed progress marker`);
    const tic=Number(match[1]);
    assert.ok(!progress.has(tic),`${file}: duplicate progress tic ${tic}`);
    progress.set(tic,match[2]);
  }
  const terminalLines=text.split(/\r?\n/)
    .filter(line=>line.startsWith('PMLE_TEAVM_LEDGER_DIFFERENTIAL|'));
  assert.ok(terminalLines.length<=1,`${file}: duplicate terminal marker`);
  let terminal=null;
  if(terminalLines.length===1) {
    const match=terminalLines[0].match(terminalPattern);
    assert.ok(match,`${file}: non-PASS or malformed terminal marker`);
    terminal=match[1];
  }
  return {file,progress,terminal};
}

function compare(candidate,baselines) {
  const tics=[...candidate.progress.keys()].sort((left,right)=>left-right);
  assert.ok(tics.length>0,`${candidate.file}: no progress markers`);
  for(let index=0;index<tics.length;index+=1) {
    const expected=(index+1)*100;
    const acceptedFinal=index===132&&tics[index]===13272;
    assert.ok(tics[index]===expected||acceptedFinal,
      `${candidate.file}: progress sequence gap`);
  }
  if(candidate.terminal!==null) {
    assert.equal(tics.at(-1),13272,
      `${candidate.file}: terminal marker precedes final progress`);
    assert.equal(candidate.progress.get(13272),candidate.terminal,
      `${candidate.file}: final progress and terminal digest differ`);
  }
  for(const baseline of baselines) {
    for(const tic of tics) {
      assert.equal(candidate.progress.get(tic),baseline.progress.get(tic),
        `${path.basename(baseline.file)}: digest mismatch at tic ${tic}`);
    }
    if(candidate.terminal!==null) {
      assert.equal(candidate.terminal,baseline.terminal,
        `${path.basename(baseline.file)}: terminal digest mismatch`);
    }
  }
  const through=tics.at(-1);
  return {classification:candidate.terminal===null?'PREFIX':'TERMINAL',
    markers:tics.length,through,digest:candidate.progress.get(through),
    terminal:candidate.terminal};
}

function selfTest() {
  const digestA='a'.repeat(64),digestB='b'.repeat(64);
  const terminal='c'.repeat(64);
  const prefix=`PMLE_LEDGER_PROGRESS|tic=100|cumulative_sha256=${digestA}\n`
    + `PMLE_LEDGER_PROGRESS|tic=200|cumulative_sha256=${digestB}\n`;
  const terminalLine=
    'PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1'
      + `|route_runs=1152|vector_runs=1246|cumulative_sha256=${terminal}\n`;
  const completePrefix=Array.from({length:132},(_,index)=>
    `PMLE_LEDGER_PROGRESS|tic=${(index+1)*100}`
      + `|cumulative_sha256=${digestA}\n`).join('')
    + `PMLE_LEDGER_PROGRESS|tic=13272|cumulative_sha256=${terminal}\n`;
  const result=compare(
    parse('candidate',completePrefix+terminalLine),
    [parse('baseline',completePrefix+terminalLine)]);
  assert.deepEqual(result,{classification:'TERMINAL',markers:133,through:13272,
    digest:terminal,terminal});
  for(const mutation of [
    prefix.replace('tic=200','tic=300'),
    prefix.replace(digestB,digestA),
    prefix+`PMLE_LEDGER_PROGRESS|tic=200|cumulative_sha256=${digestB}\n`,
    prefix.replace('cumulative_sha256','cumulative_sha'),
  ]) {
    assert.throws(()=>compare(parse('mutant',mutation),
      [parse('baseline',prefix)]));
  }
  assert.throws(()=>compare(parse('candidate',prefix+terminalLine),
    [parse('baseline',prefix+terminalLine.replace(terminal,digestA))]));
  assert.throws(()=>compare(parse('candidate',completePrefix+terminalLine
    .replace(terminal,digestA)),[parse('baseline',completePrefix+terminalLine)]));
  assert.throws(()=>compare(parse('candidate',prefix+terminalLine),
    [parse('baseline',prefix+terminalLine)]));
  process.stdout.write('PMLE_LEDGER_PROGRESS_AUDIT_SELFTEST|PASS|mutations=7\n');
}

const inputs=process.argv.slice(2);
if(inputs.length===1&&inputs[0]==='--self-test') {
  selfTest();
  process.exit(0);
}
assert.ok(inputs.length>=2,
  'usage: compare-ledger-progress.mjs CANDIDATE_LOG BASELINE_LOG [...]');
const [candidate,...baselines]=inputs.map(file=>
  parse(file,fs.readFileSync(file,'utf8')));
const result=compare(candidate,baselines);
process.stdout.write(
  `PMLE_LEDGER_PROGRESS_AUDIT|PASS|classification=${result.classification}`
    + `|markers=${result.markers}|through_tic=${result.through}`
    + `|progress_sha256=${result.digest}|baselines=${baselines.length}`
    + (result.terminal===null?'':`|terminal_sha256=${result.terminal}`)
    + '\n');
