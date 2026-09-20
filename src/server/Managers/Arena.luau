--!strict
--[[
	Arena — masa fizica a unui meci, detinuta de server.

	Platforma si zidurile traiesc aici, nu pe client: sunt lucruri pe care le vad
	toti jucatorii si pe care nimeni nu are voie sa le mute din browserul lui.
	Clientul doar apasa pe o celula; cine sta unde decide serverul.

	Arena nu stie reguli. Primeste starea deja validata de `Match` si o pune in
	lume: aseaza avatarele pe celule si ridica zidurile care au aparut. Daca
	cineva vrea sa schimbe cum arata un zid, umbla in `Skins`; daca vrea sa
	schimbe cine poate sa-l puna, umbla in motor.

	Fiecare meci isi primeste propriul colt de lume, altfel doua meciuri
	simultane s-ar calca pe tabla.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local World = ReplicatedStorage:WaitForChild("World")
local Platform = require(World.Platform)
local Barricade = require(World.Barricade)
local Fireworks = require(World.Fireworks)
local Podium = require(World.Podium)
local Skins = require(World.Skins)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Loadout = require(Shared.Loadout)
local Types = require(Shared.Types)

type BoardState = Types.BoardState

-- Distanta dintre doua arene. Tabla are ~79 studs, deci ramane loc de respiro.
local ARENA_SPACING = 400
local ARENA_HEIGHT = 8

--[[
	Cat din celula ocupa soclul castigatorului.

	Nu o umple: marginea de celula ramasa libera arata pe ce patrat s-a castigat,
	adica de unde a iesit soclul. Nici mai mic nu are voie sa fie — un soclu
	subtire sub un avatar de marime intreaga arata ca o greseala de asezare, nu
	ca un piedestal.
]]
local PODIUM_COVERAGE = 0.82

local Arena = {}
Arena.__index = Arena

type ArenaFields = {
	Id: string,
	Model: Folder,
	Platform: Platform.Platform,
	Walls: { [string]: Barricade.Barricade },
	--[[
		Soclul castigatorului. Exista doar dupa fluierul final, si doar unul.

		In timpul meciului nu e niciun podium pe tabla: acolo se joaca, iar un
		soclu sub fiecare pion ar ridica jucatorii deasupra grilei si ar ascunde
		tocmai celulele pe care se apasa.
	]]
	Podium: Podium.Podium?,
	--[[
		Ce tine in viata ceremonia: urcarea soclului. Se opreste daca masa se
		darama inainte sa se termine.
	]]
	Ceremony: thread?,
	--[[
		Corpul tinut pe loc cat urca soclul.

		Se tine minte ca sa poata fi dezlegat si daca ceremonia e intrerupta la
		mijloc: un jucator ramas tintuit s-ar intoarce in lobby ca o statuie.
	]]
	Standing: BasePart?,
	--[[
		Oprirea artificiilor. Ele tin cat tine masa dupa fluierul final, nu cat
		urca soclul: urcarea e de o secunda, iar sarbatoarea are voie sa dureze
		cat se uita omul la ea.
	]]
	Cheer: (() -> ())?,
	Index: number,
	--[[
		Ultima stare pusa in lume, si jucatorii ei.

		Se tine minte pentru respawn: sincronizarea se face doar la schimbari de
		stare, iar un jucator care moare si reapare intre doua mutari ar ramane
		langa tabla, nu pe ea. Cu starea la indemana, poate fi asezat inapoi in
		clipa in care are din nou corp.
	]]
	LastState: BoardState?,
	LastPlayers: { [number]: Player? },
	Watched: { [number]: RBXScriptConnection },
	--[[
		Unde sta masa. Se tine minte, nu se recalculeaza: meciurile din meniu isi
		primesc coltul lor din sirul de arene, dar cel de free play se aseaza
		unde arata piesa din lume, si atunci indexul nu mai spune adevarul.
	]]
	Origin: CFrame,
}

export type Arena = typeof(setmetatable({} :: ArenaFields, Arena))

local nextIndex = 0

--[[
	Exista o lume in care sa se aseze meciul?

	Pe varianta 2D asseturile lipsesc, iar meciul merge mai departe fara arena:
	tabla lui traieste in ScreenGui-ul fiecarui client. De aceea intrebarea asta
	nu e o verificare de eroare, ci comutatorul dintre cele doua forme ale
	jocului — acelasi pe care il citeste si clientul.
]]
function Arena.isAvailable(): boolean
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets ~= nil and assets:FindFirstChild("Board") ~= nil
end

-- Toate arenele stau intr-un singur folder, ca Workspace sa ramana citibil.
local function arenaRoot(): Folder
	local existing = workspace:FindFirstChild("Arenas")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Arenas"
	folder.Parent = workspace
	return folder
end

local function wallKey(wall: Types.Wall): string
	return string.format("%d,%d,%s", wall.X, wall.Y, wall.Orientation)
end

function Arena.new(matchId: string, origin: CFrame?): Arena
	local self = setmetatable({}, Arena) :: Arena

	nextIndex += 1
	self.Index = nextIndex
	self.Id = matchId
	self.Walls = {}
	self.LastPlayers = {}
	self.Watched = {}

	local container = Instance.new("Folder")
	container.Name = "Arena_" .. matchId
	container.Parent = arenaRoot()
	self.Model = container

	self.Origin = origin or CFrame.new(self.Index * ARENA_SPACING, ARENA_HEIGHT, 0)
	self.Platform = Platform.new(container, self.Origin)

	--[[
		Clicurile se leaga pe server, dar `ClickDetector` raporteaza oricum
		jucatorul care a apasat, deci clientul nu poate trimite in locul altuia.
		E acelasi drum ca `RequestMove`, doar ca vine direct din lume.
	]]
	self.Platform:enableClicks()

	return self
end

-- Unde sta tabla, ca alte sisteme (camera, spawn) sa nu recalculeze singure.
function Arena.origin(self: Arena): CFrame
	return self.Origin
end

--[[
	Aseaza avatarul unui jucator pe celula lui.

	Personajul poate lipsi — jucatorul tocmai s-a alaturat, sau a murit si
	asteapta respawn. Nu e o eroare: la urmatorul `sync` va fi acolo.
]]
function Arena.placePlayer(self: Arena, player: Player, cell: Types.Cell, objective: any)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (humanoid and root) then
		return
	end

	--[[
		Mersul liber se taie pe server, nu doar pe client: altfel un client
		modificat s-ar plimba pe tabla in afara turelor. Clientul isi dezactiveaza
		si controalele, dar aia e doar ca sa nu se zbata animatia degeaba.
	]]
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	local top = self.Platform:cellTop(cell.X, cell.Y)
	if not top then
		return
	end

	local standing = top + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)

	--[[
		Avatarul se intoarce cu fata spre obiectivul lui.

		Fara asta toti pionii privesc in aceeasi directie, oricare ar fi tabara
		lor, si doi adversari care ar trebui sa vina unul spre celalalt stau
		amandoi cu spatele in aceeasi parte. Directia se cere platformei, care o
		masoara din celule.
	]]
	local facing = self.Platform:directionForObjective(objective, cell)
	local target = if facing
		then CFrame.lookAt(standing, standing + facing)
		else CFrame.new(standing)

	if
		(root.Position - standing).Magnitude < 0.05
		and root.CFrame.LookVector:Dot(target.LookVector) > 0.99
	then
		return
	end
	character:PivotTo(target)
end

--[[
	Ceremonia castigatorului: soclul iese chiar din celula pe care a castigat.

	Podiumul e obiectul ales de el din magazin — id-ul vine din atributul scris
	de `Loadout` — si porneste ingropat: talpa lui incepe cu o inaltime intreaga
	sub fata tablei, deci in prima clipa nu se vede nimic. Urca pana ce plinta
	ajunge la nivelul celulei si mai sus, ridicandu-l odata cu ea.

	Avatarul nu e lasat in seama fizicii. Un soclu ancorat care urca printr-un
	corp liber il imbranceste intr-o parte inainte sa apuce sa-l ridice, asa ca
	pe durata urcarii corpul e tintuit si asezat noi, cadru cu cadru. Pana cand
	plinta il ajunge din urma sta pe celula, nu sub ea: altfel ar cobori odata
	cu soclul in pamant, in loc sa-l astepte.

	Se cheama o singura data, dupa ultimul `sync`. Un al doilea apel nu face
	nimic — masa nu are doi castigatori.
]]
function Arena.celebrate(self: Arena, slot: number?)
	if not slot or self.Podium then
		return
	end

	local state = self.LastState
	local playerState = state and state.Players[slot]
	local player = self.LastPlayers[slot]
	if not (playerState and player) then
		return
	end

	local cell = playerState.Position
	local top = self.Platform:cellTop(cell.X, cell.Y)
	local face = self.Platform:cell(cell.X, cell.Y)
	if not (top and face) then
		return
	end

	--[[
		Soclul priveste incotro priveste castigatorul.

		Un podium are o fata — tronul, arcada, fulgerul stau toate intr-o
		directie — si pana acum era asezat fara nicio rotatie, adica dupa axele
		lumii, nu dupa om. Iesea la intamplare: pe o margine a tablei jucatorul
		il avea cu fata spre el, pe cealalta cu spatele, fiindca cei doi privesc
		in directii opuse.

		Intors odata cu el, fata soclului cade exact spre camera, care vine sa se
		aseze in fata castigatorului — vezi `followWinner` din `WorldController`.
		Directia se ia doar din plan: `lookAt` si-ar inclina altfel si verticala,
		iar soclul ar urca stramb din celula.
	]]
	local facing = self.Platform:directionForObjective(playerState.Objective, cell)
	local flat = if facing then Vector3.new(facing.X, 0, facing.Z) else nil
	local surface = if flat and flat.Magnitude > 0.01
		then CFrame.lookAt(top, top + flat.Unit)
		else CFrame.new(top)

	local wanted = player:GetAttribute(Loadout.attribute("Podium"))
	local podium = Podium.new(
		if typeof(wanted) == "string" then wanted else nil,
		self.Model,
		surface,
		math.min(face.Size.X, face.Size.Z) * PODIUM_COVERAGE
	)
	if not podium then
		return
	end

	--[[
		Solid, ca sa-l tina, si transparent razelor, ca sa nu prinda clicuri: e
		ultimul lucru care se ridica pe masa, si nimeni nu mai apasa pe ea.
	]]
	podium:setSolid(true)
	podium:setQueryable(false)
	self.Podium = podium

	--[[
		Artificiile poarta culoarea obiectului cu care a castigat.

		Accentul skinului e ce are el mai aprins — flacara lui `dragon`, lumina
		lui `energy` — deci scanteile se sting exact in culoarea soclului de sub
		om. Cele care n-au accent isi dau culoarea corpului, care tot a lor e.
	]]
	local skin = Skins.get(podium.Id)
	self.Cheer = Fireworks.celebrate(self.Model, CFrame.new(top), {
		Color = skin.AccentColor or skin.Color,
	})

	local _, size = podium.Model:GetBoundingBox()
	local depth = size.Y

	self.Ceremony = task.spawn(function()
		local began = os.clock()
		local seconds = GameConfig.Timing.PodiumRise

		while true do
			local progress = math.clamp((os.clock() - began) / seconds, 0, 1)
			local eased =
				TweenService:GetValue(progress, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

			podium:moveTo(surface * CFrame.new(0, -depth * (1 - eased), 0))
			self:rideAlong(player, podium, top, facing)

			if progress >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end

		self:endCeremony()
	end)
end

--[[
	Aseaza corpul pe plinta soclului care urca, sau pe celula, daca soclul inca
	n-a ajuns la ea. `X` si `Z` raman ale celulei: podiumul e centrat pe ea, deci
	castigatorul nu are de ce sa alunece intr-o parte cat urca.
]]
function Arena.rideAlong(
	self: Arena,
	player: Player,
	podium: Podium.Podium,
	top: Vector3,
	facing: Vector3?
)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (humanoid and root) then
		return
	end

	if not self.Standing then
		root.Anchored = true
		self.Standing = root
	end

	local plinth = math.max(podium:standCFrame().Position.Y, top.Y)
	local standing = Vector3.new(top.X, plinth + humanoid.HipHeight + root.Size.Y / 2, top.Z)

	character:PivotTo(
		if facing then CFrame.lookAt(standing, standing + facing) else CFrame.new(standing)
	)
end

--[[
	Inchide ceremonia: opreste urcarea si dezleaga corpul.

	Se cheama si la capatul urcarii, si cand masa se darama inainte — in
	amandoua cazurile trebuie sa ramana acelasi lucru in urma: un jucator care
	se poate misca.
]]
function Arena.endCeremony(self: Arena)
	local running = self.Ceremony
	self.Ceremony = nil
	if running and running ~= coroutine.running() and coroutine.status(running) ~= "dead" then
		task.cancel(running)
	end

	local held = self.Standing
	self.Standing = nil
	if held and held.Parent then
		held.Anchored = false
	end
end

--[[
	Aduce lumea la zi cu starea.

	Se cheama dupa fiecare schimbare validata. Zidurile se adauga o singura data:
	cheia lor e pozitia plus orientarea, iar o baricada deja ridicata nu se mai
	construieste — altfel ar cadea din cer la fiecare mutare a oricui.
]]
function Arena.sync(self: Arena, state: BoardState, playerBySlot: { [number]: Player? })
	self.LastState = state
	self.LastPlayers = playerBySlot

	for slot, playerState in state.Players do
		local player = playerBySlot[slot]
		if player then
			self:placePlayer(player, playerState.Position, playerState.Objective)
			self:watchRespawn(player, slot)
		end
	end

	for _, wall in state.Walls do
		local id = wallKey(wall)
		if self.Walls[id] then
			continue
		end

		--[[
			Zidul poarta skinul celui care l-a pus, nu al arenei.

			Id-ul vine din atributul scris de `Loadout`, acelasi pe care il
			citeste si clientul proprietarului ca sa-si deseneze fantoma. Fara
			proprietar — la zidurile venite din pregatirea unui test, sau daca
			jucatorul a plecat — ramane `nil`, iar `Barricade` cade pe skinul de
			start, cum face la orice id pe care nu-l cunoaste.
		]]
		local owner = if wall.Owner then playerBySlot[wall.Owner] else nil
		local skinId = if owner then owner:GetAttribute(Loadout.attribute("Barricade")) else nil
		local barricade = Barricade.new(
			self.Platform,
			{ X = wall.X, Y = wall.Y, Orientation = wall.Orientation },
			if typeof(skinId) == "string" then skinId else nil
		)
		if barricade then
			barricade:play()
			self.Walls[id] = barricade
		end
	end
end

--[[
	Aseaza jucatorul inapoi pe tabla cand primeste corp nou.

	Se leaga o singura data per slot. Mica asteptare exista pentru ca membrele
	personajului apar pe rand: pozitionat prea devreme, avatarul e mutat inainte
	sa aiba de ce sa fie tinut si cade inapoi langa masa.
]]
function Arena.watchRespawn(self: Arena, player: Player, slot: number)
	if self.Watched[slot] then
		return
	end
	self.Watched[slot] = player.CharacterAdded:Connect(function()
		task.wait(0.3)
		local state = self.LastState
		local playerState = state and state.Players[slot]
		if playerState then
			self:placePlayer(player, playerState.Position, playerState.Objective)
		end
	end)
end

--[[
	Unde se intoarce un jucator cand pleaca de la masa: pe `SpawnLocation`-ul
	lobby-ului, acolo unde a aparut prima oara cand a intrat in joc.

	Nu se scrie o pozitie in cod. Inainte era `(0, 10, 0)`, si de acolo venea
	senzatia de "m-a intors pe masa": arena cu indexul 0 sta chiar in origine, la
	inaltimea 8, deci punctul ala nu era lobby-ul, ci exact deasupra primei
	table. Orice mutare a lobby-ului in Studio l-ar fi stricat din nou.

	Se cauta intai printre copiii directi ai lui `workspace`, unde sta de obicei,
	si abia apoi peste tot: `GetDescendants` traverseaza si mesele cu tot cu
	mesh-urile lor, iar asta se face degeaba de cele mai multe ori.
]]
local SPAWN_CLEARANCE = 3

local function lobbySpawn(player: Player): CFrame?
	local usable = function(item: Instance?): SpawnLocation?
		if item and item:IsA("SpawnLocation") and item.Enabled then
			return item
		end
		return nil
	end

	-- Ce i-a dat Roblox jucatorului, daca i-a dat ceva: e chiar raspunsul la
	-- "unde ai aparut ultima oara".
	local spawn = usable(player.RespawnLocation)

	if not spawn then
		for _, item in workspace:GetChildren() do
			spawn = usable(item)
			if spawn then
				break
			end
		end
	end

	if not spawn then
		for _, item in workspace:GetDescendants() do
			spawn = usable(item)
			if spawn then
				break
			end
		end
	end

	if not spawn then
		return nil
	end

	--[[
		Un pas la intamplare in patratul spawn-ului. Doi jucatori care termina
		acelasi meci sunt eliberati in aceeasi clipa, iar pe acelasi punct s-ar
		imbranci pana ii arunca fizica unul peste altul.
	]]
	local reach = math.max(spawn.Size.X, spawn.Size.Z) / 4
	local offset = Vector3.new(
		(math.random() - 0.5) * 2 * reach,
		spawn.Size.Y / 2 + SPAWN_CLEARANCE,
		(math.random() - 0.5) * 2 * reach
	)
	return CFrame.new(spawn.Position + offset)
end

--[[
	Scoate jucatorul de pe tabla si ii da mersul inapoi. Fara asta, cine
	paraseste meciul ramane o statuie pe o masa care tocmai a disparut.

	Nu tine de o arena anume — de aceea e functie locala, nu metoda.
]]
local function releasePlayer(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
	end
	if not character then
		return
	end

	local home = lobbySpawn(player)
	if home then
		character:PivotTo(home)
		return
	end

	--[[
		Fara niciun spawn in lume nu exista "locul de unde ai plecat", si nu are
		rost sa fie inventat unul: Roblox stie sa aseze un personaj nou, deci il
		punem pe el sa o faca. E cazul in care cineva a sters `SpawnLocation`-ul
		din lobby — rar, dar mai bun decat o cadere in gol.

		Pe fir separat: incarcarea asteapta pana personajul e gata, iar `destroy`
		n-are de ce sa tina masa in picioare pana atunci.
	]]
	task.spawn(function()
		player:LoadCharacterAsync()
	end)
end

function Arena.destroy(self: Arena)
	--[[
		Ceremonia se inchide prima. Corpul castigatorului e tintuit cat urca
		soclul, iar `releasePlayer` de mai jos il trimite in lobby: trimis inainte
		sa fie dezlegat, ar ajunge acolo tot statuie.
	]]
	self:endCeremony()

	local cheer = self.Cheer
	self.Cheer = nil
	if cheer then
		cheer()
	end

	for _, player in Players:GetPlayers() do
		if player:GetAttribute("ArenaId") == self.Id then
			player:SetAttribute("ArenaId", nil)
			releasePlayer(player)
		end
	end
	for _, connection in self.Watched do
		connection:Disconnect()
	end
	self.Watched = {}
	for _, wall in self.Walls do
		wall:destroy()
	end
	self.Walls = {}
	if self.Podium then
		self.Podium:destroy()
		self.Podium = nil
	end
	self.Platform:destroy()
	self.Model:Destroy()
end

return Arena
