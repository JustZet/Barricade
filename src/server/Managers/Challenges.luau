--!strict
--[[
	Challenges — provocarile directe, pe server, si unde se afla fiecare jucator.

	Regula e in `Challenge`; aici e ceasul, registrul si mesajele. Tot aici se
	tine la zi atributul `Presence` al fiecarui jucator — "MATCH", "QUEUE" sau
	nimic — pe care clientul il scrie pe carduri ca „In a match" / „In queue".
	E acelasi fapt de care are nevoie si validarea, deci il socoteste un singur
	loc.

	Nimic nu se ia de la client pe cuvant: cine provoaca e argumentul `player`,
	cei provocati se cauta dupa userId printre cei din server, iar starea lor
	(meci, coada, alta provocare, cooldown) se afla aici.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Challenge = require(Shared.Challenge)
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local MatchManager = require(script.Parent.MatchManager)
local MatchmakingManager = require(script.Parent.MatchmakingManager)

local SETTINGS = GameConfig.Social

local Challenges = {}

local open: { [string]: Challenge.Challenge } = {}
-- Cine e deja intr-o provocare deschisa, si in care.
local engaged: { [number]: string } = {}
local cooldowns: { [string]: number } = {}
-- Numele de la deschidere, ca vestea sa-l poata spune si dupa ce omul a plecat.
local names: { [number]: string } = {}
local nextId = 0

local PRESENCE = "Presence"

local function clock(): number
	return os.clock()
end

local function presenceOf(player: Player): string?
	if MatchManager.getForPlayer(player) then
		return "MATCH"
	end
	if MatchmakingManager.isQueued(player) then
		return "QUEUE"
	end
	return nil
end

-- Starea unei provocari, trimisa tuturor celor implicati care mai sunt in server.
local function publish(challenge: Challenge.Challenge)
	local invitees = {}
	local accepted = {}
	for _, userId in challenge.Invitees do
		table.insert(invitees, { UserId = userId, Name = names[userId] or "?" })
		if challenge.Accepted[userId] then
			table.insert(accepted, userId)
		end
	end

	local payload = {
		Type = "Challenge",
		Id = challenge.Id,
		Status = challenge.Status,
		Reason = challenge.Reason,
		ByName = if challenge.By then names[challenge.By] else nil,
		Mode = challenge.Mode,
		From = { UserId = challenge.From, Name = names[challenge.From] or "?" },
		Invitees = invitees,
		Accepted = accepted,
		Remaining = math.max(0, challenge.Deadline - clock()),
		Window = SETTINGS.ChallengeWindow,
	}

	local remote = Remotes.get("SocialEvent")
	for _, userId in Challenge.members(challenge) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			remote:FireClient(player, payload)
		end
	end
end

-- O provocare inchisa se scoate din registru; refuzul lasa in urma cooldown-ul.
local function close(challenge: Challenge.Challenge)
	local key, blockedUntil =
		Challenge.cooldownAfter(challenge, clock(), SETTINGS.ChallengeCooldown)
	if key and blockedUntil then
		cooldowns[key] = blockedUntil
	end
	for _, userId in Challenge.members(challenge) do
		if engaged[userId] == challenge.Id then
			engaged[userId] = nil
		end
	end
	open[challenge.Id] = nil
end

--[[
	Toti au zis da: meciul porneste direct, fara coada. Ordinea sloturilor e cea
	din provocare — cel care provoaca primul, apoi invitatii in ordinea aleasa —
	deci in 2v2 el joaca in echipa cu primul ales.
]]
local function start(challenge: Challenge.Challenge)
	local players: { Player } = {}
	for _, userId in Challenge.members(challenge) do
		local player = Players:GetPlayerByUserId(userId)
		if not player or presenceOf(player) ~= nil then
			challenge.Status = "Cancelled"
			challenge.Reason = "UNAVAILABLE"
			challenge.By = userId
			publish(challenge)
			close(challenge)
			return
		end
		table.insert(players, player)
	end

	close(challenge)
	for _, player in players do
		MatchmakingManager.leave(player)
	end
	MatchManager.create(challenge.Mode, players)
end

local function settle(challenge: Challenge.Challenge)
	publish(challenge)
	if challenge.Status == "Accepted" then
		start(challenge)
	elseif not Challenge.isOpen(challenge) then
		close(challenge)
	end
end

local function reject(player: Player, reason: string)
	Remotes.get("ActionRejected"):FireClient(player, "CHALLENGE_" .. reason)
end

--[[
	O provocare noua. `modeId` si `invitees` vin de la client, deci se verifica
	intai forma lor, apoi tot restul prin `Challenge.validate`.
]]
function Challenges.request(player: Player, modeId: any, invitees: any)
	local mode = if type(modeId) == "string" then GameConfig.Modes[modeId] else nil
	if not mode or type(invitees) ~= "table" or #invitees > 3 then
		reject(player, "BAD_REQUEST")
		return
	end

	local list: { number } = {}
	for _, userId in invitees do
		if type(userId) ~= "number" then
			reject(player, "BAD_REQUEST")
			return
		end
		table.insert(list, userId)
	end

	local present: { [number]: boolean } = {}
	local busy: { [number]: string? } = {}
	for _, other in Players:GetPlayers() do
		present[other.UserId] = true
		busy[other.UserId] = presenceOf(other)
		names[other.UserId] = other.DisplayName
	end
	local busyEngaged: { [number]: boolean } = {}
	for userId in engaged do
		busyEngaged[userId] = true
	end

	local ok, reason = Challenge.validate({
		From = player.UserId,
		Invitees = list,
		Players = mode.Players,
		Present = present,
		Busy = busy,
		Engaged = busyEngaged,
		Cooldowns = cooldowns,
		Now = clock(),
	})
	if not ok then
		reject(player, reason or "REFUSED")
		return
	end

	nextId += 1
	local id = string.format("challenge-%d", nextId)
	local challenge =
		Challenge.new(id, player.UserId, list, mode.Id, clock(), SETTINGS.ChallengeWindow)
	open[id] = challenge
	for _, userId in Challenge.members(challenge) do
		engaged[userId] = id
	end
	publish(challenge)
end

-- Da sau nu, de la un invitat.
function Challenges.answer(player: Player, id: any, accept: any)
	local challenge = if type(id) == "string" then open[id] else nil
	if not challenge then
		return
	end
	local ok = if accept == true
		then Challenge.accept(challenge, player.UserId, clock())
		else Challenge.decline(challenge, player.UserId, clock())
	if ok then
		settle(challenge)
	end
end

-- Cel care a provocat renunta.
function Challenges.cancel(player: Player, id: any)
	local challenge = if type(id) == "string" then open[id] else nil
	if challenge and Challenge.cancel(challenge, player.UserId, clock()) then
		settle(challenge)
	end
end

--[[
	O bataie: prezenta fiecarui jucator, si provocarile care au expirat sau in
	care cineva nu mai e liber. Se face la interval, nu la fiecare cerere —
	intrarea in coada sau intr-un meci nu anunta pe nimeni, si nici n-ar trebui
	sa stie de provocari.
]]
local function beat()
	for _, player in Players:GetPlayers() do
		local presence = presenceOf(player)
		if player:GetAttribute(PRESENCE) ~= presence then
			player:SetAttribute(PRESENCE, presence)
		end
	end

	local now = clock()
	for _, challenge in open do
		local changed = false
		if Challenge.tick(challenge, now) ~= "Requested" then
			changed = true
		else
			for _, userId in Challenge.members(challenge) do
				local player = Players:GetPlayerByUserId(userId)
				if not player or presenceOf(player) ~= nil then
					changed = Challenge.drop(challenge, userId, now)
					break
				end
			end
		end
		if changed then
			settle(challenge)
		end
	end
end

function Challenges.start()
	local since = 0
	RunService.Heartbeat:Connect(function(delta: number)
		since += delta
		if since < SETTINGS.PresenceInterval then
			return
		end
		since = 0
		beat()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local id = engaged[player.UserId]
		local challenge = if id then open[id] else nil
		if challenge and Challenge.drop(challenge, player.UserId, clock()) then
			settle(challenge)
		end
	end)
end

return Challenges
