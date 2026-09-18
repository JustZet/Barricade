// Verifica fiecare PNG: dimensiuni + procentul de pixeli cu alfa > 0 (continut real).
"use strict";
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

function walk(d) {
  let r = [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) r = r.concat(walk(p)); else r.push(p);
  }
  return r;
}

function decode(buf) {
  const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20);
  const bitDepth = buf[24], colorType = buf[25];
  const chunks = [];
  let off = 8;
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString("ascii", off + 4, off + 8);
    if (type === "IDAT") chunks.push(buf.subarray(off + 8, off + 8 + len));
    off += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(chunks));
  const ch = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
  if (bitDepth !== 8 || !ch) return { w, h, alphaPct: null };
  const bpp = ch;
  const stride = w * bpp;
  const out = Buffer.alloc(h * stride);
  let pos = 0;
  for (let y = 0; y < h; y++) {
    const filter = raw[pos++];
    const line = raw.subarray(pos, pos + stride); pos += stride;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? cur[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0;
      let v = line[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      }
      cur[x] = v & 0xff;
    }
  }
  if (colorType !== 6 && colorType !== 4) return { w, h, alphaPct: 100 };
  const aOff = colorType === 6 ? 3 : 1;
  let nonZero = 0;
  for (let i = aOff; i < out.length; i += bpp) if (out[i] > 0) nonZero++;
  return { w, h, alphaPct: (nonZero / (w * h)) * 100 };
}

const files = walk("out").filter((f) => f.endsWith(".png")).sort();
const rows = [];
for (const f of files) {
  const rel = f.replace(/\\/g, "/").replace(/^out\//, "");
  try {
    const d = decode(fs.readFileSync(f));
    rows.push({ rel, ...d });
  } catch (e) {
    rows.push({ rel, err: e.message });
  }
}
const broken = rows.filter((r) => r.err);
const empty = rows.filter((r) => !r.err && r.alphaPct !== null && r.alphaPct < 0.5);
const thin = rows.filter((r) => !r.err && r.alphaPct !== null && r.alphaPct >= 0.5 && r.alphaPct < 4);

console.log(`Verificate: ${rows.length} PNG`);
console.log(`Erori decodare: ${broken.length}` + (broken.length ? " -> " + broken.map(b => b.rel).join(", ") : ""));
console.log(`GOALE (<0.5% alfa): ${empty.length}` + (empty.length ? " -> " + empty.map(e => `${e.rel} ${e.alphaPct.toFixed(2)}%`).join(", ") : ""));
console.log(`subtiri (0.5-4% alfa, normal la icoane): ${thin.length}` + (thin.length ? " -> " + thin.map(e => `${e.rel} ${e.alphaPct.toFixed(1)}%`).join(", ") : ""));
console.log("\nAcoperire alfa pe categorii:");
const cats = {};
for (const r of rows) {
  if (r.err || r.alphaPct === null) continue;
  const c = r.rel.split("/")[0];
  (cats[c] ||= []).push(r.alphaPct);
}
for (const [c, v] of Object.entries(cats)) {
  const min = Math.min(...v).toFixed(1), max = Math.max(...v).toFixed(1);
  console.log(`  ${c.padEnd(12)} n=${String(v.length).padEnd(3)} alfa ${min}%..${max}%`);
}
