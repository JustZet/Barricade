--!strict
--[[
	HudView — tot ce inconjoara tabla in timpul meciului.

	Cardurile jucatorilor, indicatorul de tura, butoanele de actiune,
	contorul de baricade si mesajele scurte. Si aici, zero reguli: primeste
	stare, deseneaza, anunta apasarile prin callback.

	**Tot ce se vede aici sta intr-un colt al ecranului, nu peste tabla.** HUD-ul
	nu e o fereastra, ci patru gramezi lipite de marginile ecranului: randul de
	sus, cardurile sub el, butoanele jos si setarile in dreapta jos. Marimea lor
	e in pixeli, fiindca placile de lemn sunt desene cu proportii fixe — si de
	aceea, pe un ecran mic, raman la fel de mari in timp ce tabla se micsoreaza,
	pana ajung sa o acopere. Exact asta se intampla pe telefon: cardurile de sus
	mancau primele randuri de celule, si nu mai aveai pe ce sa apesi.

	`fit` e raspunsul: aceleasi gramezi, micsorate cu totul cat sa lase tabla
	descoperita. Nu se rearanjeaza nimic si nu exista o a doua asezare „de
	telefon" — ar fi fost inca un ecran de intretinut, care s-ar fi despartit de
	asta la prima modificare.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Types = require(Shared.Types)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local Avatars = require(script.Parent.Avatars)
local Theme = require(script.Parent.Theme)

type BoardState = Types.BoardState

local HudView = {}
HudView.__index = HudView

--[[
	Ecranul pentru care e desenat HUD-ul, si cat de mic are voie sa ajunga.

	1280x720 e masura la care cardurile de 240 pe 100 si butoanele de 46 arata
	cum au fost desenate. Sub ea totul se micsoreaza proportional; peste ea nu se
	mareste, fiindca un card cat palma pe un monitor lat nu ajuta pe nimeni.

	Pragul de jos nu e ales din frumusete, ci din citit: sub el numele
	jucatorilor si cifrele ceasului ajung sub sapte pixeli si nu se mai disting.
	Mai bine un HUD care acopera putin decat unul care nu spune nimic.
]]
local DESIGN_W, DESIGN_H = 1280, 720
local MIN_SCALE = 0.55

--[[
	Randul de sus: doar contorul de ture, si cat mai subtire.

	Aici statea si numele jocului, cu litere de 22. Nu mai sta: in timpul unui
	meci nu-l citeste nimeni, iar randul lui impingea cardurile cu 56 de pixeli
	peste tabla — adica peste primul rand de celule, chiar cel pe care pionii se
	misca cel mai des. Numele jocului se vede oricum in lobby, inainte sa intri.

	Ce a ramas e o dunga de 22 de pixeli chiar de la marginea de sus a ecranului,
	cat sa incapa "TURN 3 · 1v1", si sub ea cardurile — mai sus de atat nu se
	poate.
]]
local TOP_BAR_H = 22

local BOTTOM_MARGIN, BOTTOM_BAR_H, BOTTOM_BAR_W = 16, 70, 460
local SETTINGS_W = 150

--[[
	Cardul, si golul dintre doua carduri.

	Stau aici, nu langa desen, pentru ca `fit` are nevoie de ele: latimea
	randului de carduri depinde de cati jucatori sunt, si un rand de patru pe un
	ecran ingust trebuie sa incapa chiar daca pentru asta trebuie coborat sub
	pragul de citit. Un card iesit de pe ecran nu se citeste deloc.
]]
local CARD_W, CARD_H, CARD_GAP = 240, 100, 10

--[[
	Cat de mic are voie sa ajunga un buton.

	Degetul nu se micsoreaza odata cu ecranul. La 0.78, „MOVE" ramane inalt de
	36 de pixeli, aproape de cei 44 pe care ii cere orice indrumar de atins cu
	degetul, si mult peste cei 25 la care ar ajunge daca s-ar micsora cat
	cardurile. Pragul cade doar cand butoanele chiar n-au loc unele langa altele.
]]
local TOUCH_FLOOR = 0.78

--[[
	Campurile sunt declarate, nu deduse. Altfel Luau nu stie in `update` ce e
	`self.Toast` si trateaza fiecare element ca pe un `Instance` gol.
]]
type HudFields = {
	Callbacks: { [string]: any },
	Cards: { [number]: Frame },
	Mode: string,
	Root: Frame,
	TurnCounter: TextLabel,
	PlayersPanel: Frame,
	--[[
		Micsorarile, in doua grupe.

		`Scales` sunt gramezile care se citesc — cardurile, banda de tura,
		mesajul scurt — si care se pot face mici cat le lasa cititul.
		`TouchScales` sunt cele care se apasa, si care se micsoreaza mai putin.
		Inauntrul fiecarei grupe valoarea e aceeasi pentru toti: doua carduri la
		doua marimi ar arata ca doua interfete suprapuse.
	]]
	Scales: { UIScale },
	TouchScales: { UIScale },
	MoveButton: TextButton,
	WallButton: TextButton,
	RotateButton: TextButton,
	TurnBanner: TextLabel,
	Toast: TextLabel,
	SoundButton: TextButton,
	ViewButton: TextButton,
	LeaveButton: TextButton,
}

export type HudView = typeof(setmetatable({} :: HudFields, HudView))

--[[
	Micsorarea unei gramezi.

	`UIScale` scade deodata marimea cutiei, pozitiile dinauntru si marimea
	textului, iar scaderea se face in jurul punctului de ancorare. De aceea
	gramada ramane lipita de marginea ei: cardurile raman centrate sus, butoanele
	centrate jos, setarile in coltul din dreapta jos. Pus pe ecranul intreg, ar
	fi mutat tocmai marginile alea spre mijloc.
]]
local function shrinkable(container: Instance): UIScale
	return Theme.create("UIScale", { Scale = 1, Parent = container }) :: UIScale
end

local function slotColor(state: BoardState, slot: number): Color3
	local perMode = GameConfig.TeamColors[state.GameMode]
	local hex = if perMode then perMode[slot] else GameConfig.SlotColors[slot]
	return Color3.fromHex(string.format("%06X", hex or 0x888888))
end

function HudView.new(parent: Instance): HudView
	local self = setmetatable({}, HudView) :: HudView

	self.Callbacks = {} :: { [string]: any }
	self.Cards = {} :: { [number]: Frame }
	self.Mode = "MOVE"

	local root = Theme.create("Frame", {
		Name = "Hud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	}) :: Frame
	self.Root = root

	-- ------------------------------------------------------------ bara de sus
	--[[
		Randul de sus e singurul care se intinde pe toata latimea, deci nu se
		micsoreaza ca celelalte: ce sta in el e lipit de mijloc, iar mijlocul nu
		se muta, oricat de lat ar fi ecranul. Sta la pixelul zero, in dunga pe
		care bara Roblox o lasa libera intre butoanele ei si lista de jucatori.
	]]
	local topBar = Theme.create("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TOP_BAR_H),
		Parent = root,
	}) :: Frame

	--[[
		Contorul de ture sta la mijloc, nu in coltul din dreapta.

		Colturile de sus nu sunt ale noastre: in stanga Roblox pune meniul, chatul
		si microfonul, iar in dreapta lista de jucatori — exact peste ea cadea
		contorul, si se citea pe jumatate. La mijloc e singura bucata de rand pe
		care n-o cere nimeni, si cade oricum chiar deasupra cardurilor, care sunt
		si ele centrate.
	]]
	self.TurnCounter = Theme.text({
		Name = "TurnCounter",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.6, 1),
		Parent = topBar,
	})

	-- ------------------------------------------------------- panoul jucatorilor
	--[[
		Cardurile stau sus, la mijloc, pe un rand.

		Pe coloana din stanga intrau peste meniul si chatul Roblox, care ocupa
		exact coltul acela pe orice ecran. La mijloc raman libere, se citesc toate
		dintr-o privire si nu acopera tabla, care in 3D incepe mai jos.
	]]
	local playersPanel = Theme.create("Frame", {
		Name = "PlayersPanel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP_BAR_H),
		Size = UDim2.fromOffset(980, CARD_H),
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, CARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	self.PlayersPanel = playersPanel
	self.Scales = { shrinkable(playersPanel) }
	self.TouchScales = {}

	-- ------------------------------------------------------------- bara de jos
	local bottomBar = Theme.create("Frame", {
		Name = "BottomBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
		Size = UDim2.fromOffset(BOTTOM_BAR_W, BOTTOM_BAR_H),
		Parent = root,
	}) :: Frame
	table.insert(self.TouchScales, shrinkable(bottomBar))

	local actions = Theme.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = bottomBar,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	}) :: Frame

	self.MoveButton = Theme.button({
		Name = "MoveButton",
		Text = "MOVE",
		Skin = "Secondary",
		Size = UDim2.fromOffset(150, 46),
		LayoutOrder = 1,
		Parent = actions,
	})

	self.WallButton = Theme.button({
		Name = "WallButton",
		Text = "BARRICADE",
		Skin = "Secondary",
		Size = UDim2.fromOffset(170, 46),
		LayoutOrder = 2,
		Parent = actions,
	})

	self.RotateButton = Theme.button({
		Name = "RotateButton",
		Text = "R",
		Skin = "Square",
		Size = UDim2.fromOffset(46, 46),
		LayoutOrder = 3,
		Parent = actions,
	})

	-- --------------------------------------------------------- indicator tura
	self.TurnBanner = Theme.text({
		Name = "TurnBanner",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -94),
		Size = UDim2.fromOffset(500, 34),
		Parent = root,
	})
	table.insert(self.Scales, shrinkable(self.TurnBanner))

	-- Mesajele de refuz: apar scurt, langa butoane, si dispar singure.
	self.Toast = Theme.text({
		Name = "Toast",
		Text = "",
		TextColor3 = Theme.Color.Invalid,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -130),
		Size = UDim2.fromOffset(520, 22),
		Parent = root,
	})
	table.insert(self.Scales, shrinkable(self.Toast))

	-- ------------------------------------------------------------- setari
	local settings = Theme.create("Frame", {
		Name = "Settings",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -BOTTOM_MARGIN, 1, -BOTTOM_MARGIN),
		Size = UDim2.fromOffset(SETTINGS_W, 114),
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	}) :: Frame
	table.insert(self.TouchScales, shrinkable(settings))

	self.SoundButton = Theme.button({
		Name = "SoundButton",
		Text = "SOUND: ON",
		TextSize = 13,
		Skin = "Pill",
		Size = UDim2.fromOffset(150, 34),
		LayoutOrder = 1,
		Parent = settings,
	})

	--[[
		Comutatorul de perspectiva.

		Privirea inclinata arata volumul pieselor, dar la ea distantele se
		citesc greu: doua celule la fel de departate par diferite, dupa cat de
		aproape sunt de tine. Privirea de sus pierde volumul si castiga exact
		lucrul ala — de sus tabla e o grila, si se numara pe ea. Fiecare e buna
		la altceva, deci se schimba intre ele, nu se alege una.
	]]
	self.ViewButton = Theme.button({
		Name = "ViewButton",
		Text = "VIEW: ANGLED",
		TextSize = 13,
		Skin = "Pill",
		Size = UDim2.fromOffset(150, 34),
		LayoutOrder = 2,
		Parent = settings,
	})

	self.LeaveButton = Theme.button({
		Name = "LeaveButton",
		Text = "LEAVE",
		TextSize = 13,
		Skin = "Pill",
		Size = UDim2.fromOffset(150, 34),
		LayoutOrder = 3,
		Parent = settings,
	})

	self.MoveButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onMode
		if callback then
			callback("MOVE")
		end
	end)

	self.WallButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onMode
		if callback then
			callback("WALL")
		end
	end)

	self.RotateButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onRotate
		if callback then
			callback()
		end
	end)

	self.ViewButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onToggleView
		if callback then
			callback()
		end
	end)

	self.SoundButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onToggleSound
		if callback then
			callback()
		end
	end)

	self.LeaveButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onLeave
		if callback then
			callback()
		end
	end)

	self:fit()

	--[[
		Ecranul se poate schimba in timpul meciului: telefonul se roteste,
		fereastra Studio se trage de colt. HUD-ul se remasoara atunci, nu doar la
		pornire.
	]]
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:fit()
		end)
	end

	return self
end

--[[
	Incadreaza HUD-ul in ecranul de acum.

	Doua lucruri deodata, si amandoua tin de acelasi rau — HUD-ul acopera tabla
	pe ecran mic:

	1. Gramezile se micsoreaza cu totul, proportional, pana la pragul de sub care
	   textul nu se mai citeste. Un card de 240 de pixeli pe un telefon de 812
	   acoperea un sfert din latime si primele doua randuri de celule.
	2. Butoanele se micsoreaza mai putin. Un card se citeste, un buton se apasa,
	   iar degetul nu se face mai mic odata cu ecranul: sub `TOUCH_FLOOR`,
	   „MOVE" ar ajunge o dunga de un centimetru pe care o ratezi. Ele coboara
	   sub prag doar cand chiar nu mai au loc unele langa altele.

	Randul de sus si cardurile nu apar aici deloc, si merita spus de ce.
	Pozitia lor e fixa, pusa o data la constructie: incep de la pixelul zero al
	ecranului. Interfata e desenata peste tot ecranul
	(`IgnoreGuiInset`), iar bara Roblox nu ocupa tot randul de sus, ci doar
	capetele lui — in stanga meniul, chatul si microfonul, in dreapta lista de
	jucatori. Mijlocul ramane liber, si acolo stau si contorul, si cardurile,
	amandoua centrate. Coborate cu inaltimea barii, cum erau, lasau deasupra o
	dunga goala cat un rand de celule, si pentru nimic: pe sub ea nu trecea
	nimeni.

	Restul gramezilor sunt lipite de marginile ecranului, si nici acolo nu e
	nimic de socotit.
]]
function HudView.fit(self: HudView)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local wanted = math.clamp(math.min(viewport.X / DESIGN_W, viewport.Y / DESIGN_H), MIN_SCALE, 1)

	--[[
		Randul de carduri nu are voie sa iasa din ecran, nici sub pragul de citit.

		Patru carduri fac 990 de pixeli; pe un telefon tinut in picioare nu incap
		nici micsorate cat le lasa cititul. Dintre doua rele, textul mic e mai
		bun decat un jucator ramas peste marginea ecranului, pe care nu-l vezi
		deloc — de aceea limita asta bate pragul, singura care face asta.
	]]
	local count = 0
	for _ in self.Cards do
		count += 1
	end
	local row = if count > 0 then count * CARD_W + (count - 1) * CARD_GAP else CARD_W
	local scale = math.min(wanted, (viewport.X - BOTTOM_MARGIN * 2) / row)

	for _, shrink in self.Scales do
		shrink.Scale = scale
	end

	--[[
		Cat de departe poate ajunge coltul cu setarile de mijlocul ecranului
		inainte sa intre peste butoanele de actiune. Jumatate din bara de jos,
		plus coloana din dreapta, plus doua margini.
	]]
	local room = (viewport.X / 2 - BOTTOM_MARGIN * 2) / (BOTTOM_BAR_W / 2 + SETTINGS_W)
	local touch = math.min(math.max(scale, TOUCH_FLOOR), room, 1)
	for _, shrink in self.TouchScales do
		shrink.Scale = touch
	end

	--[[
		Banda de tura si mesajul scurt stau deasupra butoanelor, deci urmeaza
		inaltimea lor, nu micsorarea cardurilor.
	]]
	local aboveButtons = BOTTOM_MARGIN + BOTTOM_BAR_H * touch
	self.TurnBanner.Position = UDim2.new(0.5, 0, 1, -(aboveButtons + 8 * scale))
	self.Toast.Position = UDim2.new(0.5, 0, 1, -(aboveButtons + 44 * scale))
end

function HudView.setCallbacks(self: HudView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

function HudView.setVisible(self: HudView, visible: boolean)
	-- Ecranul se putea schimba cat timp meciul nu era pe el.
	if visible then
		self:fit()
	end
	self.Root.Visible = visible
end

-- ------------------------------------------------------------ carduri

--[[
	Cardul de jucator. Placa de lemn il leaga vizual de restul interfetei, iar
	informatia sta pe trei niveluri: cine e (avatar plus nume), cat mai are
	(zidurile) si daca e randul lui (marcajul din stanga).

	Culoarea jucatorului nu mai e o banda la marginea cardului, ci inelul din
	jurul avatarului: sta lipita de fata omului, deci se leaga mai usor de
	pionul de pe tabla.
]]
local function buildCard(state: BoardState, slot: number, parent: Instance): Frame
	local player = state.Players[slot]
	local color = slotColor(state, slot)

	local card = Theme.create("Frame", {
		Name = "Card_" .. slot,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		LayoutOrder = slot,
		Parent = parent,
	}) :: Frame

	--[[
		Placa e un desen intreg, nu o placa taiata in noua.

		Cardul are marime fixa, aceeasi pentru toti, deci nu se intinde niciodata
		— iar o placa cu colturi sculptate, intinsa prin 9-slice, isi pierde
		tocmai sculptura de la colturi. Pusa asa cum a fost desenata, se vede
		exact ce a desenat artistul.
	]]
	Theme.create("ImageLabel", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Card.Plate,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		Parent = card,
	})

	--[[
		Coronita arata cine e la mutare, si tine locul vechii sageti.

		Ocupa loc si cand e ascunsa: aparuta si disparuta la fiecare tura ar
		impinge numele de langa ea dintr-o parte in alta.
	]]
	Theme.create("ImageLabel", {
		Name = "TurnMarker",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Card.Crown,
		ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(202, 12),
		Size = UDim2.fromOffset(28, 24),
		Visible = false,
		Parent = card,
	})

	--[[
		Poza sta **sub** inel, nu in el.

		Inelul e gaurit la mijloc tocmai ca sa se vada prin el. Asa rama ramane
		cea desenata, aceeasi pentru toti, iar inauntru fiecare isi vede chipul.
		Culoarea jucatorului ramane dedesubt si se vede cat se incarca poza, ca
		sa nu apara o gaura in card.

		Sub poza sta initiala, la fel ca pe pionul de pe tabla. Inainte aici era
		un `rbxthumb://` pus direct in `Image`: pentru un id fara poza — jucatorii
		de test din Studio — ramanea o imagine goala, fara sa spuna ca a esuat,
		deci cardul arata ca un cerc colorat fara nimic in el. `Avatars` spune
		daca a venit ceva, si pana atunci — sau pentru totdeauna — se vede litera.
	]]
	local avatar = Theme.create("ImageLabel", {
		Name = "Avatar",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(15, 15),
		Size = UDim2.fromOffset(66, 66),
		Parent = card,
	}, {
		Theme.corner(Theme.Radius.Round),
		Theme.text({
			Name = "Initial",
			Text = string.sub(player.Name, 1, 1):upper(),
			Font = Theme.Font.Bold,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
		}),
	}) :: ImageLabel

	local initial = avatar:FindFirstChild("Initial") :: TextLabel
	Avatars.fetch(player.UserId, function(image)
		if avatar.Parent then
			avatar.Image = image
			-- Litera e copil, deci s-ar desena peste poza. Cand poza vine, pleaca.
			initial.Visible = false
		end
	end)

	Theme.create("ImageLabel", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Card.Ring,
		ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(88, 88),
		Parent = card,
	})

	Theme.text({
		Name = "PlayerName",
		Text = player.Name,
		Font = Theme.Font.Bold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(100, 12),
		Size = UDim2.fromOffset(98, 24),
		Parent = card,
	})

	-- Semnul zidurilor, si numarul lor. Semnul spune ce e, cifra spune cat.
	Theme.create("ImageLabel", {
		Name = "WallIcon",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Card.Wall,
		ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(174, 47),
		Size = UDim2.fromOffset(22, 22),
		Parent = card,
	})

	Theme.text({
		Name = "Barricades",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(199, 46),
		Size = UDim2.fromOffset(34, 24),
		Parent = card,
	})

	--[[
		Ceasul, in dreapta cardului.

		Are nevoie de spatiu propriu, nu de o bucata din randul cu zidurile: se
		schimba in fiecare secunda, iar un text care creste si scade langa altul
		l-ar face pe celalalt sa sara.
	]]
	--[[
		Cele doua offseturi de mai jos nu sunt rotunjiri, sunt o corectie.

		Desenul ceasului are 38x42 pixeli, dar cadranul sta intre randurile 2 si
		32 — adica doi pixeli goi deasupra si noua dedesubt. `ScaleType.Fit`
		centreaza *imaginea*, nu ceea ce se vede din ea, asa ca ceasul urca cu
		vreo doi pixeli fata de mijlocul casutei lui si statea vizibil mai sus
		decat cifrele de langa el. Casuta coboara cu exact atat.
	]]
	Theme.create("ImageLabel", {
		Name = "ClockIcon",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Card.Clock,
		ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(100, 48),
		Size = UDim2.fromOffset(22, 24),
		Parent = card,
	})

	Theme.text({
		Name = "Clock",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(124, 46),
		Size = UDim2.fromOffset(48, 24),
		Parent = card,
	})

	return card
end

function HudView.buildCards(self: HudView, state: BoardState)
	for _, card in self.Cards do
		card:Destroy()
	end
	self.Cards = {}

	for _, slot in state.TurnOrder do
		self.Cards[slot] = buildCard(state, slot, self.PlayersPanel)
	end

	--[[
		Cate carduri sunt hotaraste cat de lat e randul, iar randul hotaraste cat
		de mic trebuie sa se faca. Doi jucatori si patru nu se incadreaza la fel,
		deci masuratoarea se reface la fiecare meci nou, nu doar la pornire.
	]]
	self:fit()
end

-- ----------------------------------------------------------------- update

function HudView.update(self: HudView, state: BoardState, localSlot: number?)
	self.TurnCounter.Text = string.format("TURN %d · %s", state.TurnNumber, state.GameMode)

	local currentSlot = state.TurnOrder[state.TurnIndex]

	for slot, card in self.Cards do
		local player = state.Players[slot]
		if player then
			local isCurrent = slot == currentSlot and state.Status == "PLAYING"

			--[[
				Randul se arata prin lemnul placii, nu printr-un contur: cardul
				activ primeste o nuanta mai deschisa si marcajul din stanga.
				Un contur ar fi desenat un dreptunghi care nu urmareste silueta
				rotunjita a placii.
			]]
			local plate = card:FindFirstChild("Plate") :: ImageLabel
			plate.ImageColor3 = if isCurrent then Color3.fromHex("FFE3B8") else Color3.new(1, 1, 1)

			local marker = card:FindFirstChild("TurnMarker") :: ImageLabel
			marker.Visible = isCurrent

			--[[
				Langa semnul zidurilor sta doar cifra: semnul spune deja ce sunt.
				Deconectarea nu mai incape in text si nu mai are nevoie — numele
				se stinge, si asta se vede dintr-o privire pe tot cardul.
			]]
			local label = card:FindFirstChild("Barricades") :: TextLabel
			label.Text = tostring(player.BarricadesRemaining)

			local name = card:FindFirstChild("PlayerName") :: TextLabel
			name.TextColor3 = if player.Connected
				then Theme.Color.Text
				else Theme.Color.disabledText

			--[[
				Ceasul. Se coloreaza in rosu sub un minut, ca presiunea sa se vada
				fara sa trebuiasca sa citesti cifrele — la un joc pe ture, cine se
				uita la tabla nu se uita si la ceas.
			]]
			local clock = card:FindFirstChild("Clock") :: TextLabel
			local remaining = math.max(0, math.floor(player.TimeRemaining or 0))
			clock.Text = string.format("%d:%02d", remaining // 60, remaining % 60)
			clock.TextColor3 = if remaining <= 60 then Theme.Color.Invalid else Theme.Color.Text
		end
	end

	-- Butoanele se sting cand nu e randul tau: e mai onest decat sa le lasi
	-- active si sa raspunzi cu refuz.
	local isMyTurn = localSlot ~= nil and currentSlot == localSlot and state.Status == "PLAYING"
	local myPlayer = if localSlot then state.Players[localSlot] else nil
	local hasBarricades = myPlayer ~= nil and myPlayer.BarricadesRemaining > 0

	self.MoveButton.Active = isMyTurn
	self.WallButton.Active = isMyTurn and hasBarricades
	self.RotateButton.Active = isMyTurn and hasBarricades and self.Mode == "WALL"

	Theme.recolorButton(
		self.MoveButton,
		if isMyTurn and self.Mode == "MOVE" then Theme.Color.Accent else Theme.Color.SurfaceRaised
	)
	Theme.recolorButton(
		self.WallButton,
		if isMyTurn and self.Mode == "WALL" then Theme.Color.Accent else Theme.Color.SurfaceRaised
	)

	self.MoveButton.TextTransparency = if isMyTurn then 0 else 0.55
	self.WallButton.TextTransparency = if self.WallButton.Active then 0 else 0.55
	self.WallButton.Text = if hasBarricades
		then string.format("BARRICADE (%d)", if myPlayer then myPlayer.BarricadesRemaining else 0)
		else "NO BARRICADES"

	if state.PausedUntil then
		local waiting = if state.PausedForSlot then state.Players[state.PausedForSlot] else nil
		self:setBanner(
			string.format("WAITING FOR RECONNECT: %s", if waiting then waiting.Name else "?"),
			Theme.Color.TextMuted
		)
	elseif state.Status == "PLAYING" then
		if isMyTurn then
			self:setBanner("YOUR TURN", Theme.Color.Text)
		else
			local current = state.Players[currentSlot]
			self:setBanner(
				string.format("WAITING: %s", if current then current.Name else "?"),
				Theme.Color.TextMuted
			)
		end
	end
end

function HudView.setMode(self: HudView, mode: string)
	self.Mode = mode
end

function HudView.setBanner(self: HudView, text: string, color: Color3?)
	if self.TurnBanner.Text ~= text then
		self.TurnBanner.Text = text
		AnimationController.tween(self.TurnBanner, { TextTransparency = 0 }, 0.15, "fade")
	end
	self.TurnBanner.TextColor3 = color or Theme.Color.Text
end

--[[
	Mesaj scurt pentru o actiune refuzata. Nu blocheaza nimic si nu cere
	niciun clic: dispare singur.
]]
function HudView.showToast(self: HudView, message: string)
	self.Toast.Text = message
	self.Toast.TextTransparency = 0
	AnimationController.shake(self.Toast)

	task.delay(2.2, function()
		if self.Toast.Text == message then
			AnimationController.tween(self.Toast, { TextTransparency = 1 }, 0.4, "fade")
		end
	end)
end

-- Eticheta spune perspectiva *curenta*, nu pe cea in care te duce apasarea.
function HudView.setTopDown(self: HudView, top: boolean)
	self.ViewButton.Text = if top then "VIEW: TOP" else "VIEW: ANGLED"
end

function HudView.setSoundEnabled(self: HudView, enabled: boolean)
	self.SoundButton.Text = if enabled then "SOUND: ON" else "SOUND: OFF"
end

return HudView
