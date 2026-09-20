--!strict
--[[
	Match — un meci in desfasurare.

	Tine starea tablei si o apara. Toata logica de reguli sta in motorul din
	Shared; aici e doar traducerea intre jucatori Roblox si sloturi, plus
	replicarea si ciclul de viata (numaratoare, pauza de reconectare, final).

	Serverul nu trimite niciodata clientului "ai voie sa muti". Trimite starea
	de dupa decizie. Clientul deseneaza ce primeste.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BoardState = require(Shared.BoardState)
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local Types = require(Shared.Types)

local Arena = require(script.Parent.Arena)
local Wallet = require(script.Parent.Parent.Services.Wallet)

type BoardState = Types.BoardState

local Match = {}
Match.__index = Match

--[[
	Campurile unui meci sunt declarate separat de metode.

	Fara asta, Luau deduce din tabelul din `Match.new` tipuri prea inguste —
	`PauseThread` ar ramane `nil` pentru totdeauna — si face `self` generic
	la fiecare metoda, ceea ce duce la doua tipuri `Match` care nu se
	recunosc intre ele. De aceea metodele se declara cu `self: Match` explicit.
]]
type MatchFields = {
	Id: string,
	ModeId: string,
	State: BoardState,
	PlayerBySlot: { [number]: Player? },
	SlotByUserId: { [number]: number },
	Finished: boolean,
	-- S-au dat banutii? Un meci se plateste o singura data.
	Paid: boolean,
	Destroyed: boolean,
	PauseThread: thread?,
	-- Firul care consuma ceasul celui aflat la mutare.
	ClockThread: thread?,
	-- Firul care strange masa dupa ecranul de victorie.
	CloseThread: thread?,
	--[[
		Masa fizica a meciului. Exista doar cand asseturile de lume sunt
		importate; pe varianta 2D meciul se joaca in intregime intr-un ScreenGui
		si nu are nimic de asezat in Workspace.
	]]
	Arena: Arena.Arena?,
}

export type Match = typeof(setmetatable({} :: MatchFields, Match))

local nextMatchId = 0

--[[
	`origin` spune unde se aseaza masa. Meciurile pornite din meniu nu-l dau si
	isi primesc coltul lor din sirul de arene; cel de free play il da, fiindca
	are un loc anume in lume, aratat de o piesa pusa acolo dinadins.
]]
function Match.new(modeId: string, players: { Player }, origin: CFrame?): Match
	nextMatchId += 1

	local participants = {}
	for index, player in players do
		participants[index] = { UserId = player.UserId, Name = player.DisplayName }
	end

	local self = setmetatable({
		Id = string.format("match-%d", nextMatchId),
		ModeId = modeId,
		State = BoardState.create(modeId, participants),
		PlayerBySlot = {},
		SlotByUserId = {},
		Finished = false,
		Paid = false,
		Destroyed = false,
		PauseThread = nil,
		ClockThread = nil,
		CloseThread = nil,
	}, Match) :: Match

	for slot, player in players do
		self.PlayerBySlot[slot] = player
		self.SlotByUserId[player.UserId] = slot
	end

	if Arena.isAvailable() then
		self.Arena = Arena.new(self.Id, origin)
		for _, player in players do
			-- Clientul isi gaseste tabla dupa atributul asta.
			player:SetAttribute("ArenaId", self.Id)
		end
	end

	return self
end

-- ------------------------------------------------------------- replicare

function Match.getParticipants(self: Match): { Player }
	local list: { Player } = {}
	for _, player in self.PlayerBySlot do
		if player and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function Match.broadcast(self: Match)
	if self.Destroyed then
		return
	end
	--[[
		Lumea se aduce la zi inaintea replicarii. Asa, cand clientul primeste
		starea, avatarele sunt deja pe celulele din ea si nu se vede niciun
		cadru in care tabla si starea spun lucruri diferite.

		Nu si cat se numara pana la start. Masa exista deja — se construieste
		odata cu meciul — dar jucatorii raman unde erau pana cade "unu". Asezati
		pe ea din prima clipa, numaratoarea se petrecea dupa ce ajungeai acolo,
		si nu mai anunta nimic: te trezeai pe tabla si abia apoi ti se spunea ca
		urmeaza sa incepi.
	]]
	if self.Arena and self.State.Status ~= "STARTING" then
		self.Arena:sync(self.State, self.PlayerBySlot)
	end

	local snapshot = BoardState.snapshot(self.State)
	local remote = Remotes.get("GameStateUpdate")
	for _, player in self:getParticipants() do
		remote:FireClient(player, snapshot)
	end
end

-- Evenimente punctuale: sunet, animatie, banner. Starea adevarata ramane snapshot-ul.
function Match.sendEvent(self: Match, payload: { [string]: any })
	if self.Destroyed then
		return
	end
	local remote = Remotes.get("MatchEvent")
	for _, player in self:getParticipants() do
		remote:FireClient(player, payload)
	end
end

-- Refuzul nu atinge starea meciului, deci nu are nevoie de `self`.
local function reject(player: Player, reason: string)
	Remotes.get("ActionRejected"):FireClient(player, reason)
end

-- ------------------------------------------------------------ ciclu de viata

function Match.start(self: Match)
	self.State.Status = "STARTING"
	self:broadcast()

	task.spawn(function()
		for remaining = GameConfig.Timing.StartCountdown, 1, -1 do
			if self.Destroyed then
				return
			end
			self:sendEvent({ Type = "Countdown", Value = remaining })
			task.wait(1)
		end

		if self.Destroyed or self.Finished then
			return
		end

		self.State.Status = "PLAYING"
		self:broadcast()
		self:sendEvent({ Type = "TurnChanged", Slot = BoardState.getCurrentSlot(self.State) })
		self:startClock()
	end)
end

--[[
	Consuma ceasul celui aflat la mutare, secunda cu secunda.

	Motorul tine regula si numarul, dar n-are ceas — nu are voie sa atinga
	`task` — deci bataia vine de aici. O secunda e si pasul de afisare: mai des
	n-ar schimba nimic pe ecran, mai rar s-ar vedea cifrele sarind.

	Cat meciul e in pauza, timpul nu curge: un jucator nu are de ce sa piarda
	pentru ca altcineva s-a deconectat.

	Se replica starea intreaga la fiecare bataie. Snapshot-ul e mic — o tabla si
	cateva baricade — iar alternativa, un canal separat doar pentru ceas, ar
	insemna doua adevaruri despre acelasi meci.
]]
function Match.startClock(self: Match)
	if self.ClockThread then
		return
	end

	self.ClockThread = task.spawn(function()
		while not self.Destroyed and not self.Finished do
			task.wait(1)
			if self.Destroyed or self.Finished then
				return
			end
			if self.State.Status ~= "PLAYING" or self:isPaused() then
				continue
			end

			local expired = BoardState.chargeTime(self.State, 1)
			if expired then
				local player = self.PlayerBySlot[expired]
				self:sendEvent({
					Type = "TimeOut",
					Slot = expired,
					Name = if player then player.DisplayName else "?",
				})
				--[[
					Retragerea poate incheia meciul, si atunci motorul numeste un
					castigator. Ne uitam la el, nu la `Status`: verificarea de mai
					sus l-a ingustat deja la "PLAYING", iar Luau ar respinge
					comparatia ca imposibila.
				]]
				if self.State.Winner ~= nil then
					self.Finished = true
				end
			end

			self:broadcast()
		end
	end)
end

function Match.isPaused(self: Match): boolean
	return self.State.PausedUntil ~= nil
end

--[[
	Plateste toata lumea de la masa, o singura data.

	Meciul stie *cine* a castigat, `Rewards` stie *cat* face asta, iar `Wallet`
	stie unde se pun banii. Niciunul din cele trei nu stie ce fac celelalte doua,
	si de-aia plata incape in sapte randuri.

	Se plateste la final, nu pe drum, iar `Paid` se ridica inainte de prima
	plata: daca meciul s-ar incheia de doua ori — o retragere care declanseaza
	victoria peste un ceas care expira in acelasi cadru — banii s-ar da de doua
	ori pentru acelasi meci.

	Cine a plecat inainte de fluier nu mai e la masa si nu primeste. E de
	discutat, dar nu e o scapare: altfel iesirea imediat dupa ce vezi ca pierzi
	ar plati la fel ca ramasul pana la capat.
]]
local function payout(self: Match)
	if self.Paid then
		return
	end
	self.Paid = true

	for slot, player in self.PlayerBySlot do
		local playerState = self.State.Players[slot]
		if player and player.Parent and playerState then
			local outcome: Rewards.Outcome =
				Rewards.outcomeFor(self.State.WinningTeam, playerState.Team)
			Wallet.award(player, Rewards.forMatch(outcome), "match")
		end
	end
end

local function finishIfOver(self: Match): boolean
	if self.State.Status ~= "FINISHED" or self.Finished then
		return self.Finished
	end

	self.Finished = true
	self:broadcast()

	--[[
		Ceremonia vine dupa ultima replicare, nu inaintea ei.

		`broadcast` aseaza intai avatarele pe celulele din starea finala; abia
		apoi are sens sa iasa soclul de sub castigator, chiar din patratul pe
		care a castigat. Invers, soclul ar fi urcat de sub un jucator pe care
		sincronizarea urma sa-l mai mute o data.
	]]
	if self.Arena then
		self.Arena:celebrate(self.State.Winner)
	end

	self:sendEvent({
		Type = "Victory",
		Winner = self.State.Winner,
		WinningTeam = self.State.WinningTeam,
	})
	payout(self)

	--[[
		Masa se strange singura dupa fluierul final.

		Pana acum astepta ca *toti* jucatorii sa apese "Leave", si cine inchidea
		ecranul de victorie fara sa apese ramanea inghetat pe o platforma care nu
		mai avea meci — cu mersul taiat, fiindca `Arena` il taie la asezare, si
		fara nimic care sa i-l dea inapoi. `Arena:destroy` face amandoua: darama
		masa si trimite oamenii inapoi in lobby, cu pasul redat.

		Meciul insusi ramane in registru. Ecranul de victorie inca are ce arata,
		iar revansa inca are din ce mod sa porneasca; dispare cand pleaca si
		ultimul, ca pana acum.
	]]
	self.CloseThread = task.delay(GameConfig.Timing.VictoryHold, function()
		self.CloseThread = nil
		if self.Destroyed or not self.Arena then
			return
		end
		self.Arena:destroy()
		self.Arena = nil
	end)

	return true
end

-- --------------------------------------------------------------- actiuni

--[[
	Poarta comuna a oricarei cereri: e jucatorul in meciul asta, e meciul in
	desfasurare si nu e in pauza? Slotul intors e singura identitate in care
	are incredere restul codului — niciodata ce trimite clientul.
]]
function Match.resolveSlot(self: Match, player: Player): (number?, string?)
	local slot = self.SlotByUserId[player.UserId]
	if not slot then
		return nil, "NOT_IN_MATCH"
	end
	if self.State.Status ~= "PLAYING" then
		return nil, "GAME_NOT_ACTIVE"
	end
	if self:isPaused() then
		return nil, "MATCH_PAUSED"
	end
	return slot, nil
end

function Match.handleMove(self: Match, player: Player, target: any)
	local slot, blocked = self:resolveSlot(player)
	if not slot then
		reject(player, blocked :: string)
		return
	end

	local from = self.State.Players[slot].Position
	local previousFrom = { X = from.X, Y = from.Y }

	local result = BoardState.applyMove(self.State, slot, target)
	if not result.Ok then
		reject(player, result.Reason :: string)
		return
	end

	self:broadcast()
	self:sendEvent({
		Type = "MoveApplied",
		Slot = slot,
		From = previousFrom,
		To = { X = self.State.Players[slot].Position.X, Y = self.State.Players[slot].Position.Y },
	})

	if not finishIfOver(self) then
		self:sendEvent({ Type = "TurnChanged", Slot = BoardState.getCurrentSlot(self.State) })
	end
end

function Match.handleWall(self: Match, player: Player, x: any, y: any, orientation: any)
	local slot, blocked = self:resolveSlot(player)
	if not slot then
		reject(player, blocked :: string)
		return
	end

	local result = BoardState.applyWall(self.State, slot, x, y, orientation)
	if not result.Ok then
		reject(player, result.Reason :: string)
		return
	end

	self:broadcast()
	self:sendEvent({
		Type = "WallPlaced",
		Slot = slot,
		Wall = { X = x, Y = y, Orientation = orientation },
	})
	self:sendEvent({ Type = "TurnChanged", Slot = BoardState.getCurrentSlot(self.State) })
end

-- ------------------------------------------------ deconectare si reconectare

local function withdraw(self: Match, slot: number)
	local player = self.PlayerBySlot[slot]
	if player then
		self.SlotByUserId[player.UserId] = nil
		self.PlayerBySlot[slot] = nil
	end

	self.State.PausedUntil = nil
	self.State.PausedForSlot = nil
	BoardState.withdrawPlayer(self.State, slot)

	self:broadcast()
	if not finishIfOver(self) then
		self:sendEvent({ Type = "PlayerLeft", Slot = slot })
		self:sendEvent({ Type = "TurnChanged", Slot = BoardState.getCurrentSlot(self.State) })
	end
end

--[[
	Un jucator a parasit serverul in timpul meciului.

	Comportamentul e configurabil, fiindca cele doua variante sunt potrivite
	pentru lucruri diferite: FORFEIT tine rundele scurte, PAUSE iarta o
	deconectare scurta. Ce nu se intampla niciodata: meciul nu ramane
	blocat la nesfarsit asteptand pe cineva care nu se mai intoarce.
]]
function Match.handleDisconnect(self: Match, player: Player)
	local slot = self.SlotByUserId[player.UserId]
	if not slot or self.Finished then
		return
	end

	if self.State.Status ~= "PLAYING" or GameConfig.Reconnect.Mode == "FORFEIT" then
		withdraw(self, slot)
		return
	end

	self.State.Players[slot].Connected = false
	self.State.PausedUntil = os.time() + GameConfig.Reconnect.GraceSeconds
	self.State.PausedForSlot = slot
	self.PlayerBySlot[slot] = nil

	self:broadcast()
	self:sendEvent({ Type = "Paused", Slot = slot, Until = self.State.PausedUntil })

	self.PauseThread = task.delay(GameConfig.Reconnect.GraceSeconds, function()
		self.PauseThread = nil
		if self.Destroyed or self.Finished then
			return
		end
		-- Rabdarea s-a terminat: meciul merge mai departe fara el.
		withdraw(self, slot)
	end)
end

-- Acelasi UserId s-a intors inainte sa expire rabdarea.
function Match.tryReconnect(self: Match, player: Player): boolean
	local slot = self.SlotByUserId[player.UserId]
	if not slot or self.Finished then
		return false
	end
	if self.State.PausedForSlot ~= slot then
		return false
	end

	if self.PauseThread then
		task.cancel(self.PauseThread)
		self.PauseThread = nil
	end
	if self.ClockThread then
		task.cancel(self.ClockThread)
		self.ClockThread = nil
	end

	self.PlayerBySlot[slot] = player
	self.State.Players[slot].Connected = true
	self.State.PausedUntil = nil
	self.State.PausedForSlot = nil

	self:broadcast()
	self:sendEvent({ Type = "Resumed", Slot = slot })
	return true
end

function Match.destroy(self: Match)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if self.PauseThread then
		task.cancel(self.PauseThread)
		self.PauseThread = nil
	end
	if self.CloseThread then
		task.cancel(self.CloseThread)
		self.CloseThread = nil
	end
	if self.Arena then
		self.Arena:destroy()
		self.Arena = nil
	end
	self.PlayerBySlot = {}
	self.SlotByUserId = {}
end

return Match
