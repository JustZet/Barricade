--!strict
--[[
	WorldController — meciul pe platforma, vazut de client.

	Serverul detine masa, pionii si zidurile; clientul face doua lucruri:
	arata unde ai voie sa calci si trimite ce ai apasat. Nicio mutare nu se
	aplica local — se cere prin `RequestMove`, iar tabla se schimba abia cand
	raspunde `GameStateUpdate`. Asa, ce vezi e mereu ce stie serverul.

	Legalitatea o calculeaza tot motorul pur din `src/shared/`, doar ca pe
	starea primita. Nu e o a doua implementare a regulilor: e aceeasi functie,
	rulata pe o copie, ca sa nu astepti dus-intors de la server doar ca sa
	vezi ce celule se aprind.

	Jucatorul nu merge cu WASD. Se muta apasand pe o celula, iar celulele pe
	care poate inainta sunt aprinse tot timpul.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local BoardState = require(Shared.BoardState)
local BoardUtils = require(Shared.BoardUtils)
local GameConfig = require(Shared.GameConfig)
local Loadout = require(Shared.Loadout)
local MovementRules = require(Shared.MovementRules)
local Remotes = require(Shared.Remotes)
local WallRules = require(Shared.WallRules)
local Types = require(Shared.Types)

local World = ReplicatedStorage:WaitForChild("World")
local Barricade = require(World.Barricade)
local BoardRim = require(World.BoardRim)
local Platform = require(World.Platform)

type BoardState = Types.BoardState

local LOCAL_PLAYER = Players.LocalPlayer

--[[
	Baricada echipata de jucatorul de la tastatura.

	Se citeste din atributul scris de server — `Loadout` spune de ce sta acolo si
	nu pe un canal al lui. `nil` inseamna ca serverul inca n-a apucat sa-l scrie,
	iar `Barricade` cade atunci pe skinul de start; peste o clipa fantoma se
	reface oricum cu ce trebuie.
]]
local function equippedWall(): string?
	local id = LOCAL_PLAYER:GetAttribute(Loadout.attribute("Barricade"))
	return if typeof(id) == "string" then id else nil
end

local WorldController = {}
WorldController.__index = WorldController

type ControllerFields = {
	Platform: Platform.Platform?,
	State: BoardState?,
	Slot: number?,
	-- "IDLE" inseamna ca nu e tura ta: nimic de pe tabla nu raspunde.
	Mode: "MOVE" | "WALL" | "IDLE",
	Orientation: "Horizontal" | "Vertical",
	Connections: { RBXScriptConnection },
	CellConnections: { RBXScriptConnection },
	-- Cand a plecat ultima cerere de zid, ca o apasare sa nu trimita doua.
	LastWallRequest: number,
	-- Fantoma care urmareste cursorul in modul de baricada. E locala: nu o vede
	-- nimeni altcineva, pentru ca nu s-a asezat nimic inca.
	Ghost: Barricade.Barricade?,
	--[[
		Intersectia pe care sta fantoma acum. E si ce se trimite la clic: altfel
		ar exista doua raspunsuri la "unde cade zidul", si s-ar contrazice.
	]]
	Hover: { X: number, Y: number, Orientation: "Horizontal" | "Vertical" }?,
	--[[
		Ultimul punct de pe ecran catre care s-a tintit, pentru dispozitivele
		fara cursor. Vezi `updateHover`.
	]]
	Aim: Vector2?,
	-- Priveste de sus, in loc de inclinat. Se schimba din butonul VIEW.
	TopDown: boolean,
	--[[
		Inclinarea aratata *acum*, in grade, si firul care o duce catre cea
		ceruta. Perspectiva nu sare intre cele doua unghiuri: camera se roteste
		in jurul mesei pana ajunge la noul unghi. Vezi `aimCamera`.
	]]
	Pitch: number?,
	CameraMove: RBXScriptConnection?,
	--[[
		Slotul din care a fost asezata camera ultima oara.

		Masa se leaga si starea soseste pe doua drumuri separate. La un meci nou
		dupa unul pierdut, legarea putea castiga cursa: camera se aseza dupa
		slotul din meciul **trecut**, iar daca intre timp locurile se schimbasera
		priveai masa din partea adversarului. Tinut minte, `onState` vede cand
		slotul adevarat difera de cel dupa care s-a asezat camera, si o reaseaza.
	]]
	AimedSlot: number?,
	--[[
		A plecat deja camera spre castigator?

		Starea finala vine de mai multe ori — la fluierul final, si la orice
		altceva mai trimite serverul dupa el — iar plecarea are voie sa se
		intample o singura data. Repornita, ar sari inapoi la pozitia de deasupra
		mesei si ar lua-o de la capat.
	]]
	Celebrating: boolean,
	-- Bara de lumina de pe rama tablei. Exista cat e legata o masa.
	Rim: BoardRim.BoardRim?,
}

export type WorldController = typeof(setmetatable({} :: ControllerFields, WorldController))

--[[
	Sandbox-ul are nevoie de mesh-urile importate. Daca lipsesc, nu e o eroare —
	inseamna doar ca proiectul ruleaza inca pe interfata 2D.

	Se asteapta, nu se intreaba o singura data. `Assets` e un folder greu, cu
	sute de MeshPart-uri, iar replicarea lui nu e gata cand porneste scriptul
	clientului: o simpla verificare castiga cursa cand si cand, si atunci jocul
	pornea o data in 3D si o data in 2D, pe acelasi cod.
]]
local ASSET_WAIT = 20

function WorldController.isAvailable(): boolean
	local assets = ReplicatedStorage:WaitForChild("Assets", ASSET_WAIT)
	if not assets then
		return false
	end
	return assets:WaitForChild("Board", ASSET_WAIT) ~= nil
end

--[[
	Blocheaza mersul liber pe partea de client.

	Serverul taie oricum `WalkSpeed`, deci asta nu e masura de securitate, ci de
	confort: fara ea personajul se roteste si isi joaca animatia de mers pe loc
	la fiecare apasare de tasta.

	`PlayerModule` e injectat de Roblox dupa ce clientul a pornit, deci se
	asteapta pe un fir separat si cu termen. Un `WaitForChild` fara termen, chiar
	si intr-un `pcall`, ar bloca firul la nesfarsit.
]]
--[[
	Mersul liber, pornit sau oprit.

	Pe masa nu se merge cu WASD: te muti apasand pe o celula. In lobby insa
	trebuie sa poti umbla — vitrinele si podiumurile sunt acolo tocmai ca sa te
	duci la ele. De aceea controalele se taie cand intri pe o masa si se dau
	inapoi cand o parasesti, nu o data la pornirea clientului.
]]
local function setControls(enabled: boolean)
	task.spawn(function()
		local playerScripts = LOCAL_PLAYER:FindFirstChild("PlayerScripts")
		local moduleScript = playerScripts and playerScripts:WaitForChild("PlayerModule", 10)
		if not moduleScript then
			return
		end
		pcall(function()
			local controls = (require(moduleScript) :: any):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end)
end

--[[
	Camera se intoarce la avatar.

	`aimCamera` o trece pe `Scriptable` si o fixeaza deasupra mesei. Fara pasul
	invers, un jucator care termina meciul ramanea cu privirea pe o masa care
	tocmai fusese stearsa, iar lobby-ul nu se mai vedea niciodata.
]]
local function releaseCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = LOCAL_PLAYER.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
end

--[[
	Cat de sus, cat de inclinat si cat de ingust se priveste masa, stau in
	`GameConfig.Camera`. Sunt numere de reglat pana arata bine, si locul lor e
	acolo unde stau toate celelalte.
]]

--[[
	Asteapta ca toate celulele tablei sa ajunga la client.

	Nu exista semnal de "model complet" in Roblox, asa ca se numara pana se
	ajunge la cate trebuie. Termenul e generos: tabla are 156 de piese, iar pe o
	conexiune slaba pot veni incet.
]]
local CELL_WAIT = 30

local function countCells(model: Model): number
	local found = 0
	for _, piece in ipairs(model:GetDescendants()) do
		if piece:IsA("BasePart") and piece:GetAttribute("CellX") then
			found += 1
		end
	end
	return found
end

local function waitForCells(model: Model): boolean
	local expected = GameConfig.BoardSize * GameConfig.BoardSize
	local deadline = os.clock() + CELL_WAIT
	while countCells(model) < expected do
		if os.clock() > deadline then
			return false
		end
		model.DescendantAdded:Wait()
	end
	return true
end

function WorldController.new(): WorldController
	local self = setmetatable({}, WorldController) :: WorldController

	self.Mode = "IDLE"
	self.Orientation = "Horizontal"
	self.Aim = nil :: Vector2?
	self.TopDown = false
	self.Celebrating = false
	self.Connections = {}
	self.CellConnections = {}
	self.LastWallRequest = 0

	table.insert(
		self.Connections,
		LOCAL_PLAYER.CharacterAdded:Connect(function()
			--[[
				Un personaj nou aduce cu el camera implicita. Daca esti pe o masa,
				o punem la loc deasupra ei dupa ce serverul apuca sa te aseze pe
				celula; daca nu, ramai un jucator obisnuit intr-un lobby.
			]]
			if not self.Platform then
				setControls(true)
				self:stopCameraMove()
				self.Pitch = nil
				releaseCamera()
				return
			end
			setControls(false)
			task.wait(0.4)
			self:aimCamera()
		end)
	)

	--[[
		Serverul spune pe ce masa joci punand `ArenaId` pe jucator. Se asculta si
		schimbarile, nu doar valoarea de acum: meciul poate incepe mult dupa ce
		clientul a pornit, si se poate juca mai multe la rand.
	]]
	table.insert(
		self.Connections,
		LOCAL_PLAYER:GetAttributeChangedSignal("ArenaId"):Connect(function()
			self:bindArena()
		end)
	)
	self:bindArena()

	--[[
		Skinul echipat se schimba din magazin, adica din alta parte a ecranului.
		Fantoma de sub cursor trebuie sa arate obiectul cu care chiar cazi, deci
		se arunca si se reface cand alegerea se schimba.
	]]
	table.insert(
		self.Connections,
		LOCAL_PLAYER:GetAttributeChangedSignal(Loadout.attribute("Barricade")):Connect(function()
			self:dropGhost()
			self:updateHover()
		end)
	)

	table.insert(
		self.Connections,
		Remotes.get("GameStateUpdate").OnClientEvent:Connect(function(snapshot)
			self:onState(snapshot)
		end)
	)

	--[[
		Fantoma urmareste si degetul, nu doar cursorul.

		Pe telefon nu exista „deasupra": degetul e ori pe ecran, ori nicaieri.
		Cat timp fantoma se misca numai din `MouseMovement`, pe telefon nu se
		misca niciodata — zidul se punea orb, unde nimereai, iar regula care
		interzice inchiderea drumului nu se poate ghici fara sa vezi verdictul.
		Tras cu degetul, fantoma merge dupa el si spune verde sau rosu inainte de
		orice asezare.
	]]
	table.insert(
		self.Connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self:updateHover()
			elseif input.UserInputType == Enum.UserInputType.Touch and self.Mode == "WALL" then
				self:updateHover(Vector2.new(input.Position.X, input.Position.Y))
			end
		end)
	)

	--[[
		Zidul se aseaza din apasare, nu din clicul pe o celula.

		Celulele au rost intre ele, iar zidul sta *fix in rost* — acolo il si
		tintesti, fiindca acolo il vezi. Dar in rost nu e nicio celula, deci nu e
		niciun `ClickDetector` care sa raspunda, si apasarea cadea in gol. Un
		milimetru mai incolo nimereai o celula si mergea; de aici si "trebuie sa
		mut putin cursorul".

		Mutarea ramane pe celule, unde tinta *este* celula. Asezarea zidului nu
		mai intreaba peste ce anume s-a apasat: fantoma stie unde cade, si ea e
		singurul lucru care conteaza.
	]]
	table.insert(
		self.Connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			-- Butoanele interfetei si-au luat deja apasarea; nu le-o furam.
			if processed or self.Mode ~= "WALL" then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:placeWall()
			elseif input.UserInputType == Enum.UserInputType.Touch then
				self:touchWall(Vector2.new(input.Position.X, input.Position.Y))
			end
		end)
	)

	return self
end

--[[
	Cadrul mesei: de unde se priveste, incotro, si de la ce distanta.

	Se calculeaza o data si se foloseste pentru orice inclinare — asta e tot
	rostul separarii. Rotirea camerei intre privirea inclinata si cea de sus
	schimba **doar** unghiul; centrul, directia si distanta raman aceleasi, deci
	masa nu aluneca prin cadru cat tine miscarea.
]]
type Shot = {
	Center: Vector3,
	-- Incotro priveste jucatorul: dinspre marginea lui, catre obiectiv.
	Forward: Vector3,
	Distance: number,
}

local function frameFor(shot: Shot, pitchDegrees: number): CFrame
	local pitch = math.rad(pitchDegrees)
	local back = -shot.Forward * math.cos(pitch) * shot.Distance
	local up = Vector3.new(0, math.sin(pitch) * shot.Distance, 0)
	return CFrame.lookAt(shot.Center + back + up, shot.Center)
end

--[[
	De unde se priveste masa, si incotro.

	Un joc de societate se priveste de sus, nu peste umarul unui pion: de la
	nivelul avatarului nu se vede jumatate din tabla si nu se pot compara
	distantele pana la obiectiv. De aceea camera nu mai urmareste personajul.

	Orientarea nu e la fel pentru toti. Obiectivul tau ajunge intotdeauna in
	partea de sus a ecranului, iar directia lui se **masoara** din pozitiile
	celulelor, nu se presupune — tabla importata are axele intoarse fata de
	conventia logica, si un semn gresit ar aseza jumatate din jucatori cu
	spatele la tinta.
]]
function WorldController.shot(self: WorldController): Shot?
	local platform, state, slot = self.Platform, self.State, self.Slot
	local camera = workspace.CurrentCamera
	if not (platform and state and slot and camera) then
		return nil
	end

	--[[
		De partea cui se priveste. Implicit a ta; vezi `GameConfig.Camera` pentru
		ce se intampla cand camera trece de partea celui aflat la rand.
	]]
	if GameConfig.Camera.FollowTurn and state.Status == "PLAYING" then
		local current = BoardState.getCurrentSlot(state)
		if state.Players[current] then
			slot = current
		end
	end

	local nearCorner = platform:cellTop(1, 1)
	local farCorner = platform:cellTop(state.Size, state.Size)
	local homeEdge = platform:cellTop(1, 1)
	local goalEdge = platform:cellTop(1, state.Size)
	if not (nearCorner and farCorner and homeEdge and goalEdge) then
		return nil
	end

	local center = (nearCorner + farCorner) / 2
	-- Directia "spre randul 9" pe tabla, masurata din lume.
	local towardHighRows = (goalEdge - homeEdge).Unit

	--[[
		Fiecare jucator priveste dinspre marginea de pe care a plecat, cu fata
		spre tabla. Se citeste din pozitia de start, nu din obiectiv: in modurile
		cu centru obiectivul e acelasi pentru toti si n-ar spune din ce parte
		vine fiecare — toti ar fi privit din locul slotului 1.
	]]
	local mode = GameConfig.Modes[state.GameMode]
	local start = mode and mode.Slots[slot] and mode.Slots[slot].Start
	local forward = towardHighRows
	if start and start.Y == state.Size then
		forward = -towardHighRows
	elseif start and (start.X == 1 or start.X == state.Size) and start.Y ~= 1 then
		local left = platform:cellTop(1, 1)
		local right = platform:cellTop(state.Size, 1)
		if left and right then
			local towardHighFiles = (right - left).Unit
			forward = if start.X == 1 then towardHighFiles else -towardHighFiles
		end
	end

	--[[
		Distanta se calculeaza din **latura** mesei, nu din diagonala ei.

		Diagonala e cu 41% mai lunga decat latura, deci camera se retragea cu
		mult mai mult decat era nevoie ca sa incapa tabla, si masa ramanea mica in
		mijlocul ecranului. Ce trebuie sa incapa in cadru e amprenta ei, asa ca
		se ia direct din model, cu rama cu tot.
	]]
	local _, boardSize = platform.Model:GetBoundingBox()
	local span = math.max(boardSize.X, boardSize.Z)

	--[[
		Campul vizual se pune inainte de a socoti distanta, fiindca distanta se
		calculeaza din el. Lasat cum il gaseste, se foloseste cel implicit al
		Roblox-ului, si atunci numarul de aici n-ar insemna nimic.
	]]
	camera.FieldOfView = GameConfig.Camera.FieldOfView

	local distance = (span * GameConfig.Camera.Margin)
		/ (2 * math.tan(math.rad(camera.FieldOfView) / 2))

	return { Center = center, Forward = forward, Distance = distance }
end

-- Opreste o rotire in curs. Se cheama inainte de orice alta comanda de camera:
-- doua fire care scriu acelasi `CFrame` s-ar calca reciproc la fiecare cadru.
function WorldController.stopCameraMove(self: WorldController)
	local move = self.CameraMove
	if move then
		move:Disconnect()
		self.CameraMove = nil
	end
end

--[[
	Unde se vede pe ecran un loc de pe masa, in pixeli: deasupra pionului de pe
	celula, sau peste baricada. Iese din aceleasi `cellTop` si `cframeForWall`
	care aseaza avatarele si zidurile.

	`nil` cand locul e in spatele camerei sau masa nu e inca legata. Viewport-ul
	incepe din coltul ecranului, la fel ca un `ScreenGui` cu `IgnoreGuiInset`.
]]
function WorldController.screenPoint(
	self: WorldController,
	cell: Types.Cell,
	wall: Types.Wall?
): Vector2?
	local platform = self.Platform
	local camera = workspace.CurrentCamera
	if not (platform and camera) then
		return nil
	end

	local world: Vector3? = nil
	if wall then
		local frame = platform:cframeForWall(wall.X, wall.Y, wall.Orientation)
		world = frame and frame.Position
	else
		local top = platform:cellTop(cell.X, cell.Y)
		world = top and top + Vector3.new(0, GameConfig.Callouts.WorldLift, 0)
	end
	if not world then
		return nil
	end

	local point, visible = camera:WorldToViewportPoint(world)
	if not visible then
		return nil
	end
	return Vector2.new(point.X, point.Y)
end

--[[
	Un tremur scurt al camerei, pentru callout-urile mari.

	Merge pe `CameraMove`, ca orice alta miscare: nu porneste peste o rotire
	in curs sau peste plecarea spre castigator, iar o comanda noua de camera il
	opreste pe loc. Fiecare cadru scoate deplasarea de dinainte si o pune pe
	cea noua, deci la final camera ramane exact unde era.
]]
function WorldController.shakeCamera(self: WorldController)
	local camera = workspace.CurrentCamera
	if not (camera and self.Platform) or self.CameraMove or self.Celebrating then
		return
	end

	local amount = GameConfig.Callouts.ShakeAmount
	local seconds = GameConfig.Callouts.ShakeSeconds
	local began = os.clock()
	local applied = CFrame.identity

	self.CameraMove = RunService.RenderStepped:Connect(function()
		local live = workspace.CurrentCamera
		if not live then
			self:stopCameraMove()
			return
		end

		local base = live.CFrame * applied:Inverse()
		local left = 1 - (os.clock() - began) / seconds
		if left <= 0 then
			live.CFrame = base
			self:stopCameraMove()
			return
		end

		local strength = amount * left
		applied =
			CFrame.new((math.random() * 2 - 1) * strength, (math.random() * 2 - 1) * strength, 0)
		live.CFrame = base * applied
	end)
end

--[[
	Duce camera la unghiul cerut de perspectiva curenta.

	`animate` e adevarat doar cand jucatorul apasa VIEW. La legarea mesei sau la
	reaparitia personajului camera se **pune**, nu se plimba: n-ai de unde sti de
	unde ar pleca, iar o alunecare la inceputul meciului arata ca o eroare, nu ca
	o intentie.

	Se interpoleaza unghiul, nu `CFrame`-ul. Intre doua pozitii de camera, Roblox
	merge in linie dreapta si taie prin spatiu: masa se apropie si se departeaza
	in timpul miscarii, si framing-ul se strica la mijloc. Interpoland unghiul,
	camera se roteste pe un arc in jurul mesei — distanta si centrul raman exacte
	la fiecare cadru, deci tabla sta locului si doar perspectiva se schimba.
]]
function WorldController.aimCamera(self: WorldController, animate: boolean?)
	local camera = workspace.CurrentCamera
	local shot = self:shot()
	if not (camera and shot) then
		return
	end

	self:stopCameraMove()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	self.AimedSlot = self.Slot

	local target = if self.TopDown then GameConfig.Camera.TopPitch else GameConfig.Camera.Pitch
	local from = self.Pitch

	if not animate or from == nil or math.abs(target - from) < 0.01 then
		self.Pitch = target
		camera.CFrame = frameFor(shot, target)
		return
	end

	local start = from :: number
	local began = os.clock()
	local seconds = GameConfig.Camera.ViewSeconds

	self.CameraMove = RunService.RenderStepped:Connect(function()
		local live = workspace.CurrentCamera
		if not live then
			self:stopCameraMove()
			return
		end

		local progress = math.clamp((os.clock() - began) / seconds, 0, 1)
		--[[
			Incetinire spre final, nu viteza constanta. O camera care pleaca lin
			si se aseaza lin se citeste ca o intoarcere a privirii; una care
			porneste si se opreste brusc, ca o taietura de montaj — exact ce nu
			vrem, pentru ca nu s-a schimbat scena, ci doar unghiul din care e
			privita.
		]]
		local eased =
			TweenService:GetValue(progress, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local pitch = start + (target - start) * eased
		self.Pitch = pitch
		live.CFrame = frameFor(shot, pitch)

		if progress >= 1 then
			self:stopCameraMove()
		end
	end)
end

--[[
	Cadrul castigatorului: din fata lui, putin de sus.

	Se priveste dinspre directia in care se uita el, nu dintr-un unghi ales de
	noi: avatarul sta intors spre obiectivul pe care tocmai l-a atins, iar o
	camera asezata oriunde altundeva l-ar arata din spate sau din profil la
	finalul propriului meci.

	Se recalculeaza la fiecare cadru, si de aceea primeste corpul, nu o pozitie:
	castigatorul urca in clipele alea pe soclul care iese din celula, iar un
	cadru socotit o singura data ar ramane sa priveasca locul in care era.
	Cat timp corpul inca nu a ajuns la client, se priveste celula — tot acolo va
	fi si el.
]]
local function winnerFrame(character: Model?, cell: Vector3): CFrame
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local body = if root and root:IsA("BasePart") then root else nil

	local focus = if body then body.Position else cell + Vector3.new(0, 3, 0)
	local look = if body then body.CFrame.LookVector else Vector3.new(0, 0, 1)

	-- Doar directia din plan: inclinarea cadrului o da inaltimea, nu capul lui.
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)

	local eye = focus
		+ flat * GameConfig.Camera.WinnerDistance
		+ Vector3.new(0, GameConfig.Camera.WinnerHeight, 0)
	return CFrame.lookAt(eye, focus)
end

--[[
	Camera pleaca de unde e catre castigator, si ramane pe el.

	Miscarea se interpoleaza intre `CFrame`-uri, si aici chiar asta se vrea —
	spre deosebire de schimbarea de perspectiva, unde camera trebuie sa ramana pe
	un arc in jurul mesei. Nu se reasaza aceeasi imagine, ci se pleaca din ea:
	un drum drept de deasupra tablei pana in fata omului care a castigat.

	Firul nu se opreste la capatul drumului. Tinta se muta in continuare — soclul
	inca urca — si camera trebuie sa urce cu ea; se stinge abia cand masa se
	desprinde, din `stopCameraMove`.
]]
function WorldController.followWinner(self: WorldController, slot: number?)
	local platform, state = self.Platform, self.State
	local camera = workspace.CurrentCamera
	if not (platform and state and slot and camera) then
		return
	end

	local playerState = state.Players[slot]
	if not playerState then
		return
	end

	local cell = platform:cellTop(playerState.Position.X, playerState.Position.Y)
	if not cell then
		return
	end

	local winner = Players:GetPlayerByUserId(playerState.UserId)

	self:stopCameraMove()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	local from = camera.CFrame
	local began = os.clock()
	local seconds = GameConfig.Camera.WinnerSeconds

	self.CameraMove = RunService.RenderStepped:Connect(function()
		local live = workspace.CurrentCamera
		if not live then
			self:stopCameraMove()
			return
		end

		local progress = math.clamp((os.clock() - began) / seconds, 0, 1)
		local eased =
			TweenService:GetValue(progress, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local character = if winner then winner.Character else nil
		live.CFrame = from:Lerp(winnerFrame(character, cell), eased)

		local root = character and character:FindFirstChild("HumanoidRootPart")
		local focus = if root and root:IsA("BasePart")
			then root.Position
			else cell + Vector3.new(0, 3, 0)
		self:fadeOccluders(live.CFrame.Position, focus)
	end)
end

-- Leaga controllerul de tabla meciului curent, sau il desprinde la final.
function WorldController.bindArena(self: WorldController)
	for _, connection in self.CellConnections do
		connection:Disconnect()
	end
	self.CellConnections = {}
	self.Platform = nil
	-- Rama se strange odata cu masa ei; cea noua se face cand se leaga tabla.
	if self.Rim then
		self.Rim:destroy()
		self.Rim = nil
	end
	-- Masa noua, ceremonie noua: urmatorul meci are voie sa se termine si el.
	self.Celebrating = false
	self.AimedSlot = nil

	--[[
		Fantoma apartine mesei pe care a fost facuta.

		E parintita in modelul tablei, iar cand serverul darama masa o ia cu ea.
		Tinuta mai departe, meciul urmator o muta pe tabla noua ca pe un model
		viu, desi nu mai e in lume — deci nu se mai vedea nicio previzualizare,
		nici verde, nici rosie. Se arunca odata cu masa si se reface pe cea noua.
	]]
	self:dropGhost()
	self.Hover = nil
	self.Aim = nil

	local arenaId = LOCAL_PLAYER:GetAttribute("ArenaId")
	if typeof(arenaId) ~= "string" then
		--[[
			Starea meciului trecut pleaca si ea. Pastrata, prima legare a mesei
			urmatoare ar aseza camera dupa slotul vechi si ar aprinde celulele
			vechiului meci pana la sosirea starii noi.
		]]
		self.State = nil
		self.Slot = nil
		-- Fara meci nu exista masa: jucatorul se intoarce la mersul lui prin lobby.
		setControls(true)
		self:stopCameraMove()
		--[[
			Unghiul se uita odata cu masa. Pastrat, urmatorul meci ar incepe cu o
			rotire de la perspectiva meciului trecut catre cea noua, desi camera
			tocmai a fost asezata din nimic.
		]]
		self.Pitch = nil
		releaseCamera()
		return
	end

	local arenas = workspace:WaitForChild("Arenas", 10)
	local container = arenas and arenas:WaitForChild("Arena_" .. arenaId, 10)
	local model = container and container:WaitForChild("Platform", 10)
	if not (model and model:IsA("Model")) then
		warn("WorldController: nu am gasit tabla meciului " .. arenaId)
		return
	end

	--[[
		Se asteapta tabla **intreaga**, nu doar aparitia modelului.

		Roblox replica piesele pe rand, iar `WaitForChild("Platform")` intoarce
		modelul din clipa in care exista, cu oricat de putin in el. Legat atunci,
		clientul indexa cate celule apucasera sa ajunga — s-au vazut 23 din 81 —
		si restul tablei ramanea pentru el inexistenta: fara evidentieri, fara
		clicuri, deci fara mutari. La a doua pornire mergea, pentru ca piesele
		erau deja in cache.
	]]
	if not waitForCells(model) then
		warn("WorldController: tabla nu s-a replicat complet pentru meciul " .. arenaId)
	end

	local platform = Platform.attach(model)
	self.Platform = platform
	self.Rim = BoardRim.new(model, function(x: number, y: number): Vector3?
		return platform:cellTop(x, y)
	end, GameConfig.BoardSize)
	setControls(false)
	self.CellConnections = platform:onCellClicked(function(x, y)
		self:onCellClicked(x, y)
	end)

	--[[
		Se redeseneaza imediat ce tabla e legata.

		Evidentierile se calculau doar la primirea starii, iar legarea tablei si
		sosirea starii sunt doua curse independente: daca tabla se lega dupa
		ultimul `GameStateUpdate` — cazul obisnuit, pentru ca legarea asteapta
		replicarea arenei — nu se mai aprindea nimic niciodata, si jocul parea
		blocat desi era randul tau.
	]]
	self:paintGoal()
	self:aimCamera()
	self:refresh()
end

--[[
	Starea proaspata de la server. Se reconstruieste in intregime: un snapshot
	e adevarul complet, nu o diferenta, deci nu exista nimic de impacat.
]]
function WorldController.onState(self: WorldController, snapshot: any)
	if not snapshot then
		return
	end

	local ok, state = pcall(BoardState.fromSnapshot, snapshot)
	if not ok or not state then
		return
	end
	self.State = state

	self.Slot = nil
	for slot, player in state.Players do
		if player.UserId == LOCAL_PLAYER.UserId then
			self.Slot = slot
		end
	end

	--[[
		Camera se reaseaza cand afla ca a privit din locul altcuiva.

		Nu si dupa fluierul final: acolo o duce `followWinner`, iar o reasezare
		ar smulge-o de pe castigator.
	]]
	if
		self.Platform
		and self.Slot ~= nil
		and self.Slot ~= self.AimedSlot
		and state.Status ~= "FINISHED"
	then
		self:aimCamera()
	end

	self:paintGoal()
	self:refresh()
	self:updateHover()

	--[[
		Fluierul final muta camera de pe masa pe om. O singura data: starea
		finala mai vine de cateva ori dupa ea, iar o a doua plecare ar smuci
		imaginea inapoi de unde a inceput.
	]]
	if state.Status == "FINISHED" and not self.Celebrating then
		self.Celebrating = true
		self:followWinner(state.Winner)

		-- Rama sarbatoreste si ea, in culoarea castigatorului.
		local rim = self.Rim
		if rim and state.Winner then
			local perMode = GameConfig.TeamColors[state.GameMode]
			local hex = if perMode
				then perMode[state.Winner]
				else GameConfig.SlotColors[state.Winner]
			rim:victory(if hex then Color3.fromHex(string.format("%06X", hex)) else nil)
		end
	end
end

-- Culoarea unui slot, aceeasi care leaga pionul de cardul din interfata.
local function slotColor(state: BoardState, slot: number): Color3
	local perMode = GameConfig.TeamColors[state.GameMode]
	local hex = if perMode then perMode[slot] else GameConfig.SlotColors[slot]
	return Color3.fromHex(string.format("%06X", hex or 0x888888))
end

--[[
	Marginea de pornire a unui slot, ca lista de celule.

	Se citeste din `GameConfig`, nu din stare: starea poarta pozitia *de acum* a
	jucatorului, iar dupa prima mutare nu mai spune de unde a plecat.
]]
local function homeCells(state: BoardState, slot: number): { { X: number, Y: number } }
	local mode = GameConfig.Modes[state.GameMode]
	local start = mode and mode.Slots[slot] and mode.Slots[slot].Start
	if not start then
		return {}
	end

	local cells = {}
	if start.Y == 1 or start.Y == state.Size then
		for x = 1, state.Size do
			table.insert(cells, { X = x, Y = start.Y })
		end
	elseif start.X == 1 or start.X == state.Size then
		for y = 1, state.Size do
			table.insert(cells, { X = start.X, Y = y })
		end
	end
	return cells
end

--[[
	Coloreaza tabla, o data per meci.

	Celulele pe care se termina meciul iau `GameConfig.GoalColor`, aceeasi in
	toate modurile: randul de pe partea cealalta in 1v1, celula din centru cand
	sunt trei sau patru. Marginile de pornire iau culoarea jucatorului, ca sa se
	vada si de unde a plecat fiecare.

	Tinta aratata e a ta: in 1v1 randul tau de sosire e chiar casa
	adversarului, iar acolo castiga turcoazul. Cine priveste fara sa joace vede
	tintele tuturor.

	E o tenta, nu o vopsea: peste ea trebuie sa se mai vada verdele mutarilor
	legale, iar lemnul tablei nu are voie sa dispara sub culoare. Tinta e mai
	apasata decat casele, fiindca ea e cea care trebuie gasita.
]]
local HOME_TINT = 0.28
local GOAL_TINT = 0.5

function WorldController.paintGoal(self: WorldController)
	local platform, state = self.Platform, self.State
	if not (platform and state) then
		return
	end
	if next(platform.GoalCells) ~= nil then
		return
	end

	local goals: { { X: number, Y: number } } = {}
	local isGoal: { [string]: boolean } = {}
	for slot, player in state.Players do
		if self.Slot == nil or slot == self.Slot then
			for _, cell in BoardUtils.getTargetCells(player.Objective) do
				local id = BoardUtils.cellKey(cell)
				if not isGoal[id] then
					isGoal[id] = true
					table.insert(goals, cell)
				end
			end
		end
	end

	for slot in state.Players do
		local cells = {}
		for _, cell in homeCells(state, slot) do
			if not isGoal[BoardUtils.cellKey(cell)] then
				table.insert(cells, cell)
			end
		end
		if #cells > 0 then
			platform:paintGoal(cells, slotColor(state, slot), HOME_TINT)
		end
	end

	platform:paintGoal(goals, nil, GOAL_TINT)
end

--[[
	Ce se aprinde depinde de ce urmeaza sa faci si de al cui e randul.

	Cand nu e randul tau nu se aprinde nimic: o tabla plina de verde in timp ce
	asteapti ar promite o mutare pe care serverul oricum ar refuza-o.
]]
function WorldController.refresh(self: WorldController)
	local platform, state, slot = self.Platform, self.State, self.Slot
	if not (platform and state and slot) then
		return
	end

	if state.Status ~= "PLAYING" or not BoardState.isPlayersTurn(state, slot) then
		platform:clearHighlights()
		return
	end

	if self.Mode == "MOVE" then
		platform:showLegalCells(MovementRules.getLegalMoves(state, slot))
	else
		platform:clearHighlights()
	end
end

--[[
	Fantoma de zid care urmareste cursorul.

	Arata unde ar cadea baricada **inainte** sa o pui, si daca ar fi primita:
	verde-translucid pentru o asezare valida, rosie pentru una respinsa. Fara
	ea, plasarea e o ghicitoare — intersectiile nu se vad pe tabla, iar regula
	care interzice inchiderea drumului nu se poate intui din privire.

	Verdictul il da tot `WallRules`, pe starea de la server. Nu e o a doua
	implementare a regulii, ci aceeasi functie intrebata mai devreme.
]]
function WorldController.updateHover(self: WorldController, point: Vector2?)
	local platform, state, slot = self.Platform, self.State, self.Slot
	local camera = workspace.CurrentCamera
	if not (platform and state and slot and camera) then
		self:hideHover()
		return
	end

	local playable = state.Status == "PLAYING" and BoardState.isPlayersTurn(state, slot)
	if self.Mode ~= "WALL" or not playable then
		self:hideHover()
		return
	end

	--[[
		Unde se tinteste.

		Cu mouse, raspunsul e mereu acelasi: unde sta cursorul, fiindca el sta
		undeva si cand nu apesi. Cu degetul nu exista asa ceva — ridicat, degetul
		nu e nicaieri — deci ultima tintire se tine minte. Fara ea, rotirea din
		buton ar arunca fantoma: `refresh` cheama `updateHover` fara punct, si pe
		telefon n-ar mai fi de unde sa-l ia.
	]]
	if point then
		self.Aim = point
	end

	local aim = if UserInputService.MouseEnabled
		then UserInputService:GetMouseLocation()
		else self.Aim
	if not aim then
		self:hideHover()
		return
	end

	local ray = camera:ViewportPointToRay(aim.X, aim.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { platform.Model }

	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if not hit then
		self:hideHover()
		return
	end

	--[[
		Intersectia cea mai apropiata de punctul atins. Se cauta prin toate:
		sunt 64, iar o cautare completa e mai ieftina decat un cadru pierdut
		cu geometrie inversa pe o tabla ale carei axe nu le presupunem.
	]]
	local bestX, bestY, bestDistance = nil, nil, math.huge
	for x = 1, state.Size - 1 do
		for y = 1, state.Size - 1 do
			local cframe = platform:cframeForWall(x, y, self.Orientation)
			if cframe then
				local distance = (cframe.Position - hit.Position).Magnitude
				if distance < bestDistance then
					bestX, bestY, bestDistance = x, y, distance
				end
			end
		end
	end
	if not (bestX and bestY) then
		self:hideHover()
		return
	end

	local verdict = WallRules.isValidWallPlacement(state, slot, bestX, bestY, self.Orientation)

	-- O fantoma ramasa pe alta masa, sau luata de pe lume cu ea, nu se mai vede.
	local stale = self.Ghost
	if stale and not stale.Model:IsDescendantOf(platform.Model) then
		self:dropGhost()
	end

	if self.Ghost == nil then
		self.Ghost = Barricade.new(
			platform,
			{ X = bestX, Y = bestY, Orientation = self.Orientation },
			equippedWall()
		)
	end

	local ghost = self.Ghost
	if ghost == nil then
		return
	end

	if ghost.X ~= bestX or ghost.Y ~= bestY or ghost.Orientation ~= self.Orientation then
		ghost:relocate(platform, bestX, bestY, self.Orientation)
	end

	ghost:setVisible(true)
	ghost:setPreview(if verdict.Ok then "VALID" else "INVALID")

	-- Legate in variabile fara `nil`: garda de mai sus le-a verificat deja, dar
	-- tipul lor ramane optional pentru ca se atribuie intr-o bucla.
	local hoverX: number, hoverY: number = bestX, bestY
	self.Hover = { X = hoverX, Y = hoverY, Orientation = self.Orientation }
end

function WorldController.hideHover(self: WorldController)
	self.Hover = nil
	if self.Ghost then
		self.Ghost:setVisible(false)
	end
end

--[[
	Primeste modul de joc de la `GameController`, singurul lui proprietar.

	Lumea nu hotaraste niciodata singura daca esti pe mutare sau pe baricada: ar
	fi a doua stare pentru acelasi lucru, si s-ar desincroniza de butoanele din
	interfata. Tot de aici vin si celulele legale, deja calculate — nu are rost
	sa fie cerute motorului de doua ori pentru acelasi cadru.
]]
function WorldController.setInteraction(
	self: WorldController,
	mode: string,
	legalCells: { { X: number, Y: number } },
	orientation: string
)
	--[[
		`IDLE` e un mod in sine, nu o mutare fara evidentieri.

		Pana acum orice nu era "WALL" ajungea "MOVE", deci cand nu era tura ta
		lumea tinea minte ca esti in mutare si primea in continuare clicuri pe
		celule. Iar clicul pe celula se incheie la **ridicarea** degetului: pui un
		zid, tura trece la celalalt, si tocmai ridicarea aceleiasi apasari trimite
		o mutare care nu mai are cum sa fie primita. De acolo venea sunetul de
		refuz la fiecare zid pus, desi zidul se punea.

		Cine nu e la rand nu apasa nimic. Asta spune `IDLE`.
	]]
	self.Mode = if mode == "WALL" then "WALL" elseif mode == "IDLE" then "IDLE" else "MOVE"
	self.Orientation = if orientation == "Vertical" then "Vertical" else "Horizontal"

	local platform = self.Platform
	if not platform then
		return
	end

	--[[
		Verdele ramane doar pentru mutari.

		In modul de baricada aprindeam si intersectiile libere, dar ele sunt
		aproape toate: tabla se facea verde aproape in intregime si nu mai spunea
		nimic. Unde cade zidul si daca e primit se vede oricum din fantoma de sub
		cursor, care e un raspuns exact, nu o harta.
	]]
	if self.Mode == "MOVE" then
		platform:showLegalCells(legalCells)
	else
		platform:clearHighlights()
	end

	self:updateHover()
end

--[[
	Schimba intre privirea inclinata si cea de sus. Intoarce pe care a ramas, ca
	interfata sa-si scrie eticheta din acelasi adevar, nu dintr-o copie a lui.
]]
function WorldController.toggleView(self: WorldController): boolean
	self.TopDown = not self.TopDown
	self:aimCamera(true)
	return self.TopDown
end

--[[
	Fantoma se reface cu skinul de acum.

	Nu se recoloreaza: un skin e un model intreg, nu o culoare. Stearsa aici, se
	construieste din nou la prima miscare de mouse, cu obiectul nou — si numai
	daca jucatorul chiar e in modul de baricada.
]]
function WorldController.dropGhost(self: WorldController)
	local ghost = self.Ghost
	if not ghost then
		return
	end
	self.Ghost = nil
	ghost:destroy()
end

--[[
	Clic pe o celula. Nu se aplica nimic local, se cere.

	In modul de baricada, celula apasata denumeste intersectia din coltul ei;
	ultimul rand si ultima coloana nu au colt propriu, deci nu trimit nimic.
]]
function WorldController.onCellClicked(self: WorldController, x: number, y: number)
	local state = self.State
	if not state or state.Status ~= "PLAYING" then
		return
	end

	--[[
		Doar mutarea. Zidul are propria apasare, fiindca tinta lui nu e o celula
		si nu are cum sa fie — vezi `placeWall`.
	]]
	if self.Mode == "MOVE" then
		Remotes.get("RequestMove"):FireServer({ X = x, Y = y })
	end
end

--[[
	Cere asezarea zidului aratat de fantoma.

	Se trimite **intersectia pe care o arata fantoma**, nu vreun colt socotit
	separat. Erau odata doua socoteli pentru acelasi lucru, si zidul se aseza
	langa locul in care il vedeai; acum previzualizarea e singura sursa.

	Fantoma se recalculeaza aici, la apasare, nu se citeste de unde a ramas:
	altfel raspunsul atarna de cand a fost ultima oara pusa la zi, si nu de unde
	tii cursorul. O raza si saizeci si patru de comparatii — mai ieftin decat
	cadrul pe care il pierdeai oricum.
]]
--[[
	Cat de aproape pot veni doua apasari fara sa fie considerate una singura.

	O apasare trebuie sa trimita o singura cerere. Pe unele ecrane aceeasi
	atingere ajunge de doua ori — o data ca `Touch`, o data ca `MouseButton1`,
	fiindca motorul o traduce si in mouse — iar a doua cerere ajunge la server
	dupa ce prima a mutat tura, deci e refuzata. Asta e refuzul care se auzea la
	fiecare zid pus, desi zidul se punea.

	O zecime de secunda si ceva e sub ce poate apasa un om de doua ori si mult
	peste distanta dintre cele doua fete ale aceleiasi atingeri. Oricum, intr-o
	tura nu se poate pune decat un zid.
]]
local PRESS_GAP = 0.2

function WorldController.placeWall(self: WorldController, point: Vector2?)
	local state = self.State
	if not state or state.Status ~= "PLAYING" then
		return
	end

	local now = os.clock()
	if now - self.LastWallRequest < PRESS_GAP then
		return
	end

	self:updateHover(point)

	local hover = self.Hover
	if not hover then
		return
	end

	self.LastWallRequest = now
	Remotes.get("RequestPlaceWall"):FireServer(hover.X, hover.Y, hover.Orientation)

	--[[
		Tintirea se uita dupa ce zidul a plecat.

		Pastrata, pe telefon urmatoarea tura ar incepe cu fantoma deja asezata
		acolo unde a cazut cea dinainte — si atunci **prima** atingere in locul
		ala ar fi luata drept confirmare, adica exact plasarea din greseala pe
		care o taie regula celor doua atingeri.
	]]
	self.Aim = nil
	self:hideHover()
end

--[[
	Zidul, pus cu degetul: o atingere tinteste, a doua aseaza.

	Pe mouse cele doua sunt deja separate — muti cursorul, vezi verdictul, si
	abia apoi apesi. Degetul face amandoua deodata: atingi si ai si pus. Iar
	singura regula grea a jocului — ca nu ai voie sa inchizi complet drumul
	cuiva — se citeste doar din fantoma, adica din ceva ce pe telefon nu apuca
	sa se vada niciodata.

	Asa, prima atingere aduce fantoma sub deget si o coloreaza; a doua, pe
	aceeasi intersectie, o aseaza. Intre ele poti trage degetul, sau roti din
	buton, si nimic nu pleaca la server pana nu confirmi acolo unde vezi.
]]
function WorldController.touchWall(self: WorldController, point: Vector2)
	local before = self.Hover
	self:updateHover(point)

	local aimed = self.Hover
	if not aimed then
		return
	end

	local confirms = before ~= nil
		and before.X == aimed.X
		and before.Y == aimed.Y
		and before.Orientation == aimed.Orientation

	if confirms then
		self:placeWall(point)
	end
end

function WorldController.destroy(self: WorldController)
	self:stopCameraMove()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for _, connection in self.CellConnections do
		connection:Disconnect()
	end
	self.Connections = {}
	self.CellConnections = {}
	if self.Ghost then
		self.Ghost:destroy()
		self.Ghost = nil
	end
	if self.Rim then
		self.Rim:destroy()
		self.Rim = nil
	end
end

--[[
	Latura de pe care a plecat un jucator, cu numele laturii ramei. Se citeste
	din `GameConfig`, ca `homeCells`: starea stie doar unde e acum.
]]
local function homeSide(state: BoardState, slot: number): BoardRim.Side?
	local mode = GameConfig.Modes[state.GameMode]
	local start = mode and mode.Slots[slot] and mode.Slots[slot].Start
	if not start then
		return nil
	end
	if start.Y == 1 then
		return "Y1"
	elseif start.Y == state.Size then
		return "Y9"
	elseif start.X == 1 then
		return "X1"
	elseif start.X == state.Size then
		return "X9"
	end
	return nil
end

--[[
	Rama raspunde la callout-urile unei actiuni.

	Primul din lista — cel mai important — hotaraste treapta: mic, mare sau
	epic, dupa marimea lui. Efectul pleaca de unde s-a intamplat: de pe
	baricada, sau de sub pionul care a sarit. Peste el, seria de blocaje isi
	pune caruselul si insigna, iar partea celui blocat ingheata.

	Aceeasi pentru toti de la masa: e un eveniment al tablei, nu al cuiva.
]]
function WorldController.playRim(self: WorldController, list: { any })
	local rim, platform, state = self.Rim, self.Platform, self.State
	if not (rim and platform and state) then
		return
	end

	local function origin(callout: any): Vector3?
		local wall = callout.Wall
		if type(wall) == "table" and type(wall.X) == "number" and type(wall.Y) == "number" then
			local frame = platform:cframeForWall(wall.X, wall.Y, wall.Orientation)
			if frame then
				return frame.Position
			end
		end
		local cell = callout.Cell
		if type(cell) == "table" and type(cell.X) == "number" and type(cell.Y) == "number" then
			return platform:cellTop(cell.X, cell.Y)
		end
		return nil
	end

	local lead = list[1]
	local at = if type(lead) == "table" then origin(lead) else nil
	if not at then
		return
	end

	local tier = if type(lead.Tier) == "number" then lead.Tier else 1
	if tier >= 3 then
		rim:mega()
	elseif tier == 2 then
		rim:big()
	else
		rim:small(at)
	end

	for _, callout in list do
		if type(callout) ~= "table" then
			continue
		end
		local where = origin(callout) or at
		if type(callout.Streak) == "number" and callout.Streak >= 2 then
			rim:combo(callout.Streak, where)
		end
		if
			type(callout.Target) == "number"
			and string.sub(tostring(callout.Id), 1, 5) == "BLOCK"
		then
			local side = homeSide(state, callout.Target)
			if side then
				rim:frost(side :: BoardRim.Side)
			end
		end
	end
end

--[[
	Baricadele dintre camera si castigator se fac pe jumatate stravezii.

	Camera coboara in fata omului, la inaltimea lui, iar un zid pus acolo in
	timpul meciului i-ar acoperi tocmai momentul lui. Se estompeaza doar pe
	ecranul asta (`LocalTransparencyModifier`) si doar zidurile care chiar stau
	intre ochi si om — celelalte raman cum sunt, ca tabla sa se citeasca in
	continuare. Trecerea e moale, cadru cu cadru, cat se misca si camera.
]]
local OCCLUDED = 0.75

function WorldController.fadeOccluders(self: WorldController, eye: Vector3, focus: Vector3)
	local platform = self.Platform
	if not platform then
		return
	end

	local span = focus - eye
	local length = span.Magnitude
	if length < 0.01 then
		return
	end
	local direction = span / length
	local a, b = platform:cellTop(1, 1), platform:cellTop(2, 1)
	local step = if a and b then (b - a).Magnitude else 7

	for _, child in platform.Model:GetChildren() do
		if not (child:IsA("Model") and string.sub(child.Name, 1, 10) == "Barricade_") then
			continue
		end
		local center = child:GetBoundingBox().Position
		local along = math.clamp((center - eye):Dot(direction), 0, length)
		local between = along > 0.5 and along < length - 1
		local close = (center - (eye + direction * along)).Magnitude < step * 1.1
		local target = if between and close then OCCLUDED else 0

		for _, piece in child:GetDescendants() do
			if piece:IsA("BasePart") then
				local now = piece.LocalTransparencyModifier
				piece.LocalTransparencyModifier = now + (target - now) * 0.2
			end
		end
	end
end

return WorldController
