#!/usr/bin/env node
import fs from 'node:fs';

const [input, startXText, startYText, goalXText, goalYText] = process.argv.slice(2);
if (!input) throw Error('usage: debug-clearance-route.mjs lines.txt|- start-x start-y goal-x goal-y');
const [startX, startY, goalX, goalY] = [startXText, startYText, goalXText, goalYText].map(Number);
if (![startX, startY, goalX, goalY].every(Number.isFinite)) throw Error('finite coordinates required');

const lines = fs.readFileSync(input === '-' ? 0 : input, 'utf8').trim().split('\n').map(row => {
  const [id, flags, left, right, x1, y1, x2, y2, special, tag,
    leftFloor, leftCeiling, rightFloor, rightCeiling] = row.split('|');
  return {id: Number(id), flags: Number(flags), left, right: Number(right),
    x1: Number(x1), y1: Number(y1), x2: Number(x2), y2: Number(y2),
    special: Number(special), tag: Number(tag), leftFloor: Number(leftFloor),
    leftCeiling: Number(leftCeiling), rightFloor: Number(rightFloor),
    rightCeiling: Number(rightCeiling)};
});
// E1M1 has no dynamic floor-height route dependency. Specials remain passable
// candidates because authoring commands can activate them; static portals must
// satisfy the vanilla 24-unit step and 56-unit player-height constraints.
const blockers = lines.filter(line => line.left === '-' || (line.flags & 1) !== 0 ||
  (line.special === 0 && (Math.abs(line.leftFloor - line.rightFloor) > 24 ||
    Math.min(line.leftCeiling, line.rightCeiling) -
      Math.max(line.leftFloor, line.rightFloor) < 56)));
const step = 8, radius = 15.75, binSize = 64;
const minX = Math.floor(Math.min(...lines.flatMap(line => [line.x1, line.x2])) / step) * step;
const maxX = Math.ceil(Math.max(...lines.flatMap(line => [line.x1, line.x2])) / step) * step;
const minY = Math.floor(Math.min(...lines.flatMap(line => [line.y1, line.y2])) / step) * step;
const maxY = Math.ceil(Math.max(...lines.flatMap(line => [line.y1, line.y2])) / step) * step;
const width = Math.round((maxX - minX) / step) + 1;
const height = Math.round((maxY - minY) / step) + 1;
const bins = new Map();
const binKey = (x, y) => `${x},${y}`;
for (const line of blockers) {
  const bx0 = Math.floor((Math.min(line.x1, line.x2) - radius) / binSize);
  const bx1 = Math.floor((Math.max(line.x1, line.x2) + radius) / binSize);
  const by0 = Math.floor((Math.min(line.y1, line.y2) - radius) / binSize);
  const by1 = Math.floor((Math.max(line.y1, line.y2) + radius) / binSize);
  for (let bx = bx0; bx <= bx1; bx++) for (let by = by0; by <= by1; by++) {
    const key = binKey(bx, by); const values = bins.get(key) ?? [];
    values.push(line); bins.set(key, values);
  }
}
function distanceSquared(x, y, line) {
  const dx = line.x2 - line.x1, dy = line.y2 - line.y1;
  const length = dx * dx + dy * dy;
  const t = Math.max(0, Math.min(1, ((x - line.x1) * dx + (y - line.y1) * dy) / length));
  const px = line.x1 + t * dx, py = line.y1 + t * dy;
  return (x - px) ** 2 + (y - py) ** 2;
}
function clear(x, y) {
  const nearby = bins.get(binKey(Math.floor(x / binSize), Math.floor(y / binSize))) ?? [];
  return nearby.every(line => distanceSquared(x, y, line) >= radius * radius);
}
const index = (gx, gy) => gy * width + gx;
const point = value => ({gx: value % width, gy: Math.floor(value / width)});
const snap = (x, y) => ({gx: Math.round((x - minX) / step), gy: Math.round((y - minY) / step)});
const start = snap(startX, startY), goal = snap(goalX, goalY);
const size = width * height, parent = new Int32Array(size).fill(-1);
const seen = new Uint8Array(size), queue = new Int32Array(size);
let head = 0, tail = 0;
const startIndex = index(start.gx, start.gy), goalIndex = index(goal.gx, goal.gy);
queue[tail++] = startIndex; seen[startIndex] = 1;
const directions = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
while (head < tail && !seen[goalIndex]) {
  const current = queue[head++], {gx, gy} = point(current);
  for (const [dx, dy] of directions) {
    const nx = gx + dx, ny = gy + dy;
    if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
    const next = index(nx, ny); if (seen[next]) continue;
    const x = minX + nx * step, y = minY + ny * step;
    const mx = minX + (gx + nx) * step / 2, my = minY + (gy + ny) * step / 2;
    if (!clear(x, y) || !clear(mx, my)) continue;
    seen[next] = 1; parent[next] = current; queue[tail++] = next;
  }
}
if (!seen[goalIndex]) throw Error(`no clearance route after ${head} nodes`);
const route = [];
for (let at = goalIndex; at !== -1; at = parent[at]) {
  const {gx, gy} = point(at); route.push({x: minX + gx * step, y: minY + gy * step});
}
route.reverse();
const waypoints = [route[0]];
let previousDx = null, previousDy = null;
for (let i = 1; i < route.length; i++) {
  const dx = route[i].x - route[i - 1].x, dy = route[i].y - route[i - 1].y;
  if (previousDx !== null && (dx !== previousDx || dy !== previousDy)) waypoints.push(route[i - 1]);
  previousDx = dx; previousDy = dy;
}
waypoints.push(route.at(-1));
process.stdout.write(`${JSON.stringify({step, radius, visited: head, points: route.length, waypoints}, null, 2)}\n`);
