--!strict
--[[
	Fireworks — artificiile de deasupra castigatorului.

	Ruleaza pe server, ca tot ce tine de arena: finalul meciului e un lucru pe
	care il vad toti deodata, nu o bucurie desenata separat in browserul
	fiecaruia. De aici vine si singura ciudatenie din fisier: rafalele nu se dau
	cu `Emit`, care e o chemare de metoda si nu traverseaza reteaua, ci cu
	`Rate` — o proprietate aprinsa o clipa si stinsa la loc se replica la toata
	lumea, fara niciun canal in plus.

	Nu cere niciun asset. Textura implicita a unui `ParticleEmitter` e chiar
	sclipirea din clientul Roblox, deci artificiile exista si intr-un place in
	care nu s-a importat inca nimic — la fel ca restul jocului, care merge mai
	departe si fara mesh-uri.

	Culorile vin de afara, din skinul echipat de castigator: cine termina meciul
	cu podiumul `dragon` primeste artificii portocalii, cine il are pe `portal`,
	violete. Modulul nu alege nicio culoare singur; are doar una de rezerva, aurie,
	pentru cand nu i se spune nimic.

	Tot ce porneste de aici se opreste din functia intoarsa de `celebrate`. Nimic
	nu ramane sa bata in gol dupa ce masa a fost stransa.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Fireworks = {}

export type Options = {
	-- Culoarea temei castigatorului. Scanteile mor in ea, dupa ce se nasc albe.
	Color: Color3?,
	-- Culoarea clipei de la inceput: lumina rachetei si miezul exploziei.
	Accent: Color3?,
	-- Cat de departe de centru pornesc rachetele, in studi.
	Radius: number?,
	-- Cat de sus urca inainte sa se desfaca.
	Height: number?,
	-- Secunde intre doua rachete.
	Interval: number?,
}

local DEFAULTS = {
	Color = Color3.fromHex("FFB347"),
	Accent = Color3.fromHex("FFF6E0"),
	Radius = 14,
	Height = 18,
	Interval = 0.5,
}

--[[
	Cat sta gura emitatorului deschisa pentru o rafala.

	Numarul de scantei iese din `Rate * PULSE`, deci o suta de milisecunde la un
	ritm de o mie inseamna o explozie de vreo suta de sclipiri. Mai lung, rafala
	incepe sa semene cu un jet; mai scurt, se pierde pe o conexiune care
	esantioneaza proprietatile mai rar decat le schimbam noi.
]]
local PULSE = 0.09

--[[
	Cat mai traieste in lume piesa care a purtat rafala.

	Emitatorul s-a stins demult; ce mai e de asteptat sunt scanteile deja
	plecate, care traiesc cat le spune `Lifetime`. Stearsa mai devreme, piesa le
	ia cu ea si explozia dispare la jumatate, ca si cum s-ar fi taiat curentul.
]]
local BURST_LIFE = 2.6

-- Cat urca o racheta pana in varf.
local CLIMB = 0.55

--[[
	Cum se sting scanteile: tin culoarea aproape tot drumul si abia la capat
	dispar. O stingere liniara le face cenusii la mijlocul vietii, si artificiul
	pare filmat prin ceata.
]]
local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.7, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local SHRINK = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1.3),
	NumberSequenceKeypoint.new(1, 0),
})

--[[
	Piesa care poarta un efect: nevazuta, netrecuta prin fizica si transparenta
	razelor. Nu e decor, e doar un loc din lume de care se agata particulele.
]]
local function marker(parent: Instance, at: Vector3, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(at)
	part.Parent = parent
	return part
end

--[[
	Aprinde emitatorul cat o rafala si il stinge la loc.

	Pe fir separat, ca cel care a cerut rafala sa nu astepte dupa ea: la o
	explozie se aprind doua guri deodata, si a doua n-are de ce sa inceapa cu o
	zecime de secunda mai tarziu decat prima.
]]
local function pulse(emitter: ParticleEmitter, rate: number)
	emitter.Rate = rate
	task.delay(PULSE, function()
		if emitter.Parent then
			emitter.Rate = 0
		end
	end)
end

-- Explozia: un miez iute si alb, o coroana lenta in culoarea temei, si o lumina.
local function burst(parent: Instance, at: Vector3, color: Color3, accent: Color3)
	local shell = marker(parent, at, "Burst")

	local core = Instance.new("ParticleEmitter")
	core.Color = ColorSequence.new(accent, color)
	core.Size = SHRINK
	core.Transparency = FADE
	core.Lifetime = NumberRange.new(0.6, 1.2)
	core.Speed = NumberRange.new(26, 44)
	core.SpreadAngle = Vector2.new(180, 180)
	core.Acceleration = Vector3.new(0, -26, 0)
	core.Drag = 3.5
	core.Rotation = NumberRange.new(0, 360)
	core.RotSpeed = NumberRange.new(-160, 160)
	--[[
		Lumina proprie, si niciuna imprumutata. Artificiul e sursa de lumina din
		scena aia, nu un obiect luminat de soare: lasat sa primeasca lumina
		lumii, ar fi aratat cenusiu pe partea intoarsa de la ea.
	]]
	core.LightEmission = 1
	core.LightInfluence = 0
	core.Rate = 0
	core.Parent = shell

	--[[
		Coroana: aceleasi scantei, dar grele si molcome. Ea e cea care se vede
		cazand dupa ce miezul s-a stins, si fara ea explozia se termina brusc.
	]]
	local embers = core:Clone()
	embers.Color = ColorSequence.new(color, accent)
	embers.Lifetime = NumberRange.new(1.2, 2.1)
	embers.Speed = NumberRange.new(8, 18)
	embers.Acceleration = Vector3.new(0, -14, 0)
	embers.Drag = 1.6
	embers.Parent = shell

	local flash = Instance.new("PointLight")
	flash.Color = accent
	flash.Range = 26
	flash.Brightness = 5
	flash.Shadows = false
	flash.Parent = shell
	TweenService:Create(flash, TweenInfo.new(0.45), { Brightness = 0 }):Play()

	pulse(core, 900)
	pulse(embers, 420)

	Debris:AddItem(shell, BURST_LIFE)
end

--[[
	Racheta: urca si se desface in varf.

	Incetineste spre capat (`Quad Out`), fiindca asta face si una adevarata —
	pleaca impinsa si ajunge sus fara nimic care s-o mai impinga. O urcare cu
	viteza constanta se citeste ca un lift, nu ca o racheta.
]]
local function rocket(parent: Instance, from: Vector3, to: Vector3, color: Color3, accent: Color3)
	local head = Instance.new("Part")
	head.Name = "Rocket"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(0.5, 0.5, 0.5)
	head.Material = Enum.Material.Neon
	head.Color = accent
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = false
	head.CanTouch = false
	head.CFrame = CFrame.new(from)
	head.Parent = parent

	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(accent, color)
	trail.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = FADE
	trail.Lifetime = NumberRange.new(0.25, 0.5)
	trail.Speed = NumberRange.new(1, 3)
	trail.SpreadAngle = Vector2.new(20, 20)
	trail.Acceleration = Vector3.new(0, -8, 0)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Rate = 90
	trail.Parent = head

	local climb = TweenService:Create(
		head,
		TweenInfo.new(CLIMB, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(to) }
	)
	climb.Completed:Connect(function()
		if head.Parent then
			burst(parent, to, color, accent)
			head:Destroy()
		end
	end)
	climb:Play()

	-- Plasa de siguranta: daca tween-ul nu isi mai duce treaba la capat —
	-- arena stearsa la mijloc — racheta nu are voie sa ramana agatata in aer.
	Debris:AddItem(head, CLIMB + 1)
end

--[[
	Sarbatoarea, pornita in jurul unui punct. Intoarce functia care o opreste.

	Doua lucruri deodata: o fantana de sclipiri chiar pe soclu, care tine cat
	tine si ceremonia, si rachete care pleaca de pe tabla din jur, una dupa alta,
	fiecare din alta parte. Fantana e cea care leaga efectul de om; rachetele
	sunt cele care fac sarbatoarea.
]]
function Fireworks.celebrate(parent: Instance, at: CFrame, options: Options?): () -> ()
	local given: Options = options or {}
	local color = given.Color or DEFAULTS.Color
	local accent = given.Accent or DEFAULTS.Accent
	local radius = given.Radius or DEFAULTS.Radius
	local height = given.Height or DEFAULTS.Height
	local interval = given.Interval or DEFAULTS.Interval

	local center = at.Position

	local fountain = marker(parent, center, "Cheer")
	local glitter = Instance.new("ParticleEmitter")
	glitter.Color = ColorSequence.new(accent, color)
	glitter.Size = SHRINK
	glitter.Transparency = FADE
	glitter.Lifetime = NumberRange.new(1.1, 2)
	glitter.Speed = NumberRange.new(14, 24)
	-- Ingusta si in sus: e o fantana, nu o explozie. Un con larg ar imbraca
	-- avatarul in scantei si nu i s-ar mai vedea fata.
	glitter.SpreadAngle = Vector2.new(22, 22)
	glitter.Acceleration = Vector3.new(0, -32, 0)
	glitter.Rotation = NumberRange.new(0, 360)
	glitter.RotSpeed = NumberRange.new(-120, 120)
	glitter.LightEmission = 1
	glitter.LightInfluence = 0
	glitter.Rate = 26
	glitter.Parent = fountain

	local launcher = task.spawn(function()
		while true do
			--[[
				Fiecare racheta pleaca din alt punct al cercului si se desface la
				alta inaltime. Doua rachete identice una dupa alta se citesc ca o
				bucla, nu ca o sarbatoare.
			]]
			local angle = math.random() * math.pi * 2
			local reach = radius * (0.55 + math.random() * 0.45)
			local start = center + Vector3.new(math.cos(angle) * reach, 1, math.sin(angle) * reach)
			local top = start
				+ Vector3.new(
					(math.random() - 0.5) * 6,
					height * (0.7 + math.random() * 0.5),
					(math.random() - 0.5) * 6
				)

			rocket(parent, start, top, color, accent)
			task.wait(interval * (0.7 + math.random() * 0.6))
		end
	end)

	return function()
		if coroutine.status(launcher) ~= "dead" then
			task.cancel(launcher)
		end
		if fountain.Parent then
			--[[
				Fantana se stinge, nu se sterge. Stearsa pe loc, ar lua cu ea si
				sclipirile aflate in aer, si s-ar vedea cum dispare o jumatate de
				jet; asa se opreste jetul si ce a plecat deja cade pana la capat.
			]]
			glitter.Rate = 0
			Debris:AddItem(fountain, BURST_LIFE)
		end
	end
end

return Fireworks
