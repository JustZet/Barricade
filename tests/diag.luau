--!nolint
-- Diagnostic temporar: reconstruieste pozitia din captura de ecran.
local h = require("./harness")

local Shared = h.Shared
local BoardState = Shared.BoardState
local BoardUtils = Shared.BoardUtils
local Pathfinding = Shared.Pathfinding
local WallRules = Shared.WallRules

local state = BoardState.create("1v1", {
	{ UserId = 1, Name = "Albastru" },
	{ UserId = 2, Name = "Rosu" },
})
state.Status = "PLAYING"

-- Pozitiile citite din captura.
state.Players[1].Position = { X = 5, Y = 3 }
state.Players[2].Position = { X = 5, Y = 7 }

local function seed(x, y, o)
	state.Walls[BoardUtils.wallKey(x, y, o)] = { X = x, Y = y, Orientation = o }
end

-- Linia orizontala lunga (patru baricade cap la cap) plus verticala de sus-dreapta.
seed(1, 5, "Horizontal")
seed(3, 5, "Horizontal")
seed(5, 5, "Horizontal")
seed(7, 5, "Horizontal")
seed(8, 6, "Vertical")
BoardState.rebuildCaches(state)

print("Ziduri pe tabla: 4 orizontale la Y=5 (coloanele 1-8) + V(8,6)")
print("")

local function verdict(label, x, y, o, slot)
	local result = WallRules.isValidWallPlacement(state, slot, x, y, o)
	print(
		string.format(
			"%-46s -> %s",
			label,
			result.Ok and "PERMIS" or ("REFUZAT: " .. tostring(result.Reason))
		)
	)
end

print("== Ce arata previzualizarea verde din captura ==")
verdict("V(8,4) verticala, sub cea existenta", 8, 4, "Vertical", 2)
print("")

print("== Incercari de a inchide coloana 9 pe linia Y=5 ==")
verdict("H(8,5) orizontala peste coloanele 8-9", 8, 5, "Horizontal", 2)
verdict("H(9,5) orizontala peste coloanele 9-10", 9, 5, "Horizontal", 2)
print("")

print("== Se poate sigila vreodata un rand intreg? ==")
-- O orizontala la (x, y) acopera coloanele x si x+1 si nu se poate suprapune.
-- Cate coloane pot fi acoperite simultan pe acelasi rand?
local best = 0
local bestCombo = nil
for a = 1, 8 do
	for b = a + 2, 8 do
		for c = b + 2, 8 do
			for d = c + 2, 8 do
				local covered = {}
				for _, x in { a, b, c, d } do
					covered[x] = true
					covered[x + 1] = true
				end
				local count = 0
				for _ in covered do
					count += 1
				end
				if count > best then
					best = count
					bestCombo = { a, b, c, d }
				end
			end
		end
	end
end
print(string.format("Maxim de coloane acoperite de orizontale pe acelasi rand: %d din 9", best))
print(
	string.format(
		"(combinatia %s — ramane mereu o coloana libera)",
		table.concat(bestCombo, ", ")
	)
)
print("")

print("== Drumurile care exista chiar acum ==")
for slot = 1, 2 do
	local ok, distance = Pathfinding.hasPathToGoal(state, slot)
	print(
		string.format(
			"  %s: %s, %s mutari",
			state.Players[slot].Name,
			ok and "are drum" or "INGROPAT",
			tostring(distance)
		)
	)
end

print("")
print("== Si daca as permite o baricada care inchide coloana 9? ==")
local sealed = {}
for _, edge in BoardUtils.wallBlockedEdges(8, 5, "Horizontal") do
	sealed[edge] = true
end
local everyoneOk, blocked = Pathfinding.allPlayersHavePath(state, sealed)
print(
	string.format(
		"  Toata lumea mai are drum? %s%s",
		tostring(everyoneOk),
		blocked and (" (slotul " .. blocked .. " ramane fara drum)") or ""
	)
)

return true
