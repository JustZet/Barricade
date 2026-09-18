// Planşă de contact: toate asseturile 1x pe fundal de şah, pentru verificare vizuală.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile } = require("child_process");

const CHROME = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const ROOT = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, "manifest.json"), "utf8"));

const byCat = {};
for (const a of manifest) (byCat[a.name.split("/")[0]] ||= []).push(a);

let body = "";
for (const [cat, items] of Object.entries(byCat)) {
  body += `<h2>${cat} (${items.length})</h2><div class="row">`;
  for (const a of items) {
    const uri = "file:///" + path.join(ROOT, a.files["1x"]).replace(/\\/g, "/");
    body += `<figure><div class="box"><img src="${uri}"></div><figcaption>${a.name.split("/")[1]}<br><span>${a.w}×${a.h}</span></figcaption></figure>`;
  }
  body += `</div>`;
}

const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
body{margin:0;padding:20px;background:#1b1b1b;color:#eee;font:13px system-ui;width:1240px;box-sizing:border-box}
h2{font-size:15px;margin:22px 0 10px;color:#D9A566;text-transform:uppercase;letter-spacing:.12em}
.row{display:flex;flex-wrap:wrap;gap:12px}
figure{margin:0;width:112px;text-align:center}
.box{width:112px;height:112px;display:grid;place-items:center;border-radius:8px;
  background-image:linear-gradient(45deg,#3a3a3a 25%,transparent 25%,transparent 75%,#3a3a3a 75%),
                   linear-gradient(45deg,#3a3a3a 25%,#2b2b2b 25%,#2b2b2b 75%,#3a3a3a 75%);
  background-size:16px 16px;background-position:0 0,8px 8px}
.box img{max-width:100px;max-height:100px}
figcaption{margin-top:5px;font-size:11px;color:#bbb;line-height:1.35}
figcaption span{color:#777;font-size:10px}
</style></head><body>${body}</body></html>`;

const htmlPath = path.join(ROOT, ".work", "sheet.html");
fs.writeFileSync(htmlPath, html);
const outPath = path.join(ROOT, "contact-sheet.png");
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "brc-sheet-"));

execFile(CHROME, [
  "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
  "--no-default-browser-check", `--user-data-dir=${profile}`,
  "--window-size=1240,2600", `--screenshot=${outPath}`,
  "file:///" + htmlPath.replace(/\\/g, "/"),
], { timeout: 90000 }, (err) => {
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
  console.log(err ? "EROARE: " + err.message : "Planşă scrisă: " + outPath);
});
