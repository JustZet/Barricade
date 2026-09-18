--!strict
--[[
	BoardState — motorul. Starea tablei si singurele doua actiuni care o schimba.

	Nu stie nimic despre Roblox: fara Instance, fara RemoteEvent, fara task.
	De aia poate fi rulat in teste headless cu lune, si de aia clientul poate
	folosi exact acelasi cod ca serverul pentru previzualizari.

	Un singur motor pentru toate modurile. Modul de joc alege pozitiile de
	start, obiectivele si stocul de baricade — nu si regulile.
]]

local BoardUtils = require(script.Parent.BoardUtils)
local GameConfig = require(script.Parent.GameConfig)
local MovementRules = require(script.Parent.MovementRules)
local Pathfinding = require(script.Parent.Pathfinding)
local Types = require(script.Parent.Types)
local WallRules = require(script.Parent.WallRules)

type BoardState = Types.BoardState
type PlayerState = Types.PlayerState
type Result = Types.Result
type Wall = Types.Wall

export type Participant = {
	UserId: number,
	Name: string,
}

local BoardState = {}

local function fail(reason: string): Result
	return { Ok = false, Reason = reason }
end

--[[
	Reconstruieste cache-urile derivate din lista de baricade.

	BlockedEdges si OccupiedSegments sunt intotdeauna derivate — nu se scrie
	niciodata direct in ele din afara. Asa nu pot ajunge sa contrazica Walls.
]]
function BoardState.rebuildCaches(state: BoardState)
	state.BlockedEdges = {}
	state.OccupiedSegments = {}

	for _, wall in state.Walls do
		for _, edge in BoardUtils.wallBlockedEdges(wall.X, wall.Y, wall.Orientation) do
			state.BlockedEdges[edge] = true
		end
		for _, segment in BoardUtils.wallSegments(wall.X, wall.Y, wall.Orientation) do
			state.OccupiedSegments[segment] = true
		end
	end
end

function BoardState.create(modeId: string, participants: { Participant }): BoardState
	local mode = GameConfig.Modes[modeId]
	assert(mode, "mod de joc necunoscut: " .. tostring(modeId))
	assert(
		#participants == mode.Players,
		string.format("modul %s cere %d jucatori, a primit %d", modeId, mode.Players, #participants)
	)

	local players: { [number]: PlayerState } = {}

	for slot, participant in participants do
		local slotConfig = mode.Slots[slot]
		players[slot] = {
			Slot = slot,
			UserId = participant.UserId,
			Name = participant.Name,
			Team = slotConfig.Team,
			Position = { X = slotConfig.Start.X, Y = slotConfig.Start.Y },
			BarricadesRemaining = mode.Barricades,
			Objective = slotConfig.Objective,
			Connected = true,
			Finished = false,
			TimeRemaining = GameConfig.Timing.PlayerClock,
		}
	end

	local state: BoardState = {
		Size = GameConfig.BoardSize,
		GameMode = modeId,
		Status = "STARTING",
		Players = players,
		TurnOrder = table.clone(mode.TurnOrder),
		TurnIndex = 1,
		TurnNumber = 1,
		Walls = {},
		BlockedEdges = {},
		OccupiedSegments = {},
		Winner = nil,
		WinningTeam = nil,
	}

	return state
end

function BoardState.getCurrentSlot(state: BoardState): number
	return state.TurnOrder[state.TurnIndex]
end

function BoardState.isPlayersTurn(state: BoardState, slot: number): boolean
	return BoardState.getCurrentSlot(state) == slot
end

function BoardState.advanceTurn(state: BoardState)
	state.TurnIndex += 1
	if state.TurnIndex > #state.TurnOrder then
		state.TurnIndex = 1
	end
	state.TurnNumber += 1
end

-- A ajuns jucatorul pe obiectivul lui? Pentru moduri pe echipe castiga echipa.
function BoardState.checkWinCondition(state: BoardState, slot: number): boolean
	local player = state.Players[slot]
	if not player then
		return false
	end
	return BoardUtils.isTargetCell(player.Objective, player.Position)
end

local function finish(state: BoardState, slot: number)
	local player = state.Players[slot]
	player.Finished = true
	state.Status = "FINISHED"
	state.Winner = slot
	state.WinningTeam = player.Team
end

--[[
	Aplica o mutare. Valideaza tot inainte; daca ceva nu e in regula, starea
	ramane neatinsa si tura NU trece mai departe.
]]
function BoardState.applyMove(state: BoardState, slot: number, target: any): Result
	-- Starea jocului se verifica inaintea turei: dupa fluierul final nimeni nu
	-- mai e "la rand", iar motivul corect e ca jocul s-a terminat.
	if state.Status ~= "PLAYING" then
		return fail("GAME_NOT_ACTIVE")
	end

	if not BoardState.isPlayersTurn(state, slot) then
		return fail("NOT_YOUR_TURN")
	end

	local check = MovementRules.isValidMove(state, slot, target)
	if not check.Ok then
		return check
	end

	local player = state.Players[slot]
	player.Position = { X = target.X, Y = target.Y }

	if BoardState.checkWinCondition(state, slot) then
		finish(state, slot)
		return { Ok = true }
	end

	BoardState.advanceTurn(state)
	return { Ok = true }
end

--[[
	Aplica o baricada. Baricada se consuma doar daca plasarea a fost acceptata;
	o incercare respinsa nu costa nimic si lasa jucatorul la mutare.
]]
function BoardState.applyWall(
	state: BoardState,
	slot: number,
	x: number,
	y: number,
	orientation: any
): Result
	if state.Status ~= "PLAYING" then
		return fail("GAME_NOT_ACTIVE")
	end

	if not BoardState.isPlayersTurn(state, slot) then
		return fail("NOT_YOUR_TURN")
	end

	local check = WallRules.isValidWallPlacement(state, slot, x, y, orientation)
	if not check.Ok then
		return check
	end

	local wall: Wall = { X = x, Y = y, Orientation = orientation, Owner = slot }
	state.Walls[BoardUtils.wallKey(x, y, orientation)] = wall

	for _, edge in BoardUtils.wallBlockedEdges(x, y, orientation) do
		state.BlockedEdges[edge] = true
	end
	for _, segment in BoardUtils.wallSegments(x, y, orientation) do
		state.OccupiedSegments[segment] = true
	end

	local player = state.Players[slot]
	player.BarricadesRemaining -= 1

	-- O baricada nu poate incheia jocul, deci nu se verifica victoria aici.
	BoardState.advanceTurn(state)
	return { Ok = true }
end

-- Echipele care mai au cel putin un jucator in joc.
function BoardState.getRemainingTeams(state: BoardState): { number }
	local seen: { [number]: boolean } = {}
	local teams: { number } = {}
	for _, slot in state.TurnOrder do
		local player = state.Players[slot]
		if player and not seen[player.Team] then
			seen[player.Team] = true
			table.insert(teams, player.Team)
		end
	end
	return teams
end

--[[
	Scoate un jucator din joc: a plecat si nu s-a mai intors.

	Pionul si baricadele lui raman pe tabla — sunt fapte deja intamplate — dar
	slotul iese din ordinea de tura. Indexul turei se corecteaza ca sa nu sara
	nimeni peste rand si ca sa nu ramana blocat pe un jucator inexistent.

	Daca mai ramane o singura echipa, aceea castiga.
]]
function BoardState.withdrawPlayer(state: BoardState, slot: number)
	local player = state.Players[slot]
	if not player then
		return
	end

	player.Connected = false

	local removedIndex: number? = nil
	for index, value in state.TurnOrder do
		if value == slot then
			removedIndex = index
			break
		end
	end

	if removedIndex then
		table.remove(state.TurnOrder, removedIndex)
		if removedIndex < state.TurnIndex then
			-- Cel plecat era inaintea celui la mutare; indicele s-a deplasat cu unu.
			state.TurnIndex -= 1
		end
		if state.TurnIndex > #state.TurnOrder then
			state.TurnIndex = 1
		end
	end

	if state.Status ~= "PLAYING" then
		return
	end

	local remainingTeams = BoardState.getRemainingTeams(state)
	if #remainingTeams <= 1 then
		state.Status = "FINISHED"
		state.WinningTeam = remainingTeams[1]
		-- Castigator nominal: primul jucator ramas din echipa care a rezistat.
		for _, remainingSlot in state.TurnOrder do
			state.Winner = remainingSlot
			break
		end
	end
end

--[[
	Consuma din ceasul jucatorului aflat la mutare.

	Timpul e o regula, nu o podoaba de interfata: cine ramane fara el pierde,
	exact ca la sah. De aceea scaderea traieste aici, langa celelalte reguli, si
	nu in server — asa poate fi si testata fara Roblox.

	Motorul nu are ceas propriu (n-are voie sa atinga `os` sau `task`), deci
	primeste cate secunde au trecut. Cine il cheama raspunde de cat de des.

	Intoarce slotul care tocmai a ramas fara timp, sau `nil`.
]]
function BoardState.chargeTime(state: BoardState, seconds: number): number?
	if state.Status ~= "PLAYING" then
		return nil
	end

	local slot = BoardState.getCurrentSlot(state)
	local player = state.Players[slot]
	if not player or player.Finished then
		return nil
	end

	player.TimeRemaining = math.max(0, player.TimeRemaining - seconds)
	if player.TimeRemaining > 0 then
		return nil
	end

	--[[
		Ramas fara timp inseamna iesit din meci, nu doar tura pierduta: altfel
		un jucator care nu mai e la tastatura ar bloca partida la nesfarsit,
		fiindca ceasul lui ar fi deja zero la fiecare tura care ii vine.
	]]
	BoardState.withdrawPlayer(state, slot)
	return slot
end

-- Distanta pana la obiectiv, pentru UI. nil daca nu exista drum.
function BoardState.getDistanceToGoal(state: BoardState, slot: number): number?
	local _, distance = Pathfinding.hasPathToGoal(state, slot)
	return distance
end

--[[
	Snapshot pentru replicare. Se trimit doar faptele; cache-urile se
	reconstruiesc pe client din aceleasi baricade, cu acelasi cod.
]]
function BoardState.snapshot(state: BoardState)
	local players = {}
	for slot, player in state.Players do
		players[#players + 1] = {
			Slot = slot,
			UserId = player.UserId,
			Name = player.Name,
			Team = player.Team,
			Position = { X = player.Position.X, Y = player.Position.Y },
			BarricadesRemaining = player.BarricadesRemaining,
			Objective = player.Objective,
			Connected = player.Connected,
			Finished = player.Finished,
			TimeRemaining = player.TimeRemaining,
		}
	end

	local walls = {}
	for _, wall in state.Walls do
		walls[#walls + 1] = {
			X = wall.X,
			Y = wall.Y,
			Orientation = wall.Orientation,
			Owner = wall.Owner,
		}
	end

	return {
		Size = state.Size,
		GameMode = state.GameMode,
		Status = state.Status,
		Players = players,
		TurnOrder = table.clone(state.TurnOrder),
		TurnIndex = state.TurnIndex,
		TurnNumber = state.TurnNumber,
		CurrentSlot = BoardState.getCurrentSlot(state),
		Walls = walls,
		Winner = state.Winner,
		WinningTeam = state.WinningTeam,
		PausedUntil = state.PausedUntil,
		PausedForSlot = state.PausedForSlot,
	}
end

-- Inversul lui snapshot. Clientul primeste un BoardState adevarat, nu o copie schioapa.
function BoardState.fromSnapshot(snapshot: any): BoardState
	local players: { [number]: PlayerState } = {}
	for _, player in snapshot.Players do
		players[player.Slot] = {
			Slot = player.Slot,
			UserId = player.UserId,
			Name = player.Name,
			Team = player.Team,
			Position = { X = player.Position.X, Y = player.Position.Y },
			BarricadesRemaining = player.BarricadesRemaining,
			Objective = player.Objective,
			Connected = player.Connected,
			Finished = player.Finished,
			-- Snapshot-urile vechi nu poarta ceasul; fara plasa asta, un client
			-- conectat peste o versiune mai veche ar primi nil si ar cadea.
			TimeRemaining = player.TimeRemaining or GameConfig.Timing.PlayerClock,
		}
	end

	local walls: { [string]: Wall } = {}
	for _, wall in snapshot.Walls do
		walls[BoardUtils.wallKey(wall.X, wall.Y, wall.Orientation)] = {
			X = wall.X,
			Y = wall.Y,
			Orientation = wall.Orientation,
			Owner = wall.Owner,
		}
	end

	local state: BoardState = {
		Size = snapshot.Size,
		GameMode = snapshot.GameMode,
		Status = snapshot.Status,
		Players = players,
		TurnOrder = snapshot.TurnOrder,
		TurnIndex = snapshot.TurnIndex,
		TurnNumber = snapshot.TurnNumber,
		Walls = walls,
		BlockedEdges = {},
		OccupiedSegments = {},
		Winner = snapshot.Winner,
		WinningTeam = snapshot.WinningTeam,
		PausedUntil = snapshot.PausedUntil,
		PausedForSlot = snapshot.PausedForSlot,
	}

	BoardState.rebuildCaches(state)
	return state
end

return BoardState
