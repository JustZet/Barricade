--!strict
--[[
	Barricade — punctul de intrare al clientului.

	Construieste ecranul, fixeaza camera si preda controlul mai departe.

	Tot jocul se petrece intr-un ScreenGui. Nu exista avatar care sa umble pe
	harta, nu exista camera de urmarit si nu exista fizica: o tabla 2D
	privita de sus, cum arata si un joc de societate pe masa.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")

local Theme = require(script.UI.Theme)
local BoardView = require(script.UI.BoardView)
local HudView = require(script.UI.HudView)
local LobbyView = require(script.UI.LobbyView)
local VictoryView = require(script.UI.VictoryView)

local LoadingView = require(script.UI.LoadingView)
local WalletView = require(script.UI.WalletView)
local StoreView = require(script.UI.StoreView)

local GameController = require(script.Controllers.GameController)
local SoundController = require(script.Controllers.SoundController)

--[[
	Camera ramane imobila. Fara asta, o camera fara personaj de urmarit
	ramane sa pluteasca prin lume si se vede in spatele interfetei.
]]
local function lockCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(Vector3.new(0, 60, 0), Vector3.new(0, 0, 0))
	camera.FieldOfView = 55
end

local function calmLighting()
	Lighting.Ambient = Color3.fromHex("1A1E2A")
	Lighting.OutdoorAmbient = Color3.fromHex("1A1E2A")
	Lighting.Brightness = 0
	Lighting.GlobalShadows = false
	Lighting.FogEnd = 200
	Lighting.FogColor = Theme.Color.Backdrop
end

--[[
	Sandbox-ul 3D, cand asseturile de lume sunt importate.

	Cand porneste, camera si lumina raman cele normale: varianta 2D le stingea
	tocmai pentru ca nu exista nimic de vazut in spatele interfetei, iar acum
	exista o masa si un avatar pe ea. Interfata de tabla 2D se ascunde, ca sa nu
	existe doua table deodata.
]]
local WorldController = require(script.Controllers.WorldController)
local ShowcaseController = require(script.Controllers.ShowcaseController)
local worldMode = WorldController.isAvailable()

if not worldMode then
	lockCamera()
	calmLighting()
	--[[
		Paznicul care readuce camera la loc daca altcineva o misca. Sta si el sub
		acelasi `if`: in lumea 3D camera *trebuie* sa poata trece pe `Custom` ca
		sa urmareasca avatarul, iar un paznic lasat activ ar anula schimbarea in
		aceeasi clipa in care se face.
	]]
	Workspace.CurrentCamera:GetPropertyChangedSignal("CameraType"):Connect(lockCamera)
end

SoundController.init()

local screen = Theme.create("ScreenGui", {
	Name = "BarricadeUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = PLAYER_GUI,
}) :: ScreenGui

local backdrop = Theme.create("Frame", {
	Name = "Backdrop",
	BackgroundColor3 = Theme.Color.Backdrop,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = screen,
}) :: Frame

--[[
	Zona tablei: un patrat centrat care nu intra niciodata peste barele de
	sus si de jos. Constrangerea de aspect din BoardView face restul, deci
	tabla ramane patrata pe orice ecran, de la telefon la monitor lat.
]]
local boardArea = Theme.create("Frame", {
	Name = "BoardArea",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.48),
	Size = UDim2.fromScale(0.62, 0.78),
	Parent = backdrop,
}) :: Frame

local views = {
	Board = BoardView.new(boardArea),
	Hud = HudView.new(backdrop),
	Lobby = LobbyView.new(backdrop),
	Victory = VictoryView.new(backdrop),
	--[[
		Banutii stau in afara paginilor lobby-ului, nu inauntrul lor: soldul e
		acelasi si in meniu, si in coada, si in timpul meciului. Pus intr-o
		pagina, ar disparea odata cu ea si ar trebui redesenat in fiecare.
	]]
	Wallet = WalletView.new(backdrop),
}

--[[
	Magazinul exista doar daca are cu ce se desena.

	Fereastra lui e un desen cu asezarea coapta in el; fara ea n-ar fi un magazin
	mai simplu, ci unul rupt. Cat timp asset-ul lipseste nu se construieste, si
	lobby-ul nu pune nici butonul care l-ar deschide.
]]
if StoreView.available() then
	views.Store = StoreView.new(backdrop)
end

--[[
	Lumea 3D intra in acelasi tablou de reprezentari ca tabla 2D.

	`GameController` detine modul de joc si il impinge catre tot ce deseneaza.
	Daca lumea s-ar crea dupa el, primul meci ar porni cu butoanele nelegate:
	de aceea se face aici, inainte, si i se preda ca `views.World`.
]]
if worldMode then
	views.World = WorldController.new()
end

views.Board.Container.Visible = false
views.Hud:setSoundEnabled(SoundController.isEnabled())

--[[
	`GameController` ramane la post si in lumea 3D.

	El e cel care duce meciul de la lobby la victorie: cozile, numaratoarea,
	cardurile jucatorilor, ecranul de final. Nimic din toate astea nu se schimba
	pentru ca tabla a trecut in 3D — singurul lucru care nu mai are ce cauta pe
	ecran e tabla desenata, fiindca exista una adevarata sub picioarele tale.

	`WorldController` se adauga peste, nu in locul lui: ii ia doar rolul de a
	arata mutarile si de a primi clicurile.
]]
GameController.new(views)

--[[
	Ecranul de incarcare, doar in lumea 3D.

	Varianta 2D nu are ce astepta: tabla ei e desenata, nu adusa de pe server.
	Aici insa mesh-urile sunt sute de piese, si daca nu sunt cerute din timp
	apar una cate una in timpul meciului.

	Preincarcarea ruleaza pe un fir separat: blocheaza ecranul, nu si restul
	pornirii, asa ca lobby-ul si controllerele sunt gata in spatele lui.
]]
if worldMode then
	local loading = LoadingView.new(PLAYER_GUI)
	loading:animateTitle()
	loading:spinEmblem()

	task.spawn(function()
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		loading:preload(if assets then { assets } else {})
		loading:finish()
	end)

	backdrop.BackgroundTransparency = 1

	--[[
		Tabla 2D ramane ascunsa. `GameController` o aprinde la inceputul fiecarui
		meci, deci nu ajunge sa o stingem o data — trebuie tinuta stinsa, la fel
		cum varianta 2D isi tine camera fixata.
	]]
	local board = views.Board.Container
	board.Visible = false
	board:GetPropertyChangedSignal("Visible"):Connect(function()
		if board.Visible then
			board.Visible = false
		end
	end)

	--[[
		Vitrinele din lobby se umplu din ReplicatedStorage, nu din machetele
		aduse de import. Decorul e treaba clientului, deci ruleaza pe un fir
		separat: daca lobby-ul inca nu s-a replicat, asteptarea lui nu are voie
		sa tina pe loc pornirea meciului.
	]]
	--[[
		Lobby-ul se asteapta, nu se cauta o data. Cu `StreamingEnabled` pornit nu
		e acolo cand porneste clientul, iar o simpla verificare ar pleca fara el
		si ar lasa si vitrinele, si steagurile nefacute.
	]]
	local LOBBY_WAIT = 20

	task.spawn(function()
		local lobby = Workspace:WaitForChild("Lobby", LOBBY_WAIT)
		if not lobby then
			warn("[Barricade] lobby-ul nu a ajuns la client; decorul ramane nefacut")
			return
		end
		local World = ReplicatedStorage:WaitForChild("World")

		local Showcase = require(World.Showcase)
		local stands = Showcase.build(lobby)
		print(string.format("[Barricade] %d vitrine umplute in lobby", #stands))

		--[[
			Ofertele vin dupa vitrine, si din ele: fiecare soclu primeste placuta
			lui si un `ProximityPrompt`, ca obiectul expus sa poata fi cumparat
			de pe loc. Magazinul ramane pentru cine vrea sa vada tot raftul.
		]]
		ShowcaseController.attach(stands)

		--[[
			Steagurile sunt decor pur, ca si vitrinele: se misca doar pe client.
			Nu tin de niciun meci, deci nu se opresc niciodata — pornesc odata cu
			lobby-ul si flutura pana la deconectare.

			`Flag.build` isi pandeste singura piesele care mai sosesc, deci nu are
			nevoie de nimic aici: nu se numara steagurile acum, fiindca la ora
			asta streaming-ul inca nu le-a adus pe toate si cifra ar minti.
		]]
		local Flag = require(World.Flag)
		Flag.build(lobby)
		print("[Barricade] steagurile din lobby flutura")
	end)

	print("[Barricade] lume 3D pornita — clic pe celula ca sa te muti, R = rotire zidul")
else
	print("[Barricade] client pornit")
end
