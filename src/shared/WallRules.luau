--!strict
--[[
	WallRules — cand e legala o baricada.

	Cele sase conditii din spec, in ordinea in care e ieftin sa le verifici:
	forma, apoi stocul, apoi geometria, si abia la final drumul (BFS pentru
	fiecare jucator, singura verificare scumpa).

	Modulul e pur: aceeasi functie ruleaza si pe client pentru previzualizarea
	verde/rosie, si pe server ca autoritate. Clientul o foloseste ca sa nu
	trimita gunoi; serverul o foloseste fiindca e singurul care conteaza.
]]

local BoardUtils = require(script.Parent.BoardUtils)
local Pathfinding = require(script.Parent.Pathfinding)
local Types = require(script.Parent.Types)

type BoardState = Types.BoardState
type Orientation = Types.Orientation
type Result = Types.Result

local WallRules = {}

local function fail(reason: string): Result
	return { Ok = false, Reason = reason }
end

local OK: Result = { Ok = true }

local ORIENTATIONS: { Orientation } = { "Horizontal", "Vertical" }

-- Segmentele deja ocupate se resping reciproc: si suprapunerea, si "+"-ul.
function WallRules.conflictsWithExisting(
	state: BoardState,
	x: number,
	y: number,
	orientation: Orientation
): boolean
	for _, segment in BoardUtils.wallSegments(x, y, orientation) do
		if state.OccupiedSegments[segment] then
			return true
		end
	end
	return false
end

--[[
	Verificarea completa. `slot` e jucatorul care cere plasarea.

	Nu consuma nimic si nu modifica starea — doar raspunde.
]]
function WallRules.isValidWallPlacement(
	state: BoardState,
	slot: number,
	x: number,
	y: number,
	orientation: any
): Result
	if state.Status ~= "PLAYING" then
		return fail("GAME_NOT_ACTIVE")
	end

	local player = state.Players[slot]
	if not player then
		return fail("NOT_IN_MATCH")
	end

	-- 5. Aliniere corecta. Orice altceva vine de la un client modificat.
	if orientation ~= "Horizontal" and orientation ~= "Vertical" then
		return fail("BAD_ORIENTATION")
	end

	if type(x) ~= "number" or type(y) ~= "number" then
		return fail("BAD_COORDINATES")
	end

	if x % 1 ~= 0 or y % 1 ~= 0 then
		return fail("BAD_COORDINATES")
	end

	-- 2. In interiorul tablei.
	if not BoardUtils.isWallSlotInside(x, y) then
		return fail("OUT_OF_BOUNDS")
	end

	-- 1. Mai are baricade.
	if player.BarricadesRemaining <= 0 then
		return fail("NO_BARRICADES_LEFT")
	end

	-- 3 + 4. Nu se suprapune si nu se incruciseaza.
	if WallRules.conflictsWithExisting(state, x, y, orientation) then
		return fail("WALL_CONFLICT")
	end

	-- 6. Si, cel mai important, nu ingroapa pe nimeni.
	local extraBlocked: { [string]: boolean } = {}
	for _, edge in BoardUtils.wallBlockedEdges(x, y, orientation) do
		extraBlocked[edge] = true
	end

	local everyoneHasPath, blockedSlot = Pathfinding.allPlayersHavePath(state, extraBlocked)
	if not everyoneHasPath then
		return { Ok = false, Reason = "WOULD_BLOCK_PLAYER_" .. tostring(blockedSlot) }
	end

	return OK
end

--[[
	Ar taia baricada asta ultimul drum al unui anumit jucator?
	Folosita de UI ca sa explice de ce previzualizarea e rosie.
]]
function WallRules.wouldWallBlockPlayer(
	state: BoardState,
	slot: number,
	x: number,
	y: number,
	orientation: Orientation
): boolean
	local extraBlocked: { [string]: boolean } = {}
	for _, edge in BoardUtils.wallBlockedEdges(x, y, orientation) do
		extraBlocked[edge] = true
	end
	local hasPath = Pathfinding.hasPathToGoal(state, slot, extraBlocked)
	return not hasPath
end

-- Toate plasarile legale pentru jucatorul la mutare. Folosita de teste si de bot.
function WallRules.getLegalWallPlacements(state: BoardState, slot: number): { Types.Wall }
	local placements: { Types.Wall } = {}
	for x = 1, BoardUtils.WallSlots do
		for y = 1, BoardUtils.WallSlots do
			for _, orientation in ORIENTATIONS do
				if WallRules.isValidWallPlacement(state, slot, x, y, orientation).Ok then
					-- Castul e necesar: la iterare Luau largeste uniunea de siruri la `string`.
					local placement: Types.Wall =
						{ X = x, Y = y, Orientation = orientation :: Types.Orientation }
					table.insert(placements, placement)
				end
			end
		end
	end
	return placements
end

return WallRules
