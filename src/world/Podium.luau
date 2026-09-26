--!strict
--[[
	Podium — soclul pe care se arata un skin, ca obiect.

	Fiecare skin isi are podiumul lui in `ReplicatedStorage.Assets.Podiums`, sub
	acelasi id: `wood`, `castle`, `tree`, `dragon`, `energy`, `thunder`,
	`crystal`, `portal`. Lista nu se scrie a doua oara aici — vine din
	`Catalog`, ca sa nu existe doua adevaruri despre ce se poate detine.

	Corpul vine din ReplicatedStorage si nicaieri altundeva. De acolo il ia si
	vitrina din lobby, si podiumul pe care il foloseste un jucator care l-a
	cumparat, deci o modificare adusa modelului se vede in amandoua deodata.

	Efectele — plutirea, si mai tarziu sunetul sau particulele — se pornesc de
	pe obiect si se sting odata cu el: `destroy` inchide tot ce a pornit, ca un
	podium sters sa nu lase in urma un fir care mai bate.

	Modelele vin din import cu pivotul la baza si cu doua atribute puse la
	pregatirea assetului:
	  `StandHeight` — inaltimea plintei pe care ar sta un avatar;
	  `Height`      — inaltimea totala, decorul inclus.
	Coliziunea o poarta doar soclul; decorul de deasupra e trecator, ca sa nu
	agate jucatorul care urca.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Hover = require(script.Parent.Hover)
local ModelFit = require(script.Parent.ModelFit)

local Podium = {}
Podium.__index = Podium

type PodiumFields = {
	Model: Model,
	-- Id-ul obiectului pe care il arata podiumul; acelasi cu numele modelului.
	Id: string,
	-- Unde a fost asezat. Animatiile au nevoie de un punct de intors acasa.
	Base: CFrame,
	-- Ce trebuie oprit cand podiumul dispare: plutire, recurente, mai tarziu efecte.
	Effects: { () -> () },
	-- Scara modelului din `Assets`, la care e masurat `StandHeight`.
	SourceScale: number,
}

export type Podium = typeof(setmetatable({} :: PodiumFields, Podium))

local function folder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return if assets then assets:FindFirstChild("Podiums") else nil
end

--[[
	Modelul podiumului. Un id fara model nu are voie sa lase vitrina goala, deci
	cadem pe obiectul de start si spunem de ce — exact ca la baricada.
]]
local function sourceModel(id: string): Model?
	local podiums = folder()
	if not podiums then
		return nil
	end

	local fallback = Catalog.default("Podium")
	local model = podiums:FindFirstChild(id)
	if not model then
		warn(string.format("Podium: %q nu are podium importat; folosesc %q", id, fallback))
		model = podiums:FindFirstChild(fallback)
	end
	return if model and model:IsA("Model") then model else nil
end

-- Obiectele care chiar au un podium importat, in ordinea din vitrina.
function Podium.available(): { string }
	local ready = {}
	local podiums = folder()
	if not podiums then
		return ready
	end
	for _, id in Catalog.Order do
		if podiums:FindFirstChild(id) then
			table.insert(ready, id)
		end
	end
	return ready
end

--[[
	Aseaza podiumul pe podea.

	`surface` e talpa, nu centrul: pozitia se da direct de la suprafata pe care
	sta, fara sa stii cat de inalt e decorul. `span` e latimea la care se arata,
	in studs; fara el ramane la marimea lui, cea a unui jucator.
]]
function Podium.new(itemId: string?, parent: Instance, surface: CFrame, span: number?): Podium?
	local id = if itemId and Catalog.get("Podium", itemId)
		then itemId
		else Catalog.default("Podium")
	local source = sourceModel(id)
	if not source then
		warn("Podium: nu exista niciun podium importat")
		return nil
	end

	local self = setmetatable({}, Podium) :: Podium
	self.Id = id
	self.Effects = {}
	self.SourceScale = source:GetScale()

	local model = source:Clone()
	model.Name = "Podium_" .. id

	--[[
		Tintuit pe loc, indiferent de unde vine modelul.

		Un podium nu cade si nu se impinge niciodata: nici cel din vitrina, pe
		care il misca `hover` cu `PivotTo` — si care s-ar bate cu fizica daca ar
		fi liber — nici cel din meci, pe care sta un avatar. Asa nu depinde de
		cum a fost lasat assetul la import.
	]]
	for _, piece in ipairs(model:GetDescendants()) do
		if piece:IsA("BasePart") then
			piece.Anchored = true
		end
	end

	if span then
		ModelFit.toSpan(model, span)
	end
	self.Base = ModelFit.onSurface(model, surface)
	self.Model = model

	model.Parent = parent
	return self
end

--[[
	Cat de sus e plinta fata de talpa soclului, in studi si la scara de acum.

	`StandHeight` vine din pregatirea assetului. Cand lipseste — un model nou,
	importat si uitat — raspunsul nu are voie sa fie zero: zero inseamna "stai
	pe podea", si atunci un podium n-ar mai fi podium, iar avatarul ar ramane cu
	soclul crescut prin el. Fara atribut se ia inaltimea intreaga a modelului,
	adica se sta pe capacul lui; nu e exact, dar e in picioare.

	Atributul e masurat pe modelul din `Assets`, asa cum e acolo — iar acolo
	modelele sunt deja scalate (`crystal` sta la 3.6). Se inmultea cu toata
	scara, nu cu cat s-a mai scalat de atunci, si plinta de 1.1 studi iesea de
	4.1: mai inalta decat tot podiumul. Castigatorul era ridicat pe varful
	decorului, nu pe plinta, iar `keepPlinth` nu gasea nimic de taiat.
]]
local function standHeight(self: Podium): number
	local marked = self.Model:GetAttribute("StandHeight")
	if typeof(marked) == "number" and marked > 0 then
		return marked * self.Model:GetScale() / self.SourceScale
	end

	local _, size = self.Model:GetBoundingBox()
	return size.Y
end

-- Unde sta un avatar: pe plinta, in centrul podiumului.
function Podium.standCFrame(self: Podium): CFrame
	return self.Base * CFrame.new(0, standHeight(self), 0)
end

-- Muta podiumul, impreuna cu punctul lui de referinta.
function Podium.moveTo(self: Podium, surface: CFrame)
	self.Base = ModelFit.onSurface(self.Model, surface)
end

--[[
	Taie tot ce e deasupra plintei: ramane doar placa pe care se sta.

	Asa arata podiumul in timpul meciului, sub fiecare pion — patratul lui, fara
	tron, arcada sau fulger, care ar acoperi zidurile si pionii vecini. Decorul
	iese abia la victorie, pe podiumul intreg care urca din placa.

	Piesele se sterg, nu se ascund: pe decor stau lumini si emitatoare, iar un
	emitator ramas pe o piesa nevazuta ar scoate scantei din aer. Scriptul de
	efecte al modelului sare singur peste piesele care lipsesc.

	Se taie la marimea de acum, deci se cheama dupa `new`, cand modelul e deja
	scalat — altfel placa n-ar mai fi cat plinta podiumului care urca din ea.
]]
function Podium.keepPlinth(self: Podium)
	local box, size = self.Model:GetBoundingBox()
	local standTop = box.Position.Y - size.Y / 2 + standHeight(self)

	local decor: { BasePart } = {}
	for _, piece in ipairs(self.Model:GetDescendants()) do
		if piece:IsA("BasePart") and piece.Position.Y + piece.Size.Y / 2 > standTop + 0.01 then
			table.insert(decor, piece)
		end
	end
	for _, piece in decor do
		-- O piesa poate fi deja plecata, odata cu parintele ei.
		if piece.Parent then
			piece:Destroy()
		end
	end
end

--[[
	Coliziunea, pornita sau oprita.

	Un podium pe care stai chiar trebuie sa te tina, dar unul care pluteste in
	vitrina nu: un obiect solid care se misca singur impinge jucatorul care s-a
	urcat pe el si il arunca de pe soclu.
]]
function Podium.setSolid(self: Podium, solid: boolean)
	local box, size = self.Model:GetBoundingBox()
	local standTop = box.Position.Y - size.Y / 2 + standHeight(self)

	for _, piece in ipairs(self.Model:GetDescendants()) do
		if piece:IsA("BasePart") then
			-- Doar soclul, niciodata decorul de deasupra.
			piece.CanCollide = solid and piece.Position.Y + piece.Size.Y / 2 <= standTop + 0.01
		end
	end
end

--[[
	Raspunde podiumul la raze si la clicuri?

	Pe tabla, nu: soclul sta peste celula pe care se apasa, si peste care trece
	raza care cauta unde ar cadea zidul. Lasat interogabil, ar fura si clicul, si
	fantoma — jucatorul ar da pe celula lui si nu s-ar intampla nimic. E aceeasi
	masura pe care o ia si `Barricade` pentru zidurile asezate.
]]
function Podium.setQueryable(self: Podium, queryable: boolean)
	for _, piece in ipairs(self.Model:GetDescendants()) do
		if piece:IsA("BasePart") then
			piece.CanQuery = queryable
		end
	end
end

function Podium.setVisible(self: Podium, visible: boolean)
	for _, piece in ipairs(self.Model:GetDescendants()) do
		if piece:IsA("BasePart") then
			piece.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

-- Plutirea din vitrina: se invarte incet si urca si coboara.
function Podium.hover(self: Podium, options: Hover.Options?)
	table.insert(self.Effects, Hover.attach(self.Model, self.Base, options))
end

--[[
	Recurenta: cheama `action` la fiecare `seconds`, cat timp podiumul e in lume.

	Nu tot ce face un podium e continuu. Fulgerul care cade din cand in cand sau
	sclipirea cristalului se intampla la interval, nu la fiecare cadru, si asta
	e locul lor — plutirea are `hover`.
]]
function Podium.every(self: Podium, seconds: number, action: (Podium) -> ())
	local loop = task.spawn(function()
		while true do
			task.wait(seconds)
			if not self.Model.Parent then
				break
			end
			action(self)
		end
	end)

	table.insert(self.Effects, function()
		if coroutine.status(loop) ~= "dead" then
			task.cancel(loop)
		end
	end)
end

function Podium.stopEffects(self: Podium)
	local running = self.Effects
	self.Effects = {}
	for _, stop in ipairs(running) do
		stop()
	end
end

-- Sunetul iese din corpul podiumului, ca sa se auda din directia lui.
function Podium.playSound(self: Podium, assetId: number)
	if assetId == 0 then
		return
	end
	local anchor = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. assetId
	sound.Parent = anchor
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

function Podium.destroy(self: Podium)
	self:stopEffects()
	self.Model:Destroy()
end

return Podium
