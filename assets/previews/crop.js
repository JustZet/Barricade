// Scoate previzualizarea unui obiect din doua capturi ale ferestrei Roblox Studio.
//
//   node assets/previews/crop.js <pe-negru.png> <pe-alb.png> <iesire.png>
//
// Doua lucruri se intampla aici.
//
// **Decuparea.** Reperul e rama magenta ridicata de `src/world/PreviewRig.luau`:
// patru bare Neon in jurul cadrului. Se cauta chenarul lor si se taie
// interiorul, deci in poza finala nu ramane nicio urma din ele. Nu un dreptunghi
// fix: viewportul Studio isi schimba locul la fiecare panou mutat, iar o taiere
// pe coordonate ar trebui remasurata dupa fiecare. Rama calatoreste cu scena.
//
// **Transparenta.** Aceeasi scena se randeaza de doua ori, o data pe fundal
// negru si o data pe alb. Nimic din cabina nu lumineaza, deci obiectul iese
// identic in amandoua, si singura diferenta vine din cat fundal se vede prin
// fiecare pixel:
//
//   negru = a*Obiect + (1-a)*Kn
//   alb   = a*Obiect + (1-a)*Ka    =>   1-a = (alb - negru) / (Ka - Kn)
//
// Kn si Ka sunt fundalurile **asa cum au iesit din randare**, citite din coltul
// fiecarei imagini, nu culorile cerute. Motorul trece tot prin tonemapping, deci
// o culoare ceruta nu iese niciodata identica din randare; masurata, insa, e
// exacta.
//
// Iese un PNG cu alfa adevarat, muchii moi incluse. De aceea previzualizarea nu
// poarta niciun fundal: se aseaza peste caseta din magazin, care are deja
// culoarea obiectului. Schimbi `CardColor` in `Skins` si nu trebuie randat nimic
// din nou.
"use strict";
const fs = require("fs");
const zlib = require("zlib");

// ---------- PNG ----------

// Decodor minimal: 8 biti pe canal, fara intretesere.
function decode(file) {
  const b = fs.readFileSync(file);
  const w = b.readUInt32BE(16);
  const h = b.readUInt32BE(20);
  const colorType = b[25];
  const ch = colorType === 6 ? 4 : colorType === 2 ? 3 : 1;
  if (b[24] !== 8 || ch === 1) {
    throw new Error("PNG neasteptat: adancime " + b[24] + ", tip " + colorType);
  }

  let off = 8;
  const idat = [];
  while (off < b.length) {
    const len = b.readUInt32BE(off);
    const type = b.toString("ascii", off + 4, off + 8);
    if (type === "IDAT") idat.push(b.subarray(off + 8, off + 8 + len));
    off += 12 + len;
  }

  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * ch;
  const px = Buffer.alloc(h * stride);
  let p = 0;
  for (let y = 0; y < h; y++) {
    const filter = raw[p++];
    const line = raw.subarray(p, p + stride);
    p += stride;
    const cur = px.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? px.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? cur[x - ch] : 0;
      const bb = prev ? prev[x] : 0;
      const c = prev && x >= ch ? prev[x - ch] : 0;
      let v = line[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += bb;
      else if (filter === 3) v += (a + bb) >> 1;
      else if (filter === 4) {
        const pp = a + bb - c;
        const pa = Math.abs(pp - a);
        const pb = Math.abs(pp - bb);
        const pc = Math.abs(pp - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? bb : c;
      }
      cur[x] = v & 255;
    }
  }
  return { w, h, ch, px };
}

const CRC = (() => {
  const t = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const cr = Buffer.alloc(4);
  cr.writeUInt32BE(crc(td));
  return Buffer.concat([len, td, cr]);
}

// Scrie RGBA pe 8 biti: previzualizarile sunt decupate, deci au nevoie de alfa.
function encode(file, w, h, rgba) {
  const stride = w * 4;
  const raw = Buffer.alloc(h * (stride + 1));
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  fs.writeFileSync(
    file,
    Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      chunk("IHDR", ihdr),
      chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
      chunk("IEND", Buffer.alloc(0)),
    ])
  );
}

// ---------- rama ----------

// Pragul e larg: Neon-ul iese mai spalacit spre margini.
function isMark(px, i) {
  return px[i] > 170 && px[i + 1] < 110 && px[i + 2] > 170;
}

function findFrame(img) {
  const { w, h, ch, px } = img;
  let x0 = Infinity;
  let x1 = -1;
  let y0 = Infinity;
  let y1 = -1;
  let seen = 0;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!isMark(px, (y * w + x) * ch)) continue;
      seen++;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  if (seen < 200) throw new Error("rama magenta negasita (" + seen + " pixeli)");

  // Interiorul: de la fiecare latura spre centru, pana se termina magenta.
  const midY = (y0 + y1) >> 1;
  const midX = (x0 + x1) >> 1;
  const mark = (x, y) => isMark(px, (y * w + x) * ch);

  let left = x0;
  while (left < midX && mark(left, midY)) left++;
  let right = x1;
  while (right > midX && mark(right, midY)) right--;
  let top = y0;
  while (top < midY && mark(midX, top)) top++;
  let bottom = y1;
  while (bottom > midY && mark(midX, bottom)) bottom--;

  // Inca un pixel in fiecare parte: muchia ramei lasa o aura roz.
  return { x: left + 1, y: top + 1, w: right - left - 1, h: bottom - top - 1 };
}

// ---------- decupaj ----------

// Taie interiorul ramei si intoarce pixelii ca RGB, plus marimea.
function cutout(file) {
  const img = decode(file);
  const box = findFrame(img);
  if (box.w < 40 || box.h < 40) {
    throw new Error(file + ": decupaj prea mic, " + box.w + "x" + box.h);
  }

  const rgb = Buffer.alloc(box.w * box.h * 3);
  for (let y = 0; y < box.h; y++) {
    for (let x = 0; x < box.w; x++) {
      const si = ((box.y + y) * img.w + (box.x + x)) * img.ch;
      const di = (y * box.w + x) * 3;
      rgb[di] = img.px[si];
      rgb[di + 1] = img.px[si + 1];
      rgb[di + 2] = img.px[si + 2];
    }
  }
  return { w: box.w, h: box.h, rgb };
}

// Fundalul asa cum a iesit: media coltului din stanga sus, unde nu ajunge
// niciodata obiectul. Media, si nu un pixel, ca sa nu atarne un pixel prost.
function cornerColor(img) {
  const n = 12;
  const sum = [0, 0, 0];
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const i = (y * img.w + x) * 3;
      sum[0] += img.rgb[i];
      sum[1] += img.rgb[i + 1];
      sum[2] += img.rgb[i + 2];
    }
  }
  return sum.map((v) => v / (n * n));
}

// ---------- main ----------

const [, , onBlack, onWhite, output] = process.argv;
if (!onBlack || !onWhite || !output) {
  console.error("folosire: node assets/previews/crop.js <pe-negru.png> <pe-alb.png> <iesire.png>");
  process.exit(2);
}

const dark = cutout(onBlack);
const light = cutout(onWhite);
if (dark.w !== light.w || dark.h !== light.h) {
  throw new Error("cele doua capturi nu se suprapun: " + dark.w + "x" + dark.h + " fata de " + light.w + "x" + light.h);
}

const Kn = cornerColor(dark);
const Ka = cornerColor(light);
const spread = [0, 1, 2].map((c) => Ka[c] - Kn[c]);
if (Math.min(...spread) < 40) {
  throw new Error("fundalurile sunt prea apropiate; s-a randat de doua ori aceeasi culoare?");
}

// Transparenta se citeste pe canalul cu cea mai mare diferenta intre fundaluri:
// acolo raportul e cel mai putin atins de zgomotul randarii.
let best = 0;
for (let c = 1; c < 3; c++) if (spread[c] > spread[best]) best = c;

const out = Buffer.alloc(dark.w * dark.h * 4);
let opaque = 0;
for (let p = 0; p < dark.w * dark.h; p++) {
  const i = p * 3;
  const clear = (light.rgb[i + best] - dark.rgb[i + best]) / spread[best];
  const alpha = Math.min(1, Math.max(0, 1 - clear));

  const di = p * 4;
  if (alpha < 0.004) {
    out[di] = 0;
    out[di + 1] = 0;
    out[di + 2] = 0;
    out[di + 3] = 0;
    continue;
  }
  if (alpha > 0.996) opaque++;

  // Culoarea obiectului, scoasa de sub fundalul negru amestecat in ea.
  for (let c = 0; c < 3; c++) {
    const v = (dark.rgb[i + c] - (1 - alpha) * Kn[c]) / alpha;
    out[di + c] = Math.min(255, Math.max(0, Math.round(v)));
  }
  out[di + 3] = Math.round(alpha * 255);
}

encode(output, dark.w, dark.h, out);

const filled = ((100 * opaque) / (dark.w * dark.h)).toFixed(1);
console.log(
  output +
    "  " + dark.w + "x" + dark.h +
    "  raport " + (dark.w / dark.h).toFixed(3) + " (caseta cere 1.582)" +
    "  obiect " + filled + "%"
);
