--!strict
--[[
	Effects — portalul, pus in miscare.

	Sta **in model**, nu in `src/`, si asta e o alegere: miscarea e o insusire a
	obiectului, nu a locului in care ajunge. Acelasi model e clonat de server
	pentru zidul din meci, de client pentru vitrina din lobby si pentru fantoma
	de sub cursor — iar bratele se invart in toate trei fara ca vreunul dintre
	ei sa stie ca portalul se invarte.

	`RunContext = Client` il face sa porneasca pe fiecare client, oriunde ar sta
	modelul. Nimic de aici nu se replica: fiecare isi invarte singur copia, deci
	reteaua nu duce niciun cadru.

	Fisierul asta e **copia de pe disc** a scriptului din place
	(`assets/world-scripts/portal-effects.luau`). Place-ul e adevarul; copia e
	ce repui daca modelul se importa din nou si scriptul pleaca odata cu el.

	Cat timp zidul e doar previzualizare — verde sau rosu, sub cursor —
	`Barricade` pune atributul `Preview` pe model, iar aici nu se mai atinge
	nicio culoare si nicio transparenta: verdictul „se poate / nu se poate" nu
	are voie sa clipeasca.
]]

local RunService = game:GetService("RunService")

local model = script.Parent :: Model

--[[
	Doar in lume, niciodata in magazie.

	Un script cu `RunContext = Client` porneste oriunde ajunge, inclusiv pe
	modelul-sursa din `ReplicatedStorage.Assets` — si acolo face rau in liniste:
	adauga luminile si emitatoarele **in sursa**, invarte bratele in sursa, iar
	fiecare clona de dupa pleaca la drum cu ele de-a gata, adunate una peste
	alta. Zidul din meci ajungea cu doua lumini si cu discul rotit aiurea.

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

local disc = piece("galaxy_disc")
if not disc then
	return
end

--[[
	Bratele din discul din mijloc, in ordinea in care sunt desenate: doua pe
	fiecare inel, dinspre centru spre margine.
]]
local ARMS = {
	"swirl_arm_1_1",
	"swirl_arm_1_2",
	"swirl_arm_2_1",
	"swirl_arm_2_2",
	"swirl_arm_3_1",
	"swirl_arm_3_2",
}

--[[
	Cat de repede se invarte fiecare inel, in rotatii pe secunda, si incotro.

	Semnul alterneaza din brat in brat: unul spre dreapta, urmatorul spre stanga.
	Asta e ce face discul sa arate ca un mecanism, nu ca un desen rotit — doua
	brate care merg in aceeasi parte se citesc ca o singura piesa.

	Vitezele scad spre exterior, ca la un vartej adevarat: bratul dinauntru
	prinde o rotatie in patru secunde, cel de afara in noua.
]]
local BASE_TURNS = 0.26
local TIER_FALLOFF = 0.07

type Orbit = {
	Part: BasePart,
	Offset: CFrame,
	Speed: number,
}

local orbits: { Orbit } = {}

for index, name in ARMS do
	local arm = piece(name)
	if arm then
		local direction = if index % 2 == 0 then -1 else 1
		local tier = math.ceil(index / 2)
		table.insert(orbits, {
			Part = arm,
			--[[
				Locul bratului fata de disc, nu fata de lume.

				Zidul se muta: cade pe tabla, se plimba sub cursor ca fantoma, se
				leagana in vitrina. Tinut fata de disc, bratul urmeaza modelul
				oriunde ar ajunge, iar invartirea se adauga peste.
			]]
			Offset = disc.CFrame:ToObjectSpace(arm.CFrame),
			Speed = direction * (BASE_TURNS - tier * TIER_FALLOFF) * math.pi * 2,
		})
	end
end

-- Orizontul si valul se invart si ele, mai incet si in sens invers intre ele.
local horizon = piece("event_horizon")
local horizonOffset = if horizon then disc.CFrame:ToObjectSpace(horizon.CFrame) else nil

local veil = piece("portal_veil")
local veilBase = if veil then veil.Transparency else 0

-- Inelele de pe cei doi stalpi se invart in jurul axei lor, in oglinda.
local sideRings = {
	{ Part = piece("device_ring_glow_l"), Speed = 1.1 },
	{ Part = piece("device_ring_glow_r"), Speed = -1.1 },
}

--[[
	Praful care cade in portal.

	Modelul vine cu bile mici imprastiate in jurul discului — noua pe zid,
	paisprezece pe soclu. Nu se numara: se cauta dupa nume, deci artistul mai
	poate adauga una fara sa se atinga scriptul. Ca bile arata
	a bile; ca **locuri din care ies particule**, arata a portal care trage
	totul spre el. De aceea se fac invizibile si se intorc cu fata spre centru:
	emitatorul isi trimite particulele inainte, iar inainte inseamna acum „spre
	gaura neagra".

	Particulele nu apar si nu dispar brusc: transparenta lor urca din nimic,
	sta aprinsa la mijlocul drumului si se stinge la capat. Asta e „luminozitate
	care se schimba progresiv" — se vede ca materia se aprinde cand intra in
	campul portalului.
]]
local DUST_COLOR = ColorSequence.new(Color3.fromHex("d9c6ff"), Color3.fromHex("8e6bff"))

local DUST_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.25, 0.05),
	NumberSequenceKeypoint.new(0.75, 0.15),
	NumberSequenceKeypoint.new(1, 1),
})

local DUST_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 0.04),
})

for _, dot in model:GetDescendants() do
	if not dot:IsA("BasePart") or not string.match(dot.Name, "^dust_%d+$") then
		continue
	end

	hide(dot)
	dot.CFrame = CFrame.lookAt(dot.Position, disc.Position)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Dust"
	emitter.Color = DUST_COLOR
	emitter.Size = DUST_SIZE
	emitter.Transparency = DUST_FADE
	emitter.Lifetime = NumberRange.new(0.9, 1.5)
	emitter.Speed = NumberRange.new(1.4, 2.4)
	emitter.SpreadAngle = Vector2.new(14, 14)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.LightEmission = 0.5
	emitter.LightInfluence = 0
	emitter.Rate = 8
	emitter.Parent = dot
end

--[[
	Lumina din gaura neagra. Bate incet, ca o respiratie, si e singurul lucru
	care lumineaza cu adevarat aici — restul sunt piese Neon, care se vad
	singure dar nu lumineaza nimic.
]]
local core = piece("black_hole_core")
local glow: PointLight? = nil
if core then
	local light = Instance.new("PointLight")
	light.Name = "CoreGlow"
	light.Color = Color3.fromHex("8e6bff")
	light.Range = 9
	light.Brightness = 0.55
	light.Shadows = false
	light.Parent = core
	glow = light
end

--[[
	Ce are soclul in plus fata de zid.

	Acelasi script sta si in `Podiums.portal`, fiindca piesele poarta acolo
	aceleasi nume: disc, brate, praf. Soclul mai are insa o emblema pe plinta si
	o lumina sub obiect — se cauta dupa nume si, daca lipsesc, nu se intampla
	nimic. Asa nu exista doua scripturi care sa spuna acelasi lucru in doua
	feluri, si nici unul care sa se planga ca lipseste o piesa.
]]
local emblem = piece("emblem_ring")
local emblemInner = piece("emblem_ring_inner")
local standGlow = piece("stand_glow")
local standBase = if standGlow then standGlow.Transparency else 0

local clock = 0

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

	local center = disc.CFrame
	for _, orbit in orbits do
		orbit.Part.CFrame = center * CFrame.Angles(0, 0, clock * orbit.Speed) * orbit.Offset
	end

	if horizon and horizonOffset then
		horizon.CFrame = center * CFrame.Angles(0, 0, -clock * 0.7) * horizonOffset
	end

	for _, ring in sideRings do
		local part = ring.Part
		if part then
			part.CFrame = part.CFrame * CFrame.Angles(0, 0, delta * ring.Speed)
		end
	end

	-- Emblema de pe plinta soclului se invarte plat, in jurul axei ei verticale.
	if emblem then
		emblem.CFrame = emblem.CFrame * CFrame.Angles(0, delta * 0.5, 0)
	end
	if emblemInner then
		emblemInner.CFrame = emblemInner.CFrame * CFrame.Angles(0, -delta * 0.8, 0)
	end

	-- Ce coloreaza si ce face transparent se opreste cat zidul e doar o parere.
	if model:GetAttribute("Preview") then
		return
	end

	local breath = (math.sin(clock * 1.6) + 1) / 2

	if veil then
		veil.Transparency = veilBase - 0.06 + breath * 0.12
	end
	if glow then
		glow.Brightness = 0.4 + breath * 0.5
	end
	if standGlow then
		standGlow.Transparency = standBase + 0.2 - breath * 0.2
	end
end)
