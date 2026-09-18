--!strict
--[[
	Ripple — valul care calatoreste prin panza unui steag.

	`Flag` leagana panza intreaga in jurul stalpului. Arata bine, dar valul din
	ea ramane cel sculptat de artist: un val *inghetat*. Un steag adevarat nu se
	balanseaza doar, ci isi schimba forma — umflatura dintr-o parte trece in
	cealalta, si asa la nesfarsit. Modulul asta face exact partea aia, si e
	singurul loc din proiect care atinge vertecsii unui mesh.

	Cum se poate, daca `MeshPart`-urile sunt rigide: `EditableMesh` da acces la
	vertecsii mesh-ului, iar un `MeshPart` nascut din el se redeseneaza cand ii
	muti. Partea originala nu poate fi deformata, deci se face o copie vie langa
	ea, iar originalul se ascunde local prin `LocalTransparencyModifier` —
	proprietate care exista doar pe clientul asta si nu atinge ce detine
	serverul.

	Descompunerea e ideea intregului modul. Panza nu e un corp cu grosime, ci o
	foaie cu o singura suprafata, cutata: de aceea originalul poarta
	`DoubleSided` (copia incearca la fel, vezi `showBothSides`), si de aceea nu e de
	ajuns sa inmultesti adancimea cu ceva — ai turti odata cu valul si cutele,
	iar la trecerea prin zero foaia ar iesi plata ca o scandura.

	Asa ca fiecare vertex se desparte in doua: *linia mediana*, care e valul mare
	de-a lungul panzei, si *abaterea lui de la ea*, care sunt cutele marunte. Se
	inlocuieste doar prima. Cutele raman exact cum le-a sculptat artistul,
	inclusiv felul in care se domolesc spre capat.

	Valul nou e o sinusoida care calatoreste dinspre stalp spre capatul liber,
	cu amplitudinea crescand pe drum. Asta nu e infrumusetare: un steag e prins
	de stalp, deci acolo nu are cum sa fluture, si de aceea amplitudinea trebuie
	sa porneasca de la zero. Cat de mare ajunge se masoara din chiar valul
	sculptat, ca steagul sa nu unduleze nici mai tare, nici mai moale decat l-a
	desenat artistul.

	Daca API-ul de mesh e inchis din Game Settings, `attach` intoarce `nil` si nu
	se supara: steagul ramane cu leganarea din `Flag`, adica exact cum era
	inainte sa existe fisierul asta.
]]

local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local Ripple = {}

--[[
	Semnul pus pe copia vie.

	Fara el, copia se intoarce impotriva noastra: se cheama tot "cloth", sta tot
	sub steag, deci urmatoarea cautare o ia drept o panza nou sosita si ii face
	la randul ei o copie, care declanseaza alta cautare, si tot asa. Semnul e
	singurul lucru care deosebeste panza adusa de streaming de cea facuta aici.
]]
Ripple.Mark = "RippleTwin"

export type Options = {
	-- Cate valuri incap deodata pe lungimea panzei.
	Waves: number?,
	-- Secunde in care un val strabate panza de la stalp la capat.
	Period: number?,
	--[[
		De cate ori pe secunda se rescriu vertecsii. Leganarea din `Flag` merge
		la cadenta ecranului; ondularea nu are nevoie, si e de departe partea
		scumpa — `SetPosition` singur inseamna doua treimi din costul ei.
	]]
	Rate: number?,
	-- Decalajul de start, in secunde.
	Phase: number?,
}

local DEFAULTS = {
	Waves = 1.15,
	Period = 1.9,
	Rate = 30,
	Phase = 0,
}

local TAU = math.pi * 2

-- Cate felii se folosesc ca sa se masoare linia mediana a valului sculptat.
local BINS = 24

--[[
	Cand panza e sculptata plata nu exista val din care sa se ia amplitudinea.
	Atunci se alege una din lungimea ei, ca sa unduleze totusi ceva.
]]
local FLAT_AMPLITUDE = 0.06
local FLAT_THRESHOLD = 1e-3

local function NOOP() end

--[[
	Ondularea n-a pornit. Vestea se da o singura data pe sesiune.

	Opt steaguri dau peste acelasi obstacol, si opt mesaje identice ingroapa
	orice altceva din consola. Nici nu e o eroare: steagul ramane cu leganarea
	din `Flag`, adica exact cum era inainte sa existe modulul asta.

	Motivul se spune asa cum a venit, nu ghicit. Cel mai des e API-ul de mesh
	inchis din Game Settings — dar nu e singurul, si o instiintare care da mereu
	aceeasi vina trimite pe drumul gresit tocmai cand nu trebuie.
]]
local announced = false

local function stalled(reason: any): (BasePart?, () -> ())
	if not announced then
		announced = true
		warn(
			string.format(
				"Ripple: steagurile raman doar cu leganarea, fara ondulare.\n  Motiv: %s\n"
					.. "  Daca scrie ca EditableMesh nu e accesibil, se deschide din "
					.. "Game Settings -> Security -> Allow Mesh / Image APIs.",
				tostring(reason)
			)
		)
	end
	return nil, NOOP
end

type Prepared = {
	Ids: { number },
	X: { number },
	Y: { number },
	Z: { number },
	-- Departarea de stalp: 0 langa el, 1 la capatul liber.
	U: { number },
	-- Abaterea vertexului de la linia mediana: cutele marunte ale panzei.
	Thickness: { number },
	-- Adancimea valului sta pe Z cand lungimea sta pe X, si invers.
	DepthIsZ: boolean,
	Amplitude: number,
}

-- Ce iese din deschiderea mesh-ului, cand a mers toata.
type Built = {
	Mesh: any,
	Ready: Prepared,
	Live: BasePart,
}

--[[
	Masoara panza si imparte fiecare vertex in "unde sta" si "cat de gros e".

	Lungimea si adancimea nu cad pe aceleasi axe la toate steagurile: mesh-urile
	vin din import fiecare cu orientarea lui, iar doua din cele opt au lungimea
	pe Z in loc de X. De aceea nu se presupune nimic — se masoara intinderea si
	se ia drept lungime axa pe care panza e mai lata.
]]
local function prepare(mesh: any, cloth: BasePart, hinge: Vector3): Prepared?
	local verts = mesh:GetVertices()
	if #verts == 0 then
		return nil
	end

	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, id in verts do
		local p = mesh:GetPosition(id)
		lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
		hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
	end
	local size = hi - lo

	local spanIsX = size.X >= size.Z
	local spanLength = if spanIsX then size.X else size.Z
	if spanLength <= 0 then
		return nil
	end

	--[[
		Care capat e prins de stalp. Se intreaba geometria, nu numele: axa
		lungimii dusa in lumea reala, comparata cu directia spre stalp.
	]]
	local spanAxis = if spanIsX then Vector3.xAxis else Vector3.zAxis
	local worldSpan = cloth.CFrame:VectorToWorldSpace(spanAxis)
	local hoistAtMax = (hinge - cloth.Position):Dot(worldSpan) >= 0

	local spanLo = if spanIsX then lo.X else lo.Z

	local function binOf(p: Vector3): number
		local along = if spanIsX then p.X else p.Z
		return math.clamp(math.floor((along - spanLo) / spanLength * BINS) + 1, 1, BINS)
	end

	-- Linia mediana a valului sculptat, felie cu felie de-a lungul panzei.
	local sum = table.create(BINS, 0)
	local count = table.create(BINS, 0)
	for _, id in verts do
		local p = mesh:GetPosition(id)
		local b = binOf(p)
		sum[b] += if spanIsX then p.Z else p.X
		count[b] += 1
	end

	local middle = table.create(BINS, 0)
	local amplitude = 0
	for i = 1, BINS do
		local value = if count[i] > 0 then sum[i] / count[i] else 0
		middle[i] = value
		amplitude = math.max(amplitude, math.abs(value))
	end
	if amplitude < FLAT_THRESHOLD then
		amplitude = spanLength * FLAT_AMPLITUDE
	end

	local n = #verts
	local ready: Prepared = {
		Ids = table.create(n),
		X = table.create(n),
		Y = table.create(n),
		Z = table.create(n),
		U = table.create(n),
		Thickness = table.create(n),
		DepthIsZ = spanIsX,
		Amplitude = amplitude,
	}

	for i, id in verts do
		local p = mesh:GetPosition(id)
		local along = if spanIsX then p.X else p.Z
		local depth = if spanIsX then p.Z else p.X
		local a = (along - spanLo) / spanLength

		ready.Ids[i] = id
		ready.X[i] = p.X
		ready.Y[i] = p.Y
		ready.Z[i] = p.Z
		ready.U[i] = if hoistAtMax then 1 - a else a
		ready.Thickness[i] = depth - middle[binOf(p)]
	end

	return ready
end

--[[
	Panza se vede din amandoua partile, sau macar se incearca.

	Panza nu e un corp, ci o foaie cu o singura suprafata: se vede doar dinspre
	partea in care ii sunt intoarse fetele, iar pe cealalta e taiata la randare
	si steagul dispare cand treci pe langa el. Originalele scapa prin
	`DoubleSided`, deci copia are nevoie de acelasi lucru.

	Sta sub plasa lui, si nu din prudenta gratuita: `RenderFidelity`, vecina ei
	de clasa, cere drepturi de plugin si arunca dintr-un LocalScript. Daca si
	asta e la fel, un steag cu o singura fata e cu mult mai bun decat un steag
	care nu se mai unduleaza deloc — iar asa esecul costa exact cat trebuie.

	Ce NU merge, ca sa nu se mai incerce: dublarea fetelor in mesh. La runtime
	`EditableMesh` e fixed-size, si `AddTriangle` raspunde limpede — "adding or
	removing elements is not allowed in-experience". In Studio trece, fiindca
	acolo codul are drepturi de plugin; in joc, nu.
]]
local function showBothSides(copy: BasePart)
	pcall(function()
		(copy :: any).DoubleSided = true
	end)
end

--[[
	Copia vie: acelasi steag, dar cu un mesh care poate fi deformat.

	Isi ia infatisarea din original, ca sa nu existe doua adevaruri despre cum
	arata steagul — culoarea si materialul se schimba in Studio, intr-un singur
	loc. Nu se ciocneste si nu se poate atinge: e decor la cincisprezece studi
	inaltime, iar o copie care ar intra in fizica ar fi munca degeaba.

	Se copiaza doar ce are voie sa scrie un script obisnuit. `RenderFidelity`,
	`TextureID` si `DoubleSided` cer pe dinafara drepturi de plugin: atribuite
	dintr-un LocalScript arunca, si arunca *inainte* sa apuce sa se ridice
	steagul. `RenderFidelity` se da de aceea la creare, unde e primita; celelalte
	doua nu se ating deloc.
]]
local function twin(cloth: BasePart, mesh: any): BasePart?
	local ok, built = pcall(function()
		return AssetService:CreateMeshPartAsync((Content :: any).fromObject(mesh), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if not ok or not built then
		return nil
	end

	local copy = built :: BasePart
	copy.Name = cloth.Name .. "_Live"
	copy:SetAttribute(Ripple.Mark, true)
	copy.Size = cloth.Size
	copy.CFrame = cloth.CFrame
	copy.Color = cloth.Color
	copy.Material = cloth.Material
	copy.Transparency = cloth.Transparency
	copy.CastShadow = cloth.CastShadow
	copy.Reflectance = cloth.Reflectance
	showBothSides(copy)
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Parent = cloth.Parent
	return copy
end

--[[
	Porneste ondularea. Intoarce partea care trebuie leganata de acum incolo si
	functia care opreste tot.

	Partea intoarsa e copia vie, nu originalul: `Flag` trebuie sa miste ce se
	vede. Cand intoarce `nil`, mesh-ul nu s-a putut deschide — si atunci cine a
	chemat leagana originalul, exact ca pana acum.
]]
function Ripple.attach(cloth: BasePart, hinge: Vector3, options: Options?): (BasePart?, () -> ())
	if not cloth:IsA("MeshPart") or cloth.MeshId == "" then
		return nil, NOOP
	end

	--[[
		Toata deschiderea mesh-ului sta sub o singura plasa.

		`CreateEditableMeshAsync` trece si cu API-ul inchis; abia primul
		`GetVertices` arunca. Pazit doar apelul de deschidere, cum era la
		inceput, fiecare steag isi varsa propria eroare cu tot cu stiva, si opt
		steaguri umplu consola cu aceeasi veste.
	]]
	local ok, built = pcall(function(): Built?
		local mesh = AssetService:CreateEditableMeshAsync((Content :: any).fromUri(cloth.MeshId))
		local ready = prepare(mesh, cloth, hinge)
		if not ready then
			mesh:Destroy()
			return nil
		end

		-- Fara oglindire in mesh: la runtime nu se pot adauga fete. Vezi showBothSides.

		local twinned = twin(cloth, mesh)
		if not twinned then
			mesh:Destroy()
			return nil
		end
		return { Mesh = mesh, Ready = ready, Live = twinned }
	end)

	if not ok then
		return stalled(built)
	end
	if not built then
		return nil, NOOP
	end

	local mesh, ready, live = built.Mesh, built.Ready, built.Live

	-- Originalul nu se sterge: nu e al nostru. Se ascunde doar pe clientul asta.
	cloth.LocalTransparencyModifier = 1

	local given: Options = options or {}
	local waves = given.Waves or DEFAULTS.Waves
	local period = given.Period or DEFAULTS.Period
	local rate = math.max(1, given.Rate or DEFAULTS.Rate)
	local clock = given.Phase or DEFAULTS.Phase

	local interval = 1 / rate
	--[[
		Ceasul de rescriere porneste deja pornit pe drum, altfel toate steagurile
		si-ar rescrie vertecsii in acelasi cadru si munca s-ar aduna in varfuri
		in loc sa se imprastie.
	]]
	local due = clock % interval

	local connection: RBXScriptConnection? = nil

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if live.Parent then
			live:Destroy()
		end
		if cloth.Parent then
			cloth.LocalTransparencyModifier = 0
		end
		mesh:Destroy()
	end

	local ids, xs, ys, zs = ready.Ids, ready.X, ready.Y, ready.Z
	local us, thickness = ready.U, ready.Thickness
	local depthIsZ, amplitude = ready.DepthIsZ, ready.Amplitude
	local count = #ids
	local sin = math.sin

	connection = RunService.Heartbeat:Connect(function(delta: number)
		--[[
			Panza plecata din lume opreste singura firul, la fel ca la leganare.
			Cu streaming pornit se intampla des, si fiecare copie vie lasata in
			urma ar tine un mesh intreg in memorie degeaba.
		]]
		if not cloth.Parent or not live.Parent then
			stop()
			return
		end

		clock += delta
		due -= delta
		if due > 0 then
			return
		end
		due += interval

		local travel = clock * TAU / period

		for i = 1, count do
			local u = us[i]
			--[[
				`u * u`, nu `u`: amplitudinea creste incet langa stalp si repede
				spre capatul liber, cum se misca o panza prinsa intr-o margine.
				Crescuta liniar, arata a banda de cauciuc trasa uniform.
			]]
			local depth = amplitude * u * u * sin(u * waves * TAU - travel) + thickness[i]
			if depthIsZ then
				mesh:SetPosition(ids[i], Vector3.new(xs[i], ys[i], depth))
			else
				mesh:SetPosition(ids[i], Vector3.new(depth, ys[i], zs[i]))
			end
		end
	end)

	return live, stop
end

return Ripple
