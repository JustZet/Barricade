--!strict
--[[
	MovementRules — o mutare pe tura, ortogonala, cu saritura peste adversar.

	Regula de baza e banala: o celula sus/jos/stanga/dreapta, daca nu e
	baricada intre ele. Partea cu carlig e intalnirea a doi pioni:

		1. Daca vecinul in directia dorita e ocupat, incerci sa sari drept
		   peste el, pe celula imediat urmatoare.
		2. Saritura dreapta reuseste doar daca acea celula exista, e libera
		   si nu e baricada intre adversar si ea.
		3. Daca saritura dreapta e imposibila — perete, margine de tabla sau
		   un al treilea pion — primesti in schimb cele doua ocoliri
		   diagonale, in jurul adversarului.

	Punctul 3 e singurul loc din joc unde te misti in diagonala si exista
	tocmai ca sa nu fii blocat de un pion pe care nu-l poti sari.
]]

local BoardUtils = require(script.Parent.BoardUtils)
local Types = require(script.Parent.Types)

type Cell = Types.Cell
type BoardState = Types.BoardState
type Result = Types.Result

local MovementRules = {}

local function fail(reason: string): Result
	return { Ok = false, Reason = reason }
end

-- Harta celula -> slot, construita din pozitiile curente.
function MovementRules.getOccupancy(state: BoardState): { [string]: number }
	local occupancy: { [string]: number } = {}
	for slot, player in state.Players do
		occupancy[BoardUtils.cellKey(player.Position)] = slot
	end
	return occupancy
end

local function isBlocked(state: BoardState, from: Cell, to: Cell): boolean
	return state.BlockedEdges[BoardUtils.edgeKey(from, to)] == true
end

--[[
	Toate mutarile legale ale unui jucator, inclusiv sariturile.

	Sursa unica de adevar: si serverul, si evidentierea celulelor din client
	cheama functia asta. Nu exista o a doua implementare a regulii.
]]
function MovementRules.getLegalMoves(state: BoardState, slot: number): { Cell }
	local player = state.Players[slot]
	if not player then
		return {}
	end

	local occupancy = MovementRules.getOccupancy(state)
	local from = player.Position
	local moves: { Cell } = {}
	local seen: { [string]: boolean } = {}

	local function add(cell: Cell)
		local key = BoardUtils.cellKey(cell)
		if not seen[key] and not occupancy[key] then
			seen[key] = true
			table.insert(moves, cell)
		end
	end

	for _, dir in BoardUtils.Directions do
		local neighbor: Cell = { X = from.X + dir.X, Y = from.Y + dir.Y }

		if BoardUtils.isInside(neighbor) and not isBlocked(state, from, neighbor) then
			if not occupancy[BoardUtils.cellKey(neighbor)] then
				-- Drum liber: mutarea obisnuita.
				add(neighbor)
			else
				-- Vecinul e ocupat. Incearca saritura dreapta peste el.
				local behind: Cell = { X = neighbor.X + dir.X, Y = neighbor.Y + dir.Y }
				local canJumpStraight = BoardUtils.isInside(behind)
					and not isBlocked(state, neighbor, behind)
					and not occupancy[BoardUtils.cellKey(behind)]

				if canJumpStraight then
					add(behind)
				else
					-- Blocata: ocoleste-l prin lateral, perpendicular pe directie.
					for _, side in BoardUtils.Directions do
						local isPerpendicular = (side.X * dir.X + side.Y * dir.Y) == 0
						if isPerpendicular then
							local diagonal: Cell =
								{ X = neighbor.X + side.X, Y = neighbor.Y + side.Y }
							if
								BoardUtils.isInside(diagonal)
								and not isBlocked(state, neighbor, diagonal)
								and not occupancy[BoardUtils.cellKey(diagonal)]
							then
								add(diagonal)
							end
						end
					end
				end
			end
		end
	end

	return moves
end

--[[
	E legala mutarea acestui jucator pe celula ceruta?

	Se sprijina pe getLegalMoves ca sa nu existe doua seturi de reguli care
	pot sa se desincronizeze.
]]
function MovementRules.isValidMove(state: BoardState, slot: number, target: any): Result
	if state.Status ~= "PLAYING" then
		return fail("GAME_NOT_ACTIVE")
	end

	local player = state.Players[slot]
	if not player then
		return fail("NOT_IN_MATCH")
	end

	if type(target) ~= "table" or type(target.X) ~= "number" or type(target.Y) ~= "number" then
		return fail("BAD_COORDINATES")
	end

	if target.X % 1 ~= 0 or target.Y % 1 ~= 0 then
		return fail("BAD_COORDINATES")
	end

	if not BoardUtils.isInside(target) then
		return fail("OUT_OF_BOUNDS")
	end

	if BoardUtils.sameCell(player.Position, target) then
		return fail("SAME_CELL")
	end

	for _, move in MovementRules.getLegalMoves(state, slot) do
		if BoardUtils.sameCell(move, target) then
			return { Ok = true }
		end
	end

	return fail("ILLEGAL_MOVE")
end

return MovementRules
