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
local Callouts = require(Shared.Callouts)
local Catalog = require(Shared.Catalog)
local Emotes = require(Shared.Emotes)
local GameConfig = require(Shared.GameConfig)
local Loadout = require(Shared.Loadout)
local MovementRules = require(Shared.MovementRules)
local RematchVote = require(Shared.RematchVote)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local WallRules = require(Shared.WallRules)

local EmoteBubble = require(script.Parent.Parent.UI.EmoteBubble)
local SoundController = require(script.Parent.SoundController)
local SocialController = require(script.Parent.SocialController)
local Pocket = require(script.Parent.Parent.Pocket)
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
	GIFT_OWNED = "You already have that one.",
	-- La fel si la echipare: butonul e stins peste ce nu se poate, deci pana
	-- aici ajunge doar un client care a cerut ceva ce nu vedea pe ecran.
	EQUIP_UNKNOWN = "That item does not exist.",
	EQUIP_LOCKED = "You do not own that yet.",
	EQUIP_REFUSED = "Could not equip that.",
	-- Revansa: butonul se stinge, iar randul asta spune de ce.
	REMATCH_UNAVAILABLE = "No rematch: someone has already left the table.",
	REMATCH_CLOSED = "The rematch vote is already over.",
	REMATCH_NOT_SEATED = "You are not at this table.",
	REMATCH_ALONE = "There is nobody left to play with.",
}

--[[
	Care refuzuri se aud, si care raman doar scrise.

	Bufnitura e raspunsul la un zid care nu intra — acolo ai tintit un rost, ai
	vazut fantoma rosie si ai apasat oricum, iar sunetul e confirmarea. La o
	mutare nu e nimic de confirmat: celulele in care poti intra sunt aprinse
	verde tot timpul, deci un clic in alta parte nu e o incercare respinsa, ci o
	apasare pe langa. Pana acum suna la fel de grav ca un zid refuzat.

	Ce nu e aici tace: propozitia de pe ecran spune tot.
]]
local NOISY_REJECTIONS: { [string]: true } = {
	WALL_CONFLICT = true,
	NO_BARRICADES_LEFT = true,
	BAD_ORIENTATION = true,
}

local function isNoisy(reason: string?): boolean
	if not reason then
		return false
	end
	if NOISY_REJECTIONS[reason] then
		return true
	end
	-- „Ar ingropa pe cineva" e tot un refuz de zid, si inca cel mai important.
	return string.match(reason, "^WOULD_BLOCK_PLAYER_%d+$") ~= nil
end

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
	--[[
		Ecranul de victorie e programat, dar inca nu a aparut.

		Cat timp e adevarat, starile care mai vin nu il deschid mai devreme: ar
		sari peste ceremonia pe care tocmai o asteapta.
	]]
	VictoryPending: boolean,
	--[[
		S-a spus deja, o data in sesiunea asta, ce se face la rand.

		O singura data si numai la prima tura proprie: e pentru cine intra intai
		oara, si dupa aceea e zgomot. Nu se tine minte intre sesiuni — n-avem
		unde — dar pe cineva care joaca a doua partida il costa o propozitie
		citita o data, nu la fiecare meci.
	]]
	HintShown: boolean,
	--[[
		Ai cerut sa pleci si serverul inca nu te-a scos.

		Cat timp e adevarat, interfata de meci nu se mai reface din starile care
		mai vin — nici HUD-ul, nici panoul de victorie. Lumea 3D le primeste in
		continuare pe ale ei, fiindca tocmai ea are ce arata in intervalul asta:
		camera care pleaca spre castigator.
	]]
	Leaving: boolean,
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
	self.VictoryPending = false
	self.HintShown = false
	self.Leaving = false

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

		--[[
			Echiparea pleaca la fel: o cerere, nimic aplicat local. Ce porti se
			afla inapoi din atributul pe care il scrie serverul, nu din faptul ca
			ai apasat.
		]]
		views.Store:on("onEquip", function(kind: string, itemId: string)
			Remotes.get("RequestEquip"):FireServer(kind, itemId)
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
			Emote-ul pleaca ca id si atat, ca orice alta cerere. Nu se deseneaza
			nimic local: balonul propriu vine tot de la server, prin `MatchEvent`,
			odata cu al celorlalti. Asa toti vad acelasi lucru in aceeasi clipa,
			iar daca serverul refuza — esti prea repede, nu esti in meci — nu
			ramane pe ecranul tau un balon pe care nimeni altcineva nu l-a vazut.
		]]
		onEmote = function(id: string)
			Remotes.get("RequestEmote"):FireServer(id)
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
		--[[
			Plecarea se intreaba o data.

			Butonul sta in coltul de jos, langa sunet si perspectiva, si se apasa
			din greseala — dar spre deosebire de ele, incheie partida si o da
			castigata celuilalt. Fara fereastra, nu exista niciun pas inapoi.
		]]
		onLeave = function()
			local confirm = views.Confirm
			if not confirm then
				self:leaveMatch()
				return
			end
			confirm:ask({
				Title = "LEAVE THE MATCH?",
				Body = "The match counts as lost and the others win it. "
					.. "You keep the coins for having played.",
				Accept = "LEAVE",
				Cancel = "STAY",
			}, function(accepted: boolean)
				if accepted then
					self:leaveMatch()
				end
			end)
		end,
	})

	--[[
		Revansa se cere de pe ecranul de final si se voteaza in banner. Ecranul
		ramane deschis: masa e aceeasi, iar raspunsul celorlalti vine peste el.
	]]
	views.Victory:setCallbacks({
		onRematch = function()
			views.Victory:setRematch("WAITING")
			Remotes.get("RequestRematch"):FireServer()
		end,
		onAddFriend = function(userId: number)
			SocialController.promptFriendRequest(userId)
		end,
		onLeave = function()
			views.Victory:hide()
			self:leaveMatch()
		end,
	})

	local rematch = views.Rematch
	if rematch then
		rematch:setCallbacks({
			onAccept = function()
				views.Victory:setRematch("WAITING")
				Remotes.get("RequestRematch"):FireServer()
			end,
			onDecline = function()
				Remotes.get("RequestRematchDecline"):FireServer()
			end,
			onClosed = function(accepted: boolean)
				self:afterRematch(accepted)
			end,
		})
	end
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
		Pocket.watch(function()
			--[[
				Cat timp serverul n-a spus nimic, nu se arata nimic: zero inainte
				de primul mesaj si zero dupa el arata la fel pe ecran, dar numai
				al doilea e un raspuns.
			]]
			if not Pocket.known() then
				return
			end

			local coins = Pocket.coins()
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
		Pocket.watch(function()
			store:setOwned(Pocket.items())
		end)

		--[[
			Ce poarta jucatorul nu vine pe un canal, ci ca atribut pe el — vezi
			`Loadout`. Se citeste o data acum, pentru cazul in care serverul l-a
			scris inainte ca ecranul sa existe, si apoi la fiecare schimbare.
		]]
		for _, kind: Catalog.Kind in Catalog.Kinds do
			local name = Loadout.attribute(kind)
			local function read()
				local id = LOCAL_PLAYER:GetAttribute(name)
				store:setEquipped(kind, if typeof(id) == "string" then id else nil)
			end
			LOCAL_PLAYER:GetAttributeChangedSignal(name):Connect(read)
			read()
		end
	end
end

-- --------------------------------------------------------------- stare

--[[
	Identitatea unui meci, vazuta din client: modul plus cine joaca in el.
	Doua meciuri consecutive cu aceiasi oameni si acelasi mod arata la fel si
	oricum au nevoie de aceeasi interfata, deci nu conteaza ca se confunda.
]]
function GameController.matchSignature(_self: GameController, state: BoardState): string
	--[[
		Cine joaca, nu cine mai e la rand.

		Socotita din `TurnOrder`, semnatura se schimba in clipa in care cineva se
		retrage — si atunci cardurile se dadeau jos si se refaceau, iar tabla se
		golea, in mijlocul aceluiasi meci. `Players` tine toti oamenii pana la
		capat, si asa semnatura se schimba doar cand chiar incepe alt meci.
	]]
	local ids = {}
	for slot, player in state.Players do
		table.insert(ids, string.format("%d:%d", slot, player.UserId))
	end
	table.sort(ids)
	return state.GameMode .. "|" .. table.concat(ids, ",")
end

function GameController.onState(self: GameController, snapshot)
	--[[
		Cine a cerut sa plece nu mai primeste interfata de meci.

		Starea finala i se trimite dinadins — ca lumea 3D sa stie cine a castigat
		si sa duca camera pana la el — dar panoul de victorie nu-i mai apartine:
		nu e victoria lui, si n-are de ce sa i se ofere revansa la un meci din
		care tocmai a iesit. Se uita la ceremonie, si apoi il cheama serverul in
		lobby.
	]]
	if self.Leaving then
		return
	end

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
	if views.Social then
		views.Social:setInLobby(false)
	end
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

	--[[
		Ecranul de victorie asteapta ceremonia.

		Panoul sta la mijlocul ecranului, iar camera tocmai pleaca spre
		castigatorul care urca pe soclu — adica fix acolo. Aparut in aceeasi
		clipa, ar acoperi singurul lucru pe care il are de aratat finalul de
		meci. Asa se vede intai ce s-a intamplat, si abia apoi ce scrie despre
		ce s-a intamplat.

		Doar in lumea 3D. Pe tabla 2D nu exista nici camera, nici soclu: acolo
		o intarziere ar fi o secunda de ecran gol, fara nimic in ea.
	]]
	if state.Status == "FINISHED" then
		if views.World and not self.VictoryPending and not views.Victory:isOpen() then
			self.VictoryPending = true
			task.delay(GameConfig.Timing.VictoryReveal, function()
				self.VictoryPending = false
				local now = self.State
				if now and now.Status == "FINISHED" then
					views.Victory:setFriends(self:strangers(now))
					views.Victory:show(now, self.LocalSlot)
				end
			end)
		elseif not self.VictoryPending then
			if not views.Victory:isOpen() then
				views.Victory:setFriends(self:strangers(state))
			end
			views.Victory:show(state, self.LocalSlot)
		end
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

	--[[
		Prima tura din sesiune spune si ce se poate face in ea.

		Celulele verzi arata *unde* poti merge, dar nu si ca se merge apasand pe
		ele, si mai ales nu ca exista a doua actiune: zidul. Cine intra intai oara
		vede o tabla frumoasa si nu stie ca butonul de jos e jumatate din joc.
	]]
	if not self.HintShown then
		self.HintShown = true
		views.Hud:showToast(
			"Your turn — tap a green square to move, or BARRICADE to block a path.",
			"HINT"
		)
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
	if views.Social then
		views.Social:setInLobby(true)
	end
	views.Hud:setVisible(false)
	views.Board.Container.Visible = false
	views.Victory:hide()
	--[[
		Aici se incheie plecarea, oricum ar fi inceput ea. Si intrebarea se
		inchide: daca meciul s-a terminat singur cat statea deschisa, nu mai are
		ce sa confirme.
	]]
	self.Leaving = false
	if views.Confirm then
		views.Confirm:dismiss()
	end
	--[[
		Baloanele tin de masa, nu de jucator. Lasate sa se stinga singure, ultimul
		emote al partidei ar fi plutit deasupra cuiva prin lobby.
	]]
	EmoteBubble.clearAll()
	if views.Rematch then
		views.Rematch:hide()
	end
	if views.Callouts then
		views.Callouts:clear()
	end
	self.MatchSignature = nil
	self.State = nil
	self.LocalSlot = nil

	if payload and payload.Mode and payload.Needed and payload.Needed > 0 then
		views.Lobby:showQueue(payload.Mode, payload.Names or {}, payload.Needed)
	else
		views.Lobby:showHome()
	end
end

--[[
	Sunetul unei fapte, ales dupa cine a facut-o.

	Serverul spune in fiecare eveniment **al cui** slot e — asta se stia si pana
	acum, doar ca nimeni nu se uita. Cine n-are inca slot, fiindca starea n-a
	ajuns, aude varianta celuilalt: un spectator care intra in mijlocul unui meci
	nu a mutat nimic, deci nimic din ce aude nu e al lui.

	Numele se compun, nu se scriu in cazuri: `Move` plus `Self` sau `Other` da
	cheia din `GameConfig.Sounds`. Un `if` cu patru ramuri ar fi trebuit tinut la
	zi odata cu tabelul, si s-ar fi despartit de el la prima adaugare.
]]
function GameController.playByAuthor(self: GameController, slot: any, action: string)
	local mine = self.LocalSlot ~= nil and slot == self.LocalSlot
	SoundController.play(action .. (if mine then "Self" else "Other"))
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
		self:playByAuthor(payload.Slot, "Move")
		self:showCallouts(payload.Callouts)
	elseif payload.Type == "WallPlaced" then
		self:playByAuthor(payload.Slot, "Wall")
		self:showCallouts(payload.Callouts)
	elseif payload.Type == "TurnChanged" then
		if payload.Slot == self.LocalSlot then
			SoundController.play("TurnChange")
		end
		-- O tura noua inseamna mereu intoarcerea la mutare: e actiunea implicita.
		self.Mode = "MOVE"
		self.Hovered = nil
		views.Board:hidePreview()
		self:refresh()
	elseif payload.Type == "Emote" then
		self:showEmote(payload)
	elseif payload.Type == "Rematch" then
		self:onRematch(payload)
	elseif payload.Type == "Payout" then
		views.Victory:setRewards(if type(payload.Lines) == "table" then payload.Lines else {})
	elseif payload.Type == "Victory" then
		if views.Callouts then
			views.Callouts:clear()
		end
		views.Victory:setSeries(self:seriesLabel(payload.Series))
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
	Callout-urile unei actiuni, asa cum le-a hotarat serverul.

	Verdictul vine gata facut; aici se alege doar cum se citeste de la locul
	tau (`Callouts.format`) si unde se aseaza: pe masa 3D cand exista, altfel
	pe tabla desenata. Al doilea callout al aceleiasi actiuni vine putin dupa
	primul si mai sus, ca sa nu se suprapuna.

	Datele vin de pe retea si se verifica la intrare: o celula fara coordonate
	ar arunca eroarea tocmai in mijlocul evenimentului care muta pionul.
]]
local function isCell(value: any): boolean
	return type(value) == "table" and type(value.X) == "number" and type(value.Y) == "number"
end

function GameController.showCallouts(self: GameController, list: any)
	local views = self.Views
	local view = views.Callouts
	if not view or type(list) ~= "table" then
		return
	end

	-- Rama tablei se aprinde odata cu textul, la toti de la masa.
	if views.World and #list > 0 then
		views.World:playRim(list)
	end

	local world = views.World
	for index, callout in list do
		if type(callout) ~= "table" or not isCell(callout.Cell) then
			continue
		end
		local wall = if isCell(callout.Wall) and type(callout.Wall.Orientation) == "string"
			then callout.Wall
			else nil

		local state = self.State
		local author = state and state.Players[callout.Slot]
		local me = state and self.LocalSlot and state.Players[self.LocalSlot]
		local allied = author ~= nil and me ~= nil and author ~= me and author.Team == me.Team
		local presented = Callouts.format(callout, self.LocalSlot, author and author.Name, allied)
		if not presented then
			continue
		end

		local point = if world
			then world:screenPoint(callout.Cell, wall)
			else views.Board:screenPoint(callout.Cell, wall)

		view:show(presented, point, {
			Delay = (index - 1) * GameConfig.Callouts.Stagger,
			Index = index - 1,
			OnImpact = if world
				then function()
					world:shakeCamera()
				end
				else nil,
		})
	end
end

--[[
	Emote-ul cuiva de la masa: sunetul, si balonul deasupra lui.

	Id-ul se cauta din nou in catalog, desi serverul l-a verificat inainte sa-l
	trimita. Nu din neincredere in server, ci pentru ca asa nu exista drum prin
	care un simbol nestiut sa ajunga pe ecran — nici daca catalogul se schimba
	si un client ramane cu versiunea veche.

	Balonul sta pe cardul jucatorului, nu deasupra capului lui.

	Deasupra capului a fost prima incercare, si parea evidenta — acolo se pune
	un balon de vorba. Dar meciul se joaca privind masa de sus, de la vreo suta
	de studi, iar la distanta aia un balon destul de mare cat sa i se vada semnul
	acopera mai mult decat celula pe care stai: ori e prea mic ca sa se
	citeasca, ori prea mare ca sa nu incurce. Nu e o marime de nimerit, e o
	pozitie gresita.

	Cardul rezolva amandoua: e sus, unde nu e tabla, are marime fixa pe ecran
	deci semnul se citeste mereu la fel, si poarta deja chipul si numele omului —
	„cine a spus" se vede fara sa mai lege nimeni balonul de un avatar.

	Deasupra capului ramane pentru cine n-are card: un jucator a carui placuta
	inca nu s-a desenat. Se vede prost, dar se vede.
]]
function GameController.showEmote(self: GameController, payload)
	local emote = Emotes.get(payload.EmoteId)
	if not emote then
		return
	end

	SoundController.playEmote(emote.Id)

	local userId = payload.UserId
	if type(userId) ~= "number" then
		return
	end

	local views = self.Views
	local card = if type(payload.Slot) == "number" then views.Hud:cardFor(payload.Slot) else nil
	if card then
		EmoteBubble.overCard(userId, card, emote.Symbol)
		return
	end

	local player = EmoteBubble.playerOf(userId)
	if views.World and player then
		EmoteBubble.overHead(player, emote.Symbol)
	end
end

--[[
	Traduce un cod de refuz in text. Cazul special e cel mai important din
	joc: baricada respinsa fiindca ar taia ultimul drum al cuiva.
]]
function GameController.onRejected(self: GameController, reason: string)
	local message = REJECTION_TEXT[reason]

	-- Refuzurile provocarilor le spune `SocialController`, in lobby, nu HUD-ul meciului.
	if type(reason) == "string" and string.sub(reason, 1, 10) == "CHALLENGE_" then
		return
	end

	-- Un refuz de revansa nu e o mutare gresita: nu clipeste tabla, doar se stinge butonul.
	if type(reason) == "string" and string.sub(reason, 1, 8) == "REMATCH_" then
		self.Views.Victory:setRematch("CLOSED")
		self.Views.Hud:showToast(message or "No rematch.")
		return
	end

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

	self.Views.Hud:showToast(message or reason or "That move was refused.")
	self.Views.Board:flashInvalid()
	if isNoisy(reason) then
		SoundController.play("WallInvalid")
	end
end

--[[
	Pleaca din meci — si asteapta.

	Pana acum clientul se muta singur in lobby in aceeasi clipa, fara sa astepte
	serverul, si de aici veneau doua lucruri stricate deodata. Intai, daca
	plecarea ta incheia meciul, nu apucai sa vezi asta niciodata: interfata
	sarea in lobby peste o camera care ramanea agatata deasupra mesei, fiindca
	nimeni nu-i spusese sa plece de acolo. Al doilea, camera nu se dezlega pana
	cand nu pleca si adversarul — atributul `ArenaId` se sterge abia cand se
	darama masa, iar masa se daramă abia atunci.

	Acum serverul hotaraste cand pleci: iti trimite starea finala daca meciul
	tocmai s-a terminat, te lasa sa vezi ceremonia castigatorului, si abia apoi
	iti trimite `LobbyUpdate`. Aici se stinge doar HUD-ul — butoanele nu mai au
	pe ce sa lucreze — si se tine minte ca esti pe plecare.
]]
--[[
	Adversarii de la masa care nu-ti sunt inca prieteni: lor li se pune ADD
	FRIEND pe ecranul de final. Coechipierii din 2v2 nu intra — jucati deja
	impreuna, iar randul e pentru cei pe care i-ai cunoscut ca adversari.
]]
function GameController.strangers(
	self: GameController,
	state: BoardState
): { { UserId: number, Name: string } }
	local me = if self.LocalSlot then state.Players[self.LocalSlot] else nil
	local social = self.Views.Social
	local list = {}
	for slot = 1, #state.Players do
		local player = state.Players[slot]
		local opponent = player and slot ~= self.LocalSlot and (not me or player.Team ~= me.Team)
		if opponent and player.UserId > 0 and not (social and social:isFriend(player.UserId)) then
			table.insert(list, { UserId = player.UserId, Name = player.Name })
		end
	end
	return list
end

--[[
	„Rematch #3 · 2–1" din seria trimisa de server, scrisa dinspre jucatorul
	local: tabara lui prima, apoi celelalte in ordinea sloturilor. In 2v2 o
	tabara e o echipa, altfel un om.
]]
function GameController.seriesLabel(self: GameController, series: any): string?
	local state = self.State
	if
		not state
		or type(series) ~= "table"
		or type(series.Games) ~= "number"
		or type(series.Wins) ~= "table"
	then
		return nil
	end

	local me = if self.LocalSlot then state.Players[self.LocalSlot] else nil
	local sides: { { number } } = {}
	local byTeam: { [number]: { number } } = {}
	local order: { number } = {}
	for slot = 1, #state.Players do
		local player = state.Players[slot]
		if player then
			local team = byTeam[player.Team]
			if not team then
				team = {}
				byTeam[player.Team] = team
				table.insert(order, player.Team)
			end
			table.insert(team, player.UserId)
		end
	end
	if me and byTeam[me.Team] then
		table.insert(sides, byTeam[me.Team])
	end
	for _, team in order do
		if not me or team ~= me.Team then
			table.insert(sides, byTeam[team])
		end
	end

	return RematchVote.label({ Games = series.Games, Wins = series.Wins }, sides)
end

--[[
	Starea votului de revansa, venita de la server.

	Bannerul o deseneaza; aici se tine doar ecranul de final in pas cu ea: cat
	se voteaza, numaratoarea spre lobby sta pe loc, iar dupa vot butonul nu se
	mai aprinde — la masa asta revansa s-a jucat, sau s-a refuzat.
]]
function GameController.onRematch(self: GameController, payload: any)
	local views = self.Views
	local localUserId = Players.LocalPlayer.UserId
	local accepted = if type(payload.Accepted) == "table" then payload.Accepted else {}

	if views.Rematch then
		views.Rematch:update(payload, localUserId)
	end

	if payload.Status == "Pending" then
		views.Victory:stopTimeout()
		if table.find(accepted, localUserId) then
			views.Victory:setRematch("WAITING")
		end
	elseif payload.Status == "Accepted" then
		views.Victory:setRematch("WAITING")
	else
		views.Victory:setRematch("CLOSED")
	end
end

--[[
	Dupa o revansa anulata. Cine o acceptase e intrebat daca vrea in coada
	obisnuita — nu e aruncat singur acolo; ceilalti isi vad ecranul de final
	inchizandu-se in cateva secunde, ca inainte.
]]
function GameController.afterRematch(self: GameController, accepted: boolean)
	local views = self.Views
	local state = self.State
	local modeId = if state then state.GameMode else nil
	local confirm = views.Confirm

	if not accepted or not confirm or not modeId or not views.Victory:isOpen() then
		if views.Victory:isOpen() then
			views.Victory:startTimeout(GameConfig.Timing.RematchResume)
		end
		return
	end

	local mode = GameConfig.Modes[modeId]
	confirm:ask({
		Title = "FIND A NEW MATCH?",
		Body = string.format(
			"The rematch is off. Join the %s queue with other players?",
			if mode then mode.DisplayName else modeId
		),
		Accept = "JOIN QUEUE",
		Cancel = "MAIN MENU",
	}, function(join: boolean)
		views.Victory:hide()
		self:leaveMatch()
		if join then
			Remotes.get("RequestJoinQueue"):FireServer(modeId)
		end
	end)
end

function GameController.leaveMatch(self: GameController)
	self.Leaving = true
	self.Views.Hud:setVisible(false)
	Remotes.get("RequestLeaveMatch"):FireServer()
end

return GameController
