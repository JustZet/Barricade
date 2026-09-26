--!strict
--[[
	Effects — fulgerul care chiar trece prin bolturi.

	Sta **in model**, nu in `src/`, din acelasi motiv ca la portal: descarcarea e
	o insusire a obiectului. Server, lobby sau fantoma de sub cursor — oriunde
	ajunge modelul, fulgerul pleaca singur.

	`RunContext = Client`: fiecare client isi joaca singur descarcarea, deci
	reteaua nu duce nimic si doi jucatori nu vad neaparat acelasi fulger in
	aceeasi clipa. Nici nu trebuie: nu e o regula de joc, e vreme.

	**Cum e facuta descarcarea.** Arcul nu se aprinde tot deodata. Fiecare
	segment isi stie locul pe drumul dintre cei doi electrozi, ca un numar intre
	0 si 1, iar la fiecare descarcare un cap de fulger porneste dintr-un capat si
	trece prin toate, in ordine. Abia dupa ce ajunge la celalalt electrod arcul
	arde intreg, o clipa, si se stinge. Directia se schimba de la o descarcare la
	alta, deci nu se vede niciodata acelasi lucru de doua ori la rand.

	Intre descarcari, cristalele **se incarca**: lumina lor urca incet spre
	urmatoarea descarcare si cade brusc odata cu ea. Asta leaga cele doua
	momente intre ele — altfel fulgerul ar parea ca vine de nicaieri.

	Fisierul asta e copia de pe disc a scriptului din place
	(`assets/world-scripts/thunder-effects.luau`). Place-ul e adevarul.
]]

local RunService = game:GetService("RunService")

local model = script.Parent :: Model

--[[
	Doar in lume, niciodata in magazie.

	Un script cu `RunContext = Client` porneste oriunde ajunge, inclusiv pe
	modelul-sursa din `ReplicatedStorage.Assets` — si acolo face rau in liniste:
	scrie luminile si emitatoarele **in sursa**, iar fiecare clona de dupa pleaca
	la drum cu ele de-a gata, adunate una peste alta. S-a si vazut: electrodul
	avea doua lumini, una moarta si una vie, iar cea moarta era prima gasita.

	Sursa nu se vede oricum niciodata; ce se vede sunt clonele, si ele sunt in
	`Workspace`.
]]
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

local left = piece("electrode_l")
local right = piece("electrode_r")
if not (left and right) then
	return
end

--[[
	Placa dreptunghiulara dintre stalpi nu mai are ce cauta in cadru.

	Era un halou desenat in jurul arcului, la transparenta 0.92 — destul cat sa
	nu se vada ca lumina, si destul cat sa se vada ca o cutie. Acum lumina o dau
	particulele si luminile de pe electrozi, care nu au muchii.
]]
local halo = piece("arc_halo")
if halo then
	hide(halo)
end

--[[
	Segmentele arcului, pe trei feluri.

	Modelul desenase fulgerul in trei bucati: **arcul de sus**, dintre
	electrozi; doua **ramuri** care cad din el; si un **arc de jos**, care trece
	pe sub ele. Pana acum toate trei stateau la fel, palide, tot timpul — si
	atunci desenul se citea ca o sarma incurcata, nu ca o descarcare.

	Acum doar arcul de sus ramane, subtire, intre descarcari. Ramurile si arcul
	de jos **nu exista** pana nu trece fulgerul: atunci cad din arcul de sus si
	se leaga intre ele pe dedesubt, si abia impreuna se vede de ce sunt acolo.

	Locul fiecarui segment pe drumul dintre electrozi nu se ia din nume, ci se
	**masoara**: se proiecteaza pozitia lui pe axa dintre cei doi. Asa ordinea e
	cea adevarata si ramane corecta daca artistul mai adauga un segment.
]]
type Kind = "main" | "branch" | "low"

type Segment = {
	Part: BasePart,
	Kind: Kind,
	Branch: number,
	Step: number,
	At: number,
	Rest: number,
	-- La a cata secunda din descarcare se aprinde. Se scrie la fiecare fulger.
	Moment: number,
}

local segments: { Segment } = {}

local span = right.Position - left.Position
local length = span.Magnitude
local direction = if length > 0 then span.Unit else Vector3.new(1, 0, 0)

local function add(part: BasePart, kind: Kind, branch: number, step: number)
	table.insert(segments, {
		Part = part,
		Kind = kind,
		Branch = branch,
		Step = step,
		At = math.clamp(
			(part.Position - left.Position):Dot(direction) / math.max(length, 0.01),
			0,
			1
		),
		Rest = part.Transparency,
		Moment = 0,
	})
end

for _, part in model:GetDescendants() do
	if not part:IsA("BasePart") then
		continue
	end
	local limb, order = string.match(part.Name, "^arc_branch_(%d+)_seg_(%d+)$")
	if limb and order then
		add(part, "branch", tonumber(limb) or 0, tonumber(order) or 0)
	elseif string.match(part.Name, "^arc_low_seg_%d+$") then
		add(part, "low", 0, 0)
	elseif string.match(part.Name, "^arc_main_seg_%d+$") then
		add(part, "main", 0, 0)
	end
end

--[[
	De unde pleaca fiecare ramura si unde ii sta piciorul.

	Radacina e locul primului ei segment pe drumul dintre electrozi: de acolo se
	desprinde din arcul de sus, si abia dupa ce fulgerul trece pe acolo are de ce
	sa cada. Piciorul e segmentul cel mai de jos, si de la el porneste arcul de
	jos.
]]
local roots: { [number]: number } = {}
local depth: { [number]: number } = {}
local stem: { [number]: number } = {}

for _, segment in segments do
	if segment.Kind ~= "branch" then
		continue
	end
	local branch = segment.Branch
	if stem[branch] == nil or segment.Step < stem[branch] then
		stem[branch] = segment.Step
		roots[branch] = segment.At
	end
	depth[branch] = math.max(depth[branch] or 0, segment.Step)
end

--[[
	Scanteile: bilele mici pe care modelul le are imprastiate in jurul arcului —
	opt pe zid, douasprezece pe soclu. Nu se numara, se cauta dupa nume. Ca bile
	se vad ca niste bile; ca guri de emitator, se vad ca scantei.

	Emitatorul sta stins si scuipa o rafala doar cand trece fulgerul. Un jet
	continuu ar fi facut din zid o fantana; o rafala la fiecare descarcare e
	chiar ce arunca un arc electric cand se stinge.
]]
local SPARK_COLOR = ColorSequence.new(Color3.fromHex("ffffff"), Color3.fromHex("6fd2ff"))

local SPARK_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.35, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local SPARK_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 0),
})

local sparks: { ParticleEmitter } = {}

for _, dot in model:GetDescendants() do
	if not dot:IsA("BasePart") or not string.match(dot.Name, "^spark_%d+$") then
		continue
	end

	hide(dot)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Spark"
	emitter.Color = SPARK_COLOR
	emitter.Size = SPARK_SIZE
	emitter.Transparency = SPARK_FADE
	emitter.Lifetime = NumberRange.new(0.25, 0.6)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -22, 0)
	emitter.Drag = 2.5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.LightEmission = 0.5
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Parent = dot

	table.insert(sparks, emitter)
end

-- Lumina de pe fiecare electrod: se incarca intre descarcari si arde in ele.
local function lampOn(part: BasePart): PointLight
	local light = Instance.new("PointLight")
	light.Name = "Charge"
	light.Color = Color3.fromHex("bfe9ff")
	light.Range = 10
	light.Brightness = 0
	light.Shadows = false
	light.Parent = part
	return light
end

local lamps = { lampOn(left), lampOn(right) }

local crystals = { piece("core_crystal_l"), piece("core_crystal_r") }

--[[
	Ce are soclul in plus fata de zid.

	Acelasi script sta si in `Podiums.thunder`: piesele poarta acolo aceleasi
	nume, deci arcul, electrozii si scanteile se gasesc singure. Soclul mai are
	o lumina sub obiect, doua serpentine in plinta si o emblema — se cauta dupa
	nume si, daca lipsesc, nu se intampla nimic. Un singur script, doua obiecte.
]]
local standGlow = piece("stand_glow")
local standBase = if standGlow then standGlow.Transparency else 0
local emblem = piece("emblem_ring")
local plinth = { piece("plinth_coil_1"), piece("plinth_coil_2") }

--[[
	Ritmul descarcarii, in secunde.

	`TRAVEL` e cat ii ia capului de fulger sa treaca dintr-un electrod in
	celalalt: sub o zecime de secunda nu s-ar vedea ca trece, peste o jumatate
	ar parea ca se tarnaie. `DROP` e cat sta capul pe fiecare segment de ramura
	cand cade, iar `SPREAD` cat i-ar lua arcului de jos sa strabata toata
	deschiderea — el pleaca insa din piciorul fiecarei ramuri, deci face mai
	putin de-atat.

	`HOLD` e clipa in care arde tot, `FADE` cat se stinge. Stingerea e lunga
	dinadins: ramurile si arcul de jos apar deodata si pleaca incet, cum se duce
	o urma de pe retina. Pauza dintre descarcari se trage la sorti intre doua
	margini, ca sa nu se prinda nimeni in ritm.
]]
local TRAVEL, DROP, SPREAD = 0.18, 0.06, 0.5
local HOLD, FADE = 0.1, 0.75
local GAP_MIN, GAP_MAX = 1.3, 2.8

-- Cat de stins sta arcul intre descarcari. Nu de tot: un fir subtire ramane.
local IDLE = 0.92

local LIT = Color3.fromHex("ffffff")
local COOL = Color3.fromHex("d8f0ff")

local strike = -1
local gap = GAP_MIN
local clock = 0
local forward = true

-- Cand arde tot, adica dupa ce s-a aprins si ultimul segment.
local peak = TRAVEL + HOLD

--[[
	O descarcare noua.

	Aici se scrie, pentru fiecare segment, **la a cata secunda se aprinde**. Se
	socoteste la fiecare fulger, nu o data la pornire, fiindca sensul alterneaza:
	descarcarea care pleaca din electrodul celalalt aprinde intai ramura
	cealalta, iar arcul de jos se intinde invers.

	Un singur numar pe segment tine toata coregrafia, iar bucla nu mai are de
	socotit decat daca i-a trecut clipa.
]]
local function fire()
	strike = 0
	forward = not forward
	gap = GAP_MIN + math.random() * (GAP_MAX - GAP_MIN)

	local function reach(at: number): number
		return if forward then at else 1 - at
	end

	-- Piciorul fiecarei ramuri: cand ajunge caderea la capatul ei de jos.
	local feet: { [number]: number } = {}
	for branch, at in roots do
		feet[branch] = reach(at) * TRAVEL + (depth[branch] or 1) * DROP
	end

	peak = 0
	for _, segment in segments do
		local moment
		if segment.Kind == "main" then
			moment = reach(segment.At) * TRAVEL
		elseif segment.Kind == "branch" then
			moment = reach(roots[segment.Branch] or segment.At) * TRAVEL + segment.Step * DROP
		else
			--[[
				Arcul de jos pleaca din piciorul ramurii celei mai apropiate si se
				intinde in amandoua partile. Asa se vede ca fulgerul a cazut si
				apoi a alergat pe dedesubt, nu ca s-a aprins o a doua sarma.
			]]
			local best, from = math.huge, reach(segment.At) * TRAVEL + DROP
			for branch, at in roots do
				local away = math.abs(segment.At - at)
				if away < best then
					best = away
					from = (feet[branch] or 0) + away * SPREAD
				end
			end
			moment = from
		end

		segment.Moment = moment
		peak = math.max(peak, moment)
	end

	peak += HOLD

	for _, emitter in sparks do
		emitter:Emit(math.random(6, 12))
	end
end

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

	if strike >= 0 then
		strike += delta
		if strike > peak + FADE then
			strike = -1
			clock = 0
		end
	elseif clock >= gap then
		fire()
	end

	--[[
		Cat timp zidul e doar previzualizare — verde sau rosu sub cursor —
		verdictul are intaietate: nu se atinge nicio culoare si nicio
		transparenta, ca sa nu clipeasca „se poate" peste „nu se poate".
	]]
	if model:GetAttribute("Preview") then
		return
	end

	-- Incarcarea: cat de aproape e urmatoarea descarcare, intre 0 si 1.
	local charge = if strike >= 0 then 0 else math.clamp(clock / gap, 0, 1)

	--[[
		Cat de aprins e fulgerul acum.

		Un segment e aprins daca i-a trecut clipa lui, si tot ce e aprins se
		stinge impreuna, dupa `peak`. De aceea ramurile pleaca odata cu arcul
		din care au cazut, nu fiecare pe cont propriu.
	]]
	local fade = 1
	if strike > peak then
		fade = math.clamp(1 - (strike - peak) / FADE, 0, 1)
	end

	for _, segment in segments do
		local lit = if strike >= 0 and strike >= segment.Moment then fade else 0

		--[[
			Intre descarcari ramane doar arcul de sus, si el palpaie: fiecare
			segment in ritmul lui, dat de locul lui pe drum, ca sa nu clipeasca
			toate odata. Ramurile si arcul de jos se sting de tot — ele sunt ce
			se intampla, nu ce e acolo.
		]]
		local dark = 1
		if segment.Kind == "main" then
			dark = IDLE - 0.04 * (math.sin(clock * 9 + segment.At * 14) + 1) / 2
		end

		segment.Part.Transparency = dark * (1 - lit) + segment.Rest * lit
		segment.Part.Color = COOL:Lerp(LIT, lit)
	end

	local burn = if strike >= 0 then fade else 0
	for _, lamp in lamps do
		lamp.Brightness = charge * 0.4 + burn * 2.2
	end
	for _, crystal in crystals do
		if crystal then
			crystal.Color = COOL:Lerp(LIT, math.max(charge * 0.5, burn))
		end
	end

	--[[
		Plinta soclului se incarca odata cu cristalele: serpentinele din ea se
		albesc pe masura ce se apropie descarcarea, iar lumina de sub obiect
		creste cu ele. Asa se vede ca tot soclul lucreaza, nu doar arcul de
		deasupra lui.
	]]
	local swell = math.max(charge * 0.6, burn)
	for _, coil in plinth do
		if coil then
			coil.Color = Color3.fromHex("c0793c"):Lerp(LIT, swell * 0.7)
		end
	end
	if standGlow then
		standGlow.Transparency = standBase + 0.25 - swell * 0.25
	end
	if emblem then
		emblem.CFrame = emblem.CFrame * CFrame.Angles(0, delta * 0.45, 0)
	end
end)
