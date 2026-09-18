--!nolint
--[[
	Construieste place-ul gata de urcat:

		lune run tools/build            verifica tot, apoi construieste
		lune run tools/build --rapid    doar construieste (CI a verificat deja)

	Iese `build/Barricade.rbxl` — binar, nu XML, pentru ca asta urca Open Cloud.
	Fara `--rapid` nu se construieste nimic daca verificarile pica, tocmai ca sa
	nu poti urca din greseala un build cu teste cazute.
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
