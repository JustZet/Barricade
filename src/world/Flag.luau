--!strict
--[[
	Flag — panza unui steag care flutura.

	Steagurile din lobby sunt MeshPart-uri rigide, sculptate deja in val: n-au
	oase si n-au textura, deci nu exista material de simulat. Ce se poate face,
	si ce face modulul asta, e sa le *miste*. O panza care se leagana in jurul
	stalpului citeste "vant" chiar daca forma ei nu se schimba niciodata.

	Balamaua e axa verticala a stalpului, nu centrul panzei. Un steag rotit in
	jurul propriului centru se invarte ca o elice; unul rotit in jurul stalpului
	matura aerul cu marginea libera, adica exact ce face un steag adevarat.
	Stalpul, talpa si varful raman pe loc — se misca doar panza.

	Miscarea are trei componente, toate mici:

	  Sway  — leganarea in jurul stalpului; marginea libera pleaca si vine
	  Lift  — capatul departat urca si coboara
	  Twist — panza se rasuceste in jurul propriei axe lungi

	Perioadele lor sunt alese dinadins fara numitor comun. Doua sinusoide intr-un
	raport simplu se aduna intr-un ritm pe care ochiul il prinde in cateva
	secunde, si dupa aceea obiectul arata a jucarie mecanica, nu a panza. Trei
	perioade care nu se imparte una la alta nu se repeta niciodata vizibil.

	Din acelasi motiv leganarea nu e o sinusoida curata, ci una cu o a doua
	armonica mai iute peste ea: un steag adevarat nu se misca lin, ci pocneste.

	Ruleaza pe client si nu se replica, exact ca `Hover`: fiecare jucator isi
	flutura singur decorul. Opt panze trimise prin retea de saizeci de ori pe
	secunda ar fi trafic pentru ceva ce nimeni nu verifica.
]]

local RunService = game:GetService("RunService")

local Ripple = require(script.Parent.Ripple)

local Flag = {}

export type Options = {
	-- Amplitudinea leganarii in jurul stalpului, in grade.
	Sway: number?,
	-- Secunde pentru un ciclu complet de leganare.
	SwayPeriod: number?,
	-- Cat urca si coboara capatul liber, in grade fata de orizontala.
	Lift: number?,
	LiftPeriod: number?,
	-- Rasucirea panzei in jurul axei ei lungi, in grade.
	Twist: number?,
	TwistPeriod: number?,
	-- Decalajul de start, in secunde.
	Phase: number?,
	--[[
		Ondularea, dusa mai departe la `Ripple`. Leganarea misca panza intreaga;
		astea trei schimba forma ei, adica valul care trece prin ea.
	]]
	Waves: number?,
	RipplePeriod: number?,
	RippleRate: number?,
}

--[[
	Fisa unui steag pornit.

	Pornirea asteapta, deci opritorul nu exista din prima clipa. Pana apare,
	`Cancelled` e singurul mod prin care un steag disparut intre timp poate
	spune firului care il porneste sa se opreasca din drum.
]]
type Started = {
	Stop: (() -> ())?,
	Cancelled: boolean,
}

local DEFAULTS = {
	Sway = 8,
	SwayPeriod = 2.6,
	Lift = 4,
	LiftPeriod = 1.7,
	Twist = 5,
	TwistPeriod = 2.1,
	Phase = 0,
}

local TAU = math.pi * 2

--[[
	A doua armonica a leganarii: de trei ori mai iute, la o treime din
	amplitudine, decalata ca sa nu porneasca din acelasi punct. Impartirea la
	final readuce rezultatul in intervalul [-1, 1], ca `Sway` sa insemne tot
	numarul de grade pe care il scrie.
]]
local RIPPLE_RATE = 2.37
local RIPPLE_SHARE = 0.35
local RIPPLE_SHIFT = 1.1

local function gust(clock: number, period: number): number
	local a = clock * TAU / period
	return (math.sin(a) + RIPPLE_SHARE * math.sin(a * RIPPLE_RATE + RIPPLE_SHIFT))
		/ (1 + RIPPLE_SHARE)
end

-- Sub atat, "directia de la stalp spre panza" nu mai inseamna nimic.
local EPSILON = 0.05

--[[
	Porneste fluturatul si intoarce functia care il opreste.

	`hinge` e un punct de pe stalp; conteaza doar X si Z din el, fiindca axa
	balamalei e verticala. Inaltimea la care se roteste panza vine din panza
	insasi, nu din stalp — altfel un steag prins sus s-ar roti in jurul unui
	punct de la baza si ar descrie un con.

	Oprirea o pune inapoi exact unde a gasit-o, ca un steag oprit sa nu ramana
	strambat intr-o parte.

	Se misca `MeshPart`-ul, nu invelisul lui `..._Node`, si asta nu e o
	preferinta de stil. Importul glTF lasa fiecare invelis fara `PrimaryPart` si
	cu `WorldPivot` ramas in originea fisierului sursa — `(0, 4, 0)` pentru
	lobby-ul asta. Un `PivotTo` pe el ar roti panza in jurul centrului hartii,
	la zeci de studi distanta, in loc sa o legene langa stalpul ei. Partea are
	mereu un `CFrame` adevarat, deci nu are cum sa minta.
]]
function Flag.attach(cloth: BasePart, hinge: Vector3, options: Options?): () -> ()
	local given: Options = options or {}
	local sway = math.rad(given.Sway or DEFAULTS.Sway)
	local swayPeriod = given.SwayPeriod or DEFAULTS.SwayPeriod
	local lift = math.rad(given.Lift or DEFAULTS.Lift)
	local liftPeriod = given.LiftPeriod or DEFAULTS.LiftPeriod
	local twist = math.rad(given.Twist or DEFAULTS.Twist)
	local twistPeriod = given.TwistPeriod or DEFAULTS.TwistPeriod
	local clock = given.Phase or DEFAULTS.Phase

	local base = cloth.CFrame
	local pivot = CFrame.new(hinge.X, base.Position.Y, hinge.Z)
	local rest = pivot:ToObjectSpace(base)

	--[[
		Bratul: de la stalp spre mijlocul panzei, pe orizontala. El da cele doua
		axe de care mai e nevoie — rasucirea se face in jurul lui, iar ridicarea
		in jurul perpendicularei pe el.
	]]
	local arm = Vector3.new(rest.Position.X, 0, rest.Position.Z)
	if arm.Magnitude < EPSILON then
		warn(
			string.format("Flag: %q sta chiar pe stalp, n-am in jurul a ce sa-l legan", cloth.Name)
		)
		return function() end
	end

	local along = arm.Unit
	local across = Vector3.new(-along.Z, 0, along.X)

	local connection: RBXScriptConnection? = nil

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if cloth.Parent then
			cloth.CFrame = base
		end
	end

	connection = RunService.Heartbeat:Connect(function(delta: number)
		--[[
			Panza scoasa din lume opreste singura firul. Altfel un lobby
			reincarcat ar lasa in urma un ascultator care misca un steag pe care
			nu-l mai vede nimeni, la fiecare cadru, pana la sfarsitul sesiunii.
		]]
		if not cloth.Parent then
			stop()
			return
		end

		clock += delta

		local swing = gust(clock, swayPeriod) * sway
		local rise = math.sin(clock * TAU / liftPeriod) * lift
		local roll = math.sin(clock * TAU / twistPeriod) * twist

		cloth.CFrame = pivot
			* CFrame.Angles(0, swing, 0)
			* CFrame.fromAxisAngle(across, rise)
			* CFrame.fromAxisAngle(along, roll)
			* rest
	end)

	return stop
end

-- ------------------------------------------------------------- gasirea lor

--[[
	Importul glTF pune fiecare mesh intr-un Model numit `..._Node`. Gruparea
	adevarata a unui steag e cea care *nu* se termina asa: `arena_flag_left`,
	`rim_flag2`, `profile_flag`.
]]
local function isFlag(model: Model): boolean
	local name = string.lower(model.Name)
	if string.match(name, "_node$") then
		return false
	end
	return string.find(name, "flag") ~= nil
end

--[[
	Panza propriu-zisa. Vezi `attach` pentru ce se misca partea, nu invelisul ei.

	Copia vie lasata de `Ripple` se sare: e panza pe care *o desenam noi*, nu
	cea adusa de streaming, si luata drept original ar porni steagul a doua oara.
]]
local function clothOf(flag: Model): BasePart?
	for _, node in flag:GetDescendants() do
		if
			node:IsA("BasePart")
			and node:GetAttribute(Ripple.Mark) == nil
			and string.find(string.lower(node.Name), "cloth")
		then
			return node
		end
	end
	return nil
end

--[[
	Stalpul propriu-zis, nu talpa si nu gulerul: si ele au "pole" in nume, dar
	stau la baza, iar o balama masurata din ele ar trage panza in jos.
]]
local function poleOf(flag: Model): BasePart?
	for _, node in flag:GetDescendants() do
		if node:IsA("BasePart") then
			local name = string.lower(node.Name)
			if
				string.find(name, "pole")
				and not string.find(name, "foot")
				and not string.find(name, "collar")
			then
				return node
			end
		end
	end
	return nil
end

-- Decalajul dintre doua steaguri, ca sa nu fluture toate opt pe aceeasi bataie.
local PHASE_STEP = 0.7

--[[
	Merita o privire adaugarea asta, sau e zgomot de replicare?

	Lobby-ul are peste o mie de descendenti, si cu streaming pornit ei sosesc si
	pleaca in valuri. O recitire completa la fiecare sosire ar fi risipa, asa ca
	trec mai departe doar piesele care chiar pot completa un steag.
]]
local function mayCompleteFlag(node: Instance): boolean
	-- Copia vie e tot o panza la nume; daca ar trece de aici, s-ar cere o
	-- cautare care i-ar face inca o copie, la nesfarsit.
	if node:GetAttribute(Ripple.Mark) ~= nil then
		return false
	end
	local name = string.lower(node.Name)
	if node:IsA("BasePart") then
		return string.find(name, "cloth") ~= nil or string.find(name, "pole") ~= nil
	end
	return node:IsA("Model") and string.find(name, "flag") ~= nil
end

--[[
	Pune steagurile de sub `root` pe fluturat si intoarce functia care opreste
	tot, inclusiv pandirea.

	Nu se uita o singura data, si asta e partea importanta. Cu `StreamingEnabled`
	pornit, piesele lobby-ului nu sunt acolo cand porneste clientul: sosesc pe
	rand, iar pe masura ce jucatorul se plimba sunt descarcate si aduse inapoi.
	O cautare facuta o data la pornire gaseste zero panze si nu mai incearca
	niciodata — steagurile raman intepenite, exact ca inainte de a exista
	modulul asta. Mai rau, o panza descarcata e *distrusa*: cand se intoarce e
	alt obiect, iar firul vechi s-a oprit deja singur.

	De aceea se cauta la inceput si apoi de fiecare data cand mai pica o piesa
	potrivita. Cautarea e amanata cu `task.defer`: streaming-ul aduce panza si
	stalpul in acelasi val, dar nu in aceeasi clipa, si n-are rost sa masor
	balamaua dintr-un stalp care inca n-a ajuns. Daca inca lipseste ceva,
	urmatoarea piesa din val cere oricum alta cautare.

	`seen` tine panzele deja pornite, ca o cautare repetata sa nu lege al doilea
	fir la aceeasi panza. Tot el se curata de panzele plecate din lume: altfel
	un lobby strabatut indelung ar aduna la nesfarsit chei moarte.
]]
function Flag.build(root: Instance, options: Options?): () -> ()
	local given: Options = options or {}
	local seen: { [BasePart]: Started } = {}
	local started = 0
	local stopped = false

	--[[
		Pornirea unui steag asteapta, fiindca deschiderea mesh-ului asteapta. De
		aceea fiecare pleaca pe firul lui: altfel o cautare declansata de
		streaming s-ar opri la primul steag si ar lasa restul valului nepornit.

		Fisa se pune in `seen` *inainte* de a pleca firul, ca o a doua cautare
		sosita intre timp sa nu porneasca acelasi steag a doua oara.
	]]
	local function launch(cloth: BasePart, pole: BasePart, phase: number)
		local record: Started = { Stop = nil, Cancelled = false }
		seen[cloth] = record

		task.spawn(function()
			local live, stopRipple = Ripple.attach(cloth, pole.Position, {
				Waves = given.Waves,
				Period = given.RipplePeriod,
				Rate = given.RippleRate,
				Phase = phase,
			})

			-- Panza a plecat din lume cat timp se deschidea mesh-ul.
			if record.Cancelled or not cloth.Parent then
				stopRipple()
				return
			end

			--[[
				Se leagana copia vie daca exista, altfel originalul. Cand API-ul
				de mesh e inchis, steagul se poarta exact ca inainte de `Ripple`:
				fara ondulare, dar nu fara viata.
			]]
			local stopSway = Flag.attach(live or cloth, pole.Position, {
				Sway = given.Sway,
				SwayPeriod = given.SwayPeriod,
				Lift = given.Lift,
				LiftPeriod = given.LiftPeriod,
				Twist = given.Twist,
				TwistPeriod = given.TwistPeriod,
				Phase = phase,
			})

			record.Stop = function()
				stopSway()
				stopRipple()
			end
		end)
	end

	local function retire(cloth: BasePart, record: Started)
		record.Cancelled = true
		if record.Stop then
			record.Stop()
		end
		seen[cloth] = nil
	end

	local function scan()
		if stopped then
			return
		end

		for cloth, record in seen do
			if not cloth.Parent then
				retire(cloth, record)
			end
		end

		for _, node in root:GetDescendants() do
			if not node:IsA("Model") or not isFlag(node) then
				continue
			end

			local cloth = clothOf(node)
			local pole = poleOf(node)
			if not cloth or not pole or seen[cloth] then
				continue
			end

			started += 1
			launch(cloth, pole, (given.Phase or 0) + started * PHASE_STEP)
		end
	end

	local queued = false
	local function rescan()
		if queued or stopped then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			scan()
		end)
	end

	local watch = root.DescendantAdded:Connect(function(node: Instance)
		if mayCompleteFlag(node) then
			rescan()
		end
	end)

	scan()

	return function()
		stopped = true
		watch:Disconnect()
		for cloth, record in seen do
			retire(cloth, record)
		end
	end
end

return Flag
