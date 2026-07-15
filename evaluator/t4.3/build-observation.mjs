import assert from 'node:assert/strict';
import fs from 'node:fs';
const [prefix,id,x,y,angle,output]=process.argv.slice(2);assert.ok(prefix&&id&&x&&y&&angle&&output,'usage: node build-observation.mjs prefix pose-id x y angle output.json');
const lines=s=>fs.readFileSync(s,'utf8').trim().split(/\r?\n/).filter(Boolean).map(l=>l.trim().split(',').map(Number));
const pixelRows=lines(`${prefix}.pixels.csv`),palRows=lines(`${prefix}.palette.csv`),runRows=lines(`${prefix}.rle.csv`);assert.ok(pixelRows.every(r=>r.length===3&&r.every(Number.isInteger)),'bad pixel CSV');assert.ok(palRows.every(r=>r.length===4&&r.every(Number.isInteger)),'bad palette CSV');assert.ok(runRows.every(r=>r.length===4&&r.every(Number.isInteger)),'bad RLE CSV');
const palette=Array(256);for(const [i,r,g,b] of palRows){assert.equal(palette[i],undefined,'duplicate palette row');palette[i]=[r,g,b];}assert.ok(palette.every(Boolean),'incomplete palette');
const cols=Array.from({length:320},()=>[]);for(const [column,y0,length,cidx] of runRows)cols[column].push([y0,length,cidx]);
const doc={schema:1,pose:{id,x:Number(x),y:Number(y),angle:Number(angle),eyeZ:41},palette,rows:pixelRows.map(([column,row,cidx])=>({column,row,cidx})),cols};fs.writeFileSync(output,JSON.stringify(doc)+'\n');
