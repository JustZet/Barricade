--!strict
--[[
	MatchmakingManager — o coada simpla pe fiecare mod.

	Deliberat necomplicat, exact cat cere prima versiune: intri intr-o coada,
	cand se strang destui pleaca meciul. Fara rating, fara regiuni, fara
	rezervari intre servere. Tot ce trebuie sa fie corect aici e ca un jucator
	sa nu ajunga in doua cozi sau in doua meciuri deodata.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local MatchManager = require(script.Parent.MatchManager)

local MatchmakingManager = {}

-- modeId -> lista de jucatori, in ordinea intrarii
local queues: { [string]: { Player } } = {}
local queueByUserId: { [number]: string } = {}

for _, modeId in GameConfig.ModeOrder do
	queues[modeId] = {}
end

local function queueSnapshot(modeId: string)
	local mode = GameConfig.Modes[modeId]
	local names = {}
	for _, player in queues[modeId] do
		table.insert(names, player.DisplayName)
	end
	return {
		Mode = modeId,
		Needed = mode.Players,
		Names = names,
	}
end

-- Le spune celor din coada cati sunt si cati mai lipsesc.
local function publishQueue(modeId: string)
	local snapshot = queueSnapshot(modeId)
	local remote = Remotes.get("LobbyUpdate")
	for _, player in queues[modeId] do
		remote:FireClient(player, snapshot)
	end
end

local function removeFromQueue(player: Player): string?
	local modeId = queueByUserId[player.UserId]
	if not modeId then
		return nil
	end

	local queue = queues[modeId]
	for index, queued in queue do
		if queued == player then
			table.remove(queue, index)
			break
		end
	end

	queueByUserId[player.UserId] = nil
	return modeId
end

--[[
	Cand coada s-a umplut, primii N pleaca la meci. Ordinea de intrare devine
	ordinea sloturilor, deci si a echipelor in 2v2 — simplu si previzibil.
]]
local function startIfReady(modeId: string)
	local mode = GameConfig.Modes[modeId]
	local queue = queues[modeId]

	while #queue >= mode.Players do
		local group: { Player } = {}
		for _ = 1, mode.Players do
			local player = table.remove(queue, 1) :: Player
			queueByUserId[player.UserId] = nil
			table.insert(group, player)
		end

		-- Cine a plecat intre timp anuleaza formarea; ceilalti se intorc in fata cozii.
		local allPresent = true
		for _, player in group do
			if not player.Parent then
				allPresent = false
				break
			end
		end

		if allPresent then
			MatchManager.create(modeId, group)
		else
			for index = #group, 1, -1 do
				local player = group[index]
				if player.Parent then
					table.insert(queue, 1, player)
					queueByUserId[player.UserId] = modeId
				end
			end
			break
		end
	end

	publishQueue(modeId)
end

function MatchmakingManager.join(player: Player, modeId: any)
	if type(modeId) ~= "string" or not GameConfig.Modes[modeId] then
		Remotes.get("ActionRejected"):FireClient(player, "UNKNOWN_MODE")
		return
	end

	if MatchManager.getForPlayer(player) then
		Remotes.get("ActionRejected"):FireClient(player, "ALREADY_IN_MATCH")
		return
	end

	local previous = removeFromQueue(player)
	if previous and previous ~= modeId then
		publishQueue(previous)
	end

	table.insert(queues[modeId], player)
	queueByUserId[player.UserId] = modeId
	startIfReady(modeId)
end

function MatchmakingManager.leave(player: Player)
	local modeId = removeFromQueue(player)
	if modeId then
		publishQueue(modeId)
		Remotes.get("LobbyUpdate"):FireClient(player, { Mode = modeId, Needed = 0, Names = {} })
	end
end

function MatchmakingManager.isQueued(player: Player): boolean
	return queueByUserId[player.UserId] ~= nil
end

return MatchmakingManager
