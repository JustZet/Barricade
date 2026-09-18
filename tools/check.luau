--!nolint
--[[
	Cele cinci verificari de dinaintea unui commit, intr-o singura comanda:

		lune run tools/check

	Ruleaza toti pasii chiar daca unul pica, ca sa vezi tot ce e stricat dintr-o
	singura trecere, si iese cu cod 1 daca macar unul s-a plans. CI ruleaza exact
	acest fisier, deci "trece local" si "trece pe GitHub" nu pot sa se desparta.
]]

local process = require("@lune/process")

local VERDE = "\27[32m"
local ROSU = "\27[31m"
local GRI = "\27[90m"
local GROS = "\27[1m"
local STOP = "\27[0m"

type Pas = {
	nume: string,
	program: string,
	argumente: { string },
}

-- Ordinea conteaza intr-un singur loc: sourcemap-ul trebuie scris inainte ca
-- luau-lsp sa il citeasca.
local PASI: { Pas } = {
	{ nume = "stylua", program = "stylua", argumente = { "--check", "src", "tests", "tools" } },
	{ nume = "selene", program = "selene", argumente = { "src" } },
	{ nume = "teste", program = "lune", argumente = { "run", "tests/run" } },
	{ nume = "sourcemap", program = "rojo", argumente = { "sourcemap", "-o", "sourcemap.json" } },
	{
		nume = "luau-lsp",
		program = "luau-lsp",
		argumente = {
			"analyze",
			"--sourcemap=sourcemap.json",
			"--definitions=globalTypes.d.luau",
			"--base-luaurc=.luaurc",
			"src",
		},
	},
}

local cazute: { string } = {}

for _, pas in PASI do
	print(`{GRI}--- {pas.nume}{STOP}`)

	local rezultat = process.exec(pas.program, pas.argumente, { stdio = "default" })

	if rezultat.ok then
		print(`{VERDE}  {pas.nume}: curat{STOP}`)
	else
		table.insert(cazute, pas.nume)
		print(`{ROSU}  {pas.nume}: cod {rezultat.code}{STOP}`)
		if #rezultat.stdout > 0 then
			print(rezultat.stdout)
		end
		if #rezultat.stderr > 0 then
			print(rezultat.stderr)
		end
	end
end

print("")

if #cazute == 0 then
	print(`{VERDE}{GROS}Toate cele {#PASI} verificari trec.{STOP}`)
	process.exit(0)
end

print(`{ROSU}{GROS}Cazute: {table.concat(cazute, ", ")}{STOP}`)
process.exit(1)
