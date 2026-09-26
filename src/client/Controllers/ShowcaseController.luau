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
local Gift = require(Shared.Gift)
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local World = ReplicatedStorage:WaitForChild("World")
local Pedestal = require(World.Pedestal)
local Skins = require(World.Skins)

local OfferView = require(script.Parent.Parent.UI.OfferView)
local Pocket = require(script.Parent.Parent.Pocket)

type Kind = Catalog.Kind

local LOCAL_PLAYER = Players.LocalPlayer

local ShowcaseController = {}

--[[
	De la ce distanta se poate cumpara, in studi.

	Se masoara de la **talpa** vitrinei, nu de la punctul de care atarna
	placuta. Pana acum se masura de sus: placuta pluteste peste un soclu inalt
	de vreo douasprezece studi, iar de acolo pana la pieptul cuiva care sta pe
	podea sunt deja aproape toti cei paisprezece — asa ca trebuia sa te lipesti
	de soclu ca sa se deschida cartonasul, desi stateai chiar in fata lui.
	Coborata la nivelul pe care umbla omul, aceeasi cifra acopera locul din care
	chiar te uiti la vitrina.

	Cu doua vitrine alaturate se ajunge acum des in raza amandurora. Nu mai e o
	problema: se alege cea mai apropiata — vezi `updateFocus`.
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

--[[
	Cat de des se cauta vitrina cea mai apropiata, in secunde.

	Nu la fiecare cadru: nimeni nu trece dintr-o vitrina in alta intre doua
	cadre, iar o cautare de sapte distante de saizeci de ori pe secunda e munca
	facuta degeaba. O saptime de secunda e sub ce se simte ca intarziere si de
	zece ori mai ieftina.
]]
local FOCUS_INTERVAL = 0.14

type Stand = {
	View: OfferView.OfferView,
	Prompt: ProximityPrompt,
	--[[
		Punctul de la care se masoara apropierea: talpa vitrinei, la nivelul
		podelei pe care umbla jucatorul. Vezi `reachFor`.
	]]
	Reach: BasePart,
	Kind: Kind,
	Id: string,
	-- Stagiul darului: nu se plateste, se cere.
	Gift: boolean,
}

local stands: { Stand } = {}
local listening = false
local watching = false

--[[
	Oferta unei vitrine, asa cum arata *acum*.

	Cele trei stari pe care le poate avea un obiect — nu e al tau, e al tau, il
	porti — se citesc din aceleasi functii pe care le ruleaza si magazinul si
	serverul. Daca ar fi socotite aici a doua oara, cartonasul ar putea aprinde
	un buton peste un refuz.
]]
local function describe(kind: Kind, id: string, gift: boolean): OfferView.Offer
	local item = Catalog.get(kind, id)
	local isOwned = Catalog.owns(Pocket.owned(), kind, id)
	local isWorn = LOCAL_PLAYER:GetAttribute(Loadout.attribute(kind)) == id

	local offer: OfferView.Offer = {
		Kind = kind,
		Id = id,
		Name = Skins.get(id).DisplayName,
		Title = if gift then Gift.Title elseif kind == "Podium" then "PODIUM" else "BARRICADE",
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

	--[[
		Darul n-are pret, deci n-are nici moneda si nici socoteala de facut: pe
		buton scrie indemnul din `Gift`, si il primeste oricine apasa. Ce se cere
		in schimb — un like — nu se poate verifica din cod, si asta e in regula:
		e o intelegere, spusa pe fata, nu o poarta.
	]]
	if gift then
		offer.Action = Gift.Call
		offer.Tone = "BUY"
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
		stand.View:paint(describe(stand.Kind, stand.Id, stand.Gift))
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

	--[[
		Cererea darului nu duce cu ea niciun id: serverul stie ce da. Un id venit
		de aici ar face din dar un magazin fara bani.
	]]
	if stand.Gift then
		Remotes.get("RequestGift"):FireServer()
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

--[[
	Punctul de la care se masoara apropierea de o vitrina.

	Sta la talpa ei, nu in varf. `OfferAnchor` — de care atarna placuta si
	cartonasul — e pus deasupra obiectului expus, adica la vreo douasprezece
	studi peste podea; masurata de acolo, distanta pana la cineva care sta in
	fata soclului e aproape numai pe verticala, si se consuma degeaba toata raza.
	Aici coboara la inaltimea la care chiar umbla omul.

	Nu raspunde la raze si nu se poate atinge: e un reper, nu un obiect.
]]
local function reachFor(anchor: Model): BasePart
	local existing = anchor:FindFirstChild("OfferReach")
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local box, size = anchor:GetBoundingBox()

	local part = Instance.new("Part")
	part.Name = "OfferReach"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(box.Position.X, box.Position.Y - size.Y / 2, box.Position.Z)
	part.Parent = anchor
	return part
end

--[[
	Deschide cartonasul unei singure vitrine: cea mai apropiata, daca e in raza.

	Pana acum fiecare vitrina isi hotara singura soarta, dupa `PromptShown` si
	`PromptHidden`. Mergea cat timp razele nu se atingeau, dar in galerie
	soclurile stau la cincisprezece studi unul de altul: cu raza coborata la
	nivelul podelei ajungi des intre doua, si se deschideau amandoua deodata —
	doua cartonase suprapuse peste doua vitrine, si nu se stia care buton al
	cui e.

	Alegerea celui mai apropiat inchide si promptul celorlalti, nu doar
	cartonasul: altfel tasta ar fi cumparat de la o vitrina al carei cartonas nu
	era pe ecran.
]]
local function updateFocus()
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	local closest: Stand? = nil
	if root and root:IsA("BasePart") then
		local best = REACH
		for _, stand in stands do
			local away = (stand.Reach.Position - root.Position).Magnitude
			if away < best then
				best = away
				closest = stand
			end
		end
	end

	for _, stand in stands do
		local focused = stand == closest
		stand.Prompt.Enabled = focused
		stand.View:setNear(focused)
	end
end

--[[
	Cautarea merge pe firul ei, si porneste o singura data oricate vitrine ar fi.

	Pe `Heartbeat` ar fi fost mai simplu de scris, dar ar fi legat pretul unei
	cautari de cadenta ecranului — vezi `FOCUS_INTERVAL`.
]]
local function watch()
	if watching then
		return
	end
	watching = true

	task.spawn(function()
		while true do
			updateFocus()
			task.wait(FOCUS_INTERVAL)
		end
	end)
end

local function bind(stand: Stand, view: OfferView.OfferView, prompt: ProximityPrompt)
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
		local reach = reachFor(anchor)
		local view = OfferView.new(part, LIFT)

		--[[
			Cupola care tine oamenii jos de pe soclu. Poate sa nu iasa — o vitrina
			fara `DisplayBase` sau lipita de podea nu are ce pazi — si atunci
			totul merge mai departe fara ea.
		]]
		Pedestal.guard(anchor)

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
		--[[
			Promptul sta pe reperul de la talpa, nu pe cel de sus: el masoara
			distanta de la piesa pe care e pus, si trebuie sa raspunda exact de
			unde se deschide si cartonasul.
		]]
		prompt.Parent = reach

		local stand: Stand = {
			View = view,
			Prompt = prompt,
			Reach = reach,
			Kind = showcase.Kind,
			Id = showcase.Id,
			Gift = showcase.Gift == true,
		}
		table.insert(stands, stand)
		bind(stand, view, prompt)
	end

	listen()
	watch()
	refresh()
end

return ShowcaseController
