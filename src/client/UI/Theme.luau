--!strict
--[[
	Theme — vocabularul vizual al jocului, intr-un singur loc.

	Versiunea asta inlocuieste paleta rece cu cea din Barricade Design System:
	lemn si hartie, lumina mereu de sus, Fredoka pentru display si Nunito pentru
	interfata. Butoanele nu mai sunt dreptunghiuri colorate, ci placi de lemn
	9-slice din asseturile urcate — textura poarta materialul, textul sta separat
	deasupra ei.

	**API-ul public e neschimbat.** Aceleasi chei in `Color`, `Font` si `Radius`,
	aceleasi semnaturi la `create`, `corner`, `stroke`, `padding`, `text`, `button`
	si `recolorButton`. Fisierul se poate schimba singur, fara sa se atinga niciun
	view — de aceea arata asa, in loc sa fie o rescriere a intregului UI.

	Culorile tot nu poarta singure informatie: design system-ul cere ca fiecare
	jucator sa aiba si o forma (cerc, romb, patrat, triunghi), nu doar o culoare.
	Formele vin din asseturile `Assets.Token`, nu din culoarea de aici.
]]

local Theme = {}

--[[
	Paleta. Rolurile sunt cele dinainte, ca view-urile existente sa nu se schimbe;
	doar valorile trec de la rece-inchis la lemn cald.
]]
Theme.Color = {
	-- Fundal, de la cel mai adanc la cel mai ridicat plan.
	Backdrop = Color3.fromHex("2A1A0E"),
	Surface = Color3.fromHex("4A2E17"),
	SurfaceRaised = Color3.fromHex("B5763C"),
	Board = Color3.fromHex("7A4A22"),

	-- Celulele au doua nuante foarte apropiate: se citeste grila fara sa tipe.
	CellLight = Color3.fromHex("EFD9AE"),
	CellDark = Color3.fromHex("EBD9BC"),
	CellHover = Color3.fromHex("F2DCA8"),
	CellTarget = Color3.fromHex("C7DCAE"),

	Line = Color3.fromHex("8A6034"),
	Wall = Color3.fromHex("C68B4E"),
	WallShadow = Color3.fromHex("5A3418"),

	Valid = Color3.fromHex("4BA63C"),
	Invalid = Color3.fromHex("D9443F"),
	Accent = Color3.fromHex("E87A2C"),
	-- Singurul contur permis de design system: inelul de selectie.
	Highlight = Color3.fromHex("FFD666"),

	Text = Color3.fromHex("FBF3E2"),
	-- Textul secundar apare si pe fundal inchis, si pe placa de lemn. Wood/300 se
	-- pierde pe lemn, deci nuanta e trasa spre crem: ramane discreta pe inchis si
	-- lizibila pe placa.
	TextMuted = Color3.fromHex("EBD2A8"),
	TextInverse = Color3.fromHex("3B2412"),

	-- Starea dezactivata, din spec sheet-ul design system-ului (sectiunea 17).
	disabledFill = Color3.fromHex("CFC0A4"),
	disabledText = Color3.fromHex("A08A6A"),
}

--[[
	Fredoka exista in Roblox doar ca FredokaOne, cu o singura grosime (~700);
	nivelurile Fredoka 600 din design sunt aproximate cu ea. Nunito e tot o
	singura fata, deci `Medium` si `Regular` arata la fel si se diferentiaza
	prin marime si spatiere, nu prin grosime.

	`fontOr` exista pentru ca lista de fonturi difera intre versiuni de client:
	daca una lipseste, UI-ul trebuie sa ramana lizibil, nu sa cada pe Legacy.
]]
local function fontOr(name: string, fallback: Enum.Font): Enum.Font
	local ok, value = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: Enum.Font
	end
	return fallback
end

Theme.Font = {
	Bold = fontOr("FredokaOne", Enum.Font.GothamBold),
	Medium = fontOr("Nunito", Enum.Font.GothamMedium),
	Regular = fontOr("Nunito", Enum.Font.Gotham),
}

-- Razele din spec sheet: chip 10, card 12, panou 20, pastila completa.
Theme.Radius = {
	Small = UDim.new(0, 10),
	Medium = UDim.new(0, 14),
	Large = UDim.new(0, 20),
	Round = UDim.new(1, 0),
}

--[[
	Asseturile urcate pe contul creatorului. ID-urile canonice stau in
	`assets/design-system/ids.json`; aici sunt doar cele de care are nevoie
	interfata. Toate sunt exportate la 2x, deci `SliceCenter` e in pixelii
	bitmap-ului de 2x, nu in cei de la 1x.
]]
Theme.Assets = {
	--[[
		Placile implicite sunt fara grain copt. La 9-slice centrul se intinde, iar
		un grain desenat in textura se manjeste pe butoanele late si lasa o
		cusatura vizibila acolo unde centrul intalneste marginea. Design system-ul
		cere exact separarea asta: lemnul e gradient plus muchie, iar fibra vine
		dintr-o singura textura tileabila de 256px, adaugata cu `Theme.grain`.

		Variantele `Textured*` pastreaza grain-ul copt si sunt utile doar la
		suprafete mici, care nu se intind aproape deloc.
	]]
	Plate = {
		Large = "rbxassetid://99460863755172",
		Medium = "rbxassetid://127705370769313",
		Small = "rbxassetid://122531410899099",
		Disabled = "rbxassetid://87431084954685",
		Green = "rbxassetid://137475878813893",
		Panel = "rbxassetid://78313856397703",
		Card = "rbxassetid://76367558578065",

		TexturedLarge = "rbxassetid://81339455939561",
		TexturedMedium = "rbxassetid://91988087944826",
		TexturedSmall = "rbxassetid://121714518979409",
	},
	Token = {
		blue = "rbxassetid://110855189699055",
		blueActive = "rbxassetid://135760893307529",
		red = "rbxassetid://114107745898202",
		redActive = "rbxassetid://88068196856378",
		green = "rbxassetid://71348727869282",
		greenActive = "rbxassetid://129498354017998",
		yellow = "rbxassetid://136038308721017",
		yellowActive = "rbxassetid://112475239783312",
		eliminated = "rbxassetid://105930516034494",
		crownPip = "rbxassetid://130157377920395",
	},
	Barricade = {
		horizontal = "rbxassetid://117499290501346",
		vertical = "rbxassetid://108370254912490",
		valid = "rbxassetid://79613103854680",
		invalid = "rbxassetid://78681838022361",
	},
	--[[
		Cardul de jucator, taiat din plansa de prezentare.

		Nu sunt desene noi, sunt bucatile aceleiasi machete: placa, inelul, si
		cele trei semne de pe ea. Se folosesc impreuna, si de aceea stau
		impreuna — cine schimba placa vrea aproape sigur sa schimbe si inelul.

		`Ring` e gaurit la mijloc dinadins: poza jucatorului se pune *sub* el,
		iar inelul ii tine loc de rama. Asa fiecare isi vede chipul lui, in loc
		de cel inventat de model pe macheta.
	]]
	Card = {
		Plate = "rbxassetid://101120180360420",
		Ring = "rbxassetid://108274564013290",
		Crown = "rbxassetid://129534059259424",
		Clock = "rbxassetid://85544414065765",
		Wall = "rbxassetid://118049812159354",
	},

	--[[
		Asseturile de interfata din a doua plansa, inca nefolosite in cod.

		Stau aici ca sa existe un singur loc in care se cauta un id, si ca sa nu
		se piarda: sunt incarcate si aprobate, iar fara o lista scrisa singura
		urma a lor ar fi inventarul Roblox.
	]]
	Store = {
		coinLarge = "rbxassetid://71648076745073",
		-- Bara de monede gata desenata: moneda la stanga, loc de cifra la dreapta.
		currencyBar = "rbxassetid://94757248264213",
		coinMedium = "rbxassetid://78098037174108",
		coinSmall = "rbxassetid://86238265279081",
		badgeCrown = "rbxassetid://105137452982482",
		barricade3d = "rbxassetid://101509868464309",
		barricadeFlat = "rbxassetid://71213498795713",

		buttonAvatar = "rbxassetid://79840275914766",
		buttonMove = "rbxassetid://127519083014474",
		buttonMoveIdle = "rbxassetid://98951189998348",
		buttonMoveActive = "rbxassetid://92363998976181",
		buttonMoveDisabled = "rbxassetid://80765104154520",
		buttonWall = "rbxassetid://74198671176347",
		buttonWallIdle = "rbxassetid://85130060466570",
		buttonWallActive = "rbxassetid://81063802351466",
		buttonWallDisabled = "rbxassetid://90986982642070",

		logoCrown = "rbxassetid://113839093280337",
		logoPlanks = "rbxassetid://129441255420724",
		logoMossy = "rbxassetid://76562236771445",
		logoSmall = "rbxassetid://103494523961022",
		logoRound = "rbxassetid://82052473250817",

		barGold = "rbxassetid://103590540430762",
		barBlue = "rbxassetid://104806079101543",
		barRed = "rbxassetid://116212827422921",
		barGreen = "rbxassetid://136354930253912",
		barGrey = "rbxassetid://106903567191665",

		panelLarge = "rbxassetid://132689037442871",
		panelSlim = "rbxassetid://125663188040657",
		panelSmall = "rbxassetid://125198995661942",
		panelInventory = "rbxassetid://102908059679583",
		panelStore = "rbxassetid://101453348280483",

		tabLeft = "rbxassetid://129864566402657",
		tabActive = "rbxassetid://80178996348534",
		tabRight = "rbxassetid://123936255646466",

		--[[
			Fereastra de magazin, si cartonasele care stau in ea.

			Fereastra e un desen cu asezare **coapta in el**: taburile din stanga,
			bara de sold din dreapta sus si butonul de inchidere sunt pictate la
			locuri fixe. `StoreView` nu le poate muta, deci isi pune elementele
			peste ele, la fractiunile masurate pe imagine. Cine schimba desenul
			trebuie sa remasoare acolo.

			Cat timp e gol, magazinul nu se deschide deloc: mai bine lipseste
			decat sa apara pe jumatate desenat.
		]]
		panelStoreWindow = "rbxassetid://91082978523904",
		cardWood = "rbxassetid://120583627758152",
		cardGold = "rbxassetid://122294752992626",
		cardMossy = "rbxassetid://105616887778661",
		cardRed = "rbxassetid://130817119019394",
		cardDark = "rbxassetid://103731733355416",
		iconCoinRound = "rbxassetid://125853923641922",
		buttonStore = "rbxassetid://83033095744188",
		buttonClose = "rbxassetid://131754737457582",

		-- Variante inca nefolosite in cod, pastrate ca sa existe un singur loc
		-- in care se cauta un id.
		buttonWideDark = "rbxassetid://95412420597417",
		buttonWideLight = "rbxassetid://71024837578025",
		buttonWideDarkAlt = "rbxassetid://109713806120766",
		pillDarkAlt = "rbxassetid://127994065027913",
		buttonSmallGold = "rbxassetid://96600462158058",
		iconStoreRound = "rbxassetid://118083789013797",
	},

	Icon = {
		home = "rbxassetid://80548198284283",
		settings = "rbxassetid://121703120941696",
		sound = "rbxassetid://74649486616815",
		mute = "rbxassetid://84111608235438",
		music = "rbxassetid://140579249131095",
		back = "rbxassetid://74475653693512",
		next = "rbxassetid://89705125299300",
		close = "rbxassetid://80354790272609",
		check = "rbxassetid://136706122965770",
		player = "rbxassetid://124139590529867",
		team = "rbxassetid://127762608141720",
		trophy = "rbxassetid://129841673277890",
		crown = "rbxassetid://80808988854830",
		timer = "rbxassetid://113886057783682",
		help = "rbxassetid://124765034849100",
		rotate = "rbxassetid://120425651178639",
		horizontal = "rbxassetid://74147368130241",
		vertical = "rbxassetid://108057633041498",
		lock = "rbxassetid://135832320049066",
		shop = "rbxassetid://75198337192296",
		inventory = "rbxassetid://79119959739975",
		leave = "rbxassetid://117872720220468",
	},
	Texture = {
		woodGrain = "rbxassetid://76795381854493",
	},
}

-- Insets de 9-slice, in pixeli de bitmap 2x. Barele se intind doar pe axa lunga:
-- un inset pe ambele axe ar manca centrul unei bare de 48px si ar rupe capetele.
Theme.Slice = {
	Plate = Rect.new(36, 36, 156, 156),
	Panel = Rect.new(48, 48, 192, 192),
	Card = Rect.new(28, 28, 164, 164),
	BarricadeH = Rect.new(24, 0, 236, 48),
	BarricadeV = Rect.new(0, 24, 48, 236),
}

--[[
	Skinurile de buton: lemn desenat intreg, nu placa plus culoare.

	Placile din `Assets.Plate` sunt suprafete neutre pe care codul pune o culoare;
	skinurile sunt butoane gata pictate, cu muchie, lumina si buza de jos deja in
	imagine. De aceea aici nu se mai adauga `Theme.grain`: fibra e in desen, iar
	una peste alta se vad amandoua.

	`Slice` si `SliceScale` nu sunt de ochi. Coltul fiecarui desen a fost masurat
	(raza pana unde marginea se indreapta: 20px la butoanele late, 15 la pastile,
	8 la patrat) si insetul luat cu cativa pixeli peste el, ca taietura sa cada pe
	drept, nu pe curba. `SliceScale` de 0.75 e singura valoare la care un buton de
	46px inaltime iese intreg: la 1.0 colturile ocupa toata inaltimea si butonul
	devine o pastila cu cusatura la mijloc, iar la 0.5 se aplatizeaza si isi
	pierde sculptura. Am verificat fiecare combinatie randand 9-slice-ul pe disc
	inainte sa ajunga in joc.

	Cat timp un `Image` e gol, `Theme.button` se intoarce la placa de lemn de
	dinainte. Asa un asset respins la moderare, sau unul inca neincarcat, lasa
	butonul functional si urat, nu gol si nefolosibil.
]]
export type Skin = {
	Image: string,
	Slice: Rect,
	SliceScale: number,
}

Theme.Skin = {
	-- Aurul e pentru actiunea principala a ecranului. Un singur buton auriu pe
	-- ecran, altfel nu mai indica nimic.
	Primary = {
		Image = "rbxassetid://76929818464999",
		Slice = Rect.new(24, 24, 220, 46),
		SliceScale = 0.75,
	},
	-- Lemnul inchis: tot restul. Se citeste ca buton fara sa ceara privirea.
	Secondary = {
		Image = "rbxassetid://133330312965221",
		Slice = Rect.new(24, 24, 220, 44),
		SliceScale = 0.75,
	},
	-- Pastilele, pentru randurile de setari: mai scunde si mai rotunde.
	Pill = {
		Image = "rbxassetid://70399455055654",
		Slice = Rect.new(19, 19, 160, 43),
		SliceScale = 0.75,
	},
	PillGold = {
		Image = "rbxassetid://112982562318721",
		Slice = Rect.new(19, 19, 147, 42),
		SliceScale = 0.75,
	},
	-- Patratul, pentru butoanele de o litera sau un semn.
	Square = {
		Image = "rbxassetid://129157936369593",
		Slice = Rect.new(14, 14, 43, 42),
		SliceScale = 0.9,
	},
} :: { [string]: Skin }

--[[
	Constructor declarativ. Fara el, fiecare ecran ar fi trei sute de linii de
	`Instance.new` urmate de atribuiri, si structura ar disparea sub ele.

	create("Frame", { ... }, { copii })
]]
function Theme.create(
	className: string,
	properties: { [string]: any }?,
	children: { Instance }?
): Instance
	local instance = Instance.new(className)

	if properties then
		for key, value in properties do
			(instance :: any)[key] = value
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	return instance
end

function Theme.corner(radius: UDim?): Instance
	return Theme.create("UICorner", { CornerRadius = radius or Theme.Radius.Medium }) :: UICorner
end

function Theme.stroke(color: Color3?, thickness: number?, transparency: number?): Instance
	return Theme.create("UIStroke", {
		Color = color or Theme.Color.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(all: number): Instance
	return Theme.create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	})
end

function Theme.text(properties: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font.Medium,
		TextColor3 = Theme.Color.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	}
	for key, value in properties do
		defaults[key] = value
	end
	return Theme.create("TextLabel", defaults) :: TextLabel
end

--[[
	Placa de lemn 9-slice. Se foloseste direct cand un view vrea o suprafata de
	material fara sa fie buton — panouri, carduri, bare de actiuni.
]]
function Theme.plate(image: string, slice: Rect, properties: { [string]: any }?): ImageLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Image = image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = slice,
		--[[
			Asseturile sunt exportate la 2x, dar Roblox deseneaza marginile unui
			9-slice la 1:1 cu pixelii din bitmap. Fara scalare, un inset de 36px
			cere 72px doar pentru marginea de sus si cea de jos — mai mult decat
			inaltimea unui buton de 46px, asa ca marginile se striveau una in alta
			si fata placii aproape disparea. Textul parea atunci descentrat, pentru
			ca nu mai era centrat pe nimic.

			0.5 aduce marginile inapoi la dimensiunea de la 1x: inset 18px si raza
			exact cea din design, cu detaliul unei texturi de rezolutie dubla.
		]]
		SliceScale = 0.5,
	}
	local extra: { [string]: any } = properties or {}
	for key, value in extra do
		defaults[key] = value
	end
	return Theme.create("ImageLabel", defaults) :: ImageLabel
end

--[[
	Fibra lemnului, ca strat separat. Se pune ca prim copil al unei placi si se
	intinde peste ea: textura e tileabila la 256px, deci nu se deformeaza oricat
	de lata ar fi suprafata — spre deosebire de un grain copt in placa.

	`UICorner` taie si imaginea, nu doar fundalul, deci fibra respecta coltul
	rotunjit al placii in loc sa iasa din el.
]]
function Theme.grain(cornerRadius: UDim?, transparency: number?): ImageLabel
	return Theme.create("ImageLabel", {
		Name = "Grain",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Texture.woodGrain,
		ImageTransparency = transparency or 0.82,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(128, 128),
		Size = UDim2.fromScale(1, 1),
	}, {
		Theme.create("UICorner", { CornerRadius = cornerRadius or Theme.Radius.Medium }),
	}) :: ImageLabel
end

-- Icoanele sunt albe pe transparent, deci se coloreaza prin ImageColor3.
function Theme.icon(image: string, properties: { [string]: any }?): ImageLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Image = image,
		ImageColor3 = Theme.Color.Text,
	}
	local extra: { [string]: any } = properties or {}
	for key, value in extra do
		defaults[key] = value
	end
	return Theme.create("ImageLabel", defaults) :: ImageLabel
end

--[[
	Buton cu starile de interactiune deja legate. Roblox nu ofera hover si
	pressed din oficiu, iar un buton fara ele se simte mort.

	Ramane un TextButton, ca apelantii sa poata seta `Text`, `Size` si sa lege
	`MouseButton1Click` exact ca inainte.

	Lemnul apare **doar cand apelantul nu cere o culoare anume**. Cine trimite
	`BackgroundColor3` primeste in continuare o suprafata plata colorata, si e
	important sa ramana asa: `BoardView` construieste fiecare celula a tablei cu
	`Theme.button`, iar o placa de lemn 9-slice sub fiecare din cele 81 de celule
	ar fi si gresita vizual, si inutil de scumpa. Celulele au nevoie de umplere
	plata cu separatori subtiri, exact cum cere sectiunea 11.

	Butoanele de actiune nu trimit nimic, deci primesc placa. `PlateImage` permite
	alegerea explicita a placii (verde pentru actiunea implicita, mica pentru
	butoanele de colt).
]]
function Theme.button(properties: { [string]: any }): TextButton
	local explicitColor = properties.BackgroundColor3
	local plateImage = properties.PlateImage
	local usePlate = explicitColor == nil
	properties.PlateImage = nil

	--[[
		Skinul se cere pe nume, si poate lipsi.

		Un nume care nu exista, sau unul al carui desen nu e inca incarcat, nu e
		o eroare: butonul se face din placa de lemn dinainte si merge mai departe.
		Ecranul ramane folosibil chiar daca inventarul de asseturi e incomplet.
	]]
	local skinName = properties.Skin
	properties.Skin = nil

	local skin: Skin? = nil
	if skinName then
		local candidate = Theme.Skin[skinName]
		if candidate and candidate.Image ~= "" then
			skin = candidate
		end
	end

	local base = explicitColor or Color3.new(1, 1, 1)
	local hover = properties.HoverColor or base:Lerp(Color3.new(1, 1, 1), 0.12)
	properties.HoverColor = nil

	--[[
		Placa trebuie sa stea intre fundalul ecranului si textul butonului, si nu
		incape acolo fara sa ridicam butonul cu un nivel.

		`ZIndexBehavior.Sibling` ordoneaza dupa ZIndex in tot arborele, iar la
		valori egale decide ordinea din arbore. Placa e copil, deci la ZIndex egal
		cu butonul s-ar desena *peste* textul lui si l-ar acoperi; la ZIndex mai
		mic cu unu decat valoarea implicita ajunge la 0, sub fundalul opac al
		ecranului, si dispare. Solutia e sa urcam butonul la baza+1 si sa lasam
		placa pe baza: ramane peste fundal, pentru ca e mai adanca in arbore, si
		sub text, care acum e mai sus cu un nivel.
	]]
	local baseZIndex = properties.ZIndex or 1

	local defaults: { [string]: any } = {
		BackgroundColor3 = base,
		BackgroundTransparency = if usePlate then 1 else 0,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextColor3 = Theme.Color.Text,
		TextSize = 16,
		BorderSizePixel = 0,
	}
	for key, value in properties do
		defaults[key] = value
	end
	if usePlate then
		defaults.ZIndex = baseZIndex + 1
	end

	local button = Theme.create("TextButton", defaults) :: TextButton

	local plate: ImageLabel? = nil
	if usePlate then
		local drawn = skin :: Skin
		plate = Theme.plate(
			if skin then drawn.Image else plateImage or Theme.Assets.Plate.Medium,
			if skin then drawn.Slice else Theme.Slice.Plate,
			{
				Name = "Plate",
				Size = UDim2.fromScale(1, 1),
				ImageColor3 = base,
				SliceScale = if skin then drawn.SliceScale else 0.5,
				ZIndex = baseZIndex,
			}
		)
		local textured = plate :: ImageLabel
		if skin then
			-- Semnul ca butonul e pictat: `setButtonEnabled` nu are voie sa-i
			-- schimbe desenul, pentru ca placa de inactiv are alt inset si alta
			-- forma, si ar iesi un buton rupt in loc de unul stins.
			textured:SetAttribute("Skin", skinName)
		else
			Theme.grain(Theme.Radius.Medium).Parent = textured
		end
		textured.Parent = button

		--[[
			Textul trece intr-un label separat, iar cel propriu al butonului se
			stinge.

			`ZIndexBehavior.Sibling` deseneaza copiii mereu peste parinte, oricat
			de mic le-ar fi ZIndex-ul. Placa e copil, deci ar acoperi intotdeauna
			textul scris direct pe buton — nicio valoare de ZIndex nu schimba asta.
			Un label adaugat *dupa* placa e frate cu ea si se aseaza deasupra.

			`.Text` ramane proprietatea pe care o scriu apelantii: `HudView` o
			schimba dupa constructie pentru butonul de sunet si cel de baricade,
			asa ca label-ul o urmareste in loc sa o copieze o singura data.
		]]
		--[[
			Label-ul urca trei pixeli. Placa are o muchie dura de jos, opaca, care
			nu face parte din fata butonului; un text centrat pe dreptunghiul
			intreg cade optic sub mijlocul lemnului. Jumatate din muchie il aduce
			inapoi pe centrul suprafetei pe care sta.
		]]
		local label = Theme.create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, -3),
			Size = UDim2.fromScale(1, 1),
			Font = button.Font,
			TextSize = button.TextSize,
			TextColor3 = button.TextColor3,
			Text = button.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			RichText = true,
			ZIndex = baseZIndex + 1,
		}) :: TextLabel
		label.Parent = button
		button.TextTransparency = 1

		for _, property in { "Text", "TextColor3", "TextSize", "Font" } do
			button:GetPropertyChangedSignal(property):Connect(function()
				(label :: any)[property] = (button :: any)[property]
			end)
		end
	end

	--[[
		Culoarea de baza sta intr-un atribut, nu intr-o variabila prinsa in
		closure: butoanele isi schimba culoarea cand devin inactive, si
		hover-ul trebuie sa se intoarca la culoarea de *acum*, nu la cea de
		la constructie.
	]]
	button:SetAttribute("BaseColor", base)
	button:SetAttribute("HoverColor", hover)

	button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		local color = button:GetAttribute("HoverColor") :: Color3
		if plate then
			plate.ImageColor3 = color
		else
			button.BackgroundColor3 = color
		end
	end)
	button.MouseLeave:Connect(function()
		-- Un buton inactiv nu se reaprinde la iesirea cursorului. Fara garda
		-- asta, plimbarea peste un buton stins il readucea la culoarea vie.
		if not button.Active then
			return
		end
		local color = button:GetAttribute("BaseColor") :: Color3
		if plate then
			plate.ImageColor3 = color
		else
			button.BackgroundColor3 = color
		end
	end)

	return button
end

--[[
	Aprinde sau stinge un buton.

	Un buton stins trebuie sa arate stins, nu doar sa nu raspunda: altfel arata
	apasabil, il apesi, si nu se intampla nimic — ceea ce se citeste ca joc
	stricat, nu ca actiune indisponibila. De aceea se schimba si placa, si
	culoarea textului, nu doar `Active`.

	Placa initiala se tine minte in atribut, ca sa se poata reveni la ea: un
	buton poate fi stins si reaprins de mai multe ori in acelasi ecran.
]]
function Theme.setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false

	local plate = button:FindFirstChild("Plate")
	if plate and plate:IsA("ImageLabel") then
		if plate:GetAttribute("Skin") ~= nil then
			--[[
				Butonul pictat se stinge, nu se inlocuieste.

				Placa de inactiv e alt desen, cu alt inset si alta forma; pusa in
				locul unui skin ar iesi un buton rupt, nu unul inactiv. Culoarea
				il duce spre gri si il lasa recognoscibil — vezi ca e acelasi
				buton, doar ca nu raspunde.
			]]
			plate.ImageColor3 = if enabled
				then button:GetAttribute("BaseColor") :: Color3
				else Color3.fromRGB(120, 116, 112)
		else
			if plate:GetAttribute("EnabledImage") == nil then
				plate:SetAttribute("EnabledImage", plate.Image)
			end
			plate.Image = if enabled
				then plate:GetAttribute("EnabledImage") :: string
				else Theme.Assets.Plate.Disabled
		end
	end

	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = if enabled then Theme.Color.Text else Theme.Color.disabledText
	else
		button.TextColor3 = if enabled then Theme.Color.Text else Theme.Color.disabledText
	end
end

-- Schimba culoarea de baza a unui buton impreuna cu cea de hover.
function Theme.recolorButton(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("HoverColor", color:Lerp(Color3.new(1, 1, 1), 0.12))

	local plate = button:FindFirstChild("Plate")
	if plate and plate:IsA("ImageLabel") then
		plate.ImageColor3 = color
	else
		-- Butoanele construite inainte de placi raman colorabile pe fundal.
		button.BackgroundColor3 = color
	end
end

return Theme
