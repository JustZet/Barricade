--!strict
--[[
	ShowcaseController — cumperi de la vitrina, fara sa mai deschizi magazinul.

	Vitrinele din lobby aratau obiectele si atat. Acum, cand te apropii de una,
	placuta de deasupra ei creste intr-un cartonas cu poza, pretul si un buton —
	si obiectul se cumpara de pe loc. Magazinul ramane: acolo vezi tot raftul
	deodata si compari. Vitrina e celalalt drum, cel pentru cine s-a oprit deja
	in fata obiectului.

	Apropierea o masoara un `ProximityPrompt`, nu cod scris de mana. El stie deja
	tot ce e greu: distanta, obiectul cel mai apropiat, tastatura, gamepad-ul si
	ecranul de telefon. Desenul lui implicit e stins (`Custom`), fiindca avem
	desenele noastre de lemn — dar drumul spre cumparare ramane al lui, unul
	singur, prin `Triggered`.

	Se cumpara dintr-o apasare pe dunga de jos, care e sculptata in desen ca un
	buton si se poarta ca unul. Tasta `E` face exact acelasi lucru: amandoua
	chema aceeasi functie, iar ea isi verifica singura starea.

	Nimic nu se hotaraste aici. Ce detii vine prin `InventoryUpdate`, cati banuti
	ai prin `WalletUpdate`, ce porti din atributul scris de `Loadout`, iar
	cumpararea pleaca prin `RequestPurchase` — aceleasi canale pe care le
	foloseste si magazinul, cu aceleasi verificari pe server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local Skins = require(ReplicatedStorage:WaitForChild("World").Skins)

local OfferView = require(script.Parent.Parent.UI.OfferView)
local Pocket = require(script.Parent.Parent.Pocket)

type Kind = Catalog.Kind

local LOCAL_PLAYER = Players.LocalPlayer

local ShowcaseController = {}

--[[
	De la ce distanta se poate cumpara, in studi.

	Cam doi pasi in jurul vitrinei. Mai mult, si doua vitrine alaturate ar fi
	deodata la indemana, iar `ProximityPrompt` ar tot comuta intre ele cat te
	misti; mai putin, si ar trebui sa intri cu nasul in obiect.
]]
local REACH = 14

--[[
	Se cumpara dintr-o apasare, nu tinand apasat.

	Pornise cu o tinere de jumatate de secunda, ca sa nu se cumpere din greseala.
	Dunga de jos arata insa a buton — e sculptata ca unul in desen — iar un buton
	care nu face nimic la apasare pare stricat. Un cartonas care apare doar cand
	te opresti in fata vitrinei nu prea are cum sa fie apasat din intamplare.

	Zero, aici, chiar inseamna „la apasare": promptul declanseaza fara asteptare.
	Cine vrea protectia inapoi ii pune o valoare si schimba textul butonului.
]]
local PRESS_DELAY = 0

-- Cat de sus fata de varful vitrinei pluteste placuta.
local LIFT = 1.4

type Stand = {
	View: OfferView.OfferView,
	Prompt: ProximityPrompt,
	Kind: Kind,
	Id: string,
}

local stands: { Stand } = {}
local listening = false

--[[
	Oferta unei vitrine, asa cum arata *acum*.

	Cele trei stari pe care le poate avea un obiect — nu e al tau, e al tau, il
	porti — se citesc din aceleasi functii pe care le ruleaza si magazinul si
	serverul. Daca ar fi socotite aici a doua oara, cartonasul ar putea aprinde
	un buton peste un refuz.
]]
local function describe(kind: Kind, id: string): OfferView.Offer
	local item = Catalog.get(kind, id)
	local isOwned = Catalog.owns(Pocket.owned(), kind, id)
	local isWorn = LOCAL_PLAYER:GetAttribute(Loadout.attribute(kind)) == id

	local offer: OfferView.Offer = {
		Kind = kind,
		Id = id,
		Name = Skins.get(id).DisplayName,
		Title = if kind == "Podium" then "PODIUM" else "BARRICADE",
		Action = "",
		Tone = "SOON",
		Coined = false,
	}

	if isWorn then
		offer.Action = "EQUIPPED"
		offer.Tone = "WORN"
		return offer
	end

	if isOwned then
		offer.Action = "EQUIP"
		offer.Tone = "EQUIP"
		return offer
	end

	if not item or item.Coins <= 0 then
		offer.Action = "SOON"
		return offer
	end

	--[[
		Pretul e si el o stare, nu doar un numar: scris cu rosu, spune ca nu
		ajung banutii, fara sa mai fie nevoie de un cuvant care sa o spuna. De
		aceea pe buton ramane tot pretul — se vede ce dai si daca ai de unde.
	]]
	local allowed = Catalog.canBuy(kind, id, Pocket.coins(), Pocket.owned())
	offer.Action = tostring(item.Coins)
	offer.Coined = true
	offer.Tone = if allowed then "BUY" else "POOR"
	return offer
end

local function refresh()
	for _, stand in stands do
		stand.View:paint(describe(stand.Kind, stand.Id))
	end
end

--[[
	Apasarea dusa la capat.

	Se verifica din nou tot, desi cartonasul stinge butonul peste ce nu se poate:
	tasta trece pe langa buton, iar intre clipa in care s-a aprins si clipa in
	care s-a terminat apasarea se poate schimba si soldul, si inventarul.
]]
local function act(stand: Stand)
	-- Tipurile se scriu, nu se deduc: la o atribuire in doi, Luau uita ca `Kind`
	-- e o pereche de nume si il largeste la `string`.
	local kind: Kind, id: string = stand.Kind, stand.Id

	if LOCAL_PLAYER:GetAttribute(Loadout.attribute(kind)) == id then
		return
	end

	if Catalog.owns(Pocket.owned(), kind, id) then
		Remotes.get("RequestEquip"):FireServer(kind, id)
		return
	end

	if Catalog.canBuy(kind, id, Pocket.coins(), Pocket.owned()) then
		Remotes.get("RequestPurchase"):FireServer(kind, id)
	end
end

--[[
	Punctul de care se agata oferta: o piesa nevazuta chiar deasupra vitrinei.

	Nu se agata de obiectul expus, desi ar fi fost mai la indemana: acela
	pluteste si se roteste, deci si eticheta ar dansa cu el, iar cand vitrina
	isi schimba obiectul ar disparea cu tot cu ofertă. Piesa asta sta pe loc.

	Traieste doar pe clientul asta, ca toata vitrina: decorul lobby-ului nu se
	replica, fiecare si-l construieste singur.
]]
local function anchorFor(anchor: Model): BasePart
	local existing = anchor:FindFirstChild("OfferAnchor")
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local box, size = anchor:GetBoundingBox()

	local part = Instance.new("Part")
	part.Name = "OfferAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(box.Position.X, box.Position.Y + size.Y / 2, box.Position.Z)
	part.Parent = anchor
	return part
end

local function bind(stand: Stand, view: OfferView.OfferView, prompt: ProximityPrompt)
	prompt.PromptShown:Connect(function()
		view:setNear(true)
	end)
	prompt.PromptHidden:Connect(function()
		view:setNear(false)
	end)

	--[[
		Doua intrari, o singura fapta.

		Tasta ajunge aici prin prompt, butonul de pe cartonas direct. Nu trece si
		butonul prin prompt, desi s-ar fi putut: `InputHoldBegin` e facut pentru
		o apasare care *tine*, iar ce face el la o tinere de zero secunde nu e
		scris nicaieri. Chemarea aceleiasi functii din amandoua nu depinde de
		asta, si oricum ramane o singura cale prin care se cere ceva — `act`,
		care isi verifica singur starea.
	]]
	local function attempt()
		view:flash()
		act(stand)
	end

	prompt.Triggered:Connect(attempt)
	view.Button.MouseButton1Click:Connect(attempt)
end

--[[
	Ascultatorii buzunarului si ai obiectelor purtate.

	Se leaga o singura data, oricate vitrine ar fi: toate arata acelasi buzunar.
	Banutii si inventarul vin din `Pocket`, care le tine minte — vitrinele se
	construiesc tarziu, dupa ce arena s-a replicat, si pana atunci soldul a ajuns
	demult la client. Ascultat direct de pe canal, mesajul lui era deja trecut, si
	toate ofertele ramaneau pe "NOT ENOUGH" cu buzunarul plin.
]]
local function listen()
	if listening then
		return
	end
	listening = true

	Pocket.watch(refresh)

	for _, kind: Kind in Catalog.Kinds do
		LOCAL_PLAYER:GetAttributeChangedSignal(Loadout.attribute(kind)):Connect(refresh)
	end
end

--[[
	Pune cate o oferta pe fiecare vitrina construita de `Showcase`.

	Primeste vitrinele deja facute, nu le cauta singur: cine le construieste stie
	ce arata fiecare, iar o a doua cautare prin lobby ar putea gasi altceva.
]]
function ShowcaseController.attach(showcases: { any })
	for _, showcase in showcases do
		local anchor = showcase.Anchor
		if typeof(anchor) ~= "Instance" or not anchor:IsA("Model") then
			continue
		end

		local part = anchorFor(anchor)
		local view = OfferView.new(part, LIFT)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "OfferPrompt"
		prompt.ActionText = "Buy"
		prompt.ObjectText = Skins.get(showcase.Id).DisplayName
		-- Desenul e al nostru; promptului ii ramane doar apropierea si apasarea.
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.HoldDuration = PRESS_DELAY
		prompt.MaxActivationDistance = REACH
		--[[
			Obiectul expus sta chiar intre jucator si punctul de care atarna
			oferta, deci cerinta de vedere directa ar stinge promptul tocmai cand
			te uiti la el.
		]]
		prompt.RequiresLineOfSight = false
		prompt.Parent = part

		local stand: Stand = {
			View = view,
			Prompt = prompt,
			Kind = showcase.Kind,
			Id = showcase.Id,
		}
		table.insert(stands, stand)
		bind(stand, view, prompt)
	end

	listen()
	refresh()
end

return ShowcaseController
