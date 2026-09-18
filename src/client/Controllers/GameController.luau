--!strict
--[[
	GameController — creierul clientului.

	Tine ultima stare primita de la server, decide ce ecran se vede si
	traduce atingerile in cereri. Nu decide niciodata rezultatul unei actiuni:
	trimite cererea si asteapta noua stare.

	Regulile pe care le consulta pentru evidentieri si previzualizari sunt
	*exact* aceleasi module pe care le ruleaza serverul. De aceea
	previzualizarea verde/rosie nu minte aproape niciodata — iar cand
	minte, fiindca starea locala e cu o fractiune de secunda in urma,
	serverul refuza si jucatorul vede motivul.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BoardState = require(Shared.BoardState)
local MovementRules = require(Shared.MovementRules)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local WallRules = require(Shared.WallRules)

local SoundController = require(script.Parent.SoundController)
local InputController = require(script.Parent.InputController)

type BoardState = Types.BoardState

local LOCAL_PLAYER = Players.LocalPlayer

-- Codurile de refuz sunt pentru cod; oamenii primesc propozitii.
local REJECTION_TEXT: { [string]: string } = {
	NOT_YOUR_TURN = "It is not your turn.",
	ILLEGAL_MOVE = "You cannot move there.",
	OUT_OF_BOUNDS = "Outside the board.",
	SAME_CELL = "You are already on that square.",
	BAD_COORDINATES = "Invalid coordinates.",
	BAD_ORIENTATION = "Invalid orientation.",
	WALL_CONFLICT = "Barricades cannot overlap or cross.",
	NO_BARRICADES_LEFT = "You have no barricades left.",
	GAME_NOT_ACTIVE = "The match is not running.",
	MATCH_PAUSED = "The match is paused, waiting for a player.",
	NOT_IN_MATCH = "You are not in a match.",
	ALREADY_IN_MATCH = "You are already in a match.",
	UNKNOWN_MODE = "Unknown game mode.",
	BAD_REQUEST = "Invalid request.",
	-- Refuzurile magazinului. Ecranul stinge butonul dinainte, deci aici ajung
	-- doar cazurile in care serverul stia altceva decat clientul.
	PURCHASE_UNKNOWN = "That item does not exist.",
	PURCHASE_OWNED = "You already own that.",
	PURCHASE_POOR = "You do not have enough coins.",
	PURCHASE_NOT_FOR_SALE = "That item is not for sale yet.",
	PURCHASE_REFUSED = "Purchase refused.",
}

local GameController = {}
GameController.__index = GameController

--[[
	Vederile sunt tinute ca tabel liber de obiecte: controllerul le comanda,
	dar nu depinde de structura lor interna. Asa se poate schimba o vedere
	fara sa se atinga logica.
]]
type ControllerFields = {
	Views: { [string]: any },
	State: BoardState?,
	LocalSlot: number?,
	Mode: string,
	Orientation: string,
	Hovered: { X: number, Y: number }?,
	MatchSignature: string?,
}

export type GameController = typeof(setmetatable({} :: ControllerFields, GameController))

function GameController.new(views: { [string]: any }): GameController
	local self = setmetatable({}, GameController) :: GameController

	self.Views = views
	self.State = nil :: BoardState?
	self.LocalSlot = nil :: number?
	self.Mode = "MOVE"
	self.Orientation = "Horizontal"
	self.Hovered = nil :: { X: number, Y: number }?
	self.MatchSignature = nil :: string?

	self:wireViews()
	self:wireRemotes()

	InputController.bind({
		onRotate = function()
			self:rotate()
		end,
		onCancel = function()
			self:setMode("MOVE")
		end,
		onMoveMode = function()
			self:setMode("MOVE")
		end,
		--[[
			Rotita face, in fiecare mod, singurul lucru care are rost acolo.

			Cu baricada in mana o roteste. Asta e miscarea pe care o faci de zeci
			de ori intr-o partida, si degetul e deja pe rotita; comutarea pe mutare
			e ceva ce faci o data si stii dinainte ca o faci, deci are butonul ei,
			tasta `M` si `Escape`.

			Din mutare te duce pe baricada, fiindca acolo n-are ce roti. Trece prin
			`setMode`, deci primeste aceleasi refuzuri ca butonul: cine n-are
			baricade ramane pe mutare si i se spune de ce.
		]]
		onCycleMode = function()
			if self.Mode == "WALL" then
				self:rotate()
			else
				self:setMode("WALL")
			end
		end,
	})

	views.Lobby:showHome()
	return self
end

-- ------------------------------------------------------------- legaturi

function GameController.wireViews(self: GameController)
	local views = self.Views

	views.Lobby:setCallbacks({
		onSelectMode = function(modeId: string)
			Remotes.get("RequestJoinQueue"):FireServer(modeId)
		end,
		onCancel = function()
			Remotes.get("RequestLeaveQueue"):FireServer()
			views.Lobby:showHome()
		end,
		onOpenStore = function()
			if views.Store then
				views.Store:show()
			end
		end,
	})

	--[[
		Cumpararea pleaca doar ca id. Pretul, banii si ce detii sunt toate ale
		serverului; el raspunde prin `WalletUpdate` si `InventoryUpdate`, iar
		ecranul se deseneaza din ce primeste. Butonul nu scade nimic singur.
	]]
	if views.Store then
		views.Store:on("onPurchase", function(kind: string, itemId: string)
			Remotes.get("RequestPurchase"):FireServer(kind, itemId)
		end)
	end

	views.Board:setCallbacks({
		onCell = function(cell)
			Remotes.get("RequestMove"):FireServer(cell)
		end,
		onWallSlot = function(x: number, y: number, orientation: string)
			Remotes.get("RequestPlaceWall"):FireServer(x, y, orientation)
		end,
		onWallHover = function(x: number, y: number, orientation: string)
			self:previewWall(x, y, orientation)
		end,
	})

	views.Hud:setCallbacks({
		onMode = function(mode: string)
			self:setMode(mode)
		end,
		onRotate = function()
			self:rotate()
		end,
		onToggleSound = function()
			views.Hud:setSoundEnabled(SoundController.toggle())
		end,
		--[[
			Perspectiva o tine lumea, nu interfata. Butonul doar cere schimbarea si
			isi scrie eticheta din ce raspunde ea, ca sa nu existe doua pareri
			despre cum se priveste masa acum.

			Fara masa n-are ce comuta: pe varianta 2D nu exista camera de asezat.
		]]
		onToggleView = function()
			local world = views.World
			if world then
				views.Hud:setTopDown(world:toggleView())
			end
		end,
		onLeave = function()
			self:leaveMatch()
		end,
	})

	views.Victory:setCallbacks({
		onRematch = function()
			views.Victory:hide()
			Remotes.get("RequestRematch"):FireServer()
		end,
		onLeave = function()
			views.Victory:hide()
			self:leaveMatch()
		end,
	})
end

function GameController.wireRemotes(self: GameController)
	Remotes.get("GameStateUpdate").OnClientEvent:Connect(function(snapshot)
		self:onState(snapshot)
	end)

	Remotes.get("LobbyUpdate").OnClientEvent:Connect(function(payload)
		self:onLobby(payload)
	end)

	Remotes.get("MatchEvent").OnClientEvent:Connect(function(payload)
		self:onEvent(payload)
	end)

	Remotes.get("ActionRejected").OnClientEvent:Connect(function(reason: string)
		self:onRejected(reason)
	end)

	--[[
		Soldul vine gata socotit de pe server; clientul doar il arata.

		Primul mesaj nu se numara pe ecran, se pune: la intrare vine cat ai
		stranse pana acum, si o urcare de la zero pana acolo ar arata ca un
		castig de acum. Urcarea e pentru ce castigi *cat te uiti*.
	]]
	local wallet = self.Views.Wallet
	local store = self.Views.Store
	if wallet or store then
		local first = true
		Remotes.get("WalletUpdate").OnClientEvent:Connect(function(payload: any)
			local coins = if typeof(payload) == "table" then payload.Coins else nil
			if type(coins) ~= "number" then
				return
			end
			if wallet then
				wallet:set(coins, not first)
			end
			-- In magazin soldul nu urca: acolo se citeste ca sa se compare cu un
			-- pret, si un numar in miscare nu se poate compara cu nimic.
			if store then
				store:setCoins(coins)
			end
			first = false
		end)
	end

	if store then
		Remotes.get("InventoryUpdate").OnClientEvent:Connect(function(payload: any)
			local items = if typeof(payload) == "table" then payload.Items else nil
			if typeof(items) ~= "table" then
				return
			end
			store:setOwned(items)
		end)
	end
end

-- --------------------------------------------------------------- stare

--[[
	Identitatea unui meci, vazuta din client: modul plus cine joaca in el.
	Doua meciuri consecutive cu aceiasi oameni si acelasi mod arata la fel si
	oricum au nevoie de aceeasi interfata, deci nu conteaza ca se confunda.
]]
function GameController.matchSignature(_self: GameController, state: BoardState): string
	local ids = {}
	for _, slot in state.TurnOrder do
		local player = state.Players[slot]
		if player then
			table.insert(ids, string.format("%d:%d", slot, player.UserId))
		end
	end
	table.sort(ids)
	return state.GameMode .. "|" .. table.concat(ids, ",")
end

function GameController.onState(self: GameController, snapshot)
	local state = BoardState.fromSnapshot(snapshot)
	self.State = state

	for slot, player in state.Players do
		if player.UserId == LOCAL_PLAYER.UserId then
			self.LocalSlot = slot
			break
		end
	end

	local views = self.Views
	views.Lobby:setVisible(false)
	views.Hud:setVisible(true)
	views.Board.Container.Visible = true

	--[[
		Banutii dispar cat tine meciul.

		Cat joci, nimic din ce nu se poate schimba prin ce faci pe tabla n-are ce
		cauta pe ecran: soldul nu se misca pana la ultima mutare, deci nu spune
		nimic, dar sta peste masa si cere privirea. Se intoarce la ecranul de
		victorie, unde e chiar concluzia — acolo numaratoarea catre suma noua e
		rasplata, nu zgomot.
	]]
	self:showWallet(state.Status ~= "PLAYING")

	--[[
		La revansa acceptata imediat, clientul nu mai trece prin lobby: serverul
		formeaza meciul nou din prima si trimite direct starea lui. Ecranul nu
		are voie sa se bazeze pe lobby ca sa se curete, asa ca meciul se
		recunoaste dupa componenta lui si tot ce e vechi se reface aici.
	]]
	local signature = self:matchSignature(state)
	if signature ~= self.MatchSignature then
		self.MatchSignature = signature
		views.Hud:buildCards(state)
		views.Board:reset()
	end

	if state.Status == "FINISHED" then
		views.Victory:show(state, self.LocalSlot)
	else
		views.Victory:hide()
	end

	self:refresh()
end

--[[
	Redeseneaza si recalculeaza ce se poate atinge.

	Interactivitatea e adevarul afisat: daca nu e randul tau, tabla nu
	raspunde deloc. Un buton care pare apasabil dar e refuzat de fiecare data
	e mai rau decat unul stins.
]]
function GameController.refresh(self: GameController)
	local state = self.State
	if not state then
		return
	end

	local views = self.Views
	views.Board:render(state, self.LocalSlot)
	views.Hud:setMode(self.Mode)
	views.Hud:update(state, self.LocalSlot)

	local slot = self.LocalSlot
	local isMyTurn = slot ~= nil
		and state.Status == "PLAYING"
		and state.PausedUntil == nil
		and BoardState.getCurrentSlot(state) == slot

	--[[
		Tabla 3D primeste aceeasi comanda ca cea 2D.

		Modul de joc are un singur proprietar — controllerul asta — iar ambele
		reprezentari doar il executa. Cand lumea isi tinea propriul mod, butonul
		"BARRICADE" din interfata schimba una si o lasa pe cealalta in urma, si
		jocul raspundea la ce nu scria pe ecran.
	]]
	local world = views.World

	if not isMyTurn then
		views.Board:setInteraction("IDLE", {}, self.Orientation)
		if world then
			world:setInteraction("IDLE", {}, self.Orientation)
		end
		return
	end

	local legalMoves = if self.Mode == "MOVE"
		then MovementRules.getLegalMoves(state, slot :: number)
		else {}
	views.Board:setInteraction(self.Mode, legalMoves, self.Orientation)
	if world then
		world:setInteraction(self.Mode, legalMoves, self.Orientation)
	end
end

function GameController.setMode(self: GameController, mode: string)
	local state = self.State
	if mode == "WALL" and state and self.LocalSlot then
		local player = state.Players[self.LocalSlot]
		if player and player.BarricadesRemaining <= 0 then
			self.Views.Hud:showToast(REJECTION_TEXT.NO_BARRICADES_LEFT)
			return
		end
	end

	self.Mode = mode
	self.Hovered = nil
	self.Views.Board:hidePreview()
	self:refresh()
end

function GameController.rotate(self: GameController)
	if self.Mode ~= "WALL" then
		return
	end

	self.Orientation = if self.Orientation == "Horizontal" then "Vertical" else "Horizontal"
	self:refresh()

	-- Previzualizarea ramane sub cursor dupa rotire, daca mai are sens acolo.
	local hovered = self.Hovered
	if hovered then
		self:previewWall(hovered.X, hovered.Y, self.Orientation)
	end
end

--[[
	Verde sau rosu, pe loc. Verdictul vine din aceleasi reguli pe care le
	aplica serverul, inclusiv verificarea ca nu ingroapa pe nimeni.
]]
function GameController.previewWall(self: GameController, x: number, y: number, orientation: string)
	local state = self.State
	local slot = self.LocalSlot
	if not state or not slot or self.Mode ~= "WALL" then
		return
	end

	self.Hovered = { X = x, Y = y }
	local verdict = WallRules.isValidWallPlacement(state, slot, x, y, orientation)
	self.Views.Board:showPreview(x, y, orientation, verdict.Ok)
end

-- ------------------------------------------------------------- evenimente

-- Banutii se vad oriunde in afara mesei. Vederea poate lipsi, deci se intreaba.
function GameController.showWallet(self: GameController, visible: boolean)
	local wallet = self.Views.Wallet
	if wallet then
		wallet:setVisible(visible)
	end
end

function GameController.onLobby(self: GameController, payload)
	local views = self.Views
	self:showWallet(true)
	views.Hud:setVisible(false)
	views.Board.Container.Visible = false
	views.Victory:hide()
	self.MatchSignature = nil
	self.State = nil
	self.LocalSlot = nil

	if payload and payload.Mode and payload.Needed and payload.Needed > 0 then
		views.Lobby:showQueue(payload.Mode, payload.Names or {}, payload.Needed)
	else
		views.Lobby:showHome()
	end
end

function GameController.onEvent(self: GameController, payload)
	if type(payload) ~= "table" or not payload.Type then
		return
	end

	local views = self.Views

	if payload.Type == "Countdown" then
		views.Hud:setVisible(false)
		views.Lobby:showCountdown(payload.Value)
		SoundController.play("Countdown")
	elseif payload.Type == "MoveApplied" then
		SoundController.play("Move")
	elseif payload.Type == "WallPlaced" then
		SoundController.play("WallPlaced")
	elseif payload.Type == "TurnChanged" then
		if payload.Slot == self.LocalSlot then
			SoundController.play("TurnChange")
		end
		-- O tura noua inseamna mereu intoarcerea la mutare: e actiunea implicita.
		self.Mode = "MOVE"
		self.Hovered = nil
		views.Board:hidePreview()
		self:refresh()
	elseif payload.Type == "Victory" then
		SoundController.play("Victory")
	elseif payload.Type == "Paused" then
		views.Hud:showToast("A player disconnected. Waiting for them to return.")
	elseif payload.Type == "Resumed" then
		views.Hud:showToast("The player is back. The match continues.")
	elseif payload.Type == "PlayerLeft" then
		views.Hud:showToast("A player left the match.")
	end
end

--[[
	Traduce un cod de refuz in text. Cazul special e cel mai important din
	joc: baricada respinsa fiindca ar taia ultimul drum al cuiva.
]]
function GameController.onRejected(self: GameController, reason: string)
	local message = REJECTION_TEXT[reason]

	if not message then
		local blockedSlot = tonumber(string.match(reason or "", "^WOULD_BLOCK_PLAYER_(%d+)$"))
		if blockedSlot then
			local state = self.State
			local victim = if state then state.Players[blockedSlot] else nil
			local name = if victim then victim.Name else "a player"
			message = if blockedSlot == self.LocalSlot
				then "That barricade would cut off your own route to the goal."
				else string.format(
					"That barricade would cut off %s's route to the goal.",
					name
				)
		end
	end

	self.Views.Hud:showToast(message or reason or "Actiune refuzata.")
	self.Views.Board:flashInvalid()
	SoundController.play("WallInvalid")
end

function GameController.leaveMatch(self: GameController)
	Remotes.get("RequestLeaveMatch"):FireServer()
	self:onLobby(nil)
end

return GameController
