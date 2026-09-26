--!strict
--[[
	BoardRim — bara de lumina de pe rama tablei, si ce iese din colturile ei.

	Tabla ramane curata: tot ce se aprinde sta pe rama, in afara celulelor. Bara
	e taiata in segmente, noua pe latura plus cele patru colturi, iar fiecare
	segment isi ia culoarea in fiecare cadru din efectele vii. Un efect nu
	misca piese, doar spune, pentru un punct de pe rama si o clipa, ce culoare si
	cata lumina are acolo; bucla le compune pe toate si pastreaza ce e mai
	aprins. Asa doua efecte care se suprapun nu se bat, se aduna.

	Patru trepte, pe marimea callout-ului:

	  Small — doua margele pleaca de unde a cazut zidul, in ambele sensuri, cu
	          coada aurie; colturile pocnesc cand trec pe langa ele
	  Big   — toata rama se aprinde intr-un val care curge, cu confetti din
	          colturi si un fulger alb la impact
	  Mega  — inel curcubeu care bate ca o inima, stalpi de lumina in colturi,
	          arcuri electrice intre ei, o unda de soc si sclipici care cade
	  Combo — seria de blocaje: caruselul se invarte mai repede cu fiecare
	          treapta, flacari colorate pe margini si insigna „x3" pe rama

	Peste ele, `frost`: partea celui blocat ingheata o clipa, albastru si lila.

	Traieste doar pe client. Piesele se pun in modelul tablei, local, si nu se
	replica nicaieri; cand serverul darama masa, pleaca odata cu ea.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local SETTINGS = GameConfig.Rim

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FLAME = "rbxasset://textures/particles/fire_main.dds"

-- Laturile, cu numele lor logice: `Y1` e marginea randului 1, `X9` a coloanei 9.
export type Side = "Y1" | "X9" | "Y9" | "X1"
local SIDES: { Side } = { "Y1", "X9", "Y9", "X1" }

export type Kind = "Small" | "Big" | "Mega"

type Segment = {
	-- Piesele lui: cilindrul si cele doua bile, sau bila din colt. Se coloreaza impreuna.
	Parts: { Part },
	-- Unde sta pe perimetru, de la coltul (1,1), in studi.
	D: number,
	-- Laturile carora le apartine; un colt apartine la doua.
	Sides: { [Side]: boolean },
	-- Ce i s-a scris ultima oara, ca sa nu se rescrie degeaba.
	Lit: boolean,
}

-- Ce spune un efect despre un punct de pe rama, intr-o clipa: culoare si lumina.
type Shade = (d: number, t: number) -> (Color3, number)

type Effect = {
	Began: number,
	Seconds: number,
	Shade: Shade,
}

local BoardRim = {}
BoardRim.__index = BoardRim

type RimFields = {
	Folder: Folder,
	Segments: { Segment },
	-- Centrul barei, la inaltimea ei.
	Center: Vector3,
	-- Axele tablei in lume: spre coloanele mari, spre randurile mari, in sus.
	U: Vector3,
	V: Vector3,
	Up: Vector3,
	-- Jumatatea laturii barei si perimetrul intreg, in studi.
	Half: number,
	Perimeter: number,
	-- Pasul unei celule, dupa care se masoara marimile efectelor.
	Step: number,
	Corners: { Part },
	CornerEmitters: { ParticleEmitter },
	SideEmitters: { [Side]: ParticleEmitter },
	Glow: PointLight,
	Effects: { Effect },
	Loop: RBXScriptConnection?,
	Badge: BillboardGui?,
}

export type BoardRim = typeof(setmetatable({} :: RimFields, BoardRim))

local function hex(value: number): Color3
	return Color3.fromHex(string.format("%06X", value))
end

local function palette(values: { number }): { Color3 }
	local colors = {}
	for _, value in values do
		table.insert(colors, hex(value))
	end
	return colors
end

-- O culoare dintr-o paleta, la pozitia `t` (0..1, circular).
local function sample(colors: { Color3 }, t: number): Color3
	local count = #colors
	local position = (t % 1) * count
	local index = math.floor(position)
	return colors[index + 1]:Lerp(colors[(index + 1) % count + 1], position - index)
end

-- Intrare si iesire moale: urca in `attack`, coboara in ultimele `release` secunde.
local function envelope(t: number, seconds: number, attack: number, release: number): number
	if t < 0 or t > seconds then
		return 0
	end
	if t < attack then
		return t / attack
	end
	if t > seconds - release then
		return math.max(0, (seconds - t) / release)
	end
	return 1
end

local function quietPart(name: string, size: Vector3, frame: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = frame
	part.Parent = parent
	return part
end

local function emitter(parent: Instance): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Enabled = false
	particles.Texture = SPARKLE
	particles.LightEmission = 1
	particles.LightInfluence = 0
	particles.Rate = 0
	particles.Parent = parent
	return particles
end

--[[
	Construieste rama pe o tabla. Intoarce `nil` daca tabla nu are celulele din
	colturi — fara ele nu se stie nici marimea, nici directia ei.

	`cellTop` e al platformei: centrul fetei unei celule, in lume.
]]
function BoardRim.new(
	parent: Instance,
	cellTop: (number, number) -> Vector3?,
	size: number
): BoardRim?
	local first, alongU, alongV, far =
		cellTop(1, 1), cellTop(size, 1), cellTop(1, size), cellTop(size, size)
	local second = cellTop(2, 1)
	if not (first and alongU and alongV and far and second) then
		return nil
	end

	local self = setmetatable({}, BoardRim) :: BoardRim
	self.U = (alongU - first).Unit
	self.V = (alongV - first).Unit
	local up = self.U:Cross(self.V).Unit
	self.Up = if up.Y < 0 then -up else up
	self.Step = (second - first).Magnitude
	self.Half = self.Step * SETTINGS.Offset
	self.Perimeter = self.Half * 8
	self.Center = (first + far) / 2 + self.Up * (self.Step * SETTINGS.Drop)
	self.Effects = {}
	self.Segments = {}
	self.Corners = {}
	self.CornerEmitters = {}
	self.SideEmitters = {}

	local folder = Instance.new("Folder")
	folder.Name = "BoardRim"
	folder.Parent = parent
	self.Folder = folder

	local side = self.Half * 2
	local perSide = size
	local length = side / perSide
	local width, thickness = SETTINGS.Width, SETTINGS.Thickness

	for sideIndex, name: Side in SIDES do
		local origin = (sideIndex - 1) * side

		-- Coltul de la inceputul laturii: apartine si laturii dinainte.
		local previous: Side = SIDES[(sideIndex - 2) % 4 + 1]
		local cornerAt = self:pointAt(origin)
		local knob = width * 1.5
		local corner = quietPart(
			"Corner_" .. name,
			Vector3.new(knob, knob, knob),
			CFrame.fromMatrix(cornerAt + self.Up * knob * 0.2, self.U, self.Up),
			folder
		)
		corner.Shape = Enum.PartType.Ball
		table.insert(self.Corners, corner)
		local cornerSides: { [Side]: boolean } = {}
		cornerSides[name] = true
		cornerSides[previous] = true
		local cornerSegment: Segment = {
			Parts = { corner },
			D = origin,
			Sides = cornerSides,
			Lit = true,
		}
		table.insert(self.Segments, cornerSegment)
		local cornerAttachment = Instance.new("Attachment")
		cornerAttachment.Parent = corner
		table.insert(self.CornerEmitters, emitter(cornerAttachment))

		local direction = self:directionAt(origin + 0.01)
		--[[
			Fiecare segment e o pastila: un cilindru culcat cu cate o bila la
			capete. Asezata pe jumatate in rama, se vede ca o bara rotunda, fara
			muchiile drepte ale unui bloc.
		]]
		local radius = width / 2
		local body = length * 0.9 - width
		for index = 1, perSide do
			local d = origin + (index - 0.5) * length
			local center = self:pointAt(d) + self.Up * radius * 0.35
			local rod = quietPart(
				string.format("Rim_%s_%d", name, index),
				Vector3.new(body, width, width),
				CFrame.fromMatrix(center, direction, self.Up),
				folder
			)
			rod.Shape = Enum.PartType.Cylinder
			local parts = { rod }
			for _, sign in { -1, 1 } do
				local cap = quietPart(
					string.format("Rim_%s_%d_cap", name, index),
					Vector3.new(width, width, width),
					CFrame.new(center + direction * sign * body / 2),
					folder
				)
				cap.Shape = Enum.PartType.Ball
				table.insert(parts, cap)
			end
			local sides: { [Side]: boolean } = {}
			sides[name] = true
			local segment: Segment = { Parts = parts, D = d, Sides = sides, Lit = true }
			table.insert(self.Segments, segment)
		end

		-- O placa nevazuta cat latura, din care ies flacarile si fulgii.
		local strip = quietPart(
			"Strip_" .. name,
			Vector3.new(side * 0.95, 0.2, width),
			CFrame.fromMatrix(
				self:pointAt(origin + side / 2) + self.Up * thickness,
				direction,
				self.Up
			),
			folder
		)
		strip.Transparency = 1
		self.SideEmitters[name] = emitter(strip)
	end

	local glowPart = quietPart(
		"Glow",
		Vector3.new(1, 1, 1),
		CFrame.new(self.Center + self.Up * self.Step * 2),
		folder
	)
	glowPart.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Range = self.Half * 1.6
	glow.Brightness = 0
	glow.Parent = glowPart
	self.Glow = glow

	self:rest()
	return self
end

-- Punctul de pe rama aflat la `d` studi pe perimetru, pornind din coltul (1,1).
function BoardRim.pointAt(self: BoardRim, d: number): Vector3
	local h = self.Half
	local side = h * 2
	local wrapped = d % self.Perimeter
	local index = math.floor(wrapped / side)
	local f = wrapped - index * side
	local u, v
	if index == 0 then
		u, v = -h + f, -h
	elseif index == 1 then
		u, v = h, -h + f
	elseif index == 2 then
		u, v = h - f, h
	else
		u, v = -h, h - f
	end
	return self.Center + self.U * u + self.V * v
end

-- Directia in care inainteaza perimetrul la `d`.
function BoardRim.directionAt(self: BoardRim, d: number): Vector3
	local index = math.floor((d % self.Perimeter) / (self.Half * 2))
	if index == 0 then
		return self.U
	elseif index == 1 then
		return self.V
	elseif index == 2 then
		return -self.U
	end
	return -self.V
end

-- Cel mai apropiat punct de pe rama de un loc din lume, ca pozitie pe perimetru.
function BoardRim.project(self: BoardRim, world: Vector3): number
	local h = self.Half
	local side = h * 2
	local offset = world - self.Center
	local u = math.clamp(offset:Dot(self.U), -h, h)
	local v = math.clamp(offset:Dot(self.V), -h, h)
	if math.abs(v) >= math.abs(u) then
		return if v < 0 then u + h else 2 * side + (h - u)
	end
	return if u > 0 then side + (v + h) else 3 * side + (h - v)
end

-- Latura cea mai apropiata de un loc din lume.
function BoardRim.sideOf(self: BoardRim, world: Vector3): Side
	local index = math.floor(self:project(world) / (self.Half * 2)) % 4
	return SIDES[index + 1]
end

-- Mijlocul unei laturi, in lume.
function BoardRim.middleOf(self: BoardRim, side: Side): Vector3
	local index = table.find(SIDES, side) or 1
	return self:pointAt((index - 0.5) * self.Half * 2)
end

-- Cum arata un segment: aprins, sau stins in culoarea de repaus.
local function dress(segment: Segment, material: Enum.Material, color: Color3, transparency: number)
	for _, part in segment.Parts do
		part.Material = material
		part.Color = color
		part.Transparency = transparency
	end
end

-- Bara in repaus: un sant inchis in rama.
function BoardRim.rest(self: BoardRim)
	local color = hex(SETTINGS.RestColor)
	for _, segment in self.Segments do
		if segment.Lit then
			dress(segment, Enum.Material.SmoothPlastic, color, SETTINGS.RestTransparency)
			segment.Lit = false
		end
	end
end

-- Un cadru: fiecare segment ia ce e mai aprins din efectele vii.
function BoardRim.paint(self: BoardRim)
	local now = os.clock()
	for index = #self.Effects, 1, -1 do
		local effect = self.Effects[index]
		if now - effect.Began > effect.Seconds then
			table.remove(self.Effects, index)
		end
	end

	if #self.Effects == 0 then
		self:rest()
		local loop = self.Loop
		if loop then
			loop:Disconnect()
			self.Loop = nil
		end
		return
	end

	local restColor = hex(SETTINGS.RestColor)
	for _, segment in self.Segments do
		local best, color = 0, restColor
		for _, effect in self.Effects do
			local tint, light = effect.Shade(segment.D, now - effect.Began)
			if light > best then
				best, color = light, tint
			end
		end

		if best > 0.03 then
			dress(segment, Enum.Material.Neon, color, 1 - math.clamp(best, 0, 1) * 0.95)
			segment.Lit = true
		elseif segment.Lit then
			dress(segment, Enum.Material.SmoothPlastic, restColor, SETTINGS.RestTransparency)
			segment.Lit = false
		end
	end
end

function BoardRim.add(self: BoardRim, seconds: number, shade: Shade)
	table.insert(self.Effects, { Began = os.clock(), Seconds = seconds, Shade = shade })
	if not self.Loop then
		self.Loop = RunService.RenderStepped:Connect(function()
			self:paint()
		end)
	end
end

-- Un fulger alb de lumina peste tabla, la impact.
function BoardRim.flash(self: BoardRim, brightness: number, seconds: number)
	self.Glow.Color = Color3.new(1, 1, 1)
	self.Glow.Brightness = brightness
	TweenService
		:Create(self.Glow, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { Brightness = 0 })
		:Play()
end

--[[
	O rafala de particule. Emitatorul e acelasi pentru toate efectele, deci se
	potriveste inainte de fiecare `Emit`: ce culoare, ce forma, cat de repede.
]]
local function burst(
	particles: ParticleEmitter,
	count: number,
	colors: { Color3 },
	options: {
		Texture: string?,
		Size: number,
		Speed: number,
		Life: number,
		Fall: number?,
		Spread: number?,
	}
)
	local points = {}
	for index, color in colors do
		table.insert(
			points,
			ColorSequenceKeypoint.new((index - 1) / math.max(#colors - 1, 1), color)
		)
	end
	if #points == 1 then
		table.insert(points, ColorSequenceKeypoint.new(1, colors[1]))
	end
	particles.Texture = options.Texture or SPARKLE
	particles.Color = ColorSequence.new(points)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, options.Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new(0)
	particles.Speed = NumberRange.new(options.Speed * 0.6, options.Speed)
	particles.Lifetime = NumberRange.new(options.Life * 0.7, options.Life)
	particles.Acceleration = Vector3.new(0, -(options.Fall or 0), 0)
	particles.SpreadAngle = Vector2.new(options.Spread or 35, options.Spread or 35)
	particles.EmissionDirection = Enum.NormalId.Top
	particles.RotSpeed = NumberRange.new(-180, 180)
	particles.Rotation = NumberRange.new(0, 360)
	particles:Emit(count)
end

-- ------------------------------------------------------------ treptele

--[[
	Small: doua margele din punctul de impact, una in fiecare sens, pana se
	intalnesc de partea cealalta. Cand trec pe langa un colt, coltul pocneste.
]]
function BoardRim.small(self: BoardRim, origin: Vector3)
	local colors = palette(SETTINGS.Palettes.Small)
	local seconds = SETTINGS.Seconds.Small
	local start = self:project(origin)
	local travel = seconds * 0.8
	local speed = (self.Perimeter / 2) / travel
	local tail = self.Perimeter * 0.12
	local perimeter = self.Perimeter

	self:add(seconds, function(d: number, t: number): (Color3, number)
		local best, tint = 0, colors[1]
		for _, sign in { 1, -1 } do
			local head = start + sign * speed * math.min(t, travel)
			local behind = ((head - d) * sign) % perimeter
			if behind < tail then
				local light = (1 - behind / tail) ^ 1.5 * envelope(t, seconds, 0.04, 0.25)
				if light > best then
					best, tint = light, sample(colors, behind / tail * 0.66)
				end
			end
		end
		return tint, best
	end)

	-- Colturile pocnesc la trecerea primei margele.
	for index, corner in self.Corners do
		local cornerD = (index - 1) * self.Half * 2
		local ahead = math.min((cornerD - start) % perimeter, (start - cornerD) % perimeter)
		task.delay(ahead / speed, function()
			if corner.Parent then
				burst(
					self.CornerEmitters[index],
					6,
					colors,
					{ Size = 0.5, Speed = 9, Life = 0.6, Fall = 12 }
				)
			end
		end)
	end
end

--[[
	Big: val in gradient pe toata rama, fulger alb la impact si confetti din
	cele patru colturi.
]]
function BoardRim.big(self: BoardRim)
	local colors = palette(SETTINGS.Palettes.Big)
	local seconds = SETTINGS.Seconds.Big
	local perimeter = self.Perimeter
	local white = Color3.new(1, 1, 1)

	self:add(seconds, function(d: number, t: number): (Color3, number)
		if t < 0.1 then
			return white, 1
		end
		local x = d / perimeter
		local wave = 0.55 + 0.45 * math.sin(math.pi * 2 * (x * 3 - t * 1.6))
		return sample(colors, x * 2 - t * 0.8), envelope(t, seconds, 0.1, 0.7) * wave
	end)

	self:flash(4, 0.45)
	for _, particles in self.CornerEmitters do
		burst(particles, 22, colors, { Size = 0.7, Speed = 22, Life = 1.3, Fall = 30, Spread = 25 })
	end
end

--[[
	Mega: inelul curcubeu care bate ca o inima, stalpii din colturi cu arcuri
	intre ei, unda de soc pe podea si sclipiciul care cade dupa.
]]
function BoardRim.mega(self: BoardRim)
	local rainbow = palette(SETTINGS.Palettes.Rainbow)
	local seconds = SETTINGS.Seconds.Mega
	local perimeter = self.Perimeter
	local white = Color3.new(1, 1, 1)

	-- Doua batai apropiate, apoi pauza: ritmul unei inimi, nu al unui stroboscop.
	local function heartbeat(t: number): number
		local x = t % 0.8
		return 0.5
			+ 0.5
				* math.max(math.exp(-((x / 0.07) ^ 2)), 0.6 * math.exp(-(((x - 0.22) / 0.07) ^ 2)))
	end

	self:add(seconds, function(d: number, t: number): (Color3, number)
		if t < 0.12 then
			return white, 1
		end
		return sample(rainbow, d / perimeter - t * 0.35),
			envelope(t, seconds, 0.05, 0.9) * heartbeat(t)
	end)

	self:flash(7, 0.7)
	self:pillars(rainbow)
	self:shockwave()

	for _, particles in self.CornerEmitters do
		burst(
			particles,
			30,
			rainbow,
			{ Size = 0.8, Speed = 30, Life = 1.6, Fall = 30, Spread = 20 }
		)
	end

	-- Sclipiciul: dupa impact, cade incet peste tabla.
	task.delay(0.6, function()
		for _, particles in self.SideEmitters do
			burst(
				particles,
				25,
				rainbow,
				{ Size = 0.45, Speed = 14, Life = 3.2, Fall = 5, Spread = 60 }
			)
		end
	end)
end

-- Stalpii de lumina din colturi, si arcurile care sar intre ei.
function BoardRim.pillars(self: BoardRim, rainbow: { Color3 })
	local height = self.Step * 2.4
	local tops: { Attachment } = {}
	local made: { Instance } = {}

	for index, corner in self.Corners do
		local base = corner.Position
		local pillar = quietPart(
			"Pillar",
			Vector3.new(height, SETTINGS.Width * 1.4, SETTINGS.Width * 1.4),
			CFrame.fromMatrix(base + self.Up * height / 2, self.Up, self.U),
			self.Folder
		)
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Material = Enum.Material.Neon
		pillar.Color = rainbow[(index - 1) % #rainbow + 1]
		pillar.Transparency = 0.1
		TweenService
			:Create(pillar, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			})
			:Play()
		table.insert(made, pillar)

		local top = Instance.new("Attachment")
		top.Position = Vector3.new(height / 2, 0, 0)
		top.Parent = pillar
		table.insert(tops, top)
	end

	local beams: { Beam } = {}
	for index, top in tops do
		local beam = Instance.new("Beam")
		beam.Attachment0 = top
		beam.Attachment1 = tops[index % #tops + 1]
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 0.5
		beam.Width1 = 0.5
		beam.Segments = 24
		beam.Color = ColorSequence.new(rainbow[index % #rainbow + 1], Color3.new(1, 1, 1))
		beam.Parent = top.Parent
		table.insert(beams, beam)
	end

	-- Arcurile tremura: curbura se alege din nou de cateva ori pe secunda.
	task.spawn(function()
		local began = os.clock()
		while os.clock() - began < 1.3 do
			for _, beam in beams do
				if beam.Parent then
					beam.CurveSize0 = (math.random() * 2 - 1) * self.Step
					beam.CurveSize1 = (math.random() * 2 - 1) * self.Step
					beam.Transparency = NumberSequence.new((os.clock() - began) / 1.3)
				end
			end
			task.wait(0.08)
		end
		for _, beam in beams do
			beam:Destroy()
		end
	end)

	task.delay(2, function()
		for _, part in made do
			part:Destroy()
		end
	end)
end

-- Unda de soc: un inel care porneste de sub tabla si se intinde pe podea.
function BoardRim.shockwave(self: BoardRim)
	local span = self.Half * 2
	local ring = quietPart(
		"Shockwave",
		Vector3.new(0.2, span * 1.1, span * 1.1),
		CFrame.fromMatrix(self.Center - self.Up * 0.5, self.Up, self.U),
		self.Folder
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromHex("FFD6F5")
	ring.Transparency = 0.35
	local grow = TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quart), {
		Size = Vector3.new(0.2, span * 2.4, span * 2.4),
		Transparency = 1,
	})
	grow.Completed:Once(function()
		ring:Destroy()
	end)
	grow:Play()
end

--[[
	Seria: caruselul de culori se invarte cu atat mai repede cu cat seria e mai
	lunga, flacarile danseaza pe margini si insigna sare pe rama.
]]
function BoardRim.combo(self: BoardRim, streak: number, origin: Vector3)
	local colors = palette(SETTINGS.Palettes.Combo)
	local seconds = SETTINGS.Seconds.Combo
	local perimeter = self.Perimeter
	local speed = 0.25 + 0.2 * streak
	local bright = math.min(1, 0.55 + 0.15 * streak)

	self:add(seconds, function(d: number, t: number): (Color3, number)
		local x = d / perimeter
		local flicker = 0.75 + 0.25 * math.sin(math.pi * 2 * (x * 9 + t * speed * 4))
		return sample(colors, x * 2 + t * speed), envelope(t, seconds, 0.1, 0.6) * bright * flicker
	end)

	-- Flacarile: fiecare treapta mai adauga cateva, in nuante care se schimba.
	task.spawn(function()
		local rounds = 3 + streak
		for round = 1, rounds do
			for index, name: Side in SIDES do
				local tint = colors[(round + index) % #colors + 1]
				burst(self.SideEmitters[name], 2 + streak, { tint, Color3.new(1, 1, 1) }, {
					Texture = FLAME,
					Size = 0.9,
					Speed = 4,
					Life = 0.7,
					Fall = -6,
					Spread = 15,
				})
			end
			task.wait(seconds * 0.7 / rounds)
		end
	end)

	self:badge(streak, self:middleOf(self:sideOf(origin)), seconds)
end

-- Insigna „x3" pe rama, cu saltul ei elastic.
function BoardRim.badge(self: BoardRim, streak: number, at: Vector3, seconds: number)
	local previous = self.Badge
	if previous then
		previous:Destroy()
	end

	local anchor = quietPart(
		"BadgeAnchor",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(at + self.Up * 1.2),
		self.Folder
	)
	anchor.Transparency = 1

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(6, 3)
	gui.StudsOffsetWorldSpace = self.Up * 2
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor

	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = gui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "x" .. streak
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = hex(0x2A1A0E)
	stroke.Thickness = 3
	stroke.Parent = label

	local gradient = Instance.new("UIGradient")
	gradient.Color =
		ColorSequence.new(hex(SETTINGS.Palettes.Combo[1]), hex(SETTINGS.Palettes.Combo[2]))
	gradient.Rotation = 90
	gradient.Parent = label

	self.Badge = gui

	-- Intrarea elastica, apoi un mic salt la fiecare jumatate de secunda.
	TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Scale = 1 }):Play()
	task.spawn(function()
		task.wait(0.6)
		while gui.Parent and self.Badge == gui do
			scale.Scale = 1.18
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { Scale = 1 })
				:Play()
			task.wait(0.5)
		end
	end)

	task.delay(seconds, function()
		if gui.Parent then
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			task.wait(0.35)
			anchor:Destroy()
			if self.Badge == gui then
				self.Badge = nil
			end
		end
	end)
end

--[[
	Frost: partea celui blocat ingheata. Albastru ca gheata si lila, cu o
	sclipire care trece peste ea si fulgi mici — „au", dar nu pedeapsa.
]]
function BoardRim.frost(self: BoardRim, side: Side)
	local colors = palette(SETTINGS.Palettes.Frost)
	local seconds = SETTINGS.Seconds.Frost
	local perimeter = self.Perimeter
	local members: { [number]: boolean } = {}
	for _, segment in self.Segments do
		if segment.Sides[side] then
			members[segment.D] = true
		end
	end

	self:add(seconds, function(d: number, t: number): (Color3, number)
		if not members[d] then
			return colors[1], 0
		end
		local shimmer = 0.5 + 0.5 * math.sin(math.pi * 2 * (d / perimeter * 6 - t * 1.2))
		return sample(colors, shimmer * 0.66),
			envelope(t, seconds, 0.15, 0.9) * (0.7 + 0.3 * shimmer)
	end)

	burst(
		self.SideEmitters[side],
		30,
		colors,
		{ Size = 0.45, Speed = 3, Life = 1.8, Fall = -1.5, Spread = 70 }
	)
end

--[[
	Victoria: rama se invarte in curcubeu, cu culoarea castigatorului in frunte,
	stalpii se ridica din colturi, iar confetti si sclipici cad in cateva
	valuri. Tine mai mult decat orice alt efect: e sfarsitul meciului, si
	ramane pe ecran cat urca podiumul si se uita omul la el.
]]
function BoardRim.victory(self: BoardRim, accent: Color3?)
	local rainbow = palette(SETTINGS.Palettes.Rainbow)
	if accent then
		table.insert(rainbow, 1, accent)
	end
	local seconds = SETTINGS.Seconds.Victory
	local perimeter = self.Perimeter
	local white = Color3.new(1, 1, 1)

	self:add(seconds, function(d: number, t: number): (Color3, number)
		if t < 0.15 then
			return white, 1
		end
		local x = d / perimeter
		local sparkle = 0.7 + 0.3 * math.sin(math.pi * 2 * (x * 8 - t * 3))
		return sample(rainbow, x * 2 - t * 0.6), envelope(t, seconds, 0.2, 1.2) * sparkle
	end)

	self:flash(5, 0.8)
	self:pillars(rainbow)
	self:shockwave()

	task.spawn(function()
		for _ = 1, 4 do
			if not self.Folder.Parent then
				return
			end
			for _, particles in self.CornerEmitters do
				burst(
					particles,
					18,
					rainbow,
					{ Size = 0.8, Speed = 26, Life = 1.5, Fall = 28, Spread = 25 }
				)
			end
			for _, particles in self.SideEmitters do
				burst(
					particles,
					12,
					rainbow,
					{ Size = 0.45, Speed = 12, Life = 2.8, Fall = 5, Spread = 60 }
				)
			end
			task.wait(seconds / 5)
		end
	end)
end

function BoardRim.destroy(self: BoardRim)
	local loop = self.Loop
	if loop then
		loop:Disconnect()
		self.Loop = nil
	end
	self.Effects = {}
	self.Folder:Destroy()
end

return BoardRim
