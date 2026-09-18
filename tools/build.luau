--!nolint
--[[
	Construieste place-ul din proiectul Rojo:

		lune run tools/build            verifica tot, apoi construieste
		lune run tools/build --rapid    doar construieste (CI a verificat deja)

	NU PUBLICA REZULTATUL. E o verificare ca proiectul Rojo e valid si ca tot codul
	intra intr-un DataModel — nimic mai mult. Rojo construieste doar ce scrie in
	default.project.json, adica numai cod, iar lumea 3D (ReplicatedStorage.Assets si
	continutul Workspace) traieste in fisierul place-ului. Urcat peste place-ul real,
	build-ul asta il goleste, si o face tacut: WorldController.isAvailable() nu mai
	gaseste Assets.Board si clientul cade pe tabla 2D.

	Publicarea se face din Studio, cu Ctrl+P. Vezi README, sectiunea "Publicare".
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local VERDE = "\27[32m"
local ROSU = "\27[31m"
local GROS = "\27[1m"
local STOP = "\27[0m"

local IESIRE = "build/Barricade.rbxl"

local rapid = false
for _, argument in process.args do
	if argument == "--rapid" then
		rapid = true
	end
end

if not rapid then
	local verificari = process.exec("lune", { "run", "tools/check" }, { stdio = "default" })
	if not verificari.ok then
		print(verificari.stdout)
		print(`{ROSU}{GROS}Verificarile au picat. Nu construiesc.{STOP}`)
		process.exit(1)
	end
	print(verificari.stdout)
end

if not fs.isDir("build") then
	fs.writeDir("build")
end

local build = process.exec("rojo", { "build", "-o", IESIRE }, { stdio = "default" })
if not build.ok then
	print(build.stdout)
	print(build.stderr)
	print(`{ROSU}{GROS}rojo build a picat.{STOP}`)
	process.exit(1)
end

local marime = #fs.readFile(IESIRE)
print(`{VERDE}{GROS}{IESIRE}{STOP} — {marime} octeti`)
