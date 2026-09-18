// Generator de asseturi Barricade -> PNG transparent 1x/2x, randat cu Chrome headless.
// Sursa de adevar: "Barricade Design System.dc.html" (sectiunile 4, 6, 8, 16, 17).
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile } = require("child_process");

const CHROME = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const ROOT = __dirname;
const OUT = path.join(ROOT, "out");
const WORK = path.join(ROOT, ".work");
const SRC = path.join(ROOT, "barricade-design-system.html");

for (const d of [OUT, WORK]) fs.mkdirSync(d, { recursive: true });

// ---------- tokens de culoare (sectiunea 02) ----------
const C = {
  wood100: "#EFD9AE", wood300: "#D9A566", wood500: "#B5763C", wood700: "#7A4A22",
  ink900: "#3B2412", paper50: "#FBF3E2", paper200: "#EBD9BC",
  woodTop: "#C68B4E", woodBot: "#A96C36", woodEdge: "#5A3418",
  highlight: "#FFD666", iconStroke: "#FFF8E6",
};
const PLAYERS = {
  blue:   { top: "#4A99E0", bot: "#2266B0", shape: "circle" },
  red:    { top: "#E4635E", bot: "#C2352F", shape: "diamond" },
  green:  { top: "#5CC24A", bot: "#41972F", shape: "square" },
  yellow: { top: "#F2C34A", bot: "#D19A1C", shape: "triangle" },
};

const GRAIN = "repeating-linear-gradient(92deg, rgba(0,0,0,.05) 0 3px, rgba(0,0,0,0) 3px 11px)";

// ---------- helperi ----------
// Marca de forma, la 34% din discul interior (spec sheet, sectiunea 17).
function shapeMark(kind, inner) {
  const s = Math.round(inner * 0.34);
  const p = C.paper50;
  if (kind === "circle") return `<div style="width:${s}px;height:${s}px;border-radius:50%;background:${p}"></div>`;
  if (kind === "square") return `<div style="width:${s}px;height:${s}px;border-radius:4px;background:${p}"></div>`;
  if (kind === "diamond") return `<div style="width:${s}px;height:${s}px;background:${p};transform:rotate(45deg);border-radius:3px"></div>`;
  // triunghi: latime = s, inaltime ~ s*0.85 (pastreaza proportia din design)
  const half = Math.round(s / 2), h = Math.round(s * 0.85);
  return `<div style="width:0;height:0;border-left:${half}px solid transparent;border-right:${half}px solid transparent;border-bottom:${h}px solid ${p}"></div>`;
}

// Placa 9-slice: muchia dura de jos e INSET ca sa intre in bitmap si sa fie feliabila.
function plate({ size, radius, edge, top, bot, edgeColor, grain = true, inset = "" }) {
  const bg = (grain ? GRAIN + ", " : "") + `linear-gradient(${top},${bot})`;
  return `<div style="width:${size}px;height:${size}px;border-radius:${radius}px;background:${bg};
    box-shadow:inset 0 3px 0 rgba(255,255,255,.4), inset 0 -${edge}px 0 ${edgeColor}${inset}"></div>`;
}

// ---------- definirea asseturilor ----------
const assets = [];
const add = (name, w, h, html, slice) => assets.push({ name, w, h, html, slice });

// --- A. Placi 9-slice (fara text ars, conform sectiunii 16) ---
add("plate/button_l", 96, 96, plate({ size: 96, radius: 18, edge: 8, top: C.woodTop, bot: C.woodBot, edgeColor: C.woodEdge }), 18);
add("plate/button_m", 96, 96, plate({ size: 96, radius: 14, edge: 6, top: C.woodTop, bot: C.woodBot, edgeColor: C.woodEdge }), 18);
add("plate/button_s", 96, 96, plate({ size: 96, radius: 11, edge: 4, top: C.woodTop, bot: C.woodBot, edgeColor: C.woodEdge }), 18);
add("plate/button_disabled", 96, 96, plate({ size: 96, radius: 14, edge: 6, top: "#CFC0A4", bot: "#BCAB8C", edgeColor: "#A08A6A" }), 18);
add("plate/button_green", 96, 96, plate({ size: 96, radius: 14, edge: 6, top: "#5CC24A", bot: "#41972F", edgeColor: "#2A6520" }), 18);
// Panou: rama 10px wood/500 + insert paper r=14 (sectiunea 17)
add("plate/panel", 120, 120, `<div style="width:120px;height:120px;border-radius:20px;background:linear-gradient(${C.wood300},${C.wood500});
  box-shadow:inset 0 3px 0 rgba(255,255,255,.35), inset 0 -6px 0 ${C.wood700};padding:10px;box-sizing:border-box">
  <div style="width:100%;height:100%;border-radius:14px;background:linear-gradient(${C.paper50},${C.paper200});
    box-shadow:inset 0 0 0 1px rgba(122,74,34,.18)"></div></div>`, 24);
// Card de hartie r=12 (sectiunea 04)
add("plate/card_paper", 96, 96, `<div style="width:96px;height:96px;border-radius:12px;
  background:radial-gradient(120% 90% at 20% 0%, rgba(255,255,255,.7), rgba(0,0,0,0)), ${C.paper50};
  box-shadow:inset 0 0 0 1px rgba(122,74,34,.18)"></div>`, 14);

// Variante fara grain: la 9-slice centrul se intinde, iar un grain copt
// se manjeste si lasa cusatura vizibila. Grain-ul se aplica separat, tileabil.
add("plate/flat_l", 96, 96, plate({ size: 96, radius: 18, edge: 8, top: C.woodTop, bot: C.woodBot, edgeColor: C.woodEdge, grain: false }), 18);
add("plate/flat_m", 96, 96, plate({ size: 96, radius: 14, edge: 6, top: C.woodTop, bot: C.woodBot, edgeColor: C.woodEdge, grain: false }), 18);
add("plate/flat_s", 96, 96, plate({ size: 96, radius: 11, edge: 4, top: C.woodTop, bot: C.woodBot, edgeColor: C.woodEdge, grain: false }), 18);
add("plate/flat_disabled", 96, 96, plate({ size: 96, radius: 14, edge: 6, top: "#CFC0A4", bot: "#BCAB8C", edgeColor: "#A08A6A", grain: false }), 18);
add("plate/flat_green", 96, 96, plate({ size: 96, radius: 14, edge: 6, top: "#5CC24A", bot: "#41972F", edgeColor: "#2A6520", grain: false }), 18);

// --- B. Token-uri jucator: 96px tabla (spec: rim 7px + inel hartie 4px) ---
const TOK = 96, RIM = 7, RING = 4;
const INNER = TOK - 2 * RIM - 2 * RING;
function token(rimTop, rimBot, faceTop, faceBot, shape, mark) {
  return `<div style="width:${TOK}px;height:${TOK}px;border-radius:50%;box-sizing:border-box;
    background:linear-gradient(${rimTop},${rimBot});padding:${RIM}px">
    <div style="width:100%;height:100%;border-radius:50%;background:${C.paper50};padding:${RING}px;box-sizing:border-box">
      <div style="width:100%;height:100%;border-radius:50%;background:linear-gradient(${faceTop},${faceBot});
        display:grid;place-items:center;box-shadow:inset 0 3px 0 rgba(255,255,255,.45)">
        ${mark !== undefined ? mark : shapeMark(shape, INNER)}
      </div></div></div>`;
}
for (const [name, p] of Object.entries(PLAYERS)) {
  add(`token/${name}`, TOK, TOK, token(C.wood300, C.woodBot, p.top, p.bot, p.shape));
  // Tura activa: rim auriu (sectiunea 06)
  add(`token/${name}_active`, TOK, TOK, token("#FFE08A", "#E8B32B", p.top, p.bot, p.shape));
}
const xMark = `<svg width="${Math.round(INNER * 0.34)}" height="${Math.round(INNER * 0.34)}" viewBox="0 0 24 24" stroke="${C.paper50}" stroke-width="3.4" stroke-linecap="round"><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></svg>`;
add("token/eliminated", TOK, TOK, token("#C3B49B", "#A2937C", "#8C9AA8", "#6B7885", null, xMark));
// Pip coroana pentru starea victory
add("token/crown_pip", 28, 20, `<div style="width:0;height:0;border-left:14px solid transparent;border-right:14px solid transparent;border-bottom:20px solid #E8B32B"></div>`);

// --- C. Baricade (spec: 2 celule lungime x 0.4 grosime, r = jumatate din grosime) ---
add("barricade/horizontal", 130, 24, `<div style="width:130px;height:24px;border-radius:12px;
  background:repeating-linear-gradient(90deg, rgba(0,0,0,.05) 0 3px, rgba(0,0,0,0) 3px 10px), linear-gradient(${C.woodTop},#9C6330);
  box-shadow:inset 0 3px 0 rgba(255,255,255,.4), inset 0 -6px 0 ${C.woodEdge}"></div>`, [12, 0]);
add("barricade/vertical", 24, 130, `<div style="width:24px;height:130px;border-radius:12px;
  background:repeating-linear-gradient(0deg, rgba(0,0,0,.05) 0 3px, rgba(0,0,0,0) 3px 10px), linear-gradient(90deg,${C.woodTop},#9C6330);
  box-shadow:inset 3px 0 0 rgba(255,255,255,.35), inset -6px 0 0 ${C.woodEdge}"></div>`, [0, 12]);
add("barricade/valid", 136, 30, `<div style="width:130px;height:24px;border-radius:12px;margin:3px;
  background:linear-gradient(#5CC24A,#41972F);box-shadow:0 0 0 3px ${C.iconStroke}, inset 0 -5px 0 #2A6520"></div>`);
add("barricade/invalid", 136, 30, `<div style="width:130px;height:24px;border-radius:12px;margin:3px;
  background:repeating-linear-gradient(45deg,#C2352F 0 6px,#8C1F1A 6px 12px);box-shadow:0 0 0 3px ${C.iconStroke}"></div>`);

// --- D. Textura de lemn tileabila (sectiunea 16: un 256px reutilizat la 3 nuante) ---
// Perioada 8px => 256/8 = 32 repetitii exacte, deci imbinare fara cusatura.
add("texture/wood_grain_256", 256, 256, `<div style="width:256px;height:256px;
  background:repeating-linear-gradient(90deg, rgba(0,0,0,.28) 0 3px, rgba(0,0,0,0) 3px 8px)"></div>`);

// --- E. Icoane: extrase automat din sectiunea 08 a design system-ului ---
const srcFull = fs.readFileSync(SRC, "utf8");
// Decupam strict sectiunea 08, altfel prima potrivire porneste de la un <svg> anterior
// din document si inghite markup strain (lazy minimizeaza lungimea, nu pozitia de start).
const secStart = srcFull.indexOf("<!-- ======== 8. ICONS ======== -->");
const secEnd = srcFull.indexOf("<!-- ======== 9.", secStart);
if (secStart === -1 || secEnd === -1) throw new Error("Nu am gasit sectiunea 08 (ICONS)");
const src = srcFull.slice(secStart, secEnd);
// (?:(?!<svg)[\s\S])*? => continutul nu poate traversa un alt <svg>
const iconRe = /(<svg(?:(?!<svg)[\s\S])*?<\/svg>)<\/div><div style="font-size:10px;font-weight:800;color:#B2946E">([^<]+)</g;
let m, iconCount = 0;
const seen = new Set();
while ((m = iconRe.exec(src)) !== null) {
  let svg = m[1];
  const label = m[2].trim().toLowerCase().replace(/[^a-z0-9]+/g, "_");
  if (seen.has(label)) continue;
  seen.add(label);
  // Randam la 64px, pe fundal transparent, ca sa poata fi tintate in Roblox.
  svg = svg.replace(/width="\d+(\.\d+)?"/, 'width="64"').replace(/height="\d+(\.\d+)?"/, 'height="64"');
  add(`icon/${label}`, 64, 64, svg);
  iconCount++;
}

// ---------- randare ----------
function pageFor(a) {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;background:transparent}
    body{width:${a.w}px;height:${a.h}px;display:grid;place-items:center;overflow:hidden}
  </style></head><body>${a.html}</body></html>`;
}

function render(a, scale) {
  return new Promise((resolve) => {
    const safe = a.name.replace(/\//g, "__");
    const htmlPath = path.join(WORK, `${safe}.html`);
    fs.writeFileSync(htmlPath, pageFor(a));
    const outPath = path.join(OUT, `${a.name}${scale === 2 ? "@2x" : ""}.png`);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    const profile = fs.mkdtempSync(path.join(os.tmpdir(), "brc-"));
    const args = [
      "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
      "--no-default-browser-check", "--disable-extensions",
      `--user-data-dir=${profile}`,
      "--default-background-color=00000000",
      `--force-device-scale-factor=${scale}`,
      `--window-size=${a.w},${a.h}`,
      `--screenshot=${outPath}`,
      "file:///" + htmlPath.replace(/\\/g, "/"),
    ];
    execFile(CHROME, args, { timeout: 60000 }, (err) => {
      try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
      resolve({ name: a.name, scale, outPath, ok: !err && fs.existsSync(outPath) });
    });
  });
}

// Manifest: numele assetului -> fisiere + inset de 9-slice, pentru upload si Assets.luau.
function writeManifest() {
  const manifest = assets.map((a) => ({
    name: a.name,
    w: a.w, h: a.h,
    slice: a.slice ?? null,
    files: { "1x": `out/${a.name}.png`, "2x": `out/${a.name}@2x.png` },
  }));
  fs.writeFileSync(path.join(ROOT, "manifest.json"), JSON.stringify(manifest, null, 2));
  console.log(`Manifest scris: ${manifest.length} intrari`);
}

(async () => {
  const jobs = [];
  for (const a of assets) for (const s of [1, 2]) jobs.push([a, s]);
  console.log(`Randez ${assets.length} asseturi x 2 scale = ${jobs.length} PNG-uri (${iconCount} icoane extrase automat)`);

  if (process.argv.includes("--manifest-only")) { writeManifest(); return; }
  const results = [];
  const CONC = 4;
  let i = 0;
  await Promise.all(Array.from({ length: CONC }, async () => {
    while (i < jobs.length) {
      const [a, s] = jobs[i++];
      results.push(await render(a, s));
    }
  }));

  const bad = results.filter((r) => !r.ok);
  console.log(`OK: ${results.length - bad.length}/${results.length}`);
  if (bad.length) console.log("ESUATE:", bad.map((b) => `${b.name}@${b.scale}x`).join(", "));

  writeManifest();
})();
