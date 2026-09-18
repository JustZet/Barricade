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

	Ecranul nu hotaraste nimic: nu stie daca ai bani si nu ia bani. Cere o
	cumparare prin callback si asteapta sa i se spuna noul sold si noul inventar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Skins = require(ReplicatedStorage:WaitForChild("World").Skins)

local Theme = require(script.Parent.Theme)

type Kind = Catalog.Kind

local StoreView = {}
StoreView.__index = StoreView

--[[
	Zonele desenului, ca fractiuni din 1214x533.

	Coloana taburilor: x 26..240. Continutul: x 242..838, y 102..497. Panoul din
	dreapta: x 846..1167. Bara de sold: x 811..1094, y 32..88. Butonul de
	inchidere: x 1105..1180, y 20..95. Taburile incep la y 130 si se repeta din
	88 in 88, inalte de 80. Bara de sus, in care incape titlul, tine de la x 200
	pana sub bara de sold.
]]
local W, H = 1214, 533

local TAB_X, TAB_W = 26 / W, 214 / W
local TAB_Y, TAB_H, TAB_STEP = 130 / H, 80 / H, 88 / H

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

-- Cartonasul unui obiect. Desenul e 170x192, deci si celula pastreaza raportul.
local CARD_W, CARD_H = 118, 133

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
	Balance: TextLabel,
	Grid: ScrollingFrame,
	Tabs: { [number]: TextButton },
	-- Cartonasele desenate acum, pe id de obiect.
	Cards: { [string]: TextButton },
	DetailName: TextLabel,
	DetailPrice: TextLabel,
	BuyButton: TextButton,
	Callbacks: { [string]: any },

	Kind: Kind,
	Selected: string?,
	Coins: number,
	Owned: { [string]: boolean },
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

	Theme.create("Frame", {
		Name = "Swatch",
		BackgroundColor3 = skin.Color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.11),
		Size = UDim2.fromScale(0.58, 0.42),
		Parent = card,
	}, {
		Theme.corner(Theme.Radius.Small),
		Theme.stroke(skin.EdgeColor, 2),
	})

	Theme.text({
		Name = "ItemName",
		Text = skin.DisplayName,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromScale(0.08, 0.56),
		Size = UDim2.fromScale(0.84, 0.16),
		Parent = card,
	})

	--[[
		Pretul, sau cuvantul care ii tine locul.

		Obiectul de start nu are pret, il ai; unul caruia nu i s-a pus inca pret
		nu e gratis, ci nu e de vanzare. Sunt doua lucruri diferite si scrie
		altceva la fiecare, ca sa nu para ca unul e o reducere.
	]]
	local price = if item.Default
		then "OWNED"
		elseif item.Coins <= 0 then "SOON"
		else tostring(item.Coins)

	Theme.text({
		Name = "Price",
		Text = price,
		Font = Theme.Font.Bold,
		TextSize = 15,
		TextColor3 = if item.Coins > 0 then Theme.Color.Highlight else Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.08, 0.74),
		Size = UDim2.fromScale(0.84, 0.18),
		Parent = card,
	})

	-- Bifa de "il ai deja". Ocupa loc si cand e ascunsa, ca sa nu miste nimic.
	Theme.text({
		Name = "OwnedMark",
		Text = "✓",
		Font = Theme.Font.Bold,
		TextSize = 17,
		TextColor3 = Theme.Color.Highlight,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.42, 0.14),
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
	Theme.create("TextButton", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = root,
	})

	local window = Theme.create("ImageLabel", {
		Name = "Window",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.panelStoreWindow,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		ZIndex = 11,
		Parent = root,
	}) :: ImageLabel
	self.Window = window

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
		TextSize = 30,
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
		TextSize = 22,
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
			TextSize = 15,
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
		Theme.padding(14),
		Theme.create("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD_W, CARD_H),
			CellPadding = UDim2.fromOffset(12, 12),
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

	self.DetailName = Theme.text({
		Name = "DetailName",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Position = UDim2.fromScale(0, 0.05),
		Size = UDim2.fromScale(1, 0.16),
		ZIndex = 13,
		Parent = side,
	})

	self.DetailPrice = Theme.text({
		Name = "DetailPrice",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0, 0.22),
		Size = UDim2.fromScale(1, 0.12),
		ZIndex = 13,
		Parent = side,
	})

	self.BuyButton = Theme.button({
		Name = "Buy",
		Text = "BUY",
		TextSize = 17,
		Skin = "Primary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.new(1, 0, 0, 48),
		ZIndex = 13,
		Parent = side,
	})

	self.BuyButton.MouseButton1Click:Connect(function()
		local chosen = self.Selected
		local callback = self.Callbacks.onPurchase
		if chosen and callback then
			callback(self.Kind, chosen)
		end
	end)

	self:showKind(self.Kind)
	return self
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

	local item = if itemId then Catalog.get(self.Kind, itemId) else nil
	self.DetailName.Text = if itemId then Skins.get(itemId).DisplayName else ""
	self.DetailPrice.Text = if item and item.Coins > 0
		then string.format("%d coins", item.Coins)
		else ""

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
	Aduce la zi ce depinde de bani si de inventar: bifele, si butonul de cumparat.

	Raspunsul la "poate cumpara?" nu se calculeaza aici, se cere catalogului —
	acelasi cod pe care il ruleaza si serverul cand ia banii. Daca cele doua ar
	raspunde diferit, jucatorul ar vedea un buton aprins care il refuza.
]]
function StoreView.refresh(self: StoreView)
	self.Balance.Text = tostring(self.Coins)

	for id, card in self.Cards do
		local mark = card:FindFirstChild("OwnedMark")
		if mark and mark:IsA("TextLabel") then
			mark.Visible = Catalog.owns(self.Owned, self.Kind, id)
		end
	end

	local chosen = self.Selected
	local allowed, reason = false, nil :: string?
	if chosen then
		allowed, reason = Catalog.canBuy(self.Kind, chosen, self.Coins, self.Owned)
	end

	Theme.setButtonEnabled(self.BuyButton, allowed)
	self.BuyButton.Text = if reason == "OWNED"
		then "OWNED"
		elseif reason == "POOR" then "NOT ENOUGH"
		elseif reason == "NOT_FOR_SALE" then "COMING SOON"
		else "BUY"
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

function StoreView.show(self: StoreView)
	self.Root.Visible = true
end

function StoreView.hide(self: StoreView)
	self.Root.Visible = false
end

function StoreView.on(self: StoreView, name: string, callback: any)
	self.Callbacks[name] = callback
end

return StoreView
