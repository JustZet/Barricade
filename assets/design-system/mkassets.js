// Genereaza luau/Assets.luau din manifest.json + ids.json (harta nume -> rbxassetid).
// Ruleaza-l din nou dupa upload ca sa completeze ID-urile reale.
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, "manifest.json"), "utf8"));
const idsPath = path.join(ROOT, "ids.json");
const ids = fs.existsSync(idsPath) ? JSON.parse(fs.readFileSync(idsPath, "utf8")) : {};

// Inset-ul de 9-slice vine per asset din manifest: 18 pentru placi (sectiunea 16),
// iar pentru formele subtiri se aliniaza la raza lor, altfel capetele rotunjite se rup.
const byCat = {};
for (const a of manifest) (byCat[a.name.split("/")[0]] ||= []).push(a);

const key = (n) => n.split("/")[1];
const lit = (v) => (v === undefined || v === null ? "0" : String(v));

let out = `--!strict
-- Barricade Design System -> harta de asseturi Roblox.
-- GENERAT de mkassets.js din manifest.json + ids.json. Nu edita manual.
-- Regenereaza cu: node mkassets.js
--
-- Reguli de export (sectiunea 16 a design system-ului):
--   * placile si baricadele se intind prin 9-slice, fara text ars in textura;
--     pune un TextLabel separat peste ele
--   * inset de referinta 18px la 1x / 36px la 2x; formele subtiri folosesc raza lor
--   * token-urile, baricadele si icoanele sunt PNG transparent la 1x/2x
--   * textura de lemn e un singur 256px tileabil, reutilizat la trei nuante

local Assets = {}

-- Scala incarcata in Roblox. Asseturile @2x arata mai bine la scalare in jos,
-- deci implicit folosim 2x si lasam motorul sa reduca.
Assets.Scale = "2x" :: "1x" | "2x"

`;

for (const [cat, items] of Object.entries(byCat)) {
  out += `-- ---------- ${cat} ----------\n`;
  out += `Assets.${cat} = {\n`;
  for (const a of items) {
    const id1 = ids[a.name] && ids[a.name]["1x"];
    const id2 = ids[a.name] && ids[a.name]["2x"];
    out += `\t${key(a.name)} = {\n`;
    out += `\t\tid1x = ${id1 ? `"rbxassetid://${id1}"` : "nil"},\n`;
    out += `\t\tid2x = ${id2 ? `"rbxassetid://${id2}"` : "nil"},\n`;
    out += `\t\tsize = Vector2.new(${lit(a.w)}, ${lit(a.h)}),\n`;
    if (a.slice) {
      // slice poate fi un numar (uniform) sau [x, y] pentru forme care se intind pe o axa.
      const sx = Array.isArray(a.slice) ? a.slice[0] : a.slice;
      const sy = Array.isArray(a.slice) ? a.slice[1] : a.slice;
      // SliceCenter se raporteaza la bitmap-ul incarcat efectiv, deci se dubleaza la 2x.
      if (sx * 2 >= a.w || sy * 2 >= a.h) {
        throw new Error(`${a.name}: inset ${sx}/${sy} nu incape in ${a.w}x${a.h}`);
      }
      out += `\t\tslice1x = Rect.new(${sx}, ${sy}, ${a.w - sx}, ${a.h - sy}),\n`;
      out += `\t\tslice2x = Rect.new(${sx * 2}, ${sy * 2}, ${a.w * 2 - sx * 2}, ${a.h * 2 - sy * 2}),\n`;
    }
    out += `\t},\n`;
  }
  out += `}\n\n`;
}

out += `-- Returneaza ID-ul pentru scala activa, cu revenire pe cealalta daca lipseste.
function Assets.id(entry: { id1x: string?, id2x: string? }): string?
	if Assets.Scale == "2x" then
		return entry.id2x or entry.id1x
	end
	return entry.id1x or entry.id2x
end

-- Returneaza SliceCenter potrivit scalei active (doar pentru placi si baricade).
function Assets.slice(entry: { slice1x: Rect?, slice2x: Rect? }): Rect?
	if Assets.Scale == "2x" then
		return entry.slice2x or entry.slice1x
	end
	return entry.slice1x or entry.slice2x
end

-- Cate asseturi asteapta inca un ID real.
function Assets.missing(): { string }
	local out = {}
	for categoryName, category in pairs(Assets) do
		if typeof(category) ~= "table" then
			continue
		end
		for entryName, entry in pairs(category) do
			if typeof(entry) == "table" and entry.id1x == nil and entry.id2x == nil then
				table.insert(out, categoryName .. "/" .. entryName)
			end
		end
	end
	table.sort(out)
	return out
end

return Assets
`;

fs.mkdirSync(path.join(ROOT, "luau"), { recursive: true });
fs.writeFileSync(path.join(ROOT, "luau", "Assets.luau"), out);

const total = manifest.length;
const withIds = manifest.filter((a) => ids[a.name]).length;
console.log(`Assets.luau generat: ${total} asseturi, ${withIds} cu ID real, ${total - withIds} in asteptare.`);
