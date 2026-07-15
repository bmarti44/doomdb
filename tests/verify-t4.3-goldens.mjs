import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..'),golden=JSON.parse(fs.readFileSync(path.join(root,'goldens/t4.3-visible.json'))),summary=JSON.parse(fs.readFileSync(path.join(root,'artifacts/t4.3-review/review-summary.json')));
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const integrity=JSON.parse(fs.readFileSync(path.join(root,'goldens/integrity-T4.3.json')));
assert.equal(sha(path.join(root,integrity.evaluatorManifest.path)),integrity.evaluatorManifest.sha256);
for(const [file,expected] of Object.entries(integrity.files))assert.equal(sha(path.join(root,file)),expected,`${file} integrity`);
assert.equal(golden.status,'HUMAN_REVIEWED_APPROVED');
assert.equal(golden.sourceEvaluatorManifestSha256,'38927540dc430ff6d3476738f122577ec15bf4ab104628282a4f19a7e7c5977a');
assert.equal(golden.poses.length,3);assert.deepEqual(golden.poses.map(p=>p.id),['spawn-east','spawn-north','spawn-south']);
for(const pose of golden.poses){
  const observed=summary.observed.find(x=>x.id===pose.id);assert.ok(observed,`missing observation ${pose.id}`);
  for(const field of ['frameSha256','rgbaSha256','pngSha256','pngBytes'])assert.equal(observed[field],pose[field],`${pose.id} ${field}`);
  const png=path.join(root,'goldens/t4.3',`${pose.id}.png`);assert.equal(fs.statSync(png).size,pose.pngBytes);assert.equal(sha(png),pose.pngSha256);
  assert.ok(pose.review.length>=100,`${pose.id} visual review is not concrete`);
}
assert.equal(new Set(golden.poses.map(p=>p.frameSha256)).size,3);assert.equal(new Set(golden.poses.map(p=>p.pngSha256)).size,3);
process.stdout.write('PASS T4.3-VISIBLE-GOLDENS (3/3 human-reviewed database PNGs)\n');
