--!strict
--[[
	Effects — dragonii care sufla foc.

	Sta **in model**, ca la celelalte skinuri, si acelasi script intra si in zidul
	`dragon`, si in soclul `dragon`: piesele poarta acolo aceleasi nume. Ce
	lipseste se sare — soclul n-are camp de jar, zidul n-are creste pe margine —
	deci nu e nevoie de doua scripturi.

	**Ce am gasit si ce am facut din el.** Modelul venea cu trei dungi portocalii
	intinse intre cele doua boturi (`flame_ribbon_*`), cu doua guri aprinse, cu
	trei pete de fum si cu cateva bile de jar. Acum:

	  - dungile dintre boturi sunt **sterse**: raman ascunse si nu mai poarta
	    nimic. O perdea de flacara intre cei doi ii lega intr-o singura pata, si
	    cu cateva ziduri pe tabla nu se mai vedea unde se termina unul;
	  - gurile poarta `Fire`, focul din motor — nu cere nicio textura si arde
	    singur;
	  - petele de fum se ascund; bilele de jar se fac invizibile si devin guri de
	    emitator: jar marunt care sare;
	  - aurul de pe solzi, coarne si gheare **se incinge** cand trece suflul, si
	    se raceste dupa. Asta leaga statuia de foc: altfel ar fi doua pietre care
	    sufla fara sa simta nimic.

	Suflul nu e continuu. Dragonii trag aer cateva secunde — ochii li se aprind,
	jarul se inteteste — si abia apoi sufla. Pauza se trage la sorti, ca sa nu se
	prinda nimeni in ritm.

	Cat timp zidul e doar previzualizare, `Barricade` ridica atributul `Preview`
	si aici nu se mai atinge nicio culoare: verdictul verde/rosu are intaietate.

	Copia de pe disc: `assets/world-scripts/dragon-effects.luau`.
]]

local RunService = game:GetService("RunService")

local model = script.Parent :: Model

-- Sursa din `ReplicatedStorage` nu se anima si nu se murdareste. Vezi portal.
if not model:IsDescendantOf(workspace) then
	return
end

--[[
	Cautarea unei piese dupa nume, **in toata adancimea**.

	Zidurile isi tin piesele una langa alta, dar soclurile le imbraca intr-un
	model interior (`podium_thunder`, `podium_crystal`…). O cautare doar pe
	primul nivel gaseste totul pe zid si nimic pe soclu — iar scripturile care
	ies din start cand nu-si gasesc piesa de baza ieseau chiar asa: tacut, si
	soclul ramanea nemiscat.
]]
local function piece(name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

--[[
	Ce se ascunde, ramane ascuns.

	Bilele de scanteie, petele de fum si haloul desenat sunt piese ca oricare
	alta: modelul le are, si noi le vrem doar ca guri de emitator, nu la vedere.
	Le facem invizibile — dar `Barricade` fotografiaza transparenta fiecarei
	piese **la clonare**, deci inainte ca scriptul asta sa apuce sa ruleze, si o
	pune inapoi de fiecare data cand zidul iese din previzualizare. De aceea
	scriem si in fotografie (`OriginalTransparency`), si mai verificam o data la
	fiecare cadru — cat costa o comparatie pentru zece piese.
]]
local hidden: { BasePart } = {}

local function hide(part: BasePart)
	part.Transparency = 1
	part.CastShadow = false
	part:SetAttribute("OriginalTransparency", 1)
	table.insert(hidden, part)
end

local function collect(pattern: string): { BasePart }
	local found: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and string.match(part.Name, pattern) then
			table.insert(found, part)
		end
	end
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found
end

local EMBER = Color3.fromHex("ffa552")
local BLAZE = Color3.fromHex("ffe08a")
local WHITE = Color3.fromHex("fff6de")
local GOLD = Color3.fromHex("e0b45c")

--[[
	Piesa fata de care se masoara tot.

	Piesele animate nu se pot tine minte in coordonatele lumii: zidul cade pe
	tabla, urmeaza cursorul ca fantoma, se leagana in vitrina — iar o flacara
	tinuta minte unde era la pornire ar ramane in urma, singura, in mijlocul
	arenei. Deci se tine minte **fata de o piesa care nu se misca**, si la
	fiecare cadru se reface de acolo.

	Ancora se alege singura: cea mai mare piesa pe care scriptul n-o atinge —
	plinta zidului sau placa soclului. Daca modelul si-a pus `PrimaryPart`, ala e.
]]
local ANIMATED = { "^wing_[lr]_%d+$" }

local function chooseAnchor(): BasePart?
	local function moves(name: string): boolean
		for _, pattern in ANIMATED do
			if string.match(name, pattern) then
				return true
			end
		end
		return false
	end

	if model.PrimaryPart and not moves(model.PrimaryPart.Name) then
		return model.PrimaryPart
	end

	local best: BasePart? = nil
	local bestVolume = -1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not moves(part.Name) then
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > bestVolume then
				best, bestVolume = part, volume
			end
		end
	end
	return best
end

local anchor = chooseAnchor()
if not anchor then
	return
end

local home = anchor.CFrame

--[[
	Dungile dintre boturi se sterg de tot.

	Modelul le desenase ca trei bare lungi intre cele doua guri. Au trecut prin
	doua incercari: intai ascunse si folosite doar ca guri de emitator, ca sa
	ramana foc in locul barelor; apoi si cu unduire, ca focul sa nu stea pe loc.
	Amandoua rateaza acelasi lucru — **nu e nevoie de nimic acolo**. Doi dragoni
	care sufla se citesc ca doi dragoni care sufla; o perdea de flacara intinsa
	intre ei ii leaga intr-o singura pata portocalie, si cu cateva ziduri pe
	tabla nu se mai vede unde se termina unul si incepe altul.

	Piesele raman ascunse, fiindca altfel modelul si-ar arata barele. Nimic nu
	mai iese din ele si nimic nu le mai misca: focul ramane acolo unde are rost,
	adica in guri.
]]
for _, part in collect("^flame_ribbon_%d+$") do
	hide(part)
end

--[[
	Focul din guri.

	`Fire` e focul din motor: nu cere nicio textura urcata si arde de la sine,
	deci merge si intr-un place in care nu s-a importat nimic. Il tinem mic
	intre suflari si il crestem cand trece suflul.
]]
local mouthL, mouthR = piece("mouth_glow_l"), piece("mouth_glow_r")
local mouths = { mouthL, mouthR }
local fires: { Fire } = {}
local mouthLights: { PointLight } = {}

for _, mouth in mouths do
	if not mouth then
		continue
	end

	local fire = Instance.new("Fire")
	fire.Name = "Breath"
	fire.Color = EMBER
	fire.SecondaryColor = Color3.fromHex("ff7a1a")
	fire.Heat = 6
	fire.Size = 1.6
	fire.Parent = mouth
	table.insert(fires, fire)

	local light = Instance.new("PointLight")
	light.Name = "MouthGlow"
	light.Color = EMBER
	light.Range = 10
	light.Brightness = 0.5
	light.Shadows = false
	light.Parent = mouth
	table.insert(mouthLights, light)
end

--[[
	Jeturi intre dragoni **nu mai sunt**.

	Fiecare gura trimitea spre celalalt un emitator cu textura lui `Fire`
	(`fire_main`). Amestecata normal, nu aditiv, textura aia iese maro-inchis:
	cele doua jeturi se intalneau la mijloc, urcau si lasau la fiecare suflare
	o coloana de funingine intre dragoni. Suflul se citeste destul din focul din
	guri, din lumina lor si din aurul care se incinge.
]]

--[[
	Jarul: bilele portocalii ale modelului, facute invizibile si puse sa emita.

	Ard incet intre suflari si sar in rafala cand dragonii sufla. Transparenta
	fiecarei scantei urca din nimic si cade la loc, deci jarul se aprinde in aer
	si se stinge — nu apare si dispare.
]]
local EMBER_COLOR = ColorSequence.new(BLAZE, Color3.fromHex("c2410c"))

local EMBER_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.05),
	NumberSequenceKeypoint.new(0.7, 0.3),
	NumberSequenceKeypoint.new(1, 1),
})

local EMBER_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.38),
	NumberSequenceKeypoint.new(1, 0.02),
})

local embers: { ParticleEmitter } = {}

for _, dot in collect("^spark_%d+$") do
	hide(dot)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Ember"
	emitter.Color = EMBER_COLOR
	emitter.Size = EMBER_SIZE
	emitter.Transparency = EMBER_FADE
	--[[
		Jarul se ridica putin si se stinge repede. Cat avea viteza si tragere in
		sus mare, bilele urcau in coloane inalte pe langa capete si se citeau ca
		niste artificii pornite din spatele dragonului — jarul sta langa foc, nu
		pleaca de acasa.
	]]
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(1, 2.5)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, 1.6, 0)
	emitter.Drag = 2.2
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-140, 140)
	emitter.LightEmission = 0.5
	emitter.LightInfluence = 0
	emitter.Rate = 4
	emitter.Parent = dot

	table.insert(embers, emitter)
end

--[[
	Petele de fum ale modelului raman doar ascunse.

	Din ele ieseau nori cenusii care urcau intre dragoni si, adunati peste foc,
	se citeau ca o coloana de funingine in mijlocul soclului. Suflul se vede si
	fara ei.
]]
for _, puff in collect("^smoke_%d+$") do
	hide(puff)
end

--[[
	Ochii, aurul si campul de jar: tot ce se incinge cand trece suflul.

	Aurul nu e de o singura culoare — solzii, coarnele, creasta soclului si
	treptele au fiecare nuanta lor — deci fiecare piesa isi tine minte culoarea
	ei si de acolo pleaca spre portocaliu. Altfel suflul ar vopsi tot modelul
	intr-un galben mort de indata ce trece o data.
]]
local eyes = collect("^eye_[lr]_%d+$")

type Metal = {
	Part: BasePart,
	Base: Color3,
}

local trim: { Metal } = {}
for _, pattern in
	{
		"^spine_[lr]_%d+$",
		"^horn_[lr]_%d+$",
		"^edge_spine_%d+$",
		"^gold_trim$",
		"^plinth_trim_[lr]$",
		"^tier_",
		"^claw_[lr]_%d+_%d+$",
	}
do
	for _, part in collect(pattern) do
		table.insert(trim, { Part = part, Base = part.Color })
	end
end

-- Emblema de pe plinta soclului: inelele se invart, razele dau ocol butucului.
local emblem = piece("emblem_ring")
local emblemInner = piece("emblem_ring_inner")
local hub = piece("emblem_hub")

type Ray = {
	Part: BasePart,
	Offset: CFrame,
}

local rays: { Ray } = {}
if hub then
	for _, part in collect("^emblem_point_%d+$") do
		table.insert(rays, { Part = part, Offset = hub.CFrame:ToObjectSpace(part.CFrame) })
	end
end

--[[
	Foaia dintre dragoni **nu se mai vede deloc**.

	Era intinsa intre cei doi ca o pojghita de caldura, dar orice pojghita cu
	muchii drepte se citeste ca o placa pusa acolo, nu ca aer fierbinte. Ce
	trebuia sa dea ea — ca intre boturi se intampla ceva — dau acum flacarile.
]]
local emberField = piece("ember_field")
if emberField then
	hide(emberField)
end

--[[
	Aripile bat din umar.

	Aripa e un triunghi lipit de spate: varful lui e prinderea de corp, iar
	partea lata, de jos, e ce trebuie sa urce si sa coboare. Rotita in jurul
	**centrului** ei, aripa se invarte ca o elice si se misca tocmai varful —
	adica exact prinderea, care ar trebui sa stea pe loc. Deci axa nu trece prin
	centru, ci prin umar.

	Umarul nu se scrie de mana: se ia coltul placii cel mai apropiat de corpul
	dragonului. Asa ramane corect si daca artistul mai muta aripa.

	Bara galbena de pe muchie (`wing_edge_*`) e parte din aripa si primeste
	exact aceeasi rotatie, in jurul aceluiasi umar; altfel ar ramane suspendata
	in aer in timp ce aripa de sub ea coboara.

	Cei doi dragoni bat in oglinda — stau fata in fata, iar doua aripi care se
	ridica in aceeasi parte s-ar citi ca o singura pasare vazuta de sus.
]]
type Wing = {
	Part: BasePart,
	Offset: CFrame,
	Pivot: Vector3,
	Way: number,
}

local wings: { Wing } = {}

do
	local function shoulder(plate: BasePart, body: Vector3): Vector3
		local best, bestDistance = plate.Position, math.huge
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				local corner = plate.CFrame
					* Vector3.new(sx * plate.Size.X / 2, sy * plate.Size.Y / 2, 0)
				local distance = (corner - body).Magnitude
				if distance < bestDistance then
					best, bestDistance = corner, distance
				end
			end
		end
		return best
	end

	for _, side in { "l", "r" } do
		local chest = piece("chest_" .. side)
		local neck = piece("neck_" .. side)
		if not chest then
			continue
		end
		local body = if neck then (chest.Position + neck.Position) / 2 else chest.Position

		local way = if side == "r" then -1 else 1
		for index = 1, 4 do
			local plate = piece(string.format("wing_%s_%d", side, index))
			if not plate then
				continue
			end
			local pivot = home:PointToObjectSpace(shoulder(plate, body))
			for _, part in { plate, piece(string.format("wing_edge_%s_%d", side, index)) } do
				if part then
					table.insert(wings, {
						Part = part,
						Offset = home:ToObjectSpace(part.CFrame),
						Pivot = pivot,
						Way = way,
					})
				end
			end
		end
	end
end

--[[
	Ritmul suflului, in secunde: cat trage aer, cat sufla, si cat se odihneste.
]]
local DRAW, BREATH = 1.1, 0.9
local REST_MIN, REST_MAX = 1.8, 3.4

--[[
	Doua ceasuri, fiindca masoara lucruri diferite.

	`clock` numara de cand a inceput faza de acum si se intoarce la zero la
	fiecare schimbare — din el ies cele trei stari. `life` nu se intoarce
	niciodata, si din el ies undele: o flacara care unduieste dupa un ceas care
	sare inapoi ar tresari vizibil la fiecare suflare.
]]
local clock = 0
local life = 0
local phase: "REST" | "DRAW" | "BREATH" = "REST"
local rest = REST_MIN

RunService.Heartbeat:Connect(function(delta: number)
	if not model.Parent then
		return
	end

	for _, part in hidden do
		if part.Transparency ~= 1 then
			part.Transparency = 1
		end
	end

	clock += delta
	life += delta
	home = anchor.CFrame

	--[[
		Cele trei stari, una dupa alta: odihna, tras de aer, suflat.

		`heat` e cat de incins e dragonul acum, intre 0 si 1, si din el ies
		toate: marimea focului, culoarea aurului, rata jarului. Un singur numar
		tine tot efectul impreuna, deci nimic nu se aprinde pe cont propriu.
	]]
	local heat = 0
	if phase == "REST" then
		if clock >= rest then
			phase = "DRAW"
			clock = 0
		end
	elseif phase == "DRAW" then
		heat = math.min(clock / DRAW, 1) * 0.45
		if clock >= DRAW then
			phase = "BREATH"
			clock = 0
			for _, emitter in embers do
				emitter:Emit(math.random(10, 18))
			end
		end
	else
		heat = math.sin(math.min(clock / BREATH, 1) * math.pi) * 0.55 + 0.45
		if clock >= BREATH then
			phase = "REST"
			clock = 0
			rest = REST_MIN + math.random() * (REST_MAX - REST_MIN)
		end
	end

	-- ------------------------------------------------------------ miscarea
	local wave = life

	--[[
		Bataia, in planul aripii: o rotatie in jurul axei care iese din placa.
		Piesele modelului stau toate drept, deci axa aia e a treia axa a ancorei.
	]]
	local flap = math.sin(wave * 1.7) * math.rad(12)
	for _, wing in wings do
		local turn = CFrame.new(wing.Pivot)
			* CFrame.Angles(0, 0, flap * wing.Way)
			* CFrame.new(-wing.Pivot)
		wing.Part.CFrame = home * turn * wing.Offset
	end

	if emblem then
		emblem.CFrame = emblem.CFrame * CFrame.Angles(0, delta * 0.4, 0)
	end
	if emblemInner then
		emblemInner.CFrame = emblemInner.CFrame * CFrame.Angles(0, -delta * 0.7, 0)
	end
	if hub then
		--[[
			Razele dau ocol butucului, nu se invart pe loc: tinute fata de el, se
			rotesc toate odata, ca spitele unei roti, si raman lipite de emblema
			oriunde ajunge soclul.
		]]
		local spin = CFrame.Angles(0, wave * 0.55, 0)
		for _, ray in rays do
			ray.Part.CFrame = hub.CFrame * spin * ray.Offset
		end
	end

	-- Verdictul verde/rosu are intaietate cat zidul e doar o parere.
	if model:GetAttribute("Preview") then
		return
	end

	-- ------------------------------------------------------------- caldura
	local flicker = (math.sin(life * 11) + math.sin(life * 7.3 + 2)) / 8 + 0.75

	for _, fire in fires do
		--[[
			Focul din bot ramane mic dinadins: el e ce licareste intre dinti, nu
			suflul. Cat era mare, urca drept in sus peste cap si tot obiectul se
			citea ca un rug aprins in spatele dragonului, nu ca doi dragoni care
			isi trimit flacara unul altuia.
		]]
		fire.Size = 1.4 + heat * 2.6
		fire.Heat = 5 + heat * 12
		fire.Color = EMBER:Lerp(BLAZE, heat)
	end
	for _, light in mouthLights do
		light.Brightness = (0.45 + heat * 1.6) * flicker
		light.Color = EMBER:Lerp(WHITE, heat * 0.6)
	end

	for index, eye in eyes do
		local blink = (math.sin(wave * 3 + index) + 1) / 2
		eye.Color = Color3.fromHex("ffe08a"):Lerp(WHITE, math.max(heat, blink * 0.3))
	end

	for _, metal in trim do
		metal.Part.Color = metal.Base:Lerp(EMBER, heat * 0.8)
	end

	for _, emitter in embers do
		emitter.Rate = 4 + heat * 40
	end
end)
