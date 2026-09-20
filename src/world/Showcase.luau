--!strict
--[[
	Showcase — vitrinele din lobby, umplute din cod.

	Lobby-ul vine din import cu obiecte deja asezate in vitrine:
	`display_classic_wood` isi are baricada lui, `podium_display_wood` isi are
	podiumul lui. Sunt machete: arata a zid si a podium, dar nu sunt *zidul* si
	*podiumul* din joc. Daca raman, orice modificare adusa unui skin trebuie
	facuta de doua ori, iar a doua oara se uita.

	De aceea machetele au fost scoase din place si in locul lor se pune obiectul
	adevarat, clonat din `ReplicatedStorage.Assets` — acelasi de unde il ia si
	meciul, si inventarul jucatorului. O singura sursa: schimbi modelul acolo si
	se schimba si ce joci, si ce vezi in lobby.

	Ce a ramas in place e soclul gol plus atributul `DisplayBase`: un CFrame care
	spune si unde sta talpa vitrinei, si incotro priveste obiectul. El e
	contractul dintre lobby si codul asta.

	Rotatia conteaza doar acolo unde obiectul nu se invarte. Podiumurile din
	galerie sunt intoarse spre treptele pe care urca vizitatorul; zidurile din
	showroom se rotesc oricum, deci soclul lor n-are nevoie de directie.

	O vitrina fara atribut se masoara din macheta, daca mai are una — calea de
	rezerva, pentru un soclu nou adaugat in Studio. Masuratoarea aia da doar
	pozitia, nu si directia.

	Ce arata fiecare vitrina se citeste din numele ei (`display_castle_stone` →
	`castle`) sau din atributul `ItemId`, daca vrei sa fixezi altceva fara sa
	redenumesti nimic. Cand vitrinele vor fi legate de magazin, `show` e metoda
	prin care se schimba obiectul expus.

	Ruleaza pe client. E decor: fiecare jucator si-l construieste singur, cum
	isi deseneaza si interfata, si nu costa nimic in retea.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

local Barricade = require(script.Parent.Barricade)
local Hover = require(script.Parent.Hover)
local Podium = require(script.Parent.Podium)

type Kind = Catalog.Kind

local BARRICADE: Kind = "Barricade"
local PODIUM: Kind = "Podium"

local Showcase = {}
Showcase.__index = Showcase

--[[
	Cum se poarta o vitrina, pe feluri. Sunt singurele numere de reglat aici.

	`Span` e latura lunga la care se arata obiectul, in studi: soclurile din
	lobby au vreo 11 studi, deci obiectul se opreste sub ei ca sa ramana o
	margine. `Rest` e cat de sus sta fata de soclu inainte sa inceapa plutirea.

	Podiumul pluteste mai putin decat zidul si nu se roteste deloc: e o piesa
	grea si arata fals daca zburda.
]]
local LOOK = {
	Barricade = {
		Span = 8.5,
		Rest = 1.6,
		SpinPeriod = 15,
		FloatHeight = 0.5,
		FloatPeriod = 3.4,
	},

	--[[
		Podiumul doar pluteste. `SpinPeriod = 0` opreste rotatia: spre deosebire
		de zid, care e o piesa pe care o pui si o privesti din orice parte, un
		podium are o fata — tronul, arcada, fulgerul stau toate intr-o directie,
		si rotit ajunge cu spatele la tine jumatate din timp.
	]]
	Podium = {
		Span = 8.5,
		Rest = 1.0,
		SpinPeriod = 0,
		FloatHeight = 0.3,
		FloatPeriod = 4.6,
	},
}

-- Decalajul dintre doua vitrine alaturate, ca sa nu urce si sa coboare la unison.
local PHASE_STEP = 0.8

-- Cat asteptam ca o macheta nemasurata inca sa ajunga la client.
local REPLICATION_WAIT = 10

type ShowcaseFields = {
	Anchor: Model,
	Kind: Kind,
	Id: string,
	-- Talpa soclului: de aici se masoara si asezarea, si plutirea.
	Base: CFrame,
	-- Locul in sir, doar ca sa-si ia faza proprie.
	Index: number,
	--[[
		Obiectul expus. E `Barricade` sau `Podium`, doua clase diferite care
		raspund la aceleasi trei lucruri de care are nevoie o vitrina: `hover`,
		`destroy` si `Model`. Un tip comun pentru ele ar insemna o interfata
		inventata doar pentru campul asta.
	]]
	Item: any,
}

export type Showcase = typeof(setmetatable({} :: ShowcaseFields, Showcase))

-- Semnul pus pe ce a asezat vitrina, ca sa nu-si ia propriul obiect drept macheta.
local MARK = "ShowcaseItem"

--[[
	Macheta din vitrina: copilul Model care nu e nici invelisul unei piese, nici
	obiectul pus de noi.

	Importul glTF pune fiecare mesh intr-un Model numit `..._Node`; ce nu se
	termina asa e o grupare adevarata, adica obiectul expus din fabrica.
]]
local function placeholder(anchor: Model): Model?
	for _, child in ipairs(anchor:GetChildren()) do
		if
			child:IsA("Model")
			and not string.match(child.Name, "_Node$")
			and child:GetAttribute(MARK) == nil
		then
			return child
		end
	end
	return nil
end

-- Sterge tot ce a lasat o constructie anterioara, ca reconstruirea sa fie curata.
local function clearOwn(anchor: Model)
	for _, child in ipairs(anchor:GetChildren()) do
		if child:GetAttribute(MARK) ~= nil then
			child:Destroy()
		end
	end
end

-- A ajuns modelul intreg la client, sau inca i se replica piesele?
local function hasParts(model: Model): boolean
	return model:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

--[[
	Talpa soclului, masurata o singura data.

	Se ia din macheta, fiindca ea spune unde si cat de sus a vrut autorul
	lobby-ului sa stea obiectul, si se pastreaza ca atribut. Atributul e forma
	buna: masuratoarea e un fapt de creatie, nu unul de rulare, iar odata salvat
	in place vitrina nu mai depinde de ce a apucat sa se replice.

	Fara el, masuratoarea se face pe loc — dar numai dupa ce macheta chiar a
	ajuns. Un model caruia inca nu i-au sosit piesele raporteaza o cutie
	incadratoare in originea lumii, si atunci toate vitrinele s-ar umple cu
	obiecte ingramadite in (0, 0, 0), departe de soclurile lor.
]]
local function slotOf(anchor: Model): CFrame?
	local saved = anchor:GetAttribute("DisplayBase")
	if typeof(saved) == "CFrame" then
		return saved
	end

	local stand = placeholder(anchor)
	if not stand then
		return nil
	end

	local deadline = os.clock() + REPLICATION_WAIT
	while not hasParts(stand) and os.clock() < deadline do
		task.wait(0.1)
	end
	if not hasParts(stand) then
		warn(string.format("Showcase: macheta din %q nu s-a replicat", anchor.Name))
		return nil
	end

	local box, size = stand:GetBoundingBox()

	--[[
		Ultima verificare: macheta trebuie sa cada in interiorul vitrinei. Daca a
		iesit departe, ce am masurat nu e macheta, ci un model inca gol asezat in
		originea scenei — si atunci e mai bine sa ramana macheta pe loc decat sa
		punem obiectul altundeva.
	]]
	local anchorBox, anchorSize = anchor:GetBoundingBox()
	local reach = math.max(anchorSize.X, anchorSize.Y, anchorSize.Z)
	if (box.Position - anchorBox.Position).Magnitude > reach then
		warn(string.format("Showcase: macheta din %q nu e inca la locul ei", anchor.Name))
		return nil
	end

	--[[
		Fara rotatie: macheta spune unde sta obiectul, nu incotro priveste. Cine
		vrea si directie o pune in atribut, o data, in Studio.
	]]
	local base = CFrame.new(box.Position.X, box.Position.Y - size.Y / 2, box.Position.Z)
	anchor:SetAttribute("DisplayBase", base)
	return base
end

--[[
	Ce arata vitrina.

	Numele lobby-ului poarta id-ul in el (`display_castle_stone`), dar pe un nume
	viitor s-ar putea potrivi doua id-uri deodata. Atunci nu ghicim: spunem ce
	nu e clar si cerem atributul. O vitrina goala se observa; una care arata
	altceva decat crezi, nu.
]]
local function resolveId(anchor: Model): string?
	local pinned = anchor:GetAttribute("ItemId")
	if type(pinned) == "string" then
		return pinned
	end

	local name = string.lower(anchor.Name)
	local found: string? = nil

	for _, id in ipairs(Catalog.Order) do
		if string.find(name, id, 1, true) then
			if found then
				warn(
					string.format(
						"Showcase: %q se potriveste si cu %q si cu %q; pune atributul ItemId",
						anchor.Name,
						found,
						id
					)
				)
				return nil
			end
			found = id
		end
	end

	return found
end

function Showcase.new(anchor: Model, kind: Kind, index: number, featured: string?): Showcase?
	--[[
		Ce arata vitrina: intai ce i s-a dat, apoi ce scrie pe ea.

		Sirul de skinuri scumpe vine din `build`, fiindca doar el stie cate
		vitrine sunt si in ce ordine. Numele soclului ramane plasa de siguranta:
		daca intr-o zi sunt mai multe vitrine decat skinuri de vanzare, ultimele
		arata ce arata azi.
	]]
	local id = featured or resolveId(anchor)
	if not id then
		warn(string.format("Showcase: nu stiu ce arata %q", anchor:GetFullName()))
		return nil
	end
	if not Catalog.get(kind, id) then
		warn(string.format("Showcase: %q nu e un %s din catalog", id, kind))
		return nil
	end

	local base = slotOf(anchor)
	if not base then
		warn(string.format("Showcase: %q nu are macheta de la care sa iau soclul", anchor.Name))
		return nil
	end

	--[[
		Macheta iese din vitrina abia acum, dupa ce soclul e cunoscut. Daca ar
		pleca la masuratoare, o vitrina cu soclul deja salvat in place nu ar mai
		scapa niciodata de ea si s-ar vedea doua obiecte suprapuse.
	]]
	clearOwn(anchor)
	local mock = placeholder(anchor)
	if mock then
		mock:Destroy()
	end

	local self = setmetatable({}, Showcase) :: Showcase
	self.Anchor = anchor
	self.Kind = kind
	self.Id = id
	self.Base = base
	self.Index = index
	self.Item = nil

	self:show(id)
	return self
end

--[[
	Schimba obiectul expus.

	Metoda prin care magazinul va vorbi cu lobby-ul: alegi alt skin, vitrina il
	arata. Vechiul obiect se sterge cu totul, cu plutire cu tot.
]]
function Showcase.show(self: Showcase, id: string)
	if self.Item then
		self.Item:destroy()
		self.Item = nil
	end

	self.Id = id

	local look = if self.Kind == "Podium" then LOOK.Podium else LOOK.Barricade
	local surface = self.Base * CFrame.new(0, look.Rest, 0)

	-- Acelasi `any` ca al campului: doua clase, un singur loc de expunere.
	local item: any = if self.Kind == "Podium"
		then Podium.new(id, self.Anchor, surface, look.Span)
		else Barricade.display(id, self.Anchor, surface, look.Span)

	if not item then
		return
	end

	item.Model:SetAttribute(MARK, true)

	if self.Kind == "Podium" then
		-- Nu te urci pe o vitrina care pluteste.
		item:setSolid(false)
	end

	item:hover({
		SpinPeriod = look.SpinPeriod,
		FloatHeight = look.FloatHeight,
		FloatPeriod = look.FloatPeriod,
		Phase = self.Index * PHASE_STEP,
	} :: Hover.Options)

	self.Item = item
end

function Showcase.destroy(self: Showcase)
	if self.Item then
		self.Item:destroy()
		self.Item = nil
	end
end

--[[
	E modelul o vitrina?

	Importul glTF numeste invelisurile de mesh `..._Node`; tot ce ramane si
	incepe cu `display_` sau `podium_display_` e un soclu de expunere.
]]
local function isStand(anchor: Model): boolean
	local name = string.lower(anchor.Name)
	if string.match(name, "_node$") then
		return false
	end
	return string.match(name, "^podium_display") ~= nil or string.match(name, "^display_") ~= nil
end

--[[
	Vitrina de podiumuri se recunoaste separat, si prima: numele ei contine si
	"display" in mijloc, iar verificarea inversa ar trece-o drept vitrina de
	ziduri.
]]
local function isPodiumStand(anchor: Model): boolean
	return string.match(string.lower(anchor.Name), "^podium_display") ~= nil
end

--[[
	Sirul skinurilor puse la vanzare in lobby: cele mai scumpe, in ordine.

	Lobby-ul e raftul din fata magazinului, nu un depozit: acolo stau lucrurile
	pentru care merita sa te opresti si sa dai banutii. Cine vrea si restul
	deschide magazinul — vitrina arata varful.

	Obiectele de start nu intra in sir. `wood` il are oricine din prima, deci o
	vitrina cu el n-ar vinde nimic, ar ocupa doar un loc.

	La pret egal decide ordinea din catalog, care merge de la sobru la
	spectaculos. Nu de dragul de a avea o regula: fara ea, doua obiecte cu
	acelasi pret si-ar schimba locurile de la o pornire la alta, dupa cum se
	nimereste sortarea, si nimeni n-ar sti de ce.
]]
local RANK: { [string]: number } = {}
for index, id in ipairs(Catalog.Order) do
	RANK[id] = index
end

local function priciest(kind: Kind): { string }
	local ranked: { Catalog.Item } = {}
	for _, item in ipairs(Catalog.list(kind)) do
		if not item.Default then
			table.insert(ranked, item)
		end
	end

	table.sort(ranked, function(a, b)
		if a.Coins ~= b.Coins then
			return a.Coins > b.Coins
		end
		if a.Price ~= b.Price then
			return a.Price > b.Price
		end
		return RANK[a.Id] > RANK[b.Id]
	end)

	local ids: { string } = {}
	for _, item in ipairs(ranked) do
		table.insert(ids, item.Id)
	end
	return ids
end

--[[
	Ordinea in care vitrinele primesc skinurile: dinspre mijlocul galeriei spre
	capete.

	Cel mai scump sta in mijloc, fiindca mijlocul e singurul loc care arata la
	fel din orice parte ai intra. Ordinea in care le gaseste `GetDescendants` ar
	fi mers si ea, dar nu inseamna nimic: e ordinea din fisierul place-ului, si
	se schimba daca cineva muta un soclu in arbore.

	Departarea se masoara fata de centrul sirului acelui fel. La distante egale
	decid coordonatele, ca doua vitrine simetrice sa nu-si schimbe locurile intre
	doua porniri.

	Locul se ia din `DisplayBase`, nu din cutia incadratoare, si asta conteaza:
	atributul e un fapt scris in place si ajunge la client intreg, pe cand un
	model caruia inca nu i-au sosit piesele raporteaza o cutie in originea lumii.
	O singura vitrina nereplicata inca trage centrul sirului dupa ea tocmai in
	clipa in care se socoteste ordinea, si atunci cel mai scump skin ajunge unde
	se nimereste. Asa s-a si intamplat: zidurile iesisera corect, soclurile nu.
]]
local function fromMiddle(anchors: { Model }): { Model }
	local center = Vector3.zero
	local spot: { [Model]: Vector3 } = {}
	for _, anchor in anchors do
		local saved = anchor:GetAttribute("DisplayBase")
		local at = if typeof(saved) == "CFrame"
			then saved.Position
			else anchor:GetBoundingBox().Position
		spot[anchor] = at
		center += at
	end
	if #anchors > 0 then
		center /= #anchors
	end

	local sorted = table.clone(anchors)
	table.sort(sorted, function(a, b)
		local near, far = (spot[a] - center).Magnitude, (spot[b] - center).Magnitude
		if math.abs(near - far) > 0.01 then
			return near < far
		end
		if spot[a].Z ~= spot[b].Z then
			return spot[a].Z < spot[b].Z
		end
		return spot[a].X < spot[b].X
	end)
	return sorted
end

--[[
	Construieste toate vitrinele gasite sub `root`.

	Cauta dupa nume, nu dupa o lista de cai scrisa de mana: cand lobby-ul mai
	primeste o vitrina, ea se umple singura, fara sa se atinga codul — si intra
	in acelasi sir, pe locul ei dupa pret.
]]
function Showcase.build(root: Instance): { Showcase }
	local found: { [string]: { Model } } = { Barricade = {}, Podium = {} }

	for _, node in ipairs(root:GetDescendants()) do
		if not node:IsA("Model") or not isStand(node) then
			continue
		end

		--[[
			Numele singur nu ajunge: un model fara macheta si fara soclu memorat
			e altceva decat o vitrina si nu are unde sa-si puna obiectul.
		]]
		if placeholder(node) == nil and node:GetAttribute("DisplayBase") == nil then
			continue
		end

		local kind: Kind = if isPodiumStand(node) then PODIUM else BARRICADE
		table.insert(found[kind], node)
	end

	local stands: { Showcase } = {}

	for _, kind: Kind in { BARRICADE, PODIUM } do
		local ids = priciest(kind)
		local rank = 0

		for _, anchor in fromMiddle(found[kind]) do
			local stand = Showcase.new(anchor, kind, #stands + 1, ids[rank + 1])
			if stand then
				-- Locul din sir se consuma doar daca vitrina chiar s-a facut.
				rank += 1
				table.insert(stands, stand)
			end
		end
	end

	return stands
end

return Showcase
