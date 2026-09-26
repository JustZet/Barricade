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
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")

local Theme = require(script.UI.Theme)
local BoardView = require(script.UI.BoardView)
local CalloutView = require(script.UI.CalloutView)
local ConfirmView = require(script.UI.ConfirmView)
local HudView = require(script.UI.HudView)
local LobbyView = require(script.UI.LobbyView)
local MusicButton = require(script.UI.MusicButton)
local RematchView = require(script.UI.RematchView)
local VictoryView = require(script.UI.VictoryView)

local WalletView = require(script.UI.WalletView)
local StoreView = require(script.UI.StoreView)
local PlayersView = require(script.UI.PlayersView)
local ChallengeView = require(script.UI.ChallengeView)
local SocialToast = require(script.UI.SocialToast)
local InviteView = require(script.UI.InviteView)
local SocialController = require(script.Controllers.SocialController)

local GameController = require(script.Controllers.GameController)
local SoundController = require(script.Controllers.SoundController)

--[[
	Semnalul prin care ecranul de incarcare afla ca poate pleca.

	Cortina e ridicata de `ReplicatedFirst.Boot`, care porneste inaintea acestui
	script si nu are de unde sti cand lobby-ul e desenat. Un atribut pe jucator e
	tot ce trebuie: nu e canal de retea — nu iese nimic din clientul asta — deci
	nu are ce cauta in `Remotes`. Numele trebuie sa fie acelasi in amandoua
	locurile, si asta e singurul lor punct de atingere.
]]
local READY_ATTRIBUTE = "BarricadeClientReady"

local function markReady()
	LOCAL_PLAYER:SetAttribute(READY_ATTRIBUTE, true)
end

--[[
	Lista de jucatori a Roblox-ului se stinge.

	Jocul isi tine deja oamenii pe ecran, si mai bine decat ea: cardurile din
	HUD spun nume, culoare, ceas, cate baricade au ramas si cine e la mutare.
	Lista din dreapta repeta doar numele — si le pune peste tabla, care in 3D
	urca pana sus in coltul acela.

	Se incearca de cateva ori: `SetCoreGuiEnabled` cere ca interfata de baza sa
	fie deja acolo, iar la pornirea clientului uneori inca nu e. Un `pcall` care
	esueaza in tacere ar lasa lista aprinsa fara sa spuna nimeni de ce.
]]
local function hidePlayerList()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.2)
	end
	warn("[Barricade] lista de jucatori a Roblox-ului nu a putut fi stinsa")
end

task.spawn(hidePlayerList)

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

--[[
	Muzica porneste cand se ridica ecranul de incarcare, nu cand porneste
	scriptul. Boot-ul scrie atributul la sfarsit, oricum s-ar fi terminat — cu
	cortina, fara ea sau pe varianta 2D. Numele e acelasi ca in
	`src/boot/init.client.luau`.
]]
local CURTAIN_ATTRIBUTE = "BarricadeCurtainLifted"
if LOCAL_PLAYER:GetAttribute(CURTAIN_ATTRIBUTE) then
	SoundController.allowMusic()
else
	LOCAL_PLAYER:GetAttributeChangedSignal(CURTAIN_ATTRIBUTE):Once(function()
		SoundController.allowMusic()
	end)
end

-- Muzica se comuta din bara de sus, oriunde ai fi: in lobby sau la masa.
MusicButton.new(PLAYER_GUI, SoundController.toggleMusic)
	:setEnabled(SoundController.isMusicEnabled())

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
	-- Bannerul votului de revansa, peste ecranul de final.
	Rematch = RematchView.new(backdrop),
	--[[
		Banutii stau in afara paginilor lobby-ului, nu inauntrul lor: soldul e
		acelasi si in meniu, si in coada, si in timpul meciului. Pus intr-o
		pagina, ar disparea odata cu ea si ar trebui redesenat in fiecare.
	]]
	Wallet = WalletView.new(backdrop),
	--[[
		Intrebarea de dinaintea plecarii sta ultima in tabel, si asta se si vede
		pe ecran: construita dupa toate celelalte, cade peste ele.
	]]
	Confirm = ConfirmView.new(backdrop),
	--[[
		Callout-urile de dupa mutari au ecranul lor, peste tot restul: trec peste
		tabla si carduri fara sa prinda vreun clic.
	]]
	Callouts = CalloutView.new(PLAYER_GUI),
	-- Stratul social: lista de jucatori, bannerul provocarii, notificarile.
	Players = PlayersView.new(backdrop),
	Challenge = ChallengeView.new(backdrop),
	SocialToast = SocialToast.new(backdrop),
	Invite = InviteView.new(backdrop),
}

--[[
	Controllerul social se face dupa vederile lui si inaintea lui `GameController`,
	care il anunta cand intri si iesi din lobby.
]]
views.Social = SocialController.new(views, backdrop)

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

	Ecranul nu se mai ridica de aici. Scriptul asta porneste abia dupa ce Roblox
	si-a strans ecranul lui si a aratat lumea, deci o cortina pusa aici vine
	mereu prea tarziu — apare peste ceva ce s-a vazut deja incarcandu-se. Acum o
	pune `ReplicatedFirst.Boot`, inainte de primul cadru, iar de aici se spune
	doar cand e gata de ridicat: vezi `READY_ATTRIBUTE`.
]]
if worldMode then
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
			markReady()
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

		--[[
			Abia acum e lobby-ul intreg. Cortina se ridica peste vitrinele pline si
			peste steagurile care deja flutura, nu peste soclurile goale care se
			umplu sub ochii jucatorului.
		]]
		markReady()
	end)

	print("[Barricade] lume 3D pornita — clic pe celula ca sa te muti, R = rotire zidul")
else
	markReady()
	print("[Barricade] client pornit")
end
