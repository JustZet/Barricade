--!strict
--[[
	Effects — bariera de energie, aprinsa.

	Sta **in model**, ca si la `portal` si `thunder`: acelasi script intra si in
	zidul `energy`, si in soclul `energy`, fiindca piesele poarta in amandoua
	aceleasi nume. Ce exista se anima, ce lipseste se sare — zidul n-are cioburi
	care plutesc, soclul n-are panglici — deci nu e nevoie de doua scripturi care
	sa spuna acelasi lucru in doua feluri.

	`RunContext = Client`: fiecare client isi joaca singur bariera, nimic nu se
	replica.

	**Din ce e facuta senzatia de energie.** Un camp care pulseaza singur arata a
	geam colorat. Ce-l face sa para sub tensiune sunt trei lucruri suprapuse,
	fiecare cu ritmul lui:

	  - *palpaitul* — doua foi de camp care respira la frecvente apropiate, dar
	    nu egale; unde se intalnesc, se aprind mai tare si apoi se sting, si de
	    aici vine tremurul care nu se repeta niciodata la fel;
	  - *scanarea* — panglicile urca prin camp si se intorc de jos, iar firele
	    subtiri trec prin el de la un stalp la altul: energia se vede ca
	    circula, nu ca sta;
	  - *descarcarea* — din cand in cand un val trece prin bariera dintr-un
	    emitator in celalalt, campul se albeste o clipa si emitatoarele scuipa
	    scantei. Directia se schimba de fiecare data.

	Cat timp zidul e doar previzualizare, `Barricade` ridica atributul `Preview`
	si aici nu se mai atinge nicio culoare: verdele si rosul verdictului au
	intaietate.

	Copia de pe disc: `assets/world-scripts/energy-effects.luau`.
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

--[[
	Piesa fata de care se masoara tot ce se misca.

	Nimic nu se tine minte in coordonatele lumii: soclul pluteste in vitrina,
	zidul cade pe tabla si urmeaza cursorul — iar un ciob tinut minte unde era
	la pornire ar ramane in urma, singur, in aer. Deci se tine minte fata de o
	piesa care nu se misca, si la fiecare cadru se reface de acolo.

	Ancora se alege singura: cea mai mare piesa pe care scriptul n-o atinge —
	plinta zidului sau placa soclului.
]]
local MOVES = {
	"^energy_ribbon_%d+$",
	"^energy_strand_%d+$",
	"^float_shard_%d+$",
	"^energy_arc$",
	"^emblem_",
}

local function chooseAnchor(): BasePart?
	local function moves(name: string): boolean
		for _, pattern in MOVES do
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

local COOL = Color3.fromHex("5fdcff")
local WARM = Color3.fromHex("a07dff")
local HOT = Color3.fromHex("ffffff")

--[[
	Foile campului, fiecare cu ritmul si faza ei.

	Frecventele sunt apropiate, dar nu in raport intreg: 1.7 si 2.3 nu se
	intalnesc niciodata de doua ori la fel, deci palpaitul nu se aude ca un
	metronom. Daca ar fi 2 si 4, bariera ar clipi in ritm si s-ar vedea ca e un
	numar, nu o tensiune.
]]
type Sheet = {
	Part: BasePart,
	Rest: number,
	Rate: number,
	Phase: number,
	Swing: number,
}

local sheets: { Sheet } = {}
local FIELDS = { "energy_field", "energy_field_inner", "energy_veil", "energy_arc" }

for index, name in FIELDS do
	local part = piece(name)
	if part then
		table.insert(sheets, {
			Part = part,
			Rest = part.Transparency,
			Rate = 1.7 + index * 0.6,
			Phase = index * 1.3,
			-- Foile deja transparente pot juca mai mult; cele opace, aproape deloc.
			Swing = if part.Transparency > 0.5 then 0.14 else 0.05,
		})
	end
end

-- Campul dupa care se masoara drumul: prima foaie gasita e si cea mai mare.
local field = if sheets[1] then sheets[1].Part else nil

--[[
	Panglicile urca prin camp si se intorc de jos.

	Pozitia lor se tine **fata de camp**, nu fata de lume: zidul cade pe tabla,
	se plimba sub cursor, se leagana in vitrina, iar panglicile trebuie sa urce
	prin el oriunde ar fi. Cand una iese pe sus, reintra pe jos — de aceea
	inaltimea se ia modulo inaltimea campului.
]]
type Scan = {
	Part: BasePart,
	Rotation: CFrame,
	Along: number,
	Across: number,
	Speed: number,
}

local ribbons: { Scan } = {}
local strands: { Scan } = {}

local height = if field then field.Size.Y else 0
local width = if field then field.Size.X else 0

if field then
	for index, ribbon in collect("^energy_ribbon_%d+$") do
		local offset = field.CFrame:ToObjectSpace(ribbon.CFrame)
		table.insert(ribbons, {
			Part = ribbon,
			Rotation = offset.Rotation,
			Along = offset.Position.Y,
			Across = offset.Position.X,
			Speed = 0.9 + index * 0.25,
		})
	end

	for index, strand in collect("^energy_strand_%d+$") do
		local offset = field.CFrame:ToObjectSpace(strand.CFrame)
		table.insert(strands, {
			Part = strand,
			Rotation = offset.Rotation,
			Along = offset.Position.X,
			Across = offset.Position.Y,
			-- Firele trec in sens invers panglicilor: asa se incruciseaza.
			Speed = -(1.6 + index * 0.4),
		})
	end
end

--[[
	Cioburile care plutesc in jurul soclului: se leagana si se rotesc, fiecare
	in ritmul lui. Faza vine din indice, ca sa nu urce si sa coboare la unison —
	patru cioburi care bat impreuna arata a mecanism, nu a energie libera.
]]
type Shard = {
	Part: BasePart,
	Offset: CFrame,
	Phase: number,
	Rise: number,
	Spin: number,
}

local shards: { Shard } = {}
for index, shard in collect("^float_shard_%d+$") do
	table.insert(shards, {
		Part = shard,
		Offset = home:ToObjectSpace(shard.CFrame),
		Phase = index * 1.7,
		Rise = 0.18 + index % 3 * 0.05,
		Spin = if index % 2 == 0 then 0.8 else -1.1,
	})
end

--[[
	Inelele de pe stalpi se aprind unul dupa altul, de jos in sus.

	Energia „urca" in stalpi si intra in camp. Locul fiecarui inel in sir il da
	inaltimea lui, nu numele: la zid sunt doua pe stalp, la soclu trei, iar
	sirul iese corect in amandoua fara sa numere nimeni.
]]
type Band = {
	Part: BasePart,
	At: number,
}

local rings: { Band } = {}
do
	local found = collect("^pylon_band_[lr]_%d+$")
	local low, high = math.huge, -math.huge
	for _, band in found do
		local y = home:PointToObjectSpace(band.Position).Y
		low, high = math.min(low, y), math.max(high, y)
	end
	local span = math.max(high - low, 0.01)

	--[[
		Locul fiecarui inel in sir se socoteste **o data**, la pornire, si fata
		de ancora. Masurat la fiecare cadru in inaltimea lumii, sirul s-ar rupe
		de indata ce obiectul se ridica: soclul pluteste in vitrina, iar inelele
		ar iesi toate deasupra capatului masurat la inceput si s-ar stinge.
	]]
	for _, band in found do
		table.insert(rings, {
			Part = band,
			At = (home:PointToObjectSpace(band.Position).Y - low) / span,
		})
	end
end

--[[
	Spira de deasupra stalpilor se roteste.

	E un semicerc asezat culcat, prins peste cei doi stalpi, si tocmai fiindca e
	doar jumatate de cerc se vede imediat cand se invarte — un inel intreg rotit
	arata la fel in orice clipa. Se invarte incet: e capacul unui generator, nu
	o elice.

	Centrul nu e al piesei, ci **mijlocul dintre stalpi**: semicercul e desenat
	in jurul acelui punct, iar rotit fata de centrul cutiei lui ar descrie un
	cerc mare prin aer, ca o praștie. Daca stalpii lipsesc, ramane centrul
	piesei — se invarte pe loc si nu strica nimic.
]]
local ARC_TURNS = 0.1

local arc = piece("energy_arc")
local arcOffset: CFrame? = nil
local arcPivot: Vector3? = nil

if arc then
	local left, right = piece("pylon_l"), piece("pylon_r")
	local middle = if left and right then (left.Position + right.Position) / 2 else arc.Position
	arcOffset = home:ToObjectSpace(arc.CFrame)
	arcPivot = home:PointToObjectSpace(Vector3.new(middle.X, arc.Position.Y, middle.Z))
end

-- Emitatoarele: miezul, lentila si lumina lor.
local cores = { piece("emitter_core_l"), piece("emitter_core_r") }
local lenses = { piece("emitter_lens_l"), piece("emitter_lens_r") }

local lamps: { PointLight } = {}
for _, core in cores do
	if core then
		local light = Instance.new("PointLight")
		light.Name = "Emitter"
		light.Color = COOL
		light.Range = 18
		light.Brightness = 1
		light.Shadows = false
		light.Parent = core
		table.insert(lamps, light)
	end
end

--[[
	Firicelele de energie care se ridica din bariera.

	Modelul are bile mici pe care le foloseam pe post de particule. Ca bile se
	vad ca bile; facute invizibile si puse sa emita, se vad ca energie care
	urca. Transparenta lor creste din nimic si scade la loc, deci firicelele se
	aprind si se sting in drum, nu apar si dispar.
]]
local MOTE_COLOR = ColorSequence.new(COOL, WARM)

local MOTE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.1),
	NumberSequenceKeypoint.new(0.7, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local MOTE_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.34),
	NumberSequenceKeypoint.new(1, 0.02),
})

local motes: { ParticleEmitter } = {}

for _, dot in collect("^particle_%d+$") do
	hide(dot)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Mote"
	emitter.Color = MOTE_COLOR
	emitter.Size = MOTE_SIZE
	emitter.Transparency = MOTE_FADE
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(1, 2.2)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-80, 80)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = 6
	emitter.Parent = dot

	table.insert(motes, emitter)
end

-- Scanteile de la descarcare ies din emitatoare, nu din camp.
local bursts: { ParticleEmitter } = {}
for _, core in cores do
	if not core then
		continue
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Surge"
	emitter.Color = ColorSequence.new(HOT, COOL)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Parent = core
	table.insert(bursts, emitter)
end

-- Sclipirile de pe marginea soclului si sigiliul din plinta.
local edges = collect("^edge_glow_%d+$")
local sigil = piece("stand_sigil")
local sigilRest = if sigil then sigil.Transparency else 0
local emblem = piece("emblem_ring")
local railGlow = piece("base_rail_glow")

--[[
	Ritmul descarcarii, in secunde. Valul trece prin bariera in `SURGE`, si intre
	doua valuri trece o pauza trasa la sorti — altfel bariera ar bate ca un ceas.
]]
local SURGE = 0.55
local GAP_MIN, GAP_MAX = 2.2, 4

local clock = 0
local surge = -1
local gap = GAP_MIN
local forward = true

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
	home = anchor.CFrame

	if surge >= 0 then
		surge += delta
		if surge > SURGE then
			surge = -1
			clock = 0
		end
	elseif clock >= gap then
		surge = 0
		forward = not forward
		gap = GAP_MIN + math.random() * (GAP_MAX - GAP_MIN)
		for _, emitter in bursts do
			emitter:Emit(math.random(8, 14))
		end
	end

	-- ------------------------------------------------------------ miscarea
	if field then
		local frame = field.CFrame

		for _, scan in ribbons do
			local travel = (scan.Along + clock * scan.Speed + height / 2) % height - height / 2
			scan.Part.CFrame = frame * (CFrame.new(scan.Across, travel, 0) * scan.Rotation)
		end

		for _, scan in strands do
			local travel = (scan.Along + clock * scan.Speed + width / 2) % width - width / 2
			scan.Part.CFrame = frame * (CFrame.new(travel, scan.Across, 0) * scan.Rotation)
		end
	end

	for _, shard in shards do
		local wave = math.sin(clock * 1.4 + shard.Phase)
		shard.Part.CFrame = home
			* shard.Offset
			* CFrame.new(0, wave * shard.Rise, 0)
			* CFrame.Angles(0, clock * shard.Spin, 0)
	end

	if arc and arcOffset and arcPivot then
		-- Cand trece o descarcare, spira o ia putin inainte.
		local turn = clock * ARC_TURNS * math.pi * 2 + (if surge >= 0 then surge * 1.6 else 0)
		arc.CFrame = home
			* CFrame.new(arcPivot)
			* CFrame.Angles(0, turn, 0)
			* CFrame.new(-arcPivot)
			* arcOffset
	end

	if emblem then
		emblem.CFrame = emblem.CFrame * CFrame.Angles(0, delta * 0.4, 0)
	end

	-- Verdictul verde/rosu are intaietate: cat e previzualizare, nu se coloreaza.
	if model:GetAttribute("Preview") then
		return
	end

	-- ------------------------------------------------------------- lumina
	--[[
		Cat de tare arde bariera acum.

		Doua unde lente, cu frecvente care nu se potrivesc, plus valul descarcarii
		daca tocmai trece unul. Impreuna dau o lumina care nu se repeta.
	]]
	local pulse = (math.sin(clock * 1.7) + math.sin(clock * 2.3 + 1.1)) / 4 + 0.5
	local wave = if surge >= 0 then math.sin(surge / SURGE * math.pi) else 0
	local burn = math.max(pulse * 0.35, wave)

	for _, sheet in sheets do
		local breath = (math.sin(clock * sheet.Rate + sheet.Phase) + 1) / 2
		sheet.Part.Transparency = math.clamp(sheet.Rest - sheet.Swing * breath - wave * 0.25, 0, 1)
		sheet.Part.Color = COOL:Lerp(HOT, wave * 0.8)
	end

	--[[
		Inelele se aprind in sir: valul urca prin stalpi si intra in camp. Cand
		trece o descarcare, sirul o ia inaintea ritmului obisnuit, deci se vede
		ca energia chiar vine dinspre picioare spre bariera.
	]]
	local climb = (clock * 0.8 + wave) % 1
	for _, ring in rings do
		local near = 1 - math.min(math.abs(ring.At - climb), math.abs(ring.At - climb + 1)) * 3
		ring.Part.Color = COOL:Lerp(HOT, math.clamp(near, 0, 1) * 0.65 + wave * 0.3)
	end

	for _, core in cores do
		if core then
			core.Color = WARM:Lerp(HOT, burn)
		end
	end
	for _, lens in lenses do
		if lens then
			lens.Color = COOL:Lerp(HOT, burn)
		end
	end
	for _, lamp in lamps do
		lamp.Brightness = 1 + pulse * 1.2 + wave * 4
		lamp.Color = COOL:Lerp(HOT, wave)
	end

	for _, mote in motes do
		mote.Rate = 6 + wave * 26
	end

	for index, edge in edges do
		local breath = (math.sin(clock * 2 + index) + 1) / 2
		edge.Color = COOL:Lerp(HOT, breath * 0.4 + wave * 0.5)
	end
	if sigil then
		sigil.Transparency = math.clamp(sigilRest + 0.2 - pulse * 0.2 - wave * 0.2, 0, 1)
	end
	if railGlow then
		railGlow.Color = COOL:Lerp(HOT, wave * 0.7)
	end
end)
