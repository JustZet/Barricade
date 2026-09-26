--!strict
--[[
	Effects — cristalele si fluturele de cristal.

	Sta **in model**, ca la portal, thunder, energy si dragon, si acelasi script
	intra si in zidul `crystal`, si in soclul `crystal`. Ce lipseste se sare, deci
	nu e nevoie de doua scripturi pentru doua obiecte care poarta aceleasi nume.

	**Ce se misca si ce nu.** Nimic din cristal nu se misca: nici stalpii, nici
	tepii, nici cioburile care plutesc. Un cristal care se clatina nu mai pare
	infipt in nimic, iar ce e prins in aer si tremura se citeste ca o piesa
	scapata. Singurul lucru care umbla e dragonul; restul primeste doar lumina
	care trece prin el.

	Peste tot trece o **unda de lumina**: un val care merge de la un capat la
	celalalt si albeste pe rand fiecare piesa prin care trece. Asta e refractia —
	un cristal aprins constant arata a plastic; unul prin care trece lumina arata
	a cristal. Din cand in cand unul tras la sorti **sclipeste**, se albeste
	brusc si arunca o rafala de scantei.

	**Dragonul.** Deasupra cristalelor pluteste o silueta facuta din piesele
	modelului: trup lung vazut din profil, gat ridicat, coarne date pe spate,
	creasta de tepi pe sira spinarii si o coada care se unduieste. Aripile bat
	din umar, nu din mijloc, fiindca acolo sunt prinse.

	Merge dus-intors, dintr-un capat al obiectului in celalalt, si se intoarce
	la capete — nu da ocol si nu se roteste pe loc.

	Cat timp zidul e doar previzualizare, `Barricade` ridica atributul `Preview`
	si aici nu se mai atinge nicio culoare: verdictul verde/rosu are intaietate.
	Miscarea insa continua — o fantoma inghetata ar arata a obiect stricat.

	Copia de pe disc: `assets/world-scripts/crystal-effects.luau`.
]]

local RunService = game:GetService("RunService")

local model = script.Parent :: Model

-- Doar in lume, niciodata in magazie. Vezi portal: altfel se murdareste sursa.
if not model:IsDescendantOf(workspace) then
	return
end

--[[
	Cautarea unei piese dupa nume, in toata adancimea: soclurile isi imbraca
	piesele intr-un model interior (`podium_crystal`), zidurile nu.
]]
local function piece(name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function collect(patterns: { string }): { BasePart }
	local found: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		for _, pattern in patterns do
			if string.match(part.Name, pattern) then
				table.insert(found, part)
				break
			end
		end
	end
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found
end

--[[
	Cele trei feluri de cristale.

	`spires` sunt cristalele inalte: stalpii zidului si formatiunile soclului.
	`rooted` e ce sta infipt in pamant — tepii dintre bolturi si talpile pe care
	se sprijina aglomerarile. `fragments` sunt cioburile mici care plutesc si
	dau tarcoale locului lor.

	Niciunul dintre primele doua nu se invarte. Se invarteau cioburile din
	mijloc, pe vremea cand erau niste placi late culcate; acum sunt tepi, si un
	tep care se roteste in pamant nu mai e tep.
]]
local spires = collect({ "^crystal_[lr]_%d+$", "^formation_%d+$" })
local rooted = collect({
	"^wall_shard_%d+$",
	"^base_shard_%d+$",
	"^cluster_base_[lr]$",
})
local fragments = collect({ "^fragment_%d+$" })
local wings = collect({ "^drake_wing_" })
local limbs = collect({ "^drake_" })

if #spires == 0 and #rooted == 0 and #limbs == 0 then
	return
end

--[[
	Piesa fata de care se masoara tot.

	Nimic nu se tine minte in coordonatele lumii: soclul pluteste in vitrina,
	zidul cade pe tabla si urmeaza cursorul ca fantoma — iar un cristal tinut
	minte unde era la pornire ar ramane in urma, singur, in mijlocul arenei. Deci
	se tine minte fata de o piesa care nu se misca, si la fiecare cadru se reface
	de acolo.
]]
local animated: { [BasePart]: boolean } = {}
for _, group in { limbs } do
	for _, part in group do
		animated[part] = true
	end
end

local function chooseAnchor(): BasePart?
	if model.PrimaryPart and not animated[model.PrimaryPart] then
		return model.PrimaryPart
	end
	local best: BasePart? = nil
	local bestVolume = -1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not animated[part] then
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

local WHITE = Color3.fromHex("ffffff")

--[[
	Un cristal, asa cum il vede bucla.

	Niciunul nu se muta din loc: singurul lucru care li se schimba e culoarea si
	transparenta, cand trece unda sau cand sclipeste unul. Se leganau pana acum,
	incet, doi dintre ei — dar cum tot de ei se masoara si locul celorlalte
	piese, urca si dragonul odata cu ei. Un cristal care nu sta pe loc nu poate
	fi reper.

	`At` e locul piesei de-a lungul obiectului, intre 0 si 1. Din el iese unda de
	lumina care trece prin ansamblu.
]]
type Crystal = {
	Part: BasePart,
	Base: Color3,
	Rest: number,
	At: number,
	Along: number,
}

local crystals: { Crystal } = {}

local function remember(part: BasePart)
	table.insert(crystals, {
		Part = part,
		Base = part.Color,
		Rest = part.Transparency,
		At = 0,
		Along = home:PointToObjectSpace(part.Position).X,
	})
end

for _, part in spires do
	remember(part)
end
for _, part in rooted do
	remember(part)
end

--[[
	Cat de departe e fiecare cristal de-a lungul obiectului.

	Se masoara, nu se ia din nume: se proiecteaza pe axa lunga a ancorei si se
	intinde intervalul gasit peste 0..1. Asa unda merge in ordinea adevarata si
	ramane corecta si pe soclu, unde cristalele stau in cerc, nu in linie.
]]
do
	local low, high = math.huge, -math.huge
	for _, crystal in crystals do
		low, high = math.min(low, crystal.Along), math.max(high, crystal.Along)
	end
	local span = math.max(high - low, 0.01)
	for _, crystal in crystals do
		crystal.At = (crystal.Along - low) / span
	end
end

--[[
	Cioburile mici stau si ele.

	Dadeau tarcoale locului lor, pe un cerc mic, si se rostogoleau. Dar pe un
	obiect in care nimic altceva nu se clinteste, trei cioburi care se foiesc in
	aer trag ochiul de la singurul lucru care chiar zboara. Le ramane licarul:
	culoarea lor bate spre alb si inapoi, fara sa se mute un fir de pe loc.
]]
type Fragment = {
	Part: BasePart,
	Base: Color3,
	Phase: number,
}

local floaters: { Fragment } = {}

for index, part in fragments do
	floaters[index] = {
		Part = part,
		Base = part.Color,
		Phase = index * 1.37,
	}
end

--[[
	Dragonul.

	Toate piesele lui se tin minte fata de trup, nu fata de model: trupul e
	originea desenului, si tot fata de el se socotesc si bataia aripilor, si
	unduirea cozii.

	Aripa nu se roteste in jurul centrului ei, ci in jurul **umarului** — acolo
	e prinsa de spate. Rotita din mijloc, s-ar invarti ca o elice si s-ar misca
	tocmai prinderea, care trebuie sa stea. Axa e lungimea trupului, deci aripile
	urca si coboara.

	Coada se unduieste in jurul trupului, fiecare inel cu o intarziere fata de
	cel dinainte si cu mai multa amplitudine decat el. De aceea unda pleaca de
	langa sold si se termina in varf, cum se misca o coada adevarata, nu ca un
	brat care se roteste intreg.
]]
type Limb = {
	Part: BasePart,
	Offset: CFrame,
	Side: number,
	Pivot: Vector3,
	Wave: number,
}

local body = piece("drake_body")
local flock: { Limb } = {}
local seatRest = CFrame.identity

if body then
	seatRest = home:ToObjectSpace(body.CFrame)

	local flapping: { [BasePart]: boolean } = {}
	for _, wing in wings do
		flapping[wing] = true
	end

	for _, part in limbs do
		local offset = body.CFrame:ToObjectSpace(part.CFrame)
		local ring = tonumber(string.match(part.Name, "^drake_tail_(%d+)$") or "") or 0
		table.insert(flock, {
			Part = part,
			Offset = offset,
			-- Aripa din stanga si cea din dreapta bat in oglinda.
			Side = if flapping[part] then (if offset.Position.Z < 0 then -1 else 1) else 0,
			-- Umarul: pe spinare, deasupra axei trupului.
			Pivot = Vector3.new(offset.Position.X, 0.1, 0),
			Wave = ring,
		})
	end
end

--[[
	Cat de larg e drumul dragonului.

	Deschiderea se masoara din obiect, nu se scrie de mana: pana unde stau
	cristalele care nu se misca. Jumatate din ea e cursa dus-intors, si e destul
	— la capete dragonul se pune de-a curmezisul ca sa se intoarca, deci nu
	ajunge cu nasul in stalpi nici acolo. Acelasi numar iese si pe zid, unde
	deschiderea e de sase studi, si pe soclu, unde e de doi.
]]
local room = 1
do
	local low, high = math.huge, -math.huge
	for _, part in spires do
		local x = home:PointToObjectSpace(part.Position).X
		low, high = math.min(low, x), math.max(high, x)
	end
	if high > low then
		room = (high - low) / 2
	end
end

local REACH = room * 0.5
local DEPTH = REACH * 0.22
local BOB = 0.12
local PACE = 0.52

-- Cat de repede bat aripile, si cat de mult, in grade.
local FLAP, SWEEP = 2.4, 22

--[[
	Scanteile.

	Nu exista piese anume pentru ele in modelul asta, deci emitatoarele stau pe
	cristalele insele. Fiecare imprumuta culoarea piesei pe care sta si o duce
	spre alb, deci paleta ramane a modelului, nu a scriptului.

	Transparenta urca si coboara de mai multe ori de-a lungul vietii particulei:
	de asta se vede ca sclipesc, nu ca doar plutesc.
]]
local SPARKLE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.15, 0.1),
	NumberSequenceKeypoint.new(0.35, 0.65),
	NumberSequenceKeypoint.new(0.55, 0.05),
	NumberSequenceKeypoint.new(0.8, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})

local SPARKLE_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.45),
	NumberSequenceKeypoint.new(0.5, 0.26),
	NumberSequenceKeypoint.new(1, 0),
})

local sparkles: { [BasePart]: ParticleEmitter } = {}

local function sparkleOn(part: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Shimmer"
	emitter.Color = ColorSequence.new(WHITE, part.Color)
	emitter.Size = SPARKLE_SIZE
	emitter.Transparency = SPARKLE_FADE
	emitter.Lifetime = NumberRange.new(1.1, 2.2)
	emitter.Speed = NumberRange.new(0.4, 1.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.1, 0)
	emitter.Drag = 1.6
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.LightEmission = 0.5
	emitter.LightInfluence = 0
	emitter.Rate = 3.5
	emitter.Parent = part
	sparkles[part] = emitter
end

-- Scanteiaza ce e cristal, nu si talpile plate: alea sunt suport, nu podoaba.
for _, part in spires do
	sparkleOn(part)
end
for _, part in fragments do
	sparkleOn(part)
end
for _, part in rooted do
	if string.match(part.Name, "^wall_shard_%d+$") then
		sparkleOn(part)
	end
end

-- Si o dara in urma aripilor, ca dragonul sa lase ceva dupa el.
for _, wing in wings do
	sparkleOn(wing)
end

--[[
	Lumina.

	Piesele Neon se vad singure, dar nu lumineaza nimic in jur. O lumina in
	miezul aglomerarilor si in capul fluturelui face cristalele sa arunce ceva pe
	plinta si pe podea, si e ce le face sa para pline, nu desenate.
]]
local lamps: { PointLight } = {}

local function lampOn(part: BasePart, range: number)
	local light = Instance.new("PointLight")
	light.Name = "Facet"
	light.Color = part.Color
	light.Range = range
	light.Brightness = 0.45
	light.Shadows = false
	light.Parent = part
	table.insert(lamps, light)
end

for _, part in collect({ "^cluster_core_[lr]$", "^drake_jaw$", "^drake_head$" }) do
	lampOn(part, 9)
end

--[[
	Daca modelul n-are nici miez, nici dragon, lumina se muta pe cele mai mari
	doua cristale. Undeva tot trebuie sa fie, ca altfel Neonul se vede singur si
	nu arunca nimic pe plinta.
]]
if #lamps < 2 then
	local tallest = table.clone(spires)
	table.sort(tallest, function(a, b)
		return a.Size.Y > b.Size.Y
	end)
	for index = 1, math.min(2 - #lamps, #tallest) do
		lampOn(tallest[index], 10)
	end
end

-- Ce are soclul in plus: emblema, razele ei si lumina de sub obiect.
local emblem = piece("emblem_ring")
local emblemInner = piece("emblem_ring_inner")
local hub = piece("emblem_hub")

type Ray = {
	Part: BasePart,
	Offset: CFrame,
}

local rays: { Ray } = {}
if hub then
	for _, part in collect({ "^emblem_point_%d+$" }) do
		table.insert(rays, { Part = part, Offset = hub.CFrame:ToObjectSpace(part.CFrame) })
	end
end

local standGlow = piece("stand_glow")
local standBase = if standGlow then standGlow.Transparency else 0

local tiers = collect({ "^tier_" })
local tierBase: { Color3 } = {}
for index, part in tiers do
	tierBase[index] = part.Color
end

-- Sclipirea: cat tine si cat se asteapta intre doua.
local FLASH = 0.5
local TWINKLE_MIN, TWINKLE_MAX = 1.1, 2.4

local clock = 0
local twinkleIn = TWINKLE_MIN
local flash = 0
local chosen: BasePart? = nil

RunService.Heartbeat:Connect(function(delta: number)
	if not model.Parent then
		return
	end

	clock += delta
	home = anchor.CFrame

	--[[
		Unda de lumina care trece prin obiect.

		Merge de la 0 la 1 si o ia de la capat; un cristal e aprins cat timp unda
		e aproape de locul lui. Diferenta se ia ciclic, ca sa nu sara cand unda
		trece de capat inapoi la inceput.
	]]
	local wave = (clock * 0.32) % 1

	local function litBy(at: number): number
		local distance = math.abs(wave - at)
		distance = math.min(distance, 1 - distance)
		return math.clamp(1 - distance / 0.22, 0, 1)
	end

	-- ------------------------------------------------------------- sclipirea
	if flash > 0 then
		flash -= delta
	else
		twinkleIn -= delta
		if twinkleIn <= 0 and #crystals > 0 then
			local pick = crystals[math.random(#crystals)].Part
			chosen = pick
			flash = FLASH
			twinkleIn = TWINKLE_MIN + math.random() * (TWINKLE_MAX - TWINKLE_MIN)
			local emitter = sparkles[pick]
			if emitter then
				emitter:Emit(math.random(14, 24))
			end
		end
	end

	-- ------------------------------------------------------------- miscarea
	if #flock > 0 then
		--[[
			Drumul dragonului: dus-intors, dintr-un capat in altul.

			Nu pe o linie, ci pe o bucla foarte turtita — lata cat deschiderea si
			adanca de-o palma. Pe linie dreapta ar trebui sa se intoarca brusc la
			capete, si atunci ori zboara cu spatele, ori se suceste pe loc ca un
			ac de busola. Pe bucla, intoarcerea vine de la sine: la capat se pune
			de-a curmezisul, se vede cum vireaza, si se intoarce.

			Incotro priveste iese din **viteza**, nu dintr-un unghi scris de mana:
			nasul merge mereu incotro merge si el. Si se apleaca in viraj, cel mai
			tare la capete, unde intoarcerea e cea mai stransa.
		]]
		local step = clock * PACE
		local travel = CFrame.new(
			REACH * math.sin(step),
			BOB * math.sin(step * 2),
			DEPTH * math.cos(step)
		) * CFrame.Angles(0, math.atan2(DEPTH * math.sin(step), REACH * math.cos(step)), 0) * CFrame.Angles(
			math.sin(step) * 0.35,
			0,
			0
		)

		local seat = home * seatRest * travel
		local flap = math.sin(clock * FLAP) * math.rad(SWEEP)

		for _, limb in flock do
			if limb.Side ~= 0 then
				limb.Part.CFrame = seat
					* CFrame.new(limb.Pivot)
					* CFrame.Angles(flap * limb.Side, 0, 0)
					* CFrame.new(-limb.Pivot)
					* limb.Offset
			elseif limb.Wave > 0 then
				local sway = math.sin(clock * 1.7 - limb.Wave * 0.7) * math.rad(5 * limb.Wave)
				limb.Part.CFrame = seat * CFrame.Angles(0, sway, 0) * limb.Offset
			else
				limb.Part.CFrame = seat * limb.Offset
			end
		end
	end

	if emblem then
		emblem.CFrame = emblem.CFrame * CFrame.Angles(0, delta * 0.4, 0)
	end
	if emblemInner then
		emblemInner.CFrame = emblemInner.CFrame * CFrame.Angles(0, -delta * 0.65, 0)
	end
	if hub then
		local spin = CFrame.Angles(0, clock * 0.5, 0)
		for _, ray in rays do
			ray.Part.CFrame = hub.CFrame * spin * ray.Offset
		end
	end

	-- Verdictul verde/rosu are intaietate cat zidul e doar o parere.
	if model:GetAttribute("Preview") then
		return
	end

	-- -------------------------------------------------------------- lumina
	local glint = if flash > 0 then math.sin(flash / FLASH * math.pi) else 0

	for _, crystal in crystals do
		local lit = litBy(crystal.At)
		local mine = if crystal.Part == chosen then glint else 0
		local level = math.max(lit * 0.75, mine)

		crystal.Part.Color = crystal.Base:Lerp(WHITE, level)
		crystal.Part.Transparency = math.clamp(crystal.Rest - level * 0.22, 0, 1)

		local emitter = sparkles[crystal.Part]
		if emitter then
			emitter.Rate = 3.5 + level * 14
		end
	end

	for index, part in tiers do
		local lit = litBy(((index - 1) / math.max(#tiers - 1, 1) + 0.5) % 1)
		part.Color = tierBase[index]:Lerp(WHITE, lit * 0.4)
	end

	local breath = (math.sin(clock * 1.4) + 1) / 2
	for _, lamp in lamps do
		lamp.Brightness = 0.35 + breath * 0.35 + glint * 0.9
	end

	for _, floater in floaters do
		local shimmer = (math.sin(clock * 2.2 + floater.Phase) + 1) / 2
		floater.Part.Color = floater.Base:Lerp(WHITE, shimmer * 0.5)
	end

	if standGlow then
		standGlow.Transparency = standBase + 0.2 - breath * 0.14 - glint * 0.12
	end
end)
