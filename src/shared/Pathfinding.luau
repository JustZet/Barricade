--!strict
--[[
	Pathfinding — BFS pe tabla, cu baricadele ca singurul obstacol.

	Tabla are 81 de celule, deci un BFS complet e instantaneu; nu are rost
	nimic mai destept.

	Jucatorii NU sunt obstacole aici, si asta e intentionat. Verificarea de
	drum raspunde la intrebarea "exista un traseu catre obiectiv daca
	baricadele raman asa cum sunt", iar pionii se misca intre timp. Daca i-am
	trata ca ziduri, o baricada perfect legala ar fi respinsa doar fiindca un
	adversar sta momentan in drum.
]]

local BoardUtils = require(script.Parent.BoardUtils)
local Types = require(script.Parent.Types)

type Cell = Types.Cell
type BoardState = Types.BoardState

local Pathfinding = {}

--[[
	Vecinii accesibili ai unei celule, tinand cont de baricade.

	`extraBlocked` permite intrebarea "cum ar arata tabla *daca* as pune si
	baricada asta", fara sa modific starea reala.
]]
function Pathfinding.getLegalNeighbors(
	state: BoardState,
	cell: Cell,
	extraBlocked: { [string]: boolean }?
): { Cell }
	local neighbors: { Cell } = {}

	for _, dir in BoardUtils.Directions do
		local target: Cell = { X = cell.X + dir.X, Y = cell.Y + dir.Y }
		if BoardUtils.isInside(target) then
			local edge = BoardUtils.edgeKey(cell, target)
			local blocked = state.BlockedEdges[edge] == true
			if not blocked and extraBlocked then
				blocked = extraBlocked[edge] == true
			end
			if not blocked then
				table.insert(neighbors, target)
			end
		end
	end

	return neighbors
end

--[[
	Exista un drum de la pozitia jucatorului pana la obiectivul lui?

	Returneaza si distanta in mutari, folosita de UI ca indiciu si de teste.
]]
function Pathfinding.hasPathToGoal(
	state: BoardState,
	slot: number,
	extraBlocked: { [string]: boolean }?
): (boolean, number?)
	local player = state.Players[slot]
	if not player then
		return false, nil
	end

	local start = player.Position
	if BoardUtils.isTargetCell(player.Objective, start) then
		return true, 0
	end

	local visited: { [string]: boolean } = { [BoardUtils.cellKey(start)] = true }
	local queue: { Cell } = { start }
	local distance: { [string]: number } = { [BoardUtils.cellKey(start)] = 0 }
	local head = 1

	while head <= #queue do
		local current = queue[head]
		head += 1
		local currentDistance = distance[BoardUtils.cellKey(current)]

		for _, neighbor in Pathfinding.getLegalNeighbors(state, current, extraBlocked) do
			local key = BoardUtils.cellKey(neighbor)
			if not visited[key] then
				visited[key] = true
				distance[key] = currentDistance + 1

				if BoardUtils.isTargetCell(player.Objective, neighbor) then
					return true, currentDistance + 1
				end

				table.insert(queue, neighbor)
			end
		end
	end

	return false, nil
end

--[[
	Toti jucatorii activi isi pot inca atinge obiectivul?

	Regula cea mai importanta din joc trece pe aici. Se verifica fiecare
	jucator individual, inclusiv coechipierii: in 2v2 nu ai voie sa-ti
	zidesti nici partenerul.

	Returneaza slotul primului jucator blocat, ca apelantul sa poata spune
	exact pe cine ar ingropa mutarea.
]]
function Pathfinding.allPlayersHavePath(
	state: BoardState,
	extraBlocked: { [string]: boolean }?
): (boolean, number?)
	for _, slot in state.TurnOrder do
		local player = state.Players[slot]
		if player and not player.Finished then
			local ok = Pathfinding.hasPathToGoal(state, slot, extraBlocked)
			if not ok then
				return false, slot
			end
		end
	end
	return true, nil
end

return Pathfinding
