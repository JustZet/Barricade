--!strict
--[[
	OfferView — oferta care pluteste deasupra unei vitrine din lobby.

	Doua desene, nu unul: o placuta cat treci pe langa vitrina, si un cartonas
	cand te opresti la ea. Asa se face intr-un joc de azi, si din doua motive.
	Intai, un panou mare deasupra fiecarei vitrine ar transforma galeria intr-un
	zid de panouri prin care nu s-ar mai vedea obiectele expuse. Apoi, cat te
	plimbi te intereseaza doar ce e si cat costa; ce scrie mai mult — poza mare,
	starea, butonul — are rost abia cand ai ajuns in fata lui.

	Ecranul asta nu hotaraste nimic si nu cere nimic. Primeste o oferta deja
	socotita de `ShowcaseController` — nume, pret, ce scrie pe buton, daca e
	aprins — si o deseneaza. Cine detine ce si cati banuti sunt in buzunar se
	afla in alta parte.

	Pozitiile sunt fractiuni masurate in cele doua PNG-uri, exact ca la fereastra
	de magazin: cine inlocuieste desenele remasoara, altfel totul aluneca.

	Marimile sunt in **studi**, nu in pixeli. Un `BillboardGui` cu marime in
	fractiuni se masoara in lume, deci oferta se micsoreaza cu departarea ca
	orice alt obiect — si nu ajunge un afis cat ecranul cand te apropii.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ItemWell = require(script.Parent.ItemWell)
local Theme = require(script.Parent.Theme)

type Kind = Catalog.Kind

local LOCAL_PLAYER = Players.LocalPlayer

local OfferView = {}
OfferView.__index = OfferView

--[[
	Zonele celor doua desene, in pixelii lor.

	Se scriu in pixeli si se impart la marimea desenului abia cand se aseaza,
	prin `spot`. Asa numerele de mai jos sunt chiar ce se masoara in PNG, si nu
	trebuie recalculate cu creionul cand se muta ceva.

	Panglica de sus a cartonasului e singura zona care nu e o scobitura, ci o
	placa ridicata: numele se scrie *pe* ea. Restul sunt scobituri — caseta mare
	de previzualizare, dunga pretului si locul butonului.
]]
local PANEL_W, PANEL_H = 504, 660

local NAME = { X = 80, Y = 32, W = 344, H = 62 }
local WELL = { X = 63, Y = 117, W = 378, H = 308 }
local PRICE = { X = 60, Y = 441, W = 383, H = 57 }
--[[
	Butonul umple scobitura lui, nu doar mijlocul ei.

	Desenul lasa locul butonului intre 505 si 621; butonul statea de la 517 la
	618, adica o duzina de pixeli de lemn gol deasupra lui si inca trei sub. Pe
	cartonas golul ala se vedea ca un buton prea mic pentru scobitura in care
	sta — placa aurie parea pusa acolo provizoriu, nu turnata in lemn.

	Doi pixeli de o parte si de alta raman dinadins: lipita de muchie, placa ar
	fi acoperit umbra sculptata a scobiturii, si butonul ar fi parut lipit peste
	desen in loc de asezat in el.
]]
local ACTION = { X = 61, Y = 507, W = 382, H = 112 }

--[[
	Moneda din capatul dungii de pret, si aerul din jurul ei.

	Sta in desen la fel cum sta si pe cartonasele din magazin, unde e pictata
	direct in lemn: numarul singur nu spune in ce se plateste. Aici desenul e
	gol, deci moneda se pune din cod — si se stinge cand in dunga nu mai scrie
	un numar, fiindca o moneda langa "EQUIPPED" nu inseamna nimic.
]]
--[[
	Cum arata butonul in fiecare stare.

	Desenul e chiar butonul auriu al jocului — acelasi lemn pictat, cu muchie,
	lumina si buza de jos, pe care il poarta si placa de pret din magazin. Se
	**intinde**, nu se taie in noua: un 9-slice isi tine colturile la o marime
	fixa in pixeli de ecran, iar un panou din lume isi schimba marimea cu
	distanta — de aproape ar fi iesit drept, de departe o pastila. Intins,
	coltul ramane cat e in desen, adica la fel in orice clipa.

	Starile care nu se pot apasa poarta acelasi lemn, vopsit: rosu cand nu
	ajung banutii, verde pentru ce porti deja. Ce nu e inca de vanzare ia
	lemnul inchis, ca sa nu para ca asteapta o apasare.

	Tabelul e doar al butonului. Placuta de departe nu poarta nicio stare: pe ea
	scrie un nume, iar un nume nu e nici de cumparat, nici echipat.
]]
local LOOK: {
	[string]: { Plate: string, Tint: Color3, Ink: Color3, Press: boolean },
} = {
	BUY = {
		Plate = Theme.Skin.Primary.Image,
		Tint = Color3.new(1, 1, 1),
		Ink = Theme.Color.TextInverse,
		Press = true,
	},
	EQUIP = {
		Plate = Theme.Skin.Primary.Image,
		Tint = Color3.new(1, 1, 1),
		Ink = Theme.Color.TextInverse,
		Press = true,
	},
	WORN = {
		Plate = Theme.Skin.Primary.Image,
		Tint = Color3.fromHex("9FE08A"),
		Ink = Theme.Color.Text,
		Press = false,
	},
	POOR = {
		Plate = Theme.Skin.Primary.Image,
		Tint = Color3.fromHex("F08A86"),
		Ink = Theme.Color.Text,
		Press = false,
	},
	SOON = {
		Plate = Theme.Skin.Secondary.Image,
		Tint = Color3.new(1, 1, 1),
		Ink = Theme.Color.TextMuted,
		Press = false,
	},
}

local COIN_SIDE, COIN_PAD = 58, 16

-- Zonele placutei, in pixelii ei. Are o singura scobitura.
local TAG_W, TAG_H = 378, 122
local TAG_INNER = { X = 31, Y = 19, W = 316, H = 79 }

--[[
	Cat de rotunjita e caseta de previzualizare.

	Raza se da in **fractiune**, nu in pixeli, si asta e singurul fel in care
	poate fi data aici: un `BillboardGui` isi schimba marimea pe ecran cu
	departarea, iar o raza in pixeli ar fi ramas aceeasi — caseta parea un cerc
	de departe si un dreptunghi de aproape. In fractiune, colturile raman
	rotunjite exact cat sunt si cele sculptate in desen, de la orice distanta.

	0.156 iese din desen: scobitura are colturi de vreo 24 de pixeli pe o
	inaltime de 308, iar la `UICorner` fractiunea se masoara din jumatatea
	laturii scurte.
]]
local WELL_RADIUS = UDim.new(0.156, 0)

--[[
	Cat de mare se vede fiecare desen, in studi de latime.

	Cartonasul e cat un jucator si jumatate: destul cat sa se citeasca de la
	distanta de la care il poti si cumpara, dar nu cat sa acopere vitrina din
	spatele lui. Placuta e mai ingusta: poarta un singur cuvant.
]]
local PANEL_STUDS = 6
local TAG_STUDS = 4.2

--[[
	De la ce distanta se vede fiecare.

	Placuta se vede din tot lobby-ul, ca sa poti alege de departe la care vitrina
	te duci. Cartonasul nu are nevoie de distanta: apare doar cand esti deja
	langa obiect, si se stinge singur la fel de repede.
]]
local TAG_DISTANCE = 120
local PANEL_DISTANCE = 60

-- Cat dureaza cresterea placutei in cartonas.
local SWAP_SECONDS = 0.18

-- Cat tine licarirea de pe buton dupa o apasare primita.
local FLASH_SECONDS = 0.12

--[[
	Oferta, asa cum o vede desenul.

	Trei locuri, trei lucruri: panglica de sus spune **ce fel** de obiect e,
	dunga de sub imagine ii spune **numele**, iar butonul spune **ce se intampla
	daca apesi** — pretul, cat timp nu e al tau, si starea lui dupa aceea.

	Pretul sta pe buton, nu langa el, fiindca pretul *este* apasarea: atat dai
	acum. Cat timp statea deasupra, butonul repeta o stare pe care o spunea deja
	si culoarea, iar cartonasul avea doua randuri care ziceau acelasi lucru.
]]
export type Tone = "BUY" | "EQUIP" | "WORN" | "POOR" | "SOON"

export type Offer = {
	Kind: Kind,
	Id: string,
	-- Numele obiectului: pe placuta de departe si pe dunga de sub imagine.
	Name: string,
	-- Felul lui, pe panglica de sus.
	Title: string,
	-- Ce scrie pe buton: un pret, sau cuvantul care ii tine locul.
	Action: string,
	--[[
		In ce stare e oferta. Controllerul spune **ce**, desenul alege **cum**:
		ce placa poarta butonul, cu ce culoare si daca se poate apasa. Asa
		culorile stau toate intr-un loc, langa desen, si nu se imprastie prin
		socoteala care le alege.
	]]
	Tone: Tone,
	-- Butonul arata un pret? Doar atunci are moneda ce sa insoteasca.
	Coined: boolean,
}

type OfferFields = {
	Tag: BillboardGui,
	TagName: TextLabel,
	Panel: BillboardGui,
	PanelScale: UIScale,
	PanelKind: TextLabel,
	PanelWell: Frame,
	PanelLabel: TextLabel,
	PanelCoin: ImageLabel,
	-- Fata butonului: placa de lemn pe care scrie pretul.
	Face: ImageLabel,
	--[[
		Cele doua asezari ale pretului: dupa moneda, cand se plateste, si pe
		toata dunga, cand acolo scrie un cuvant. Se socotesc o data, la
		constructie, fiindca se schimba intre ele la fiecare desenare.
	]]
	PricePos: UDim2,
	PriceSize: UDim2,
	WidePos: UDim2,
	WideSize: UDim2,
	PanelAction: TextLabel,
	--[[
		Butonul de pe cartonas, si dunga care licareste sub el la apasare.

		Butonul nu cumpara el: cere `ProximityPrompt`-ului sa declanseze, ca sa
		existe un singur drum spre cumparare, oricare ar fi dispozitivul. Vezi
		`ShowcaseController`.
	]]
	Button: TextButton,
	Fill: Frame,
	FillTween: Tween?,
}

export type OfferView = typeof(setmetatable({} :: OfferFields, OfferView))

--[[
	Un `BillboardGui` asezat deasupra vitrinei.

	`AlwaysOnTop` ramane stins dinadins: oferta e un obiect din lume si are voie
	sa treaca in spatele unui stalp, ca orice altceva. Aprins, ar pluti peste tot
	lobby-ul, chiar si prin ziduri, si ar arata ca o eroare. Exceptia e
	cartonasul de aproape, care trebuie sa primeasca clicuri — vezi `new`.

	**Sta insa in `PlayerGui`, nu in piesa de care se agata.** Un billboard
	parentat in `Workspace` se deseneaza, dar nu primeste nicio apasare: butonul
	din el isi schimba culoarea si sta degeaba, iar singurul fel in care se putea
	cumpara ramanea tasta de apropiere. Legat de `PlayerGui` si tinut pe loc prin
	`Adornee`, se deseneaza exact la fel si se poate si apasa — probat: un clic
	pe pret a scazut soldul cu pretul.
]]
local function billboard(
	adornee: BasePart,
	name: string,
	studs: number,
	ratio: number,
	height: number,
	distance: number
): BillboardGui
	return Theme.create("BillboardGui", {
		Name = name,
		Adornee = adornee,
		Size = UDim2.fromScale(studs, studs * ratio),
		StudsOffsetWorldSpace = Vector3.new(0, height, 0),
		MaxDistance = distance,
		ResetOnSpawn = false,
		Parent = LOCAL_PLAYER:WaitForChild("PlayerGui"),
	}) :: BillboardGui
end

--[[
	Textul de pe o eticheta din lume se masoara singur.

	`TextScaled` e regula aici, nu exceptia: marimea in pixeli a unui
	`BillboardGui` depinde de cat de departe stai, deci un `TextSize` fix ar fi
	minuscul de departe si urias de aproape. Scalat, textul umple mereu caseta
	care i s-a dat, si casetele sunt masurate in desen.
]]
local function worldText(properties: { [string]: any }): TextLabel
	properties.TextScaled = true
	properties.TextWrapped = false
	return Theme.text(properties)
end

--[[
	O zona masurata in desen, tradusa in pozitia si marimea pe care le cere
	Roblox. Pixelii raman scrisi sus, langa desen, iar impartirea se face
	intr-un singur loc.
]]
local function spot(
	x: number,
	y: number,
	w: number,
	h: number,
	width: number,
	height: number
): (UDim2, UDim2)
	return UDim2.fromScale(x / width, y / height), UDim2.fromScale(w / width, h / height)
end

-- Aceeasi masuratoare, pe cartonas.
local function panelSpot(area: { X: number, Y: number, W: number, H: number }): (UDim2, UDim2)
	return spot(area.X, area.Y, area.W, area.H, PANEL_W, PANEL_H)
end

function OfferView.new(adornee: BasePart, lift: number): OfferView
	local self = setmetatable({}, OfferView) :: OfferView

	-- ------------------------------------------------------------- placuta
	local tag = billboard(adornee, "OfferTag", TAG_STUDS, TAG_H / TAG_W, lift, TAG_DISTANCE)
	self.Tag = tag

	Theme.create("ImageLabel", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.tagShowcase,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		Parent = tag,
	})

	--[[
		Pe placuta scrie doar numele, si atat.

		Pretul statea sub el, pe al doilea rand, si nu avea ce cauta acolo: de la
		distanta de la care se vede placuta nu poti cumpara nimic, deci cifra nu
		e o informatie, e o intrebare fara raspuns. Ce trebuie sa afli din mers e
		**care** vitrina e care, ca sa stii la care te duci; cat costa afli cand
		ajungi, pe cartonasul care creste din ea.

		Fara al doilea rand, numele ia toata scobitura si se citeste de mai
		departe — `TextScaled` il umfla cat il lasa caseta, iar caseta tocmai s-a
		dublat.
	]]
	local namePos, nameSize = spot(TAG_INNER.X, TAG_INNER.Y, TAG_INNER.W, TAG_INNER.H, TAG_W, TAG_H)
	self.TagName = worldText({
		Name = "Name",
		Text = "",
		Font = Theme.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = namePos,
		Size = nameSize,
		Parent = tag,
	})

	-- ------------------------------------------------------------ cartonasul
	--[[
		Cartonasul urca mai sus decat placuta cu jumatate din inaltimea lui in
		plus: amandoua sunt centrate pe punctul lor, iar fara ridicarea asta
		marginea lui de jos ar intra in obiectul expus.
	]]
	local panelRatio = PANEL_H / PANEL_W
	local panel = billboard(
		adornee,
		"OfferPanel",
		PANEL_STUDS,
		panelRatio,
		lift + PANEL_STUDS * panelRatio / 2,
		PANEL_DISTANCE
	)
	panel.Enabled = false

	--[[
		Fara asta, butonul din panou nu poate fi apasat cu mouse-ul.

		Un `BillboardGui` nu lasa nimic dinauntrul lui sa primeasca apasari cat
		timp el insusi nu e `Active`, si vine stins din fabrica. Butonul exista,
		era legat si isi schimba culoarea, dar clicul trecea prin el ca prin aer:
		singurul fel in care se putea cumpara ramanea tasta de apropiere. De acolo
		venea si impresia ca altfel nu se poate.

		Placuta de departe n-are nevoie: pe ea nu se apasa nimic.
	]]
	panel.Active = true

	--[[
		Si tot n-ar fi fost de ajuns: clicul pe un billboard se opreste la prima
		piesa din lume pe care o loveste raza, inaintea lui. Cartonasul sta chiar
		in stalpul nevazut pus de `Pedestal` peste soclu, iar stalpul e solid —
		trebuie sa fie, ca sa nu te urci pe soclu — si o piesa solida prinde raze
		oricum, oricat i-ai stinge `CanQuery`. Masurat in lobby: raza spre buton
		lovea stalpul la 19 studi, cartonasul era la 25, iar clicul nu ajungea.

		Deasupra a tot, raza nu mai trece prin lume. Numai cartonasul, nu si
		placuta: el se deschide doar cand esti langa vitrina, iar de acolo n-are
		ce sa-l acopere pe drept. Placuta de departe ramane in lume, cu stalpi cu
		tot, cum scrie la `billboard`.
	]]
	panel.AlwaysOnTop = true
	self.Panel = panel

	self.PanelScale = Theme.create("UIScale", { Scale = 1, Parent = panel }) :: UIScale

	Theme.create("ImageLabel", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.panelShowcase,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		Parent = panel,
	})

	local titlePos, titleSize = panelSpot(NAME)
	self.PanelKind = worldText({
		Name = "Kind",
		Text = "",
		Font = Theme.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = titlePos,
		Size = titleSize,
		Parent = panel,
	})

	local wellPos, wellSize = panelSpot(WELL)
	local well = ItemWell.build(nil, "Barricade", WELL_RADIUS)
	well.Position = wellPos
	well.Size = wellSize
	well.Parent = panel
	self.PanelWell = well

	-- Numele obiectului, pe toata dunga: nimic nu mai sta langa el.
	local labelPos, labelSize = panelSpot({
		X = PRICE.X + COIN_PAD,
		Y = PRICE.Y + PRICE.H * 0.15,
		W = PRICE.W - COIN_PAD * 2,
		H = PRICE.H * 0.7,
	})
	self.PanelLabel = worldText({
		Name = "Label",
		Text = "",
		Font = Theme.Font.Bold,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = labelPos,
		Size = labelSize,
		Parent = panel,
	})

	-- ------------------------------------------------------------- butonul
	local actionPos, actionSize = panelSpot(ACTION)
	local button = Theme.create("TextButton", {
		Name = "Action",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Position = actionPos,
		Size = actionSize,
		Parent = panel,
	}) :: TextButton
	self.Button = button

	--[[
		Fata butonului.

		Pana acum butonul era o scobitura in lemnul desenat: se putea apasa, dar
		nu se vedea ca se poate, si jucatorii cautau tasta. Acum are o placa
		plina, cu colturi rotunde si un contur mai inchis — o forma pe care ai
		mai apasat in alte zece jocuri. Culoarea ei spune si daca merge: aurie
		cand se poate cumpara sau echipa, stinsa cand nu.

		Sta sub continut si peste licarire, deci ordinea lor se scrie in ZIndex:
		intr-un BillboardGui ordinea implicita nu e cea a copiilor.
	]]
	self.Face = Theme.create("ImageLabel", {
		Name = "Face",
		BackgroundTransparency = 1,
		Image = Theme.Skin.Primary.Image,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = button,
	}) :: ImageLabel

	--[[
		Dunga care licareste sub buton la apasare.

		Starea se schimba oricum — pretul devine "EQUIPPED" — dar schimbarea vine
		de pe server, adica peste o clipa. Licarirea e raspunsul de acum, cel
		care spune ca apasarea a fost primita, nu ca a si ajuns.
	]]
	self.Fill = Theme.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Color.Text,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 2,
		Size = UDim2.fromScale(0, 1),
		Parent = self.Face,
	}, {
		Theme.create("UICorner", { CornerRadius = UDim.new(0.4, 0) }),
	}) :: Frame

	--[[
		Moneda si textul stau **in** buton, nu deasupra lui.

		Moneda se agata de capatul din stanga si textul incepe dupa ea; centrat pe
		tot butonul, numarul ar fi urcat peste moneda de fiecare data cand ar fi
		avut o cifra in plus. Cand pe buton scrie un cuvant — "EQUIP", "SOON" —
		moneda se stinge si textul primeste toata latimea.

		Masurile sunt tot in pixelii desenului, imparite la marimea butonului: el
		e acum cadrul in care traiesc.
	]]
	local function inButton(area: { X: number, Y: number, W: number, H: number }): (UDim2, UDim2)
		return spot(area.X, area.Y, area.W, area.H, ACTION.W, ACTION.H)
	end

	local coinPos, coinSize = inButton({
		X = COIN_PAD,
		Y = (ACTION.H - COIN_SIDE) / 2,
		W = COIN_SIDE,
		H = COIN_SIDE,
	})
	self.PanelCoin = Theme.create("ImageLabel", {
		Name = "Coin",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.coinSmall,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 3,
		Position = coinPos,
		Size = coinSize,
		Parent = button,
	}) :: ImageLabel

	self.PricePos, self.PriceSize = inButton({
		X = COIN_PAD * 2 + COIN_SIDE,
		Y = ACTION.H * 0.2,
		W = ACTION.W - COIN_PAD * 3 - COIN_SIDE,
		H = ACTION.H * 0.6,
	})

	self.WidePos, self.WideSize = inButton({
		X = COIN_PAD,
		Y = ACTION.H * 0.2,
		W = ACTION.W - COIN_PAD * 2,
		H = ACTION.H * 0.6,
	})

	self.PanelAction = worldText({
		Name = "Label",
		Text = "",
		Font = Theme.Font.Bold,
		TextColor3 = Theme.Color.TextInverse,
		ZIndex = 3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = self.WidePos,
		Size = self.WideSize,
		Parent = button,
	})

	return self
end

--[[
	Deseneaza oferta. Se cheama ori de cate ori se schimba ceva ce o priveste:
	soldul, inventarul, sau obiectul echipat.
]]
function OfferView.paint(self: OfferView, offer: Offer)
	self.TagName.Text = offer.Name

	self.PanelKind.Text = offer.Title
	self.PanelLabel.Text = offer.Name

	--[[
		Moneda insoteste numarul, nu cuvantul. Cand pe buton scrie "EQUIP" sau
		"EQUIPPED" nu se mai plateste nimic, iar textul se muta la mijlocul
		butonului, unde ar fi stat moneda.
	]]
	self.PanelCoin.Visible = offer.Coined
	self.PanelAction.Position = if offer.Coined then self.PricePos else self.WidePos
	self.PanelAction.Size = if offer.Coined then self.PriceSize else self.WideSize

	self.PanelAction.Text = offer.Action

	--[[
		Cum arata butonul in starea asta: ce placa, cu ce culoare, cu ce cerneala
		si daca raspunde la apasare. Toate dintr-un singur tabel, sus.
	]]
	local look = LOOK[offer.Tone]
	self.Face.Image = look.Plate
	self.Face.ImageColor3 = look.Tint
	self.PanelAction.TextColor3 = look.Ink
	self.Button.Active = look.Press

	ItemWell.show(self.PanelWell, offer.Id, offer.Kind)
end

--[[
	Trecerea dintre cele doua desene.

	Cartonasul creste in loc sa apara: o aparitie brusca la un pas de vitrina
	se citeste ca o eroare de randare, una crescuta din nimic se citeste ca un
	raspuns la faptul ca te-ai apropiat.
]]
function OfferView.setNear(self: OfferView, near: boolean)
	if self.Panel.Enabled == near then
		return
	end

	self.Tag.Enabled = not near
	self.Panel.Enabled = near
	self:stopFlash()

	if near then
		self.PanelScale.Scale = 0.72
		TweenService:Create(
			self.PanelScale,
			TweenInfo.new(SWAP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
end

--[[
	Licarirea de la apasare: dunga trece o data peste buton si se stinge.

	Nu spune ca s-a cumparat — asta o spune starea care vine de pe server, peste
	o clipa. Spune doar ca apasarea a fost primita, si e singurul lucru care
	umple clipa aia.
]]
function OfferView.flash(self: OfferView)
	self:stopFlash()

	local tween = TweenService:Create(
		self.Fill,
		TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }
	)
	self.FillTween = tween
	tween.Completed:Connect(function()
		self:stopFlash()
	end)
	tween:Play()
end

function OfferView.stopFlash(self: OfferView)
	local running = self.FillTween
	if running then
		self.FillTween = nil
		running:Cancel()
	end
	self.Fill.Size = UDim2.fromScale(0, 1)
	self.Fill.BackgroundTransparency = 0.55
end

function OfferView.destroy(self: OfferView)
	self:stopFlash()
	self.Tag:Destroy()
	self.Panel:Destroy()
end

return OfferView
