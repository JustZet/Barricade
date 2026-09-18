// Iconita si thumbnail-urile pentru pagina experientei, randate cu Chrome headless,
// din aceleasi token-uri de culoare ca restul design system-ului.
//
//   node assets/store/gen-store.js
//
// Iese in assets/store/out/:
//   icon-512.png              iconita experientei (Roblox cere 512x512)
//   thumb-1-goal.png          1920x1080
//   thumb-2-rule.png          1920x1080
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile } = require("child_process");

const CHROME = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const ROOT = __dirname;
const OUT = path.join(ROOT, "out");
const WORK = path.join(ROOT, ".work");

for (const d of [OUT, WORK]) fs.mkdirSync(d, { recursive: true });

// Token-urile de culoare — aceleasi valori ca in ../design-system/gen.js.
const C = {
  wood100: "#EFD9AE", wood300: "#D9A566", wood500: "#B5763C", wood700: "#7A4A22",
  ink900: "#3B2412", paper50: "#FBF3E2", paper200: "#EBD9BC",
  woodTop: "#C68B4E", woodBot: "#A96C36", woodEdge: "#5A3418",
  highlight: "#FFD666",
};
const PLAYERS = {
  blue: { top: "#4A99E0", bot: "#2266B0", shape: "circle" },
  red: { top: "#E4635E", bot: "#C2352F", shape: "diamond" },
  green: { top: "#5CC24A", bot: "#41972F", shape: "square" },
  yellow: { top: "#F2C34A", bot: "#D19A1C", shape: "triangle" },
};
const GRAIN = "repeating-linear-gradient(92deg, rgba(0,0,0,.05) 0 3px, rgba(0,0,0,0) 3px 11px)";

// ---------- piese ----------

function marca(kind, inner) {
  const s = Math.round(inner * 0.34);
  const p = C.paper50;
  if (kind === "circle") {
    return `<div style="width:${s}px;height:${s}px;border-radius:50%;background:${p}"></div>`;
  }
  if (kind === "square") {
    return `<div style="width:${s}px;height:${s}px;border-radius:${Math.round(s * 0.15)}px;background:${p}"></div>`;
  }
  if (kind === "diamond") {
    return `<div style="width:${s}px;height:${s}px;background:${p};transform:rotate(45deg);border-radius:${Math.round(s * 0.12)}px"></div>`;
  }
  return `<div style="width:0;height:0;border-left:${s / 2}px solid transparent;border-right:${s / 2}px solid transparent;border-bottom:${s}px solid ${p}"></div>`;
}

function pion(culoare, d) {
  const p = PLAYERS[culoare];
  const inner = Math.round(d * 0.78);
  return `<div style="width:${d}px;height:${d}px;border-radius:50%;background:${C.woodEdge};
    display:flex;align-items:center;justify-content:center;
    box-shadow:0 ${Math.round(d * 0.07)}px ${Math.round(d * 0.1)}px rgba(0,0,0,.35)">
    <div style="width:${inner}px;height:${inner}px;border-radius:50%;
      background:linear-gradient(180deg,${p.top},${p.bot});
      display:flex;align-items:center;justify-content:center">${marca(p.shape, inner)}</div>
  </div>`;
}

// O baricada e o bara de lemn asezata peste santul dintre celule.
function baricada(lungime, grosime, orizontala) {
  const w = orizontala ? lungime : grosime;
  const h = orizontala ? grosime : lungime;
  const r = Math.round(grosime * 0.38);
  return `<div style="width:${w}px;height:${h}px;border-radius:${r}px;
    background:linear-gradient(180deg,${C.woodTop},${C.woodBot}),${GRAIN};
    border:${Math.max(2, Math.round(grosime * 0.13))}px solid ${C.woodEdge};
    box-sizing:border-box;
    box-shadow:0 ${Math.round(grosime * 0.22)}px ${Math.round(grosime * 0.3)}px rgba(0,0,0,.4)"></div>`;
}

/**
 * Tabla. `n` celule pe latura, `cell` latimea unei celule, `gap` santul dintre ele.
 * Pionii si zidurile vin in coordonatele jocului: X spre dreapta, Y de jos in sus,
 * exact ca in BoardUtils. Inversarea lui Y se face intr-un singur loc, ca in BoardView.
 */
function tabla({ n, cell, gap, pioni = [], ziduri = [] }) {
  const pas = cell + gap;
  const latura = n * cell + (n - 1) * gap;
  const rama = Math.round(cell * 0.42);

  let celule = "";
  for (let i = 0; i < n * n; i++) {
    const randPar = Math.floor(i / n) % 2 === 0;
    const par = randPar ? i % 2 === 0 : i % 2 === 1;
    celule += `<div style="width:${cell}px;height:${cell}px;border-radius:${Math.round(cell * 0.12)}px;
      background:${par ? C.paper50 : C.paper200};
      box-shadow:inset 0 0 0 1px rgba(90,52,24,.10)"></div>`;
  }

  const sus = (y) => (n - y) * pas; // inversarea lui Y, o singura data

  let peste = "";
  for (const p of pioni) {
    const d = Math.round(cell * 0.82);
    const off = (cell - d) / 2;
    peste += `<div style="position:absolute;left:${(p.x - 1) * pas + off}px;top:${sus(p.y) + off}px">${pion(p.culoare, d)}</div>`;
  }
  for (const z of ziduri) {
    const gros = Math.round(gap * 2.1);
    const lung = 2 * cell + gap;
    const orizontala = z.o === "H";
    // Intersectia (x, y) e coltul comun al celulelor (x,y), (x+1,y), (x,y+1), (x+1,y+1).
    // Centrul santului dintre coloanele x si x+1 sta la x * pas - gap / 2.
    const centruX = z.x * pas - gap / 2;
    const centruY = sus(z.y) - gap / 2;
    const left = orizontala ? (z.x - 1) * pas : centruX - gros / 2;
    const top = orizontala ? centruY - gros / 2 : sus(z.y + 1);
    peste += `<div style="position:absolute;left:${left}px;top:${top}px">${baricada(lung, gros, orizontala)}</div>`;
  }

  return `<div style="padding:${rama}px;border-radius:${Math.round(rama * 1.5)}px;
    background:linear-gradient(180deg,${C.wood500},${C.wood700}),${GRAIN};
    box-shadow:0 ${Math.round(rama * 0.5)}px ${Math.round(rama * 0.9)}px rgba(0,0,0,.45),
               inset 0 2px 0 rgba(255,255,255,.18)">
    <div style="position:relative;width:${latura}px;height:${latura}px;
      display:grid;grid-template-columns:repeat(${n},${cell}px);gap:${gap}px;
      border-radius:${Math.round(rama * 0.7)}px;background:${C.wood700}">
      ${celule}
      <div style="position:absolute;inset:0">${peste}</div>
    </div>
  </div>`;
}

function pagina(w, h, fundal, continut) {
  return `<!doctype html><meta charset="utf-8">
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    html,body{width:${w}px;height:${h}px;overflow:hidden}
    body{background:${fundal};display:flex;align-items:center;justify-content:center;
      font-family:"Trebuchet MS","Segoe UI",system-ui,sans-serif;color:${C.paper50}}
  </style>
  <body>${continut}</body>`;
}

// ---------- compozitiile ----------

const FUNDAL = `radial-gradient(120% 120% at 30% 10%, ${C.wood300} 0%, ${C.wood700} 55%, ${C.ink900} 100%)`;

// Iconita: o tabla 4x4, doi pioni fata in fata si baricada dintre ei. La 128px pe
// ecranul unui telefon nu s-ar mai vedea nimic dintr-o tabla 9x9, de asta e taiata.
const ICON = pagina(512, 512, FUNDAL, `
  ${tabla({
    n: 4,
    cell: 88,
    gap: 16,
    pioni: [{ x: 1, y: 4, culoare: "blue" }, { x: 4, y: 1, culoare: "red" }],
    ziduri: [{ x: 2, y: 2, o: "H" }],
  })}`);

function thumb(titlu, subtitlu, board) {
  return pagina(1920, 1080, FUNDAL, `
    <div style="display:flex;align-items:center;gap:110px">
      <div>${board}</div>
      <div style="max-width:840px">
        <div style="font-size:104px;font-weight:800;letter-spacing:-2px;line-height:1.02;
          color:${C.paper50};text-shadow:0 6px 0 ${C.woodEdge},0 14px 28px rgba(0,0,0,.45)">${titlu}</div>
        <div style="margin-top:34px;height:10px;width:220px;border-radius:5px;background:${C.highlight}"></div>
        <div style="margin-top:38px;font-size:44px;line-height:1.35;color:${C.wood100}">${subtitlu}</div>
      </div>
    </div>`);
}

// Textul e in engleza, ca UI-ul din joc ("CHOOSE A MODE", "FINDING PLAYERS...").
const T1 = thumb(
  "BARRICADE",
  "Race to the far side.<br>Or drop a wall in someone&rsquo;s way.",
  tabla({
    n: 9,
    cell: 68,
    gap: 11,
    pioni: [
      { x: 5, y: 1, culoare: "blue" },
      { x: 5, y: 9, culoare: "red" },
      { x: 1, y: 5, culoare: "green" },
      { x: 9, y: 5, culoare: "yellow" },
    ],
    ziduri: [{ x: 4, y: 3, o: "H" }, { x: 6, y: 6, o: "V" }, { x: 2, y: 5, o: "V" }],
  }),
);

const T2 = thumb(
  "NEVER<br>SEALED IN",
  "Block anyone you like.<br>You can never seal their path shut.",
  tabla({
    n: 9,
    cell: 68,
    gap: 11,
    pioni: [{ x: 5, y: 2, culoare: "blue" }, { x: 5, y: 8, culoare: "red" }],
    ziduri: [
      { x: 4, y: 2, o: "H" },
      { x: 6, y: 2, o: "H" },
      { x: 4, y: 1, o: "V" },
      { x: 6, y: 3, o: "V" },
    ],
  }),
);

// ---------- randare ----------

function shot(nume, html, w, h) {
  return new Promise((resolve) => {
    const htmlPath = path.join(WORK, `${nume}.html`);
    fs.writeFileSync(htmlPath, html);
    const outPath = path.join(OUT, `${nume}.png`);
    const profile = fs.mkdtempSync(path.join(os.tmpdir(), "brc-store-"));
    const args = [
      "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
      "--no-default-browser-check", "--disable-extensions",
      `--user-data-dir=${profile}`,
      `--window-size=${w},${h}`,
      `--screenshot=${outPath}`,
      "file:///" + htmlPath.replace(/\\/g, "/"),
    ];
    execFile(CHROME, args, { timeout: 60000 }, (err) => {
      try {
        fs.rmSync(profile, { recursive: true, force: true });
      } catch {}
      const ok = !err && fs.existsSync(outPath);
      console.log(`${ok ? "ok  " : "PICA"} ${nume}.png  ${w}x${h}`);
      resolve(ok);
    });
  });
}

(async () => {
  const rezultate = [
    await shot("icon-512", ICON, 512, 512),
    await shot("thumb-1-goal", T1, 1920, 1080),
    await shot("thumb-2-rule", T2, 1920, 1080),
  ];
  if (rezultate.some((r) => !r)) process.exit(1);
  console.log(`\nGata. Fisierele sunt in ${OUT}`);
})();
