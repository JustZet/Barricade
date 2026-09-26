--!strict
--[[
	Rematch — votul de revansa la aceeasi masa, pe server.

	Regula e in `RematchVote`, in motorul pur; aici e doar ce nu poate sta
	acolo: ceasul, jucatorii, masa si mesajele. Fiecare cerere trece prin trei
	intrebari, in ordinea asta: e jucatorul la o masa incheiata, mai sunt toti
	cei de la masa acolo, si ce spune votul.

	Primul care cere deschide votul. Ceilalti raspund cu aceeasi cerere (da) sau
	cu refuzul. Toti da → meci nou cu aceiasi oameni, in acelasi mod, fara coada,
	cu locurile rotite. Oricine spune nu, pleaca sau lasa timpul sa treaca →
	votul se inchide pentru toti, iar masa nu mai primeste altul: o revansa
	refuzata nu se mai cere in bucla.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local RematchVote = require(Shared.RematchVote)
local Remotes = require(Shared.Remotes)

local MatchManager = require(script.Parent.MatchManager)
local MatchmakingManager = require(script.Parent.MatchmakingManager)

local Rematch = {}

type Ballot = {
	Vote: RematchVote.Vote,
	-- Jucatorii de la masa, in ordinea sloturilor, cum erau cand s-a deschis votul.
	Players: { Player },
	Expiry: thread?,
}

-- Un vot per masa, dupa id-ul meciului. Ramane si dupa inchidere, ca sa nu se mai deschida altul.
local ballots: { [string]: Ballot } = {}

local function clock(): number
	return os.clock()
end

local function reject(player: Player, reason: string)
	Remotes.get("ActionRejected"):FireClient(player, reason)
end

--[[
	Cine mai sta la masa: fiecare slot are un om, omul e inca in server si tot
	meciul asta il tine. Daca lipseste unul, masa nu mai e intreaga si revansa
	nu mai are cu cine se juca.
]]
local function seatsOf(match: any): { Player }?
	local players: { Player } = {}
	for slot = 1, #match.State.Players do
		local player = match.PlayerBySlot[slot]
		if not player or not player.Parent or MatchManager.getForPlayer(player) ~= match then
			return nil
		end
		table.insert(players, player)
	end
	if #players < 2 then
		return nil
	end
	return players
end

-- Numele afisat al unui userId de la masa.
local function nameOf(ballot: Ballot, userId: number?): string
	for _, player in ballot.Players do
		if player.UserId == userId then
			return player.DisplayName
		end
	end
	return "A player"
end

--[[
	Starea votului, trimisa celor care mai sunt la masa. Clientul deseneaza din
	ea tot: bannerul, bara, avatarele aprinse si butoanele.
]]
local function publish(match: any, ballot: Ballot)
	local vote = ballot.Vote
	local accepted, remaining = RematchVote.progress(vote, clock())
	local seats = {}
	local yes = {}
	for _, player in ballot.Players do
		table.insert(seats, { UserId = player.UserId, Name = player.DisplayName })
		if vote.Accepted[player.UserId] then
			table.insert(yes, player.UserId)
		end
	end

	local payload = {
		Type = "Rematch",
		Status = vote.Status,
		Reason = vote.Reason,
		ByName = if vote.By then nameOf(ballot, vote.By) else nil,
		RequesterName = nameOf(ballot, vote.Requester),
		Seats = seats,
		Accepted = yes,
		AcceptedCount = accepted,
		Remaining = remaining,
		Window = GameConfig.Timing.RematchWindow,
	}

	local remote = Remotes.get("MatchEvent")
	for _, player in ballot.Players do
		if player.Parent and MatchManager.getForPlayer(player) == match then
			remote:FireClient(player, payload)
		end
	end
end

-- Cati sunt intr-o echipa: pasul rotatiei, ca echipele sa ramana intregi.
local function teamSize(modeId: string): number
	local mode = GameConfig.Modes[modeId]
	if not mode then
		return 1
	end
	local first = mode.Slots[1].Team
	local size = 0
	for _, slot in mode.Slots do
		if slot.Team == first then
			size += 1
		end
	end
	return math.max(size, 1)
end

--[[
	Toti au zis da: masa veche se strange, iar pe acelasi loc se aseaza una noua,
	cu aceiasi oameni, rotiti. Seria merge mai departe.

	Masa veche se darama inainte sa se ridice cea noua, fiindca stau in acelasi
	loc. Jucatorii ajung o clipa in lobby — exact ca la orice meci din coada — si
	se intorc la masa cand se termina numaratoarea.
]]
local function start(match: any, ballot: Ballot)
	local players = RematchVote.rotate(ballot.Players, teamSize(match.ModeId))
	local origin = if match.Arena then match.Arena:origin() else nil
	local series = match.Series
	local modeId = match.ModeId

	if ballot.Expiry then
		task.cancel(ballot.Expiry)
		ballot.Expiry = nil
	end

	for _, player in players do
		MatchmakingManager.leave(player)
	end
	ballots[match.Id] = nil
	MatchManager.destroy(match)
	MatchManager.create(modeId, players, origin, series)
end

--[[
	Voturile meselor care nu mai exista. Masa se strange din alta parte — la
	`VictoryHold`, sau cand pleaca ultimul — si nu anunta aici; se matura la
	urmatoarea cerere, ca registrul sa nu creasca la nesfarsit.
]]
local function sweep()
	for matchId, ballot in ballots do
		if not MatchManager.getById(matchId) then
			if ballot.Expiry then
				task.cancel(ballot.Expiry)
			end
			ballots[matchId] = nil
		end
	end
end

local function settle(match: any, ballot: Ballot)
	publish(match, ballot)
	if ballot.Vote.Status == "Accepted" then
		start(match, ballot)
	elseif ballot.Vote.Status == "Cancelled" and ballot.Expiry then
		if ballot.Expiry ~= coroutine.running() then
			task.cancel(ballot.Expiry)
		end
		ballot.Expiry = nil
	end
end

--[[
	„Rematch": deschide votul, sau spune da la cel deschis deja.
]]
function Rematch.request(player: Player)
	sweep()
	local match: any = MatchManager.getForPlayer(player)
	if not match or not match.Finished or match.Destroyed then
		reject(player, "REMATCH_UNAVAILABLE")
		return
	end

	local ballot = ballots[match.Id]
	if ballot then
		local ok, reason = RematchVote.accept(ballot.Vote, player.UserId, clock())
		if not ok then
			reject(player, "REMATCH_" .. (reason or "REFUSED"))
			return
		end
		settle(match, ballot)
		return
	end

	local seats = seatsOf(match)
	if not seats then
		reject(player, "REMATCH_UNAVAILABLE")
		return
	end

	local userIds = {}
	for _, seat in seats do
		table.insert(userIds, seat.UserId)
	end

	local window = GameConfig.Timing.RematchWindow
	local vote, reason = RematchVote.open(userIds, player.UserId, clock(), window)
	if not vote then
		reject(player, "REMATCH_" .. (reason or "REFUSED"))
		return
	end

	local opened: Ballot = { Vote = vote, Players = seats, Expiry = nil }
	ballots[match.Id] = opened

	--[[
		Ceasul votului. Se trezeste la termen si il inchide daca inca astepta;
		daca s-a inchis intre timp, n-are ce face.
	]]
	opened.Expiry = task.delay(window, function()
		opened.Expiry = nil
		if
			RematchVote.tick(opened.Vote, clock()) == "Cancelled"
			and opened.Vote.Reason == "EXPIRED"
		then
			publish(match, opened)
		end
	end)

	settle(match, opened)
end

-- „Decline": nu, pentru toti.
function Rematch.decline(player: Player)
	local match: any = MatchManager.getForPlayer(player)
	local ballot = match and ballots[match.Id]
	if not (match and ballot) then
		return
	end
	local ok = RematchVote.decline(ballot.Vote, player.UserId, clock())
	if ok then
		settle(match, ballot)
	end
end

--[[
	Cineva pleaca de la masa — din buton sau din server. Se cheama inainte ca
	registrul sa-l uite, ca vestea sa ajunga si la ceilalti.
]]
function Rematch.leave(player: Player)
	local match: any = MatchManager.getForPlayer(player)
	local ballot = match and ballots[match.Id]
	if not (match and ballot) then
		return
	end
	if RematchVote.leave(ballot.Vote, player.UserId, clock()) then
		settle(match, ballot)
	end
end

return Rematch
