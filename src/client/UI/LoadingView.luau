--!strict
--[[
	LoadingView — ecranul de pornire, cat se aduc asseturile.

	Exista pentru un motiv concret, nu de decor: mesh-urile tablei sunt sute de
	piese, iar daca nu sunt cerute din timp, Roblox le aduce **in timpul
	meciului** — celulele apar una cate una sub picioarele jucatorilor, iar
	zidurile se materializeaza dupa ce au fost deja puse. Ecranul asta tine
	jocul acoperit exact cat dureaza aducerea lor.

	Un singur semn: logo-ul jocului, acelasi de pe zidul din lobby, care se
	coloreaza de la stanga la dreapta pe masura ce sosesc asseturile. Asteptarea
	are nevoie de ceva care sa se miste, altfel un ecran fix de cateva secunde
	pare inghetat — iar miscarea asta spune si cat a mai ramas.

	Deasupra lui statea candva emblema tablei, rotindu-se intr-un
	`ViewportFrame`. La marimea la care incapea se citea ca un punct oarecare,
	nu ca un obiect, si a fost scoasa.
]]

local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local FADE = 0.45

--[[
	Logo-ul: cat de mare se deseneaza, si cat de stins e cat nu s-a incarcat.

	Desenul e facut pentru o placa de lemn dintr-o lume 3D, nu pentru un ecran:
	intins peste trei sute optzeci de pixeli i se vedeau marginile pixelate si
	frunzele imbacsite. Desenat mai mic decat e, se aduna la loc — un bitmap
	arata mereu mai bine micsorat decat marit. Trei sute pe o suta cincizeci e
	sub marimea lui reala si tot mai lat decat bara de dedesubt, deci cele doua
	se citesc in continuare ca o pereche: cat s-a colorat din desen si cat s-a
	umplut din bara sunt aceeasi masura, vazuta de doua ori.

	Raportul ramane doi la unu, cat are desenul; schimbat, `Fit` ar lasa dungi
	goale in lateral si taietura umplerii n-ar mai cadea pe marginea logo-ului.

	Trei sferturi de stingere lasa logo-ul vizibil ca forma dar clar neatins:
	mai putin si nu s-ar vedea unde a ajuns incarcarea, mai mult si partea
	neincarcata ar disparea de tot, iar desenul ar parea taiat in loc de stins.
]]
local LOGO_W, LOGO_H = 300, 150
local LOGO_DIM = 0.76

--[[
	Cat sta ecranul pe loc, cel putin.

	Cand asseturile sunt deja in cache — a doua pornire, sau un jucator care
	revine — preincarcarea se termina intr-o clipa, iar ecranul ar clipi si ar
	disparea. Un fulger de o zecime de secunda deranjeaza mai mult decat o
	asteptare scurta, si oricum logo-ul are nevoie de atat cat sa se coloreze.
]]
local MIN_DISPLAY = 1.7

local LoadingView = {}
LoadingView.__index = LoadingView

type LoadingFields = {
	Screen: ScreenGui,
	-- Logo-ul, rama care il descopera pe masura ce se incarca, si scara de intrare.
	Logo: Frame,
	LogoClip: Frame,
	LogoScale: UIScale,
	Status: TextLabel,
	Fill: Frame,
	OpenedAt: number,
}

export type LoadingView = typeof(setmetatable({} :: LoadingFields, LoadingView))

--[[
	Ecranul se construieste stins: se aprinde abia la `revealLogo`, cand se stie
	ca mai e ceva de adus. Asa poate fi gata din timp, fara sa se vada degeaba.
]]
function LoadingView.new(parent: Instance): LoadingView
	local self = setmetatable({}, LoadingView) :: LoadingView

	self.OpenedAt = os.clock()

	local screen = Theme.create("ScreenGui", {
		Name = "Loading",
		Enabled = false,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		-- Peste orice altceva: acopera si lumea, si interfata de meci.
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	}) :: ScreenGui
	self.Screen = screen

	local backdrop = Theme.create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Backdrop,
		BorderSizePixel = 0,
		Parent = screen,
	}, {
		Theme.create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromHex("46331E"), Theme.Color.Backdrop),
		}),
	}) :: Frame

	--[[
		Logo-ul jocului, si el e chiar bara de progres.

		Pana acum aici statea cuvantul BARRICADE scris cu litere, care se
		asternea una cate una. Arata bine, dar nu era **logo-ul** — era o
		aproximare din font a unui desen care exista deja, si pe care jucatorul
		il vede pe zidul din lobby si pe pagina experientei. Primul lucru dintr-un
		joc n-are de ce sa fie o copie palida a semnului lui.

		Umplerea: doua exemplare ale aceluiasi desen, unul peste altul. Cel de
		dedesubt e stins, cel de deasupra e intreg, si cel de deasupra sta
		intr-o rama care creste odata cu incarcarea. Asa desenul se coloreaza de
		la stanga la dreapta, iar cat s-a adus se citeste din **el**, nu dintr-o
		dunga de alaturi.

		Cel de deasupra isi tine marimea in pixeli, nu in fractiuni, tocmai
		fiindca rama de deasupra lui se ingusteaza: intins in rama, s-ar fi
		comprimat odata cu ea in loc sa fie taiat de ea, si logo-ul ar fi aratat
		ca o acordeon in loc sa se umple.
	]]
	local logo = Theme.create("Frame", {
		Name = "Logo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(LOGO_W, LOGO_H),
		Parent = backdrop,
	}) :: Frame
	self.Logo = logo

	Theme.create("ImageLabel", {
		Name = "Dim",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.logoMossy,
		ScaleType = Enum.ScaleType.Fit,
		ImageTransparency = LOGO_DIM,
		Size = UDim2.fromScale(1, 1),
		Parent = logo,
	})

	local clip = Theme.create("Frame", {
		Name = "Clip",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.fromScale(0, 1),
		Parent = logo,
	}) :: Frame
	self.LogoClip = clip

	Theme.create("ImageLabel", {
		Name = "Lit",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.logoMossy,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(LOGO_W, LOGO_H),
		Parent = clip,
	})

	--[[
		Aparitia de la inceput sta pe o scara a lui, nu pe marimea ramei: rama e
		masurata in pixeli si o citeste `Lit` ca sa nu se comprime, deci daca ea
		s-ar schimba, cele doua exemplare ar aluneca unul fata de celalalt.
	]]
	self.LogoScale = Theme.create("UIScale", { Scale = 1, Parent = logo }) :: UIScale

	self.Status = Theme.text({
		Name = "Status",
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.70),
		Size = UDim2.fromOffset(420, 22),
		Parent = backdrop,
	})

	-- Bara de progres: aceeasi pastila de lemn ca in restul interfetei.
	local track = Theme.create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.76),
		Size = UDim2.fromOffset(360, 10),
		BackgroundColor3 = Color3.fromHex("3B2412"),
		BorderSizePixel = 0,
		Parent = backdrop,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	self.Fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Color.Highlight,
		BorderSizePixel = 0,
		Parent = track,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	return self
end

--[[
	Logo-ul intra crescand din nimic.

	Nu e doar infrumusetare: ecranul asta se ridica peste unul negru al
	Roblox-ului, iar un desen aparut dintr-odata, la marime intreaga, se
	citeste ca o taietura de montaj. Crescut in doua zecimi de secunda, se
	citeste ca inceputul a ceva.
]]
function LoadingView.revealLogo(self: LoadingView)
	self.Screen.Enabled = true
	self.OpenedAt = os.clock()
	self.LogoScale.Scale = 0.86
	TweenService:Create(
		self.LogoScale,
		TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

function LoadingView.setProgress(self: LoadingView, done: number, total: number, label: string?)
	local ratio = if total > 0 then math.clamp(done / total, 0, 1) else 0
	local slide = TweenInfo.new(0.2)

	TweenService:Create(self.Fill, slide, { Size = UDim2.fromScale(ratio, 1) }):Play()

	--[[
		Rama logo-ului creste cu aceeasi masura si in acelasi timp ca bara. Sunt
		doua fete ale aceleiasi cifre, si daca una ar aluneca mai repede decat
		cealalta s-ar vedea imediat ca una dintre ele minte.

		Latimea ramei e in pixeli, nu in fractiuni, fiindca desenul dinauntru e
		si el in pixeli: amandoua masurate la fel, marginea taieturii cade exact
		acolo unde trebuie.
	]]
	TweenService:Create(self.LogoClip, slide, { Size = UDim2.new(0, LOGO_W * ratio, 1, 0) }):Play()

	if label then
		self.Status.Text = label
	end
end

--[[
	Ce merita cerut dinainte, si ce nu.

	`PreloadAsync` cere obiecte, dar ce descarca sunt **fisiere**: un mesh, o
	imagine, un sunet. O piesa fara mesh si fara textura nu aduce niciun fisier,
	deci pusa in coada nu face decat sa lungeasca numaratoarea si sa mute bara
	fara ca ceva sa se intample. Coada de pana acum era plina de ele.
]]
-- Fisierele pe care le aduce un obiect: mesh, textura, imagine, sunet.
local function contentOf(item: Instance): { string }
	local ids = {}
	--[[
		`rbxasset://` e continut care vine cu Roblox, pe disc — scanteile
		implicite ale emitatoarelor, de exemplu. Nu se descarca niciodata, deci
		nici nu ajunge vreodata „Success": numarat, ar tine cortina sus la
		nesfarsit, chiar si cand totul e deja adus.
	]]
	local function add(value: any)
		if
			type(value) == "string"
			and value ~= ""
			and string.sub(value, 1, 11) ~= "rbxasset://"
		then
			table.insert(ids, value)
		end
	end
	if item:IsA("MeshPart") then
		add(item.MeshId)
		add(item.TextureID)
	elseif
		item:IsA("Decal")
		or item:IsA("Texture")
		or item:IsA("ParticleEmitter")
		or item:IsA("Beam")
		or item:IsA("Trail")
	then
		-- Toate poarta imaginea in `Texture`, deci se citesc la fel.
		add((item :: any).Texture)
	elseif item:IsA("SpecialMesh") then
		add(item.MeshId)
	elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
		add(item.Image)
	elseif item:IsA("Sound") then
		add(item.SoundId)
	end
	return ids
end

local function carriesContent(item: Instance): boolean
	return #contentOf(item) > 0
end

--[[
	Cate fisiere din lume n-au fost inca aduse.

	Zero inseamna ca jucatorul are deja tot — s-a intors in acelasi client, sau
	le-a adus deja — si atunci cortina n-are ce acoperi: nu se mai arata deloc.
	Se intreaba `GetAssetFetchStatus`, care stie ce s-a descarcat in sesiunea asta;
	un fisier cerut, dar inca pe drum, se numara ca lipsa.
]]
function LoadingView.pending(roots: { Instance }): number
	local seen: { [string]: boolean } = {}
	local missing = 0
	for _, root in roots do
		for _, descendant in ipairs(root:GetDescendants()) do
			for _, id in contentOf(descendant) do
				if not seen[id] then
					seen[id] = true
					local ok, status = pcall(function()
						return ContentProvider:GetAssetFetchStatus(id)
					end)
					if not ok or status ~= Enum.AssetFetchStatus.Success then
						missing += 1
					end
				end
			end
		end
	end
	return missing
end

--[[
	Pe cate fire se cer fisierele deodata.

	`PreloadAsync` asteapta fiecare bucata pana la capat inainte sa ceara
	urmatoarea, deci pe un singur fir latimea de banda sta degeaba mai tot
	timpul: se descarca un mesh, se asteapta, se descarca urmatorul. Patru fire
	tin legatura plina fara sa inece un client slab — mai multe nu mai aduc
	nimic, fiindca gatuirea se muta de la asteptare la latime.
]]
local PRELOAD_THREADS = 4

--[[
	Cate obiecte intr-o cerere.

	Mic, si dinadins: bara se misca la fiecare cerere incheiata, deci bucati
	mari inseamna o bara care sta si apoi sare. Douazeci si patru e destul cat
	sa nu platim de prea multe ori pretul unei chemari.
]]
local PRELOAD_BATCH = 24

--[[
	Cere fisierele din timp.

	Doua lucruri care lipseau, si care sunt chiar motivul pentru care lumea se
	vedea aparand bucata cu bucata:

	1. **Se cerea doar tabla.** `Assets` are mesh-urile de joc, dar ce vezi la
	   intrare e lobby-ul, copacii si apa din `Workspace` — si pe alea nu le
	   cerea nimeni, deci soseau cand le venea randul, sub ochii jucatorului.
	   Cine cheama functia asta ii da acum ambele radacini.
	2. **Se cerea pe un singur fir.** Vezi `PRELOAD_THREADS`.

	Ce se intoarce e cate fisiere s-au cerut, pentru cine vrea sa scrie in
	consola cat a avut de adus.
]]
function LoadingView.preload(self: LoadingView, roots: { Instance }): number
	local queue = {}
	local seen: { [Instance]: true } = {}

	for _, root in roots do
		for _, descendant in ipairs(root:GetDescendants()) do
			if not seen[descendant] and carriesContent(descendant) then
				seen[descendant] = true
				table.insert(queue, descendant)
			end
		end
	end

	local total = #queue
	if total == 0 then
		self:setProgress(1, 1, "Ready")
		return 0
	end

	--[[
		Cursorul din care se servesc toate firele.

		Impartita dinainte in felii egale, coada s-ar termina cand termina firul
		cel mai ghinionist — un mesh greu tine o felie in loc cat celelalte trei
		stau degeaba. Asa, fiecare fir ia urmatoarea bucata cand a terminat-o pe
		a lui, si toate se opresc odata.
	]]
	local cursor = 1
	local done = 0
	local running = PRELOAD_THREADS
	local finished = Instance.new("BindableEvent")

	for _ = 1, PRELOAD_THREADS do
		task.spawn(function()
			while cursor <= total do
				local from = cursor
				cursor = math.min(from + PRELOAD_BATCH, total + 1)

				local batch = table.move(queue, from, cursor - 1, 1, {})
				pcall(function()
					ContentProvider:PreloadAsync(batch)
				end)

				done += #batch
				self:setProgress(
					done,
					total,
					string.format("Loading the world · %d%%", math.floor(done / total * 100))
				)
			end

			running -= 1
			if running == 0 then
				finished:Fire()
			end
		end)
	end

	if running > 0 then
		finished.Event:Wait()
	end
	finished:Destroy()

	self:setProgress(total, total, "Ready")
	return total
end

--[[
	Strange ecranul pe loc, fara ceremonie si fara asteptarea minima.

	Pentru cazul in care nu era nimic de asteptat: varianta 2D isi deseneaza
	tabla, nu o aduce, si acolo o cortina care apare si piere intr-o clipa e mai
	suparatoare decat lipsa ei. `finish` e pentru cand chiar s-a incarcat ceva.
]]
function LoadingView.dismiss(self: LoadingView)
	self.Screen:Destroy()
end

function LoadingView.finish(self: LoadingView)
	local shown = os.clock() - self.OpenedAt
	if shown < MIN_DISPLAY then
		task.wait(MIN_DISPLAY - shown)
	end

	local backdrop = self.Screen:FindFirstChild("Backdrop")
	if not backdrop then
		self.Screen:Destroy()
		return
	end

	local fade = TweenInfo.new(FADE)
	for _, descendant in ipairs(self.Screen:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, fade, { TextTransparency = 1 }):Play()
		elseif descendant:IsA("ImageLabel") then
			--[[
				Imaginile n-au fost stinse pana acum, fiindca pe ecran nu era
				niciuna: titlul era text, iar restul frame-uri colorate. Odata cu
				logo-ul a aparut si nevoia — lasata pe dinafara, singura din tot
				ecranul care nu se stinge ar fi ramas atarnata peste lobby pana la
				stergere.
			]]
			TweenService:Create(descendant, fade, { ImageTransparency = 1 }):Play()
		elseif descendant:IsA("Frame") or descendant:IsA("ViewportFrame") then
			TweenService:Create(descendant, fade, { BackgroundTransparency = 1 }):Play()
		end
	end

	task.delay(FADE + 0.05, function()
		self.Screen:Destroy()
	end)
end

return LoadingView
