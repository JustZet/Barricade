--!strict
--[[
	StoreView — magazinul, peste lobby.

	Fereastra e un singur desen cu asezarea coapta in el: taburile din stanga,
	bara de sold din dreapta sus si butonul de inchidere sunt pictate la locuri
	fixe. Nimic din ele nu se poate muta din cod, asa ca ecranul asta face
	invers — isi pune elementele exact peste ele.

	De aceea toate pozitiile de aici sunt fractiuni, si toate au fost **masurate
	pe imagine**, nu potrivite din ochi: am cautat in PNG unde incep si unde se
	termina zonele scobite, si am impartit la 1214x533. Cine inlocuieste desenul
	trebuie sa remasoare, altfel totul aluneca.

	Taburile pictate sunt o problema pe care merita s-o spun: primul e desenat
	auriu, adica "activ", si nu se poate stinge. Solutia e ca toate patru sa fie
	acoperite cu butoanele noastre — pastila inchisa peste cele inactive, cea
	aurie peste cel ales. Desenul de dedesubt nu se mai vede niciodata, si tabul
	activ poate fi oricare. Cum felurile de obiecte sunt deocamdata doua, ultimele
	doua locuri primesc o pastila stinsa, fara text: un loc gol aratat cinstit,
	nu un tab pictat care nu face nimic.

	Ce se vinde nu se scrie aici. Vine din `Catalog`, acelasi pe care il citesc
	serverul cand ia banii si vitrina din lobby; cum arata obiectele vine din
	`Skins`. Magazinul nu are lista lui de obiecte, si de aceea nu poate ramane
	in urma celorlalte.

	Ecranul nu hotaraste nimic: nu stie daca ai bani, nu ia bani si nu imbraca pe
	nimeni. Cere o cumparare sau o echipare prin callback si asteapta sa i se
	spuna noul sold, noul inventar si ce poarta jucatorul acum.

	Fereastra se micsoreaza pana incape pe ecran — vezi `fit`. Pe telefon,
	desenul intreg nu are unde sa intre la marimea lui, iar coltul cu butonul de
	inchidere ajungea in afara ecranului, sub butoanele Roblox.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Skins = require(ReplicatedStorage:WaitForChild("World").Skins)

local ItemWell = require(script.Parent.ItemWell)
local Theme = require(script.Parent.Theme)

type Kind = Catalog.Kind

local StoreView = {}
StoreView.__index = StoreView

--[[
	Zonele desenului, ca fractiuni din 1214x533.

	Coloana taburilor: x 26..244. Continutul: x 242..838, y 102..497. Panoul din
	dreapta: x 846..1167. Bara de sold: x 811..1094, y 32..88. Butonul de
	inchidere: x 1105..1180, y 20..95. Bara de sus, in care incape titlul, tine
	de la x 200 pana sub bara de sold. Sloturile de tab au masuratoarea lor, mai
	jos, langa pastilele care le acopera.
]]
local W, H = 1214, 533

--[[
	Pastilele de tab, asezate pe sloturile pictate.

	Sloturile din desen incep la y 135 si se repeta din 87 in 87, inalte de 84;
	coloana lor tine intre x 26 si x 244, iar slotul pictat sta la 36..234, adica
	centrat pe 135, nu pe mijlocul coloanei. Pastila umple coloana cap la cap si
	iese astfel exact peste slot: mai ingusta, ar lasa o dunga de lemn intr-o
	parte, iar lipita de marginea din stanga — cum era — o lasa in dreapta.

	Inaltimea e cu un pixel peste slot in fiecare parte, ca muchia pictata sa nu
	iasa de sub pastila; pasul ramane al desenului, deci raman doua goluri de
	doi pixeli intre pastile, ca intre sloturi.
]]
local TAB_X, TAB_W = 26 / W, 218 / W
local TAB_Y, TAB_H, TAB_STEP = 134 / H, 85 / H, 87 / H

local GRID_X, GRID_W = 242 / W, 586 / W
local GRID_Y, GRID_H = 102 / H, 395 / H

local SIDE_X, SIDE_W = 846 / W, 321 / W

local COIN_X, COIN_W = 811 / W, 283 / W
local COIN_Y, COIN_H = 32 / H, 56 / H

local CLOSE_X, CLOSE_W = 1105 / W, 75 / W
local CLOSE_Y, CLOSE_H = 20 / H, 75 / H

local TITLE_X, TITLE_W = 205 / W, 320 / W
local TITLE_Y, TITLE_H = 16 / H, 74 / H

--[[
	Fereastra pe ecran. Raportul e al desenului (2.278), ca sa nu se deformeze.

	Nu e in fractiuni de ecran: pe un monitor lat ar deveni un panou de peste un
	metru, iar pe telefon ar disparea. Marimea in pixeli tine cartonasele
	citibile peste tot, si fereastra incape si pe un ecran de 1280 latime.
]]
local WINDOW_W, WINDOW_H = 1100, 483

--[[
	Marginea lasata in jurul ferestrei, ca fractiune din ecran.

	Fereastra e desenata pentru 1100x483 si atat ramane cat timp incape. Cand nu
	incape — o fereastra Studio ingusta, un telefon in peisaj — se micsoreaza cu
	totul pana intra, in loc sa iasa pe dinafara: exact cazul din poza, in care
	butonul de inchidere cadea in afara ecranului.

	Marginea de sus e mai mare decat celelalte fiindca peste ea vin butoanele
	Roblox — meniu, chat, microfon. Inaltimea barii o spune `GuiService`, dar
	numai pe inaltime; latimea butoanelor din stanga nu o spune nimeni, si peste
	ele cade coltul ferestrei pe ecran mic.
]]
local SCREEN_MARGIN = 0.04
local TOP_MARGIN = 0.06

-- Cartonasul unui obiect. Desenul e 170x192, deci si celula pastreaza raportul.
local CARD_W, CARD_H = 118, 133

--[[
	Cat spatiu lasa grila in jurul cartonaselor.

	Numerele sunt alese ca sa intre **patru** cartonase pe rand, nu trei: grila
	are 531 de pixeli pe ecran, iar 12 + 4x118 + 3x8 + 12 face 520. Cu golurile
	de dinainte incapeau trei, si jumatatea din dreapta a raftului ramanea goala
	in timp ce ultimele doua obiecte se ascundeau sub marginea de jos. Catalogul
	are opt obiecte de fel, deci asa se vad toate deodata, fara sa se deruleze.
]]
local GRID_PAD, GRID_GAP = 12, 8

--[[
	Zonele scobite din cartonas, ca fractiuni din 170x192.

	Masurate in `card_wood.png`, la fel ca zonele ferestrei: caseta de sus tine
	de la x 24 la 148 si de la y 25 la 103, iar scobitura de jos de la y 111 la
	175, cu moneda pictata intre x 33 si 57. Casetele desenate de noi se aseaza
	**pe** ele, nu langa ele — inainte caseta de culoare era mai ingusta decat
	scobitura si lasa un chenar intunecat in jur, exact ce se vede in poza.

	Pretul incepe dupa moneda, nu de la marginea cartonasului. Centrat pe toata
	latimea nimerea langa moneda din intamplare, cat timp scria "300"; "OWNED" e
	mai lung si urca peste ea.
]]
local WELL_X, WELL_W = 24 / 170, 125 / 170
local WELL_Y, WELL_H = 25 / 192, 79 / 192

local NAME_Y, NAME_H = 111 / 192, 29 / 192
local PRICE_X, PRICE_W = 63 / 170, 87 / 170
local PRICE_Y, PRICE_H = 140 / 192, 32 / 192

--[[
	Cuvantul care tine locul pretului si moneda pictata nu incap unul peste
	altul.

	Un pret e un numar scurt si sta centrat dupa moneda, care il insoteste:
	impreuna se citesc ca un tot. "OWNED" si "EQUIPPED" nu au nicio treaba cu
	moneda, sunt mai lungi decat orice pret si, centrate pe aceeasi zona, ar urca
	peste ea. De aceea cuvintele se scriu pe toata scobitura, lipite la dreapta:
	asa se termina la marginea ei si incep dupa moneda, oricat de lungi ar fi.
]]
local TAG_SIZE, PRICE_SIZE = 13, 15

--[[
	Numele felurilor, asa cum le vede jucatorul.

	`Catalog` tine coduri la singular, pentru cod; taburile vorbesc despre
	rafturi, deci la plural. Cele doua nu au de ce sa fie acelasi cuvant.
]]
local KIND_NAMES: { [string]: string } = {
	Barricade = "BARRICADES",
	Podium = "PODIUMS",
}

--[[
	Ordinea rafturilor, si cate locuri de tab are desenul.

	Ordinea e treaba vitrinei, nu a catalogului: zidurile primele, pentru ca se
	vad la fiecare mutare a fiecarui jucator, si podiumurile dupa. Locurile ramase
	peste numarul de rafturi se deseneaza stinse.
]]
local TAB_KINDS: { Kind } = { "Barricade", "Podium" }
local TAB_SLOTS = 4

type StoreFields = {
	Root: Frame,
	Window: ImageLabel,
	-- Cat de mic trebuie facut desenul ca sa incapa pe ecranul de acum.
	Scale: UIScale,
	Balance: TextLabel,
	Grid: ScrollingFrame,
	Tabs: { [number]: TextButton },
	-- Cartonasele desenate acum, pe id de obiect.
	Cards: { [string]: TextButton },
	DetailWell: Frame,
	DetailPreview: ImageLabel,
	BuyButton: TextButton,
	--[[
		Randul din buton: moneda si cifra. Se stinge cand pe buton scrie un
		cuvant, fiindca atunci nu se mai plateste nimic.
	]]
	Cost: Frame,
	CostText: TextLabel,
	Callbacks: { [string]: any },

	Kind: Kind,
	Selected: string?,
	Coins: number,
	Owned: { [string]: boolean },
	--[[
		Ce poarta jucatorul, pe fel de obiect.

		Nu se tine ca adevar propriu: se citeste din atributele puse de server —
		vezi `Loadout` — si se reciteste la fiecare schimbare. Magazinul nu
		echipeaza nimic singur, doar cere si asteapta.
	]]
	Equipped: { [string]: string? },
}

export type StoreView = typeof(setmetatable({} :: StoreFields, StoreView))

--[[
	Magazinul are cu ce se desena?

	Fereastra nu se poate improviza: fara desenul ei n-ar exista nici taburi,
	nici zone, iar o varianta de rezerva ar fi un al doilea ecran de intretinut
	care n-ar semana cu niciunul. Cat timp asset-ul lipseste, magazinul pur si
	simplu nu exista — iar lobby-ul nu pune butonul care il deschide.
]]
function StoreView.available(): boolean
	return Theme.Assets.Store.panelStoreWindow ~= ""
end

--[[
	Eticheta de sub caseta: pretul, sau ce a ajuns obiectul sa fie.

	Patru stari, in ordinea in care conteaza pentru jucator: cu asta joci, pe
	asta o ai, asta costa atat, asta inca nu se vinde. Obiectul echipat e scris
	cu auriu, ca sa se gaseasca dintr-o privire intr-un raft de opt; cel detinut
	e scris potolit, fiindca vestea lui e deja veche.

	Un obiect caruia nu i s-a pus inca pret nu e gratis, ci nu e de vanzare — de
	aceea scrie altceva la fiecare, ca sa nu para ca unul e o reducere.
]]
local function paintTag(card: TextButton, item: Catalog.Item, owned: boolean, equipped: boolean)
	local label = card:FindFirstChild("Price")
	local mark = card:FindFirstChild("EquippedMark")
	if mark and mark:IsA("TextLabel") then
		mark.Visible = equipped
	end
	if not (label and label:IsA("TextLabel")) then
		return
	end

	local word = if equipped
		then "EQUIPPED"
		elseif owned then "OWNED"
		elseif item.Coins <= 0 then "SOON"
		else nil

	if word then
		label.Text = word
		label.TextSize = TAG_SIZE
		label.TextColor3 = if equipped
			then Theme.Color.Highlight
			elseif owned then Theme.Color.Text
			else Theme.Color.TextMuted
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.Position = UDim2.fromScale(WELL_X, PRICE_Y)
		label.Size = UDim2.fromScale(WELL_W, PRICE_H)
	else
		label.Text = tostring(item.Coins)
		label.TextSize = PRICE_SIZE
		label.TextColor3 = Theme.Color.Highlight
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Position = UDim2.fromScale(PRICE_X, PRICE_Y)
		label.Size = UDim2.fromScale(PRICE_W, PRICE_H)
	end
end

--[[
	Un cartonas de obiect.

	Culoarea si numele vin din `Skins`, care descrie tema — deci cartonasul arata
	chiar lemnul stejarului si verdele crangului, nu o culoare inventata aici.
	Podiumurile imprumuta aceeasi tema: `dragon` inseamna acelasi lucru si pe
	zid, si pe soclu.
]]
local function buildCard(item: Catalog.Item, parent: Instance): TextButton
	local skin = Skins.get(item.Id)

	local card = Theme.create("TextButton", {
		Name = "Item_" .. item.Id,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Parent = parent,
	}) :: TextButton

	Theme.create("ImageLabel", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.cardWood,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		Parent = card,
	})

	--[[
		Raza scobiturii e 10px in desenul de 170 latime; cartonasul se deseneaza
		la 118, deci coltul se micsoreaza cu el. O raza fixa ar iesi prea rotunda
		pe un cartonas mic si nu ar mai urma muchia pictata.
	]]
	local well = ItemWell.build(item.Id, item.Kind, UDim.new(0, math.round(10 * CARD_W / 170)))
	well.Position = UDim2.fromScale(WELL_X, WELL_Y)
	well.Size = UDim2.fromScale(WELL_W, WELL_H)
	well.Parent = card

	Theme.text({
		Name = "ItemName",
		Text = skin.DisplayName,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromScale(WELL_X, NAME_Y),
		Size = UDim2.fromScale(WELL_W, NAME_H),
		Parent = card,
	})

	--[[
		Pretul, sau cuvantul care ii tine locul. Ce scrie pe el se hotaraste in
		`paintTag`, fiindca se schimba dupa fiecare cumparare si echipare.
	]]
	Theme.text({
		Name = "Price",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = PRICE_SIZE,
		TextColor3 = Theme.Color.Highlight,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(PRICE_X, PRICE_Y),
		Size = UDim2.fromScale(PRICE_W, PRICE_H),
		Parent = card,
	})

	--[[
		Bifa, in coltul casetei, nu pe rama de deasupra ei: rama are opt pixeli
		in desen si bifa iesea din cartonas. Ocupa loc si cand e ascunsa, ca sa
		nu miste nimic.

		Spune "cu asta joci", nu "il ai": ce detii scrie oricum sub caseta, cu
		litere, iar doua semne pentru aceeasi informatie ar lasa raftul plin de
		bife din care nu se mai vede care e obiectul ales.
	]]
	Theme.text({
		Name = "EquippedMark",
		Text = "✓",
		Font = Theme.Font.Bold,
		TextSize = 17,
		TextColor3 = Theme.Color.Highlight,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromScale(WELL_X + WELL_W - 0.3, WELL_Y + 0.02),
		Size = UDim2.fromScale(0.28, 0.14),
		Visible = false,
		Parent = card,
	})

	return card
end

function StoreView.new(parent: Instance): StoreView
	local self = setmetatable({}, StoreView) :: StoreView
	self.Callbacks = {} :: { [string]: any }
	self.Cards = {} :: { [string]: TextButton }
	self.Tabs = {} :: { [number]: TextButton }
	self.Kind = TAB_KINDS[1]
	self.Coins = 0
	self.Owned = {} :: { [string]: boolean }
	self.Equipped = {} :: { [string]: string? }

	local root = Theme.create("Frame", {
		Name = "Store",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	}) :: Frame
	self.Root = root

	--[[
		Fundalul stins are doua treburi: spune ca restul ecranului asteapta, si
		prinde clicurile care ar ajunge altfel pe lobby-ul de dedesubt.
	]]
	local dim = Theme.create("TextButton", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = root,
	}) :: TextButton

	--[[
		Apasarea pe fundal inchide, nu doar blocheaza.

		Butonul de inchidere e pictat in coltul ferestrei si, pe telefon, ajunge
		sub butoanele Roblox din bara de sus — se vede prost si se nimereste si
		mai prost. Fundalul e cea mai mare tinta de pe ecran si inseamna deja "in
		afara magazinului", deci e locul potrivit pentru a doua iesire.
	]]
	dim.MouseButton1Click:Connect(function()
		self:hide()
	end)

	local window = Theme.create("ImageLabel", {
		Name = "Window",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.panelStoreWindow,
		ScaleType = Enum.ScaleType.Fit,
		--[[
			Fereastra opreste clicurile care cad pe lemn.

			O eticheta nu inghite apasarea, ci o lasa sa treaca la ce e dedesubt
			— iar dedesubt e fundalul care inchide magazinul. Fara asta, o
			apasare pe rama sau intre cartonase ar inchide vitrina.
		]]
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		ZIndex = 11,
		Parent = root,
	}) :: ImageLabel
	self.Window = window

	--[[
		Micsorarea intra aici, nu in marimea ferestrei.

		Tot ecranul e masurat in fractiuni din desen si in pixeli potriviti pe el
		— cartonase de 118, patru pe rand, scobituri masurate in PNG. Schimbata
		marimea ferestrei, fractiunile ar tine, dar pixelii nu: cartonasele ar
		ramane mari intr-o fereastra mica si ar da pe dinafara. Un `UIScale`
		micsoreaza deodata si fereastra, si tot ce e in ea, deci asezarea ramane
		exact aceeasi, doar mai mica.
	]]
	self.Scale = Theme.create("UIScale", { Scale = 1, Parent = window }) :: UIScale

	--[[
		Titlul, in bara de sus, dupa firma pictata.

		Aceeasi familie si aceeasi greutate ca titlul din lobby, ca sa se vada ca
		e acelasi joc; culoarea deschisa, pentru ca sta pe lemn. Aliniat la
		stanga si lipit de firma, nu centrat pe bara: bara e ocupata in dreapta
		de sold, iar un titlu centrat pe ea ar parea impins intr-o parte.
	]]
	Theme.text({
		Name = "Title",
		Text = "STORE",
		Font = Theme.Font.Bold,
		TextSize = 42,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromScale(TITLE_X, TITLE_Y),
		Size = UDim2.fromScale(TITLE_W, TITLE_H),
		ZIndex = 12,
		Parent = window,
	})

	-- ------------------------------------------------------------- sold
	self.Balance = Theme.text({
		Name = "Balance",
		Text = "0",
		Font = Theme.Font.Bold,
		TextSize = 34,
		TextColor3 = Theme.Color.Highlight,
		TextXAlignment = Enum.TextXAlignment.Center,
		-- Moneda e pictata la capatul din stanga al barii; textul incepe dupa ea.
		Position = UDim2.fromScale(COIN_X + COIN_W * 0.22, COIN_Y),
		Size = UDim2.fromScale(COIN_W * 0.74, COIN_H),
		ZIndex = 12,
		Parent = window,
	})

	-- --------------------------------------------------------- inchiderea
	local close = Theme.create("TextButton", {
		Name = "Close",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromScale(CLOSE_X, CLOSE_Y),
		Size = UDim2.fromScale(CLOSE_W, CLOSE_H),
		ZIndex = 12,
		Parent = window,
	}) :: TextButton

	close.MouseButton1Click:Connect(function()
		self:hide()
	end)

	-- ------------------------------------------------------------ taburi
	for slot = 1, TAB_SLOTS do
		local kind: Kind? = TAB_KINDS[slot]
		local tab = Theme.button({
			Name = if kind then "Tab_" .. kind else "TabEmpty_" .. slot,
			Text = if kind then KIND_NAMES[kind] or kind else "",
			TextSize = 17,
			Skin = "Pill",
			Position = UDim2.fromScale(TAB_X, TAB_Y + TAB_STEP * (slot - 1)),
			Size = UDim2.fromScale(TAB_W, TAB_H),
			ZIndex = 12,
			Parent = window,
		})
		self.Tabs[slot] = tab

		if kind then
			-- Copie locala: inauntrul unei functii Luau uita ca `kind` a fost deja
			-- gasit ne-nil de `if`-ul de afara.
			local chosen: Kind = kind
			tab.MouseButton1Click:Connect(function()
				self:showKind(chosen)
			end)
		else
			-- Loc gol: se vede ca e un raft, dar nu raspunde si nu se aprinde.
			Theme.setButtonEnabled(tab, false)
		end
	end

	-- --------------------------------------------------------- obiectele
	self.Grid = Theme.create("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Highlight,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(GRID_X, GRID_Y),
		Size = UDim2.fromScale(GRID_W, GRID_H),
		ZIndex = 12,
		Parent = window,
	}, {
		Theme.padding(GRID_PAD),
		Theme.create("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD_W, CARD_H),
			CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame

	-- ------------------------------------------------------ panoul din dreapta
	local side = Theme.create("Frame", {
		Name = "Detail",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(SIDE_X, GRID_Y),
		Size = UDim2.fromScale(SIDE_W, GRID_H),
		ZIndex = 12,
		Parent = window,
	}, { Theme.padding(18) }) :: Frame

	--[[
		Poza obiectului, facuta in lume, cap la cap in panou.

		Numele nu mai sta deasupra ei. Scria acelasi cuvant care sta si pe
		cartonasul apasat cu o clipa inainte, la doi centimetri distanta, si
		manca din inaltimea pozei — care e singurul motiv pentru care panoul
		exista. Aici te uiti la obiect inainte sa dai banii, nu la cartonasul de
		un centimetru.
	]]
	--[[
		Caseta ia toata latimea panoului si atata inaltime cat o lasa butonul.

		Poza e facuta pe un cadru lat de 933 pe 503, iar caseta se taie ca sa-l
		umple. Cat se taie e insa o limita, nu un gust: obiectul ocupa vreo 62%
		din latimea pozei, deci taietura are voie sa manance cel mult a treia
		parte din ea inainte sa ajunga la capetele unei baricade. La 1.4 fata de
		1.86 se pierde un sfert — numai cer si dala, cu o palma de aer ramasa de
		fiecare parte a obiectului.
	]]
	local well = ItemWell.build(nil, TAB_KINDS[1], UDim.new(0, 26), "Scene")
	well.Name = "DetailWell"
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.fromScale(0.5, 0.06)
	well.Size = UDim2.fromScale(1, 0.6)
	well.ZIndex = 13
	well.Parent = side
	self.DetailWell = well
	self.DetailPreview = well:FindFirstChild("Preview") :: ImageLabel

	self.BuyButton = Theme.button({
		Name = "Buy",
		Text = "",
		TextSize = 19,
		Skin = "Primary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.new(1, 0, 0, 52),
		ZIndex = 13,
		Parent = side,
	})

	--[[
		Pretul sta **in** buton, nu deasupra lui.

		Un rand separat care scria "700 coins" peste un buton pe care scria "BUY"
		spunea acelasi lucru de doua ori, in doua locuri, si lasa intre ele un
		gol care nu insemna nimic. Impreuna, moneda si cifra spun si ce faci, si
		cat te costa — asa arata butonul de cumparare in orice magazin de azi.

		Moneda si cifra stau intr-un rand care se aseaza singur la mijloc:
		`UIListLayout` le tine lipite oricat de lung ar fi numarul, iar cand pe
		buton scrie un cuvant — "EQUIP", "OWNED" — randul se stinge si ramane
		doar textul.
	]]
	local cost = Theme.create("Frame", {
		Name = "Cost",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.62),
		ZIndex = 14,
		Parent = self.BuyButton,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	self.Cost = cost

	Theme.create("ImageLabel", {
		Name = "Coin",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.coinSmall,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(26, 26),
		LayoutOrder = 1,
		ZIndex = 14,
		Parent = cost,
	})

	--[[
		Cifra isi ia singura latimea.

		Intr-o caseta de latime fixa, "600" statea lipit la stanga si lasa dupa
		el un gol pe care randul il socotea tot al lui — iar `UIListLayout`
		centra atunci moneda plus golul, nu moneda plus cifra. Se vedea limpede:
		tot ce scria pe buton parea impins spre stanga. Cu `AutomaticSize`,
		randul masoara exact cat se vede, deci mijlocul lui e chiar mijlocul.
	]]
	self.CostText = Theme.text({
		Name = "Amount",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 20,
		TextColor3 = Theme.Color.TextInverse,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = 2,
		ZIndex = 14,
		Parent = cost,
	})

	--[[
		Acelasi buton cere doua lucruri diferite, dupa cum arata.

		Un obiect pe care il ai nu se mai cumpara, se imbraca — si e chiar
		urmatorul lucru pe care il vrea cineva care tocmai l-a cumparat. Un al
		doilea buton, stins jumatate din timp, ar fi doar un loc in plus in care
		sa te uiti.
	]]
	self.BuyButton.MouseButton1Click:Connect(function()
		local chosen = self.Selected
		if not chosen then
			return
		end
		local owned = Catalog.owns(self.Owned, self.Kind, chosen)
		local callback = if owned then self.Callbacks.onEquip else self.Callbacks.onPurchase
		if callback then
			callback(self.Kind, chosen)
		end
	end)

	self:showKind(self.Kind)
	self:fit()

	--[[
		Ecranul se poate schimba sub magazin: telefonul se roteste, fereastra
		Studio se trage de colt. Fereastra se remasoara atunci, nu doar la
		deschidere.
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
	Incadreaza fereastra in ecranul de acum.

	Se micsoreaza pana intra si nu se mareste niciodata peste desen: marita, o
	fereastra de 1100 pixeli ar ajunge un panou de o suta de centimetri pe un
	monitor lat, cu cartonase cat palma.

	Centrul nu e centrul ecranului, ci al spatiului ramas sub bara Roblox.
	Interfata jocului sta sub bara aia (`IgnoreGuiInset`), deci o fereastra
	centrata pe ecran isi urca marginea de sus — si cu ea butonul de inchidere —
	chiar sub butoanele de meniu si de chat.
]]
function StoreView.fit(self: StoreView)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local inset = GuiService:GetGuiInset()
	local top = inset.Y + viewport.Y * TOP_MARGIN
	local bottom = viewport.Y * (1 - SCREEN_MARGIN)

	local usableW = viewport.X * (1 - SCREEN_MARGIN * 2)
	local usableH = bottom - top

	self.Scale.Scale = math.max(math.min(1, usableW / WINDOW_W, usableH / WINDOW_H), 0.01)
	self.Window.Position = UDim2.new(0.5, 0, 0, (top + bottom) / 2)
end

--[[
	Tabul ales.

	Se schimba *desenul*, nu culoarea. Pastila aurie e un desen propriu, cu
	lumina si muchie de aur; aceeasi pastila inchisa colorata in galben ar iesi
	un lemn murdar, pentru ca tinta inmulteste culoarea cu ce e dedesubt. Cele
	doua desene au acelasi contur, deci schimbarea nu misca nimic.
]]
function StoreView.paintTabs(self: StoreView)
	local gold = Theme.Skin.PillGold
	local dark = Theme.Skin.Pill

	for slot = 1, TAB_SLOTS do
		local kind: Kind? = TAB_KINDS[slot]
		local tab = self.Tabs[slot]
		local plate = if tab then tab:FindFirstChild("Plate") else nil
		if plate and plate:IsA("ImageLabel") and kind then
			local skin = if kind == self.Kind then gold else dark
			plate.Image = skin.Image
			plate.SliceCenter = skin.Slice
			plate.SliceScale = skin.SliceScale
		end
	end
end

--[[
	Deseneaza un fel de obiecte.

	Cartonasele se refac de la zero la fiecare schimbare de tab. Ar fi putut fi
	ascunse si aratate, dar atunci ar fi trait in memorie toate felurile deodata,
	si fiecare pret schimbat ar fi trebuit cautat prin ele. Opt cartonase se
	construiesc intr-o clipa.
]]
function StoreView.showKind(self: StoreView, kind: Kind)
	self.Kind = kind
	self:paintTabs()

	for _, card in self.Cards do
		card:Destroy()
	end
	self.Cards = {}

	local items = Catalog.list(kind)
	for index, item in items do
		local card = buildCard(item, self.Grid)
		card.LayoutOrder = index
		self.Cards[item.Id] = card

		card.MouseButton1Click:Connect(function()
			self:select(item.Id)
		end)
	end

	self:select(if items[1] then items[1].Id else nil)
end

--[[
	Alege un obiect si il arata in panoul din dreapta.

	Fara nimic ales, panoul ramane gol si butonul stins — nu exista "cumpara ce
	era selectat inainte", pentru ca de acolo ies cumparaturi pe care nu le-ai
	cerut.
]]
function StoreView.select(self: StoreView, itemId: string?)
	self.Selected = itemId

	--[[
		Caseta mare urmeaza alegerea. Se recoloreaza, nu se reconstruieste: un
		panou refacut la fiecare clic ar clipi, iar aici clicurile vin unul dupa
		altul cand jucatorul trece prin raft.
	]]
	self.DetailWell.Visible = itemId ~= nil
	if itemId then
		ItemWell.show(self.DetailWell, itemId, self.Kind)
	end

	for id, card in self.Cards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if id == itemId then
			if not stroke then
				Theme.stroke(Theme.Color.Highlight, 3).Parent = card
			end
		elseif stroke then
			stroke:Destroy()
		end
	end

	self:refresh()
end

--[[
	Aduce la zi tot ce depinde de bani, de inventar si de ce poarta: etichetele
	cartonaselor, panoul din dreapta si butonul.

	Raspunsurile la "poate cumpara?" si "poate echipa?" nu se calculeaza aici, se
	cer lui `Catalog` si lui `Loadout` — acelasi cod pe care il ruleaza si
	serverul cand ia banii sau scrie atributul. Daca cele doua ar raspunde
	diferit, jucatorul ar vedea un buton aprins care il refuza.
]]
function StoreView.refresh(self: StoreView)
	self.Balance.Text = tostring(self.Coins)

	local wearing = self.Equipped[self.Kind]

	for id, card in self.Cards do
		local item = Catalog.get(self.Kind, id)
		if item then
			paintTag(card, item, Catalog.owns(self.Owned, self.Kind, id), id == wearing)
		end
	end

	local chosen = self.Selected
	local item = if chosen then Catalog.get(self.Kind, chosen) else nil
	local owned = chosen ~= nil and Catalog.owns(self.Owned, self.Kind, chosen)
	local equipped = chosen ~= nil and chosen == wearing

	--[[
		Butonul spune, singur, si ce faci, si cat te costa.

		Cand obiectul e de cumparat, in el stau moneda si cifra — atat, fara
		cuvantul "BUY": un buton auriu sub un obiect dintr-un magazin, cu o
		moneda si un pret pe el, nu poate insemna altceva. Cand nu mai e nimic de
		platit — il ai, il porti, nu se vinde inca — randul cu moneda se stinge
		si ramane cuvantul care spune de ce.
	]]
	local allowed, label = false, ""
	if equipped then
		label = "EQUIPPED"
	elseif owned then
		allowed = true
		label = "EQUIP"
	elseif chosen then
		local canBuy, reason = Catalog.canBuy(self.Kind, chosen, self.Coins, self.Owned)
		allowed = canBuy
		label = if reason == "POOR"
			then "NOT ENOUGH"
			elseif reason == "NOT_FOR_SALE" then "COMING SOON"
			else ""
	end

	local price = if label == "" and item then item.Coins else 0
	self.Cost.Visible = price > 0
	self.CostText.Text = tostring(price)

	Theme.setButtonEnabled(self.BuyButton, allowed)
	self.BuyButton.Text = label
end

function StoreView.setCoins(self: StoreView, coins: number)
	self.Coins = coins
	self:refresh()
end

function StoreView.setOwned(self: StoreView, items: { string })
	local owned: { [string]: boolean } = {}
	for _, key in items do
		owned[key] = true
	end
	self.Owned = owned
	self:refresh()
end

--[[
	Ce poarta jucatorul acum, pe un fel.

	Vine de la server, prin `GameController`. Magazinul nu presupune niciodata ca
	o cerere de echipare a reusit: pana nu se intoarce vestea, cartonasul ramane
	cum era — altfel ar arata "EQUIPPED" peste un refuz.
]]
function StoreView.setEquipped(self: StoreView, kind: Kind, itemId: string?)
	self.Equipped[kind] = itemId
	self:refresh()
end

function StoreView.show(self: StoreView)
	-- Ecranul se putea schimba cat timp magazinul era inchis.
	self:fit()
	self.Root.Visible = true
end

function StoreView.hide(self: StoreView)
	self.Root.Visible = false
end

function StoreView.on(self: StoreView, name: string, callback: any)
	self.Callbacks[name] = callback
end

return StoreView
