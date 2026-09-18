--!strict
--[[
	BoardUtils — conventia de coordonate si cheile derivate din ea.

	CONVENTIA (o singura data, valabila peste tot):

	Celule
		X = 1..9 de la stanga la dreapta.
		Y = 1..9 de jos in sus. Y = 1 este randul de jos al tablei.
		Randarea inverseaza Y, logica nu.

	Baricade
		O baricada nu sta pe o celula, sta pe o *intersectie*.
		Intersectia (X, Y) cu X, Y = 1..8 este coltul comun al celulelor
		(X, Y), (X+1, Y), (X, Y+1) si (X+1, Y+1).

		Orizontala la (X, Y) sta pe linia dintre randul Y si randul Y+1
		si acopera coloanele X si X+1:

			(X,Y+1) │ (X+1,Y+1)
			════════╪════════      <- baricada
			 (X,Y)  │  (X+1,Y)

		Verticala la (X, Y) sta pe linia dintre coloana X si X+1 si
		acopera randurile Y si Y+1.

	Segmente
		Fiecare baricada ocupa doua jumatati de sant plus intersectia din
		centru. Doua baricade sunt in conflict daca impart macar o cheie.
		Asta acopera si suprapunerea, si incrucisarea in "+", fara cazuri
		speciale.
]]

local GameConfig = require(script.Parent.GameConfig)
local Types = require(script.Parent.Types)

type Cell = Types.Cell
type Wall = Types.Wall
type Orientation = Types.Orientation

local BoardUtils = {}

BoardUtils.Size = GameConfig.BoardSize
-- Intersectiile merg pana la Size - 1: o baricada acopera mereu doua celule.
BoardUtils.WallSlots = GameConfig.BoardSize - 1

-- Cele patru directii ortogonale. Fara diagonale la mutarea normala.
BoardUtils.Directions = {
	{ X = 0, Y = 1, Name = "UP" },
	{ X = 0, Y = -1, Name = "DOWN" },
	{ X = -1, Y = 0, Name = "LEFT" },
	{ X = 1, Y = 0, Name = "RIGHT" },
}

function BoardUtils.isInside(cell: Cell): boolean
	return cell.X >= 1 and cell.X <= BoardUtils.Size and cell.Y >= 1 and cell.Y <= BoardUtils.Size
end

function BoardUtils.isWallSlotInside(x: number, y: number): boolean
	return x >= 1 and x <= BoardUtils.WallSlots and y >= 1 and y <= BoardUtils.WallSlots
end

function BoardUtils.sameCell(a: Cell, b: Cell): boolean
	return a.X == b.X and a.Y == b.Y
end

function BoardUtils.cellKey(cell: Cell): string
	return string.format("%d,%d", cell.X, cell.Y)
end

--[[
	Cheia unei muchii intre doua celule vecine. Normalizata, ca sa iasa
	aceeasi cheie indiferent din ce capat e privita.
]]
function BoardUtils.edgeKey(a: Cell, b: Cell): string
	local ai = (a.Y - 1) * BoardUtils.Size + a.X
	local bi = (b.Y - 1) * BoardUtils.Size + b.X
	if ai > bi then
		ai, bi = bi, ai
	end
	return string.format("%d-%d", ai, bi)
end

function BoardUtils.wallKey(x: number, y: number, orientation: Orientation): string
	return string.format("%s:%d,%d", orientation == "Horizontal" and "H" or "V", x, y)
end

--[[
	Cele doua muchii pe care le taie o baricada. Aici se traduce geometria
	in interdictii de mutare; restul jocului nu mai stie de intersectii.
]]
function BoardUtils.wallBlockedEdges(x: number, y: number, orientation: Orientation): { string }
	if orientation == "Horizontal" then
		return {
			BoardUtils.edgeKey({ X = x, Y = y }, { X = x, Y = y + 1 }),
			BoardUtils.edgeKey({ X = x + 1, Y = y }, { X = x + 1, Y = y + 1 }),
		}
	end
	return {
		BoardUtils.edgeKey({ X = x, Y = y }, { X = x + 1, Y = y }),
		BoardUtils.edgeKey({ X = x, Y = y + 1 }, { X = x + 1, Y = y + 1 }),
	}
end

--[[
	Segmentele ocupate de o baricada: doua jumatati de sant si intersectia.
	Intersectia e comuna ambelor orientari, deci doua baricade perpendiculare
	pe acelasi centru se resping automat — regula "+" din spec.
]]
function BoardUtils.wallSegments(x: number, y: number, orientation: Orientation): { string }
	local center = string.format("C:%d,%d", x, y)
	if orientation == "Horizontal" then
		return {
			center,
			string.format("H:%d,%d", x, y),
			string.format("H:%d,%d", x + 1, y),
		}
	end
	return {
		center,
		string.format("V:%d,%d", x, y),
		string.format("V:%d,%d", x, y + 1),
	}
end

-- Celulele care incheie jocul pentru un obiectiv dat.
function BoardUtils.getTargetCells(objective: Types.Objective): { Cell }
	if objective.Kind == "CENTER" then
		local cell = objective.Cell or { X = 5, Y = 5 }
		return { { X = cell.X, Y = cell.Y } }
	end

	local size = BoardUtils.Size
	local cells: { Cell } = {}
	for i = 1, size do
		if objective.Edge == "Y_MAX" then
			table.insert(cells, { X = i, Y = size })
		elseif objective.Edge == "Y_MIN" then
			table.insert(cells, { X = i, Y = 1 })
		elseif objective.Edge == "X_MAX" then
			table.insert(cells, { X = size, Y = i })
		elseif objective.Edge == "X_MIN" then
			table.insert(cells, { X = 1, Y = i })
		end
	end
	return cells
end

function BoardUtils.isTargetCell(objective: Types.Objective, cell: Cell): boolean
	if objective.Kind == "CENTER" then
		local target = objective.Cell or { X = 5, Y = 5 }
		return cell.X == target.X and cell.Y == target.Y
	end

	local size = BoardUtils.Size
	if objective.Edge == "Y_MAX" then
		return cell.Y == size
	elseif objective.Edge == "Y_MIN" then
		return cell.Y == 1
	elseif objective.Edge == "X_MAX" then
		return cell.X == size
	elseif objective.Edge == "X_MIN" then
		return cell.X == 1
	end
	return false
end

return BoardUtils
