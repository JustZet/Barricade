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

local World = ReplicatedStorage:WaitForChild("World")
local Platform = require(World.Platform)
local Barricade = require(World.Barricade)
local Skins = require(World.Skins)

local Types = require(ReplicatedStorage.Shared.Types)

type BoardState = Types.BoardState

-- Distanta dintre doua arene. Tabla are ~79 studs, deci ramane loc de respiro.
local ARENA_SPACING = 400
local ARENA_HEIGHT = 8

local Arena = {}
Arena.__index = Arena

type ArenaFields = {
	Id: string,
	Model: Folder,
	Platform: Platform.Platform,
	Walls: { [string]: Barricade.Barricade },
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

		local owner = if wall.Owner then playerBySlot[wall.Owner] else nil
		local skinId = if owner then owner:GetAttribute("WallSkin") else nil
		local barricade = Barricade.new(
			self.Platform,
			{ X = wall.X, Y = wall.Y, Orientation = wall.Orientation },
			if typeof(skinId) == "string" then skinId else Skins.Default
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
	self.Platform:destroy()
	self.Model:Destroy()
end

return Arena
