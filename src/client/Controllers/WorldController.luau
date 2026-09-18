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
local GameConfig = require(Shared.GameConfig)
local MovementRules = require(Shared.MovementRules)
local Remotes = require(Shared.Remotes)
local WallRules = require(Shared.WallRules)
local Types = require(Shared.Types)

local World = ReplicatedStorage:WaitForChild("World")
local Barricade = require(World.Barricade)
local Platform = require(World.Platform)
local Skins = require(World.Skins)

type BoardState = Types.BoardState

local LOCAL_PLAYER = Players.LocalPlayer

local WorldController = {}
WorldController.__index = WorldController

type ControllerFields = {
	Platform: Platform.Platform?,
	State: BoardState?,
	Slot: number?,
	Mode: "MOVE" | "WALL",
	Orientation: "Horizontal" | "Vertical",
	Connections: { RBXScriptConnection },
	CellConnections: { RBXScriptConnection },
	-- Fantoma care urmareste cursorul in modul de baricada. E locala: nu o vede
	-- nimeni altcineva, pentru ca nu s-a asezat nimic inca.
	Ghost: Barricade.Barricade?,
	--[[
		Intersectia pe care sta fantoma acum. E si ce se trimite la clic: altfel
		ar exista doua raspunsuri la "unde cade zidul", si s-ar contrazice.
	]]
	Hover: { X: number, Y: number, Orientation: "Horizontal" | "Vertical" }?,
	-- Priveste de sus, in loc de inclinat. Se schimba din butonul VIEW.
	TopDown: boolean,
	--[[
		Inclinarea aratata *acum*, in grade, si firul care o duce catre cea
		ceruta. Perspectiva nu sare intre cele doua unghiuri: camera se roteste
		in jurul mesei pana ajunge la noul unghi. Vezi `aimCamera`.
	]]
	Pitch: number?,
	CameraMove: RBXScriptConnection?,
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

	self.Mode = "MOVE"
	self.Orientation = "Horizontal"
	self.TopDown = false
	self.Connections = {}
	self.CellConnections = {}

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

	table.insert(
		self.Connections,
		Remotes.get("GameStateUpdate").OnClientEvent:Connect(function(snapshot)
			self:onState(snapshot)
		end)
	)

	table.insert(
		self.Connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self:updateHover()
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
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:placeWall()
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
		Fiecare jucator priveste dinspre marginea lui. Slotul 1 porneste jos si
		urca, slotul 2 invers; pentru restul modurilor, obiectivul din stare
		spune incotro trebuie sa ajunga.
	]]
	local objective = state.Players[slot].Objective
	local forward = towardHighRows
	if objective.Edge == "Y_MIN" then
		forward = -towardHighRows
	elseif objective.Edge == "X_MAX" or objective.Edge == "X_MIN" then
		local left = platform:cellTop(1, 1)
		local right = platform:cellTop(state.Size, 1)
		if left and right then
			local towardHighFiles = (right - left).Unit
			forward = if objective.Edge == "X_MAX" then towardHighFiles else -towardHighFiles
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

-- Leaga controllerul de tabla meciului curent, sau il desprinde la final.
function WorldController.bindArena(self: WorldController)
	for _, connection in self.CellConnections do
		connection:Disconnect()
	end
	self.CellConnections = {}
	self.Platform = nil

	local arenaId = LOCAL_PLAYER:GetAttribute("ArenaId")
	if typeof(arenaId) ~= "string" then
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

	self:paintGoal()
	self:refresh()
	self:updateHover()
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
	Coloreaza marginile, o data per meci.

	Fiecare jucator isi primeste marginea in culoarea lui, si toti le vad pe
	toate: asa se citeste dintr-o privire si de unde ai plecat, si incotro
	trebuie sa ajungi — tinta ta e marginea adversarului.

	E o tenta, nu o vopsea: peste ea trebuie sa se mai vada verdele mutarilor
	legale, iar lemnul tablei nu are voie sa dispara sub culoare.
]]
local HOME_TINT = 0.28

function WorldController.paintGoal(self: WorldController)
	local platform, state = self.Platform, self.State
	if not (platform and state) then
		return
	end
	if next(platform.GoalCells) ~= nil then
		return
	end

	for slot in state.Players do
		local cells = homeCells(state, slot)
		if #cells > 0 then
			platform:paintGoal(cells, slotColor(state, slot), HOME_TINT)
		end
	end

	-- In modurile cu obiectiv la centru, tinta e o singura celula.
	local anySlot = next(state.Players)
	local objective = if anySlot then state.Players[anySlot].Objective else nil
	if objective and objective.Kind == "CENTER" and objective.Cell then
		platform:paintGoal({ { X = objective.Cell.X, Y = objective.Cell.Y } }, nil, 0.45)
	end
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
function WorldController.updateHover(self: WorldController)
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

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
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

	if self.Ghost == nil then
		self.Ghost = Barricade.new(
			platform,
			{ X = bestX, Y = bestY, Orientation = self.Orientation },
			Skins.Default
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
	self.Mode = if mode == "WALL" then "WALL" else "MOVE"
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
	if self.Mode == "MOVE" and mode ~= "IDLE" then
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

-- Skinul cu care iti cazi zidurile. Serverul il citeste la asezare.
function WorldController.setSkin(_self: WorldController, skinId: string)
	LOCAL_PLAYER:SetAttribute("WallSkin", Skins.get(skinId).Id)
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
function WorldController.placeWall(self: WorldController)
	local state = self.State
	if not state or state.Status ~= "PLAYING" then
		return
	end

	self:updateHover()

	local hover = self.Hover
	if not hover then
		return
	end
	Remotes.get("RequestPlaceWall"):FireServer(hover.X, hover.Y, hover.Orientation)
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
end

return WorldController
