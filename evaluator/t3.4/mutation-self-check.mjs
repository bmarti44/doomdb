import assert from 'node:assert/strict';
import fs from 'node:fs';
import {cellForPoint,decodeBlockmapBytes,decodeRejectBytes,graphEdges} from './reference.mjs';

const fixture=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url),'utf8'));
const specs=JSON.parse(fs.readFileSync(new URL('./mutation-specs.json',import.meta.url),'utf8')).mutations;
const block=decodeBlockmapBytes(Buffer.from(fixture.blockmapHex,'hex'));
const reject=decodeRejectBytes(Buffer.from(fixture.rejectHex,'hex'),fixture.rejectSectorCount);
const edges=graphEdges(fixture.graph.lines,fixture.graph.sides,fixture.graph.sectors);
const killed=new Map();
const kill=(id,value,message)=>{assert.ok(value,message);killed.set(id,true);};

kill('T34-M01-UNSIGNED-ORIGIN',Buffer.from(fixture.blockmapHex,'hex').readUInt16LE(0)!==block.originX,'unsigned origin survived');
kill('T34-M02-BYTE-OFFSET',Buffer.from(fixture.blockmapHex,'hex').readUInt16LE(10*2)===0&&Buffer.from(fixture.blockmapHex,'hex').readUInt16LE(10)!==0,'byte offset survived');
kill('T34-M03-KEEP-FRAMING',block.memberships.length+block.cells.length*2!==block.memberships.length,'framing membership survived');
kill('T34-M04-DROP-SHARED-CELLS',new Set(block.cells.map(c=>c.listWordOffset)).size!==block.cells.length,'shared-cell dedupe survived');
kill('T34-M05-SORT-LINES',block.cells[0].lines.toReversed().join(',')!==block.cells[0].lines.join(','),'line reorder survived');
const boundary=fixture.coordinateProbes[0];
kill('T34-M06-TRUNCATE-NEGATIVE',Math.trunc((boundary.x-block.originX)/128)!==cellForPoint(boundary.x,boundary.y,block).blockX,'negative truncation survived');
const bytes=Buffer.from(fixture.rejectHex,'hex'), msb=[]; for(let i=0;i<16;i++)msb.push((bytes[i>>3]>>(7-(i&7)))&1);
kill('T34-M07-REJECT-MSB',msb.join(',')!==reject.map(b=>b.rejected).join(','),'MSB mutation survived');
const transposed=reject.map(b=>reject[b.targetSectorId*fixture.rejectSectorCount+b.sourceSectorId].rejected);
kill('T34-M08-REJECT-COLUMN-MAJOR',transposed.join(',')!==reject.map(b=>b.rejected).join(','),'column-major mutation survived');
kill('T34-M09-ONLY-SET-BITS',reject.filter(b=>b.rejected).length!==reject.length,'sparse reject survived');
kill('T34-M10-ONE-WAY-EDGE',edges.filter(e=>e.edgeId%2===0).length!==edges.length,'one-way graph survived');
kill('T34-M11-INCLUDE-ONE-SIDED',fixture.graph.lines.filter(l=>l.left===65535).length===1&&!edges.some(e=>e.linedefId===3),'one-sided graph survived');
kill('T34-M12-INCLUDE-CLOSED',!edges.some(e=>e.linedefId===2),'closed graph survived');
kill('T34-M13-DROP-SOUNDBLOCK',edges.some(e=>e.soundBlock===1),'sound flag loss survived');
kill('T34-M14-COLLAPSE-MULTIEDGES',edges.filter(e=>e.sourceSectorId===0&&e.targetSectorId===1).length===2,'parallel-edge collapse survived');
const audit=fs.readFileSync(new URL('./source-audit.mjs',import.meta.url),'utf8').toUpperCase();
kill('T34-M15-PLSQL-DECODER',audit.includes('PROCEDURAL BYTE/GRAPH TRAVERSAL')&&audit.includes('DYNAMIC SQL'),'procedural guard absent');
kill('T34-M16-FAKE-GRAPH-VIEW',audit.includes('CREATE PROPERTY GRAPH')&&audit.includes('GRAPH_TABLE'),'property graph guard absent');
kill('T34-M17-FIXTURE-LOOKUP',audit.includes('ANTI-REWARD-HACKING')&&audit.includes('PINNED EXPECTED LITERAL'),'fixture guard absent');

assert.deepEqual([...killed.keys()],specs.map(s=>s.id),'mutation witnesses do not match stable specifications');
process.stdout.write(`PASS T3.4-EVAL-MUTATION-SELF-CHECK (${killed.size}/${specs.length} isolated mutations killed)\n`);
