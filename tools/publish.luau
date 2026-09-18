--!nolint
--[[
	Urca build-ul in experienta de pe Roblox, prin Open Cloud:

		lune run tools/publish                       urca build/Barricade.rbxl
		lune run tools/publish cale/catre/fisier.rbxl

	Are nevoie de trei variabile de mediu:

		ROBLOX_API_KEY       cheie din Creator Hub -> Open Cloud API Keys,
		                     cu permisiunea "universe-places:write" pe universul asta
		ROBLOX_UNIVERSE_ID   din URL-ul experientei in Creator Hub
		ROBLOX_PLACE_ID      id-ul place-ului de start

	Cheia nu apare niciodata in cod si nu se scrie in niciun fisier. Local o pui in
	mediu inainte de comanda; pe GitHub sta in Settings -> Secrets and variables.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local VERDE = "\27[32m"
local ROSU = "\27[31m"
local GRI = "\27[90m"
local GROS = "\27[1m"
local STOP = "\27[0m"

local IMPLICIT = "build/Barricade.rbxl"

-- Cele trei greseli care apar in practica, fiecare cu leacul ei.
local LAMURIRI: { [number]: string } = {
	[401] = "cheie invalida sau expirata",
	[403] = "cheia nu are 'universe-places:write' aici, sau IP-ul tau nu e permis",
	[404] = "universeId sau placeId gresit",
}

local function opreste(mesaj: string): never
	print(`{ROSU}{GROS}{mesaj}{STOP}`)
	process.exit(1)
	error(mesaj)
end

local function ceruta(nume: string): string
	local valoare = process.env[nume]
	if valoare == nil or valoare == "" then
		opreste(`Lipseste variabila de mediu {nume}.`)
	end
	return valoare :: string
end

local cheie = ceruta("ROBLOX_API_KEY")
local univers = ceruta("ROBLOX_UNIVERSE_ID")
local place = ceruta("ROBLOX_PLACE_ID")

local cale = process.args[1] or IMPLICIT
if not fs.isFile(cale) then
	opreste(`Nu gasesc {cale}. Ruleaza intai: lune run tools/build`)
end

local continut = fs.readFile(cale)
print(`{GRI}Urc {cale} ({#continut} octeti) in place-ul {place}...{STOP}`)

local raspuns = net.request({
	url = `https://apis.roblox.com/universes/v1/{univers}/places/{place}/versions?versionType=Published`,
	method = "POST",
	headers = {
		["x-api-key"] = cheie,
		["Content-Type"] = "application/octet-stream",
	},
	body = continut,
})

if not raspuns.ok then
	local lamurire = LAMURIRI[raspuns.statusCode] or "vezi raspunsul de mai jos"
	print(raspuns.body)
	opreste(`Upload esuat: HTTP {raspuns.statusCode} — {lamurire}.`)
end

local versiune = "?"
local ok, decodat = pcall(serde.decode, "json" :: any, raspuns.body)
if ok and typeof(decodat) == "table" and decodat.versionNumber ~= nil then
	versiune = tostring(decodat.versionNumber)
end

print(`{VERDE}{GROS}Publicat — versiunea {versiune}.{STOP}`)
print(`{GRI}https://www.roblox.com/games/{place}{STOP}`)
