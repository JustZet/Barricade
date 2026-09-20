--!strict
--[[
	FreePlay — meciul care porneste din lume, nu din meniu.

	Urci pe soclul din arena si astepti. Cand se strang destui, pleaca meciul.
	Nu exista buton, nu exista coada de apasat: locul *este* cererea, si de aceea
	nu trece prin niciun RemoteEvent. Un jucator nu poate minti ca sta pe soclu,
	fiindca nu el o spune — serverul se uita unde ii e corpul.

	Numaratoarea merge indiferent cati sunt pe soclu. Cand ajunge la zero:

	  destui  -> pleaca meciul cu primii sositi
	  unul    -> o ia de la capat, fiindca n-are cu cine

	Cand soclul se umple, numaratoarea se ignora si meciul pleaca pe loc: n-are
	rost sa astepti pe altcineva cand nu mai e loc pentru el.

	Ordinea sosirii e si ordinea sloturilor, ca la cozile din meniu. Cine a urcat
	primul primeste slotul unu — previzibil, si usor de explicat cuiva.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local FreePlayRules = require(Shared.FreePlayRules)
local GameConfig = require(Shared.GameConfig)

local World = ReplicatedStorage:WaitForChild("World")
local FreePlaySign = require(World.FreePlaySign)

local Arena = require(script.Parent.Arena)
local MatchManager = require(script.Parent.MatchManager)
local MatchmakingManager = require(script.Parent.MatchmakingManager)

local FreePlay = {}

local SETTINGS = GameConfig.FreePlay

--[[
	Cati incap: exact cati cere modul. Nu se scrie inca un numar langa el, ca sa
	nu existe doua adevaruri despre acelasi lucru.
]]
local CAPACITY = GameConfig.Modes[SETTINGS.Mode].Players

--[[
	Cat de sus peste soclu se mai considera ca stai pe el.

	Un avatar are centrul corpului la vreo trei studi peste talpa, iar saritura
	il mai ridica vreo sapte. Doisprezece cuprinde si saritura, si treapta pe
	care ar putea sta, fara sa numere pe cineva care trece pe deasupra cu totul.
]]
local STAND_HEIGHT = 12

-- Cat se strange marginea soclului, ca sa nu conteze cine sta agatat de muchie.
local EDGE_INSET = 1

local plinth: BasePart? = nil
local marker: BasePart? = nil
local sign: FreePlaySign.FreePlaySign? = nil

local remaining = SETTINGS.Countdown
-- Pana cand `tick` nu are voie sa scrie pe semn (numaratoarea de start).
local hold = 0
local running = false

--[[
	Sta jucatorul pe soclu?

	Se masoara in spatiul soclului, nu in cel al lumii: daca cineva roteste
	vreodata arena in Studio, verificarea se roteste cu ea si nu trebuie atinsa.
]]
local function isStanding(player: Player, pad: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end

	local inPad = pad.CFrame:PointToObjectSpace(root.Position)
	local halfX = pad.Size.X / 2 - EDGE_INSET
	local halfZ = pad.Size.Z / 2 - EDGE_INSET
	if math.abs(inPad.X) > halfX or math.abs(inPad.Z) > halfZ then
		return false
	end

	local above = inPad.Y - pad.Size.Y / 2
	return above > -1 and above < STAND_HEIGHT
end

--[[
	Cine asteapta acum, in ordinea in care a urcat.

	Cei aflati deja intr-un meci nu se numara. Nu e o pazire teoretica: dupa ce
	meciul pleaca, avatarele sunt mutate pe masa, dar intre clipa in care meciul
	s-a creat si clipa in care `Arena` le muta mai trece un cadru — si in cadrul
	ala ar fi inca pe soclu si ar porni al doilea meci.
]]
local waiting: { Player } = {}

local function refresh(pad: BasePart)
	local present: { [Player]: boolean } = {}
	for _, player in Players:GetPlayers() do
		if isStanding(player, pad) and not MatchManager.getForPlayer(player) then
			present[player] = true
		end
	end

	-- Intai pleaca cine a coborat, ca sa nu se piarda ordinea celor ramasi.
	for index = #waiting, 1, -1 do
		local player = waiting[index]
		if not present[player] or not player.Parent then
			table.remove(waiting, index)
		else
			present[player] = nil
		end
	end

	-- Ce a ramas in `present` sunt nou-venitii, si se aseaza la coada.
	for player in present do
		table.insert(waiting, player)
	end
end

local function start()
	local group: { Player } = {}
	for index = 1, CAPACITY do
		local player = waiting[index]
		if not player then
			return
		end
		table.insert(group, player)
	end

	--[[
		Iesirea din coada meniului se face inainte de creare, nu dupa: altfel un
		jucator ramas in coada ar putea fi luat de acolo pentru al doilea meci
		exact in clipa in care incepe acesta.
	]]
	for _, player in group do
		MatchmakingManager.leave(player)
	end

	local origin = if marker
		then CFrame.new(marker.Position + Vector3.new(0, marker.Size.Y / 2, 0))
		else nil

	MatchManager.create(SETTINGS.Mode, group, origin)
	table.clear(waiting)
	remaining = SETTINGS.Countdown

	--[[
		Numaratoarea pana la start se scrie pe semn, nu doar pe ecranele lor.

		`Match` o tine oricum — masa exista deja, dar jucatorii raman pe soclu
		pana cade "unu". Aici se vede de ce: stau pe soclu si se uita la un semn
		care le spune cat mai au. Cine trece pe langa vede si el ca acolo tocmai
		incepe ceva, ceea ce un contor ascuns intr-o interfata nu spune nimanui.

		`hold` tine `tick` departe de semn cat dureaza. Altfel scrisul lui, care
		vine la fiecare masuratoare, s-ar bate cu al nostru si ar clipi intre
		"3" si "step on the pad".
	]]
	hold = os.clock() + GameConfig.Timing.StartCountdown
	task.spawn(function()
		for left = GameConfig.Timing.StartCountdown, 1, -1 do
			if sign then
				sign:show(tostring(left), "match starting", true)
			end
			task.wait(1)
		end
		hold = 0
	end)
end

local function tick(delta: number)
	local quiet = os.clock() < hold

	local pad = plinth
	if not pad or not pad.Parent then
		return
	end

	refresh(pad)
	local count = #waiting

	--[[
		Soclul gol opreste ceasul si il pune la loc. Un contor care curge in fata
		unui loc pustiu nu spune nimic, si cine ajunge mai tarziu ar prinde o
		numaratoare deja pe sfarsite fara sa inteleaga de ce.
	]]
	if count == 0 then
		remaining = SETTINGS.Countdown
		if sign and not quiet then
			sign:show("FREE PLAY", string.format("step on the pad — %d players", CAPACITY), false)
		end
		return
	end

	remaining -= delta

	local decision = FreePlayRules.decide(count, SETTINGS.Minimum, CAPACITY, remaining)

	if decision == "START" then
		if sign and not quiet then
			sign:show("START", string.format("%d / %d", count, CAPACITY), true)
		end
		start()
		return
	end

	if decision == "RESTART" then
		remaining = SETTINGS.Countdown
	end

	if sign and not quiet then
		sign:show(
			string.format("%d", math.max(0, math.ceil(remaining))),
			string.format("%d / %d waiting", count, CAPACITY),
			false
		)
	end
end

--[[
	Soclul pe care se sta. Se cauta dupa nume, in lobby.

	`arena_board_plinth` e placa lata din arena spectatorilor; invelisul ei de
	import se cheama la fel plus `_Node`, deci se cere explicit o piesa, nu un
	model.
]]
local function findPlinth(): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	for _, node in lobby:GetDescendants() do
		if node:IsA("BasePart") and node.Name == "arena_board_plinth" then
			return node
		end
	end
	return nil
end

--[[
	Piesa care arata unde se aseaza masa meciului de free play.

	Se ancoreaza la gasire. E pusa de mana in Studio si vine de obicei
	neancorata, iar o piesa neancorata cade — si odata cazuta, arata alt loc la
	fiecare repornire.
]]
local function findMarker(): BasePart?
	local found = workspace:FindFirstChild(SETTINGS.ArenaMarker)
	if not found or not found:IsA("BasePart") then
		return nil
	end
	found.Anchored = true
	return found
end

-- Cat asteptam ca lobby-ul sa se replice inainte sa ne dam batuti.
local PLINTH_WAIT = 20

--[[
	Porneste supravegherea soclului.

	Se cheama o singura data, la pornirea serverului, si doar cand exista lume
	3D: fara avatare nu are cine sa stea pe soclu, iar pe varianta 2D free play
	nu inseamna nimic.
]]
function FreePlay.start()
	if running then
		return
	end
	if not Arena.isAvailable() then
		return
	end
	running = true

	task.spawn(function()
		local deadline = os.clock() + PLINTH_WAIT
		while os.clock() < deadline do
			plinth = findPlinth()
			if plinth then
				break
			end
			task.wait(0.5)
		end

		if not plinth then
			warn("FreePlay: nu am gasit arena_board_plinth in lobby; free play ramane oprit")
			running = false
			return
		end

		marker = findMarker()
		if not marker then
			warn(
				string.format(
					"FreePlay: nu exista piesa %q in Workspace; meciul se va aseza in sirul obisnuit de arene",
					SETTINGS.ArenaMarker
				)
			)
		end

		sign = FreePlaySign.new(plinth :: BasePart)

		--[[
			Se numara la interval, nu la fiecare cadru. Verificarea se uita la
			toti jucatorii si le masoara pozitia; de saizeci de ori pe secunda ar
			fi munca degeaba pentru ceva ce se schimba in pasi de om.
		]]
		local since = 0
		RunService.Heartbeat:Connect(function(delta: number)
			since += delta
			if since < SETTINGS.PollInterval then
				return
			end
			local elapsed = since
			since = 0
			tick(elapsed)
		end)
	end)
end

-- Cine pleaca de pe server pleaca si de pe soclu, chiar daca n-a apucat sa coboare.
Players.PlayerRemoving:Connect(function(player: Player)
	for index = #waiting, 1, -1 do
		if waiting[index] == player then
			table.remove(waiting, index)
		end
	end
end)

return FreePlay
