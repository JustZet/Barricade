--!strict
--[[
	Barrier — gardul nevazut de pe marginea insulei.

	Lobby-ul e o insula care pluteste; dedesubt nu e nimic. Fara gard, orice
	jucator care se apropie de margine pleaca in gol, si singura iesire din
	cadere e sa moara si sa reapara. Nu e o pedeapsa pe care sa vrea cineva sa o
	primeasca pentru ca a mers doi pasi in plus.

	Gardul e transparent dinadins: insula are priveliste de jur imprejur, si un
	zid vizibil ar ingradi-o tocmai in partea care o face frumoasa. Se vede doar
	cand te lovesti de el.

	Forma se afla pipaind insula, nu citind-o dintr-o cutie incadratoare — si
	asta nu e pedanterie, e chiar lectia care a costat. Insula pare patrata, dar
	are colturile taiate: cutia ei spune 122 pe 122, iar pamantul se opreste la
	61 pe laturi si taie diagonala la colturi. Un gard ridicat din cutie iese
	patrat, si atunci in dreptul fiecarei tesituri ramane o gaura exact acolo
	unde pamantul s-a terminat deja — te duci in gol fara sa atingi nimic.

	Asa ca se trag raze in jos de jur imprejur si se cauta, pe fiecare directie,
	raza la care insula inca tine. Punctele alea, legate intre ele, sunt gardul.
	Merge la fel de bine pentru un patrat, un octogon sau orice forma va mai
	primi insula, fara sa se atinga codul.

	Traieste pe server, ca `Arena`, fiindca e o regula a lumii, nu o parere a
	clientului: un gard construit pe client ar putea fi sters de un client
	modificat, si atunci tocmai cine vrea sa cada ar fi cel care poate.
]]

local Barrier = {}

export type Options = {
	-- Cat de inalt e gardul peste podea, in studs.
	Height: number?,
	-- Grosimea peretelui. Conteaza doar sa nu se poata trece prin el.
	Thickness: number?,
	--[[
		Cat se vede. `1` inseamna nevazut. Pentru reglaj, pune 0.85: gardul apare
		ca o pojghita si se vede exact unde sta.
	]]
	Transparency: number?,
	-- Cat de mult dincolo de margine se aseaza peretele.
	Offset: number?,
	-- In cate directii se pipaie marginea.
	Segments: number?,
}

local DEFAULTS = {
	--[[
		Un avatar Roblox sare cam 7 studi. Douazeci si cinci nu lasa loc nici
		saltului de pe ceva inalt lipit de margine, si ramane sub inaltimea la
		care ar intra in campul camerei.
	]]
	Height = 25,
	Thickness = 2,
	Transparency = 1,
	--[[
		Cat de mult trece gardul dincolo de marginea masurata.

		Sta pe dinafara ca sa se poata ajunge pana la muchie: de pe o insula care
		pluteste vrei sa poti privi in jos, nu sa fii oprit cu un pas inainte.

		Cat de mult, o spune latimea avatarului. Peretele opreste *corpul*, nu
		centrul lui, deci centrul nu trece niciodata dincolo de gard mai mult
		decat o jumatate de corp — vreo un stud. Cata vreme gardul iese sub atat,
		centrul ramane peste pamant chiar si lipit de perete, si nu are pe ce sa
		cada. Peste un stud, echilibrul se muta in gol.
	]]
	Offset = 0.5,
	--[[
		Nouazeci si sase de directii inseamna un pas de 3.75 grade. Cu cat sunt mai
		dese, cu atat gardul se lipeste mai bine de tesituri si lasa mai putina
		punte nefolosita. Peretii sunt piese simple si nevazute, deci se poate.
	]]
	Segments = 96,
}

local NAME = "LobbyBarrier"

-- Cat de sus se porneste raza, si cat de adanc cauta puntea.
local PROBE_ABOVE = 40
local PROBE_DEPTH = 80

--[[
	Cat de departe tine insula pe directia data.

	Se cauta dinspre afara spre inauntru, si asta conteaza. Cautarea fireasca ar
	fi prin injumatatire intre centru si marginea cutiei — dar ea cere ca in
	centru sa fie pamant, si nu e: puntea lobby-ului e un inel, cu hubul asezat
	in golul din mijloc. Pornita din centru, cautarea gaseste gol si se lasa
	pagubasa tocmai la insula care are cel mai mult nevoie de gard.

	Dinspre afara, primul contact *este* marginea, oricate goluri ar fi mai
	inauntru. Pasul gros da o margine aproximativa, si apoi se strange intre
	ultimul gol si primul contact.
]]
local COARSE_STEP = 1
local STEPS = 8

local function reachOf(
	ground: Instance,
	centre: Vector3,
	direction: Vector3,
	limit: number
): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ground }

	local function solid(radius: number): boolean
		local from = centre + direction * radius + Vector3.new(0, PROBE_ABOVE, 0)
		return workspace:Raycast(from, Vector3.new(0, -PROBE_DEPTH, 0), params) ~= nil
	end

	local radius = limit
	while radius > 0 and not solid(radius) do
		radius -= COARSE_STEP
	end
	if radius <= 0 then
		return nil
	end

	local inside, outside = radius, math.min(limit, radius + COARSE_STEP)
	for _ = 1, STEPS do
		local middle = (inside + outside) / 2
		if solid(middle) then
			inside = middle
		else
			outside = middle
		end
	end
	return inside
end

local function wall(parent: Instance, name: string, cf: CFrame, size: Vector3, transparency: number)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
end

--[[
	Puntea pe care se merge. Fara ea nu exista margine de aparat.
]]
local function deckOf(island: Instance): BasePart?
	local deck = island:FindFirstChild("deck_surface", true)
	if deck and deck:IsA("BasePart") then
		return deck
	end
	return nil
end

--[[
	Ridica gardul in jurul insulei si intoarce modelul lui.

	Un gard vechi se darama intai, nu se pastreaza: daca insula si-a schimbat
	forma intre timp, cel vechi e fix gardul gresit, si a-l tine ar insemna sa
	pastram tocmai gaura pe care venim sa o inchidem.
]]
function Barrier.build(island: Instance, options: Options?): Model?
	local previous = workspace:FindFirstChild(NAME)
	if previous then
		previous:Destroy()
	end

	local deck = deckOf(island)
	if not deck then
		warn("Barrier: nu am gasit deck_surface; insula ramane fara gard")
		return nil
	end

	local given: Options = options or {}
	local height = given.Height or DEFAULTS.Height
	local thickness = given.Thickness or DEFAULTS.Thickness
	local offset = given.Offset or DEFAULTS.Offset
	local segments = math.max(4, math.floor(given.Segments or DEFAULTS.Segments))
	local transparency = given.Transparency or DEFAULTS.Transparency

	--[[
		Se pipaie insula intreaga, nu doar puntea. Grinzile de margine ies putin
		peste ea si se poate sta pe ele; un gard tras dupa punte le-ar lasa pe
		dinafara, si atunci marginea aparata n-ar fi marginea pe care se merge.
	]]
	local ground = island:FindFirstChild("island", true) or island

	local centre = Vector3.new(deck.Position.X, deck.Position.Y, deck.Position.Z)
	local floor = deck.Position.Y + deck.Size.Y / 2
	local middle = floor + height / 2

	-- Cautarea nu are de ce sa treaca de coltul cutiei: dincolo sigur nu e nimic.
	local reachLimit = if ground:IsA("Model")
		then select(2, ground:GetBoundingBox())
		else Vector3.new(deck.Size.X, 0, deck.Size.Z)
	local limit = Vector3.new(reachLimit.X, 0, reachLimit.Z).Magnitude / 2 + COARSE_STEP

	--[[
		Gardul urmareste marginea indeaproape, la un pas mic pe dinafara.

		"Indeaproape" e cuvantul care conteaza. Un gard dus mult in afara inchide
		gol impreuna cu pamantul, si atunci nu treci prin el — pasesti in golul
		dinauntrul lui si cazi la fel de bine ca fara gard. Asa arata prima
		incercare: umflata la colturi, ca sa nu ramana punte neumblata, si tocmai
		la colturi se cadea.

		Dar nici tras inauntru nu e bine: te opreste la un pas de muchie, si de pe
		o insula care pluteste vrei sa poti privi in jos.

		Deci: raza masurata pe fiecare directie, plus `Offset`. Fara umflari si
		fara corectii de coarda — coarda dintre doua colturi trece pe dinauntru,
		si asta e exact partea buna, fiindca acolo unde insula are coltul taiat
		gardul taie si el, in loc sa inchida golul de dincolo. Minimul luat pe
		vecini e doar plasa pentru o margine care ar intra brusc inauntru.
	]]
	local fine = segments * 2
	local reaches = table.create(fine)
	for index = 0, fine - 1 do
		local angle = index / fine * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local reach = reachOf(ground, centre, direction, limit)
		if not reach then
			warn("Barrier: marginea insulei nu se lasa masurata; ramane fara gard")
			return nil
		end
		reaches[index + 1] = reach
	end

	local corners: { Vector3 } = {}
	for index = 0, segments - 1 do
		local angle = index / segments * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

		local closest = math.huge
		for neighbour = -1, 1 do
			local at = (index * 2 + neighbour) % fine
			closest = math.min(closest, reaches[at + 1])
		end

		local point = centre + direction * (closest + offset)
		table.insert(corners, Vector3.new(point.X, middle, point.Z))
	end

	local model = Instance.new("Model")
	model.Name = NAME

	--[[
		Gardul nu are voie sa fie descarcat de streaming.

		Peretii sunt departe de centrul insulei, exact acolo unde streaming-ul
		taie primul. Un gard care dispare cand te apropii de el e mai rau decat
		niciunul: ai invatat ca marginea tine, si apoi nu mai tine.
	]]
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	for index, from in corners do
		local to = corners[index % #corners + 1]
		local span = (to - from).Magnitude
		--[[
			Peretele e mai lung decat coarda cu o grosime, ca vecinii sa se
			intrepatrunda la capete. Doua placi puse cap la cap lasa intre ele o
			dunga cat eroarea de virgula, si exact prin dunga aia se strecoara
			cineva odata la o suta de incercari.
		]]
		wall(
			model,
			string.format("Span%02d", index),
			CFrame.lookAt((from + to) / 2, to),
			Vector3.new(thickness, height, span + thickness),
			transparency
		)
	end

	model.Parent = workspace
	return model
end

return Barrier
