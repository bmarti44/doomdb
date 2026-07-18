#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {decodeIndexedPng,encodeIndexedPng} from '../evaluator/t4.3/reference.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const container=process.env.DOOMDB_T81_CONTAINER??'doomdb-t81-live-db-1';
const routePath=path.join(root,'artifacts/t8.1-live/route-exit-completion.sql');
const outDir=path.join(root,'artifacts/t8.1-live');

function run(command,args,input=null,maxBuffer=128*1024*1024){
  const result=spawnSync(command,args,{cwd:root,input,encoding:'utf8',maxBuffer});
  if(result.status!==0){
    process.stderr.write(result.stdout??'');process.stderr.write(result.stderr??'');
    process.exit(result.status??1);
  }
  return result.stdout;
}

const password=run('docker',['exec',container,'bash','-lc',
  'printf %s "$(</run/secrets/doom_password)"']).trim();
assert.ok(password.length>0,'database password secret is empty');

let route=fs.readFileSync(routePath,'utf8').replace(/^exit\s*$/m,'');
const capture=`
  for pixel in (
    select column_no,row_no,palette_index,source_kind,source_id,layer_ordinal
    from table(doom_r2_presentation(k_session)) order by column_no,row_no
  ) loop
    dbms_output.put_line('X|' || pixel.column_no || '|' || pixel.row_no || '|' ||
      pixel.palette_index || '|' || pixel.source_kind || '|' || pixel.source_id ||
      '|' || pixel.layer_ordinal);
  end loop;
  rollback;`;
assert.ok(route.includes('  rollback;\nend;'),'route rollback seam is missing');
route=route.replace('  rollback;\nend;',`${capture}\nend;`);
const sql=`connect doom/${password}@//localhost:1521/FREEPDB1
set serveroutput on size unlimited
set feedback off heading off pagesize 0 linesize 32767 trimspool on
${route}
select 'P|'||palette_index||'|'||red||'|'||green||'|'||blue
from doom_palette_texel order by palette_index;
exit
`;
const output=run('docker',['exec','-i',container,'sqlplus','-s','/nolog'],sql);
const lines=output.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
const pixels=lines.filter(line=>line.startsWith('X|')).map(line=>line.split('|'));
const palette=lines.filter(line=>line.startsWith('P|')).map(line=>line.split('|').slice(1).map(Number));
assert.equal(pixels.length,64000,'intermission frame is incomplete');
assert.equal(palette.length,256,'PLAYPAL is incomplete');
for(let index=0;index<pixels.length;index++){
  assert.equal(Number(pixels[index][1]),Math.floor(index/200),'frame column order');
  assert.equal(Number(pixels[index][2]),index%200,'frame row order');
}
const bytes=Buffer.from(pixels.map(row=>Number(row[3])));
const png=encodeIndexedPng(bytes,palette.map(row=>row.slice(1)));
assert.ok(decodeIndexedPng(png).pixels.equals(bytes),'indexed PNG round trip');
const terminal=lines.find(line=>line.startsWith('EXIT_COMPLETION|'));
assert.ok(terminal,'terminal route evidence is missing');
const fields=Object.fromEntries(terminal.split('|').slice(1).map(part=>{
  const at=part.indexOf('=');return [part.slice(0,at),part.slice(at+1)];
}));
const frameSha=crypto.createHash('sha256').update(bytes).digest('hex');
const pngSha=crypto.createHash('sha256').update(png).digest('hex');
const sourceCounts={};
for(const row of pixels)sourceCounts[row[4]]=(sourceCounts[row[4]]??0)+1;
const evidence={schema:1,kind:'doomdb-t8.1-exit-intermission',width:320,height:200,
  order:'column-row',tic:Number(fields.tic),mapStatus:fields.status,mode:fields.mode,
  health:Number(fields.health),kills:Number(fields.kills),items:Number(fields.items),
  secrets:Number(fields.secrets),stateSha:fields.sha,frameSha,pngSha,sourceCounts};
assert.equal(evidence.tic,4118);assert.equal(evidence.mapStatus,'DONE');
assert.equal(evidence.mode,'INTERMISSION');
assert.equal(evidence.stateSha,
  'ac5d82cba9ab641192e91e02dc6856dd9210dc57b4b7fad156bab0b40373b7e6');
fs.writeFileSync(path.join(outDir,'exit-intermission.png'),png);
fs.writeFileSync(path.join(outDir,'exit-intermission.json'),
  `${JSON.stringify(evidence,null,2)}\n`);
process.stdout.write(`PASS T8.1-EXIT-FRAME state=${evidence.stateSha} `+
  `frame=${frameSha} png=${pngSha}\n`);
