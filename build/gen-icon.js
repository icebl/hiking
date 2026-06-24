// 纯 Node（内置 zlib，无第三方依赖）生成 1024×1024 App 图标 PNG。
// 设计：品牌绿渐变底 + 双白色山峰 + 橙色徒步路径（虚线）。RGB 无 alpha，避免图标透明问题。
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const N = 1024;
const buf = Buffer.alloc(N * N * 3);

function set(x, y, r, g, b) {
  if (x < 0 || y < 0 || x >= N || y >= N) return;
  const i = (y * N + x) * 3;
  buf[i] = r; buf[i + 1] = g; buf[i + 2] = b;
}
function lerp(a, b, t) { return Math.round(a + (b - a) * t); }

// 1) 背景：竖向绿色渐变 #1F9D55 → #15803D（顶→底）
const top = [0x1F, 0x9D, 0x55], bot = [0x12, 0x6E, 0x3E];
for (let y = 0; y < N; y++) {
  const t = y / N;
  const r = lerp(top[0], bot[0], t), g = lerp(top[1], bot[1], t), b = lerp(top[2], bot[2], t);
  for (let x = 0; x < N; x++) set(x, y, r, g, b);
}

// 三角形填充（重心法）
function sign(ax, ay, bx, by, cx, cy) { return (ax - cx) * (by - cy) - (bx - cx) * (ay - cy); }
function fillTri(p1, p2, p3, col) {
  const minX = Math.max(0, Math.floor(Math.min(p1[0], p2[0], p3[0])));
  const maxX = Math.min(N - 1, Math.ceil(Math.max(p1[0], p2[0], p3[0])));
  const minY = Math.max(0, Math.floor(Math.min(p1[1], p2[1], p3[1])));
  const maxY = Math.min(N - 1, Math.ceil(Math.max(p1[1], p2[1], p3[1])));
  for (let y = minY; y <= maxY; y++) {
    for (let x = minX; x <= maxX; x++) {
      const d1 = sign(x, y, p1[0], p1[1], p2[0], p2[1]);
      const d2 = sign(x, y, p2[0], p2[1], p3[0], p3[1]);
      const d3 = sign(x, y, p3[0], p3[1], p1[0], p1[1]);
      const neg = (d1 < 0) || (d2 < 0) || (d3 < 0);
      const pos = (d1 > 0) || (d2 > 0) || (d3 > 0);
      if (!(neg && pos)) set(x, y, col[0], col[1], col[2]);
    }
  }
}

// 2) 山峰：后山（浅）+ 前山主峰（白），放大居中
const backMtn = [0xCF, 0xEA, 0xD9];
const frontMtn = [0xFF, 0xFF, 0xFF];
fillTri([90, 870], [620, 870], [330, 470], backMtn);    // 后山（左，浅）
fillTri([150, 870], [874, 870], [512, 280], frontMtn);  // 前山主峰（白，居中）

// 3) 徒步路径：橙色虚线"之"字形，沿白色山体上行至峰顶
const trail = [[440, 855], [610, 770], [430, 690], [620, 610], [450, 520], [575, 440], [512, 330]];
const orange = [0xF2, 0x73, 0x0D];
function distSeg(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay;
  const l2 = dx * dx + dy * dy;
  let t = l2 ? ((px - ax) * dx + (py - ay) * dy) / l2 : 0;
  t = Math.max(0, Math.min(1, t));
  const cx = ax + t * dx, cy = ay + t * dy;
  return { d: Math.hypot(px - cx, py - cy), s: t };
}
// 预计算每段起点累计长度，做虚线
const segLen = [], cum = [0];
for (let i = 0; i < trail.length - 1; i++) {
  const L = Math.hypot(trail[i + 1][0] - trail[i][0], trail[i + 1][1] - trail[i][1]);
  segLen.push(L); cum.push(cum[i] + L);
}
const half = 16, dash = 54; // 线宽/虚线节距
for (let y = 300; y <= 880; y++) {
  for (let x = 150; x <= 880; x++) {
    let best = 1e9, bestArc = 0;
    for (let i = 0; i < trail.length - 1; i++) {
      const a = trail[i], b = trail[i + 1];
      const r = distSeg(x, y, a[0], a[1], b[0], b[1]);
      if (r.d < best) { best = r.d; bestArc = cum[i] + r.s * segLen[i]; }
    }
    if (best <= half && Math.floor(bestArc / dash) % 2 === 0) set(x, y, orange[0], orange[1], orange[2]);
  }
}

// ---- PNG 编码（RGB, 8bit, color type 2）----
function crc32(b) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < b.length; n++) {
    c = (crc ^ b[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}
const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(N, 0); ihdr.writeUInt32BE(N, 4);
ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
// 原始扫描线：每行前置 filter 0
const raw = Buffer.alloc(N * (1 + N * 3));
for (let y = 0; y < N; y++) {
  raw[y * (1 + N * 3)] = 0;
  buf.copy(raw, y * (1 + N * 3) + 1, y * N * 3, (y + 1) * N * 3);
}
const idat = zlib.deflateSync(raw, { level: 9 });
const png = Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
const out = path.join(__dirname, '..', 'front', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png');
fs.writeFileSync(out, png);
console.log('wrote', out, png.length, 'bytes');
