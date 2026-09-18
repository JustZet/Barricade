--!nolint
--[[
	harness — ruleaza modulele din src/shared in afara Roblox-ului.

	Modulele de reguli sunt scrise idiomatic pentru Roblox
	(`require(script.Parent.X)`), fiindca acolo traiesc. Ca sa le pot testa
	headless, harness-ul le compileaza cu un mediu in care `script` si
	`require` sunt falsificate: `script.Parent.BoardUtils` devine un marcaj,
	iar `require` il rezolva citind fisierul de pe disc.

	Asa nu exista doua versiuni ale motorului si nici un strat de compatibilitate
	in codul de productie.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local SHARED_DIR = "src/shared"

local harness = {}

local cache: { [string]: any } = {}

local moduleRef = {}
moduleRef.__index = moduleRef

-- `script.Parent` returneaza un marcaj pentru orice nume cerut.
local parentProxy = setmetatable({}, {
	__index = function(_, name: string)
		return setmetatable({ name = name }, moduleRef)
	end,
})

local fakeScript = { Parent = parentProxy, Name = "Module" }

--[[
	Citirile din lune sunt asincrone si nu au voie sa randeze dintr-un
	metamethod, asa ca sursele se citesc toate aici, o singura data, inainte
	sa inceapa compilarea.
]]
local sources: { [string]: string } = {}
for _, entry in fs.readDir(SHARED_DIR) do
	local name = string.match(entry, "^(.+)%.luau$")
	if name then
		sources[name] = fs.readFile(SHARED_DIR .. "/" .. entry)
	end
end

local function loadModule(name: string): any
	if cache[name] ~= nil then
		return cache[name]
	end

	local source = sources[name]
	if not source then
		error("harness: nu gasesc modulul " .. SHARED_DIR .. "/" .. name .. ".luau", 2)
	end

	local chunk = luau.load(source, {
		debugName = name .. ".luau",
		environment = {
			script = fakeScript,
			require = function(ref: any)
				if type(ref) == "table" and getmetatable(ref) == moduleRef then
					return loadModule(ref.name)
				end
				error("harness: require necunoscut " .. tostring(ref), 2)
			end,
		},
	})

	-- Marcaj inainte de executie, ca sa prind ciclurile in loc sa intru in bucla.
	cache[name] = false
	local result = chunk()
	cache[name] = result
	return result
end

harness.Shared = setmetatable({}, {
	__index = function(_, name: string)
		return loadModule(name)
	end,
})

-- ---------------------------------------------------------------- asertiuni

local suites: { { name: string, run: () -> () } } = {}
local currentSuite: string? = nil
local passed = 0
local failures: { string } = {}

function harness.describe(name: string, body: () -> ())
	table.insert(suites, { name = name, run = body })
end

function harness.it(name: string, body: () -> ())
	local label = string.format("%s › %s", currentSuite or "?", name)
	local ok, err = pcall(body)
	if ok then
		passed += 1
	else
		table.insert(failures, string.format("%s\n      %s", label, tostring(err)))
	end
end

local function describeValue(value: any): string
	if type(value) == "table" then
		local parts = {}
		for key, item in pairs(value) do
			table.insert(parts, string.format("%s=%s", tostring(key), tostring(item)))
		end
		table.sort(parts)
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	return tostring(value)
end

function harness.assertEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%s: asteptat %s, primit %s",
				message or "egalitate",
				describeValue(expected),
				describeValue(actual)
			),
			2
		)
	end
end

function harness.assertTrue(value: any, message: string?)
	if not value then
		error(
			string.format(
				"%s: asteptat adevarat, primit %s",
				message or "conditie",
				tostring(value)
			),
			2
		)
	end
end

function harness.assertFalse(value: any, message: string?)
	if value then
		error(
			string.format("%s: asteptat fals, primit %s", message or "conditie", tostring(value)),
			2
		)
	end
end

-- Rezultatele motorului sunt { Ok, Reason }; verific si motivul, nu doar esecul.
function harness.assertOk(result: any, message: string?)
	if not result.Ok then
		error(string.format("%s: respins cu %s", message or "actiune", tostring(result.Reason)), 2)
	end
end

function harness.assertRejected(result: any, expectedReason: string?, message: string?)
	if result.Ok then
		error(string.format("%s: acceptat, desi trebuia respins", message or "actiune"), 2)
	end
	if expectedReason and result.Reason ~= expectedReason then
		error(
			string.format(
				"%s: motiv %s, asteptat %s",
				message or "actiune",
				tostring(result.Reason),
				expectedReason
			),
			2
		)
	end
end

function harness.run()
	for _, suite in suites do
		currentSuite = suite.name
		print(string.format("\27[1m%s\27[0m", suite.name))
		local before = #failures
		suite.run()
		if #failures == before then
			print("  \27[32mtoate trecute\27[0m")
		end
	end

	print("")
	if #failures == 0 then
		print(string.format("\27[32m%d teste trecute, 0 esecuri\27[0m", passed))
		return
	end

	print(string.format("\27[31m%d esecuri din %d teste\27[0m", #failures, passed + #failures))
	for _, failure in failures do
		print("  \27[31mX\27[0m " .. failure)
	end
	process.exit(1)
end

return harness
