--!strict
--[[
	Platform — masa de joc, ca obiect.

	Tot ce tine de *suprafata* traieste aici: cele 81 de celule, traducerea
	dintre celula si lume, evidentierea si clicurile. Platforma stie unde e
	fiecare lucru, dar nu stie nimic despre reguli — nu intreaba niciodata daca o
	mutare e legala, primeste doar lista de celule de aprins.

	Geometria nu se mai calculeaza, se **citeste**. Modelul importat isi poarta
	celulele ca piese numite `cell_e5`, cu coordonatele in atribute, iar
	platforma le foloseste ca sursa de adevar. Motivul e concret: in modelul
	generat litera creste pe -X si cifra pe -Z, invers fata de conventia din
	`WorldConfig`. Daca am fi calculat pozitiile, tabla ar fi aratat corect si
	zidurile ar fi cazut pe celulele gresite.

	O baricada nu se construieste aici. Platforma ii spune doar *unde* sta
	(`cframeForWall`), iar `Barricade` se ocupa de restul.

	Pentru mai tarziu: modelul primeste la constructie un folder `Sounds` si unul
	`Effects`, iar `playSound` ignora id-ul 0 exact ca `SoundController`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

-- Nuantele de evidentiere. Culorile de baza ale celulelor vin din model.
local TINT = {
	Legal = Color3.fromHex("7fd06a"),
	Hover = Color3.fromHex("ffe08a"),
	Selected = Color3.fromHex("ffd666"),
	Goal = Color3.fromHex(string.format("%06X", GameConfig.GoalColor)),
}

export type CellState = "IDLE" | "LEGAL" | "HOVER" | "SELECTED"

--[[
	Respiratia celulelor legale: intre cat si cat, si in cat timp.

	Nu pornind de la zero: `PULSE_LOW` tine celula verde si in punctul cel mai
	stins, ca ea sa spuna "aici poti" tot timpul, iar pulsul doar sa o faca
	vazuta. Perioada e destul de lunga cat sa citesti miscarea ca respiratie si
	nu ca palpait.
]]
local PULSE_LOW = 0.42
local PULSE_HIGH = 0.78
local PULSE_PERIOD = 0.85

local Platform = {}
Platform.__index = Platform

--[[
	Campurile se declara, nu se deduc. Altfel `Cells`, initializat gol, ramane
	tipat gol pentru totdeauna si orice acces de mai tarziu devine eroare.
]]
type PlatformFields = {
	Model: Model,
	Cells: { [string]: BasePart },
	GoalCells: { [string]: Color3 },
	-- Pulsul viu al fiecarei celule legale, ca sa poata fi oprit la schimbare.
	Pulses: { [string]: Tween },
	--[[
		Starea ceruta ultima oara pentru fiecare celula.

		Exista ca sa se poata raspunde "asta deja se intampla" si sa nu se reia o
		animatie care merge. Vezi `setCellState`: fara ea, pulsul o lua de la
		capat la fiecare bataie de ceas a serverului.
	]]
	CellStates: { [string]: CellState },
	Sounds: Folder,
	Effects: Folder,
}

export type Platform = typeof(setmetatable({} :: PlatformFields, Platform))

local function key(x: number, y: number): string
	return string.format("%d,%d", x, y)
end

-- Modelul sursa. Nu e sincronizat de Rojo: sunt mesh-uri importate, care
-- traiesc in fisierul place-ului.
local function sourceModel(): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local board = assets and assets:FindFirstChild("Board")
	if not board or not board:IsA("Model") then
		error("Platform: ReplicatedStorage.Assets.Board lipseste — importa tabla intai", 2)
	end
	return board
end

--[[
	Indexeaza celulele unui model de tabla.

	`CollisionFidelity` nu se atinge aici: e proprietate de incarcare a mesh-ului
	si un script obisnuit n-are voie sa o scrie. Sta setata pe `Box` direct pe
	modelul din `Assets.Board`, iar clonele o mostenesc. Conteaza: coliziunea
	aproximata din geometrie iese gauroasa pe placi subtiri — o celula are sub un
	stud grosime — si avatarul cade prin tabla.
]]
local function indexCells(self: Platform, model: Model, anchor: boolean)
	for _, piece in ipairs(model:GetDescendants()) do
		if not piece:IsA("BasePart") then
			continue
		end
		if anchor then
			piece.Anchored = true
		end
		local cellX = piece:GetAttribute("CellX")
		local cellY = piece:GetAttribute("CellY")
		if typeof(cellX) == "number" and typeof(cellY) == "number" then
			self.Cells[key(cellX, cellY)] = piece
		end
	end

	local expected = GameConfig.BoardSize * GameConfig.BoardSize
	local found = 0
	for _ in self.Cells do
		found += 1
	end
	if found ~= expected then
		warn(string.format("Platform: am gasit %d celule, asteptam %d", found, expected))
	end
end

--[[
	Scoate din drum podoabele asezate peste tabla.

	Tabla vine cu un emblem in mijloc: un inel si patru raze, sculptate *peste*
	fata celulelor. Arata bine si nu are nicio treaba cu jocul, dar pana acum se
	purta ca si cum ar fi avut. Facea doua rele deodata:

	  - pionul pus pe celula centrala se aseza pe el si plutea deasupra tablei,
	    iar ceilalti il vedeau ridicat fara motiv;
	  - clicul pe celula centrala cadea pe emblem, care n-are `ClickDetector`,
	    deci nu se intampla nimic — trebuia nimerita marginea celulei, singura
	    fasie ramasa descoperita.

	Care piese sunt podoabe nu se decide dupa nume, ci dupa loc: o piesa care nu
	e celula si care totusi urca peste fata celulelor sta, prin definitie,
	deasupra suprafetei de joc. Pe tabla asta regula prinde exact emblemul — cele
	sapte piese ale lui — si lasa neatinse toate celelalte saizeci si opt, care
	stau dedesubt. Daca artistul mai adauga un ornament pe suprafata, se rezolva
	singur, fara sa se atinga codul.

	Ramane vazut, doar ca nu mai raspunde: nici corpurilor, nici mouse-ului.
]]
local function freeTheSurface(self: Platform, model: Model)
	local surface = -math.huge
	for _, cell in self.Cells do
		surface = math.max(surface, cell.Position.Y + cell.Size.Y / 2)
	end
	if surface == -math.huge then
		return
	end

	for _, piece in ipairs(model:GetDescendants()) do
		if not piece:IsA("BasePart") or piece:GetAttribute("CellX") ~= nil then
			continue
		end
		if piece.Position.Y + piece.Size.Y / 2 <= surface then
			continue
		end
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
	end
end

--[[
	Aseaza o copie a tablei sub `parent`, cu centrul in `origin`.

	`origin` e centrul tablei la nivelul suprafetei jucabile, ca un pion asezat
	pe o celula sa nu mai aiba nevoie de corectii de inaltime.
]]
function Platform.new(parent: Instance, origin: CFrame?): Platform
	local self = setmetatable({}, Platform) :: Platform

	self.Cells = {} :: { [string]: BasePart }
	self.GoalCells = {} :: { [string]: Color3 }
	self.Pulses = {} :: { [string]: Tween }
	self.CellStates = {} :: { [string]: CellState }

	local model = sourceModel():Clone()
	model.Name = "Platform"
	self.Model = model
	model:PivotTo(origin or CFrame.new(0, 0, 0))

	indexCells(self, model, true)
	freeTheSurface(self, model)

	--[[
		Liniutele aurii de pe rama (`tick_file_*`, `tick_rank_*`) pleaca din copie.
		Pe mijlocul ramei trece acum bara de lumina din `BoardRim`, iar liniutele
		stateau chiar pe drumul ei, ca niste cuie in sant. Modelul din `Assets`
		ramane intreg; doar masa de meci e fara ele.
	]]
	for _, piece in model:GetDescendants() do
		if piece:IsA("BasePart") and string.sub(piece.Name, 1, 5) == "tick_" then
			piece:Destroy()
		end
	end

	self.Sounds = Instance.new("Folder")
	self.Sounds.Name = "Sounds"
	self.Sounds.Parent = model

	self.Effects = Instance.new("Folder")
	self.Effects.Name = "Effects"
	self.Effects.Parent = model

	model.Parent = parent
	return self
end

--[[
	Se leaga de o tabla care exista deja.

	Constructorul pereche al lui `new`: serverul ridica masa, clientul se prinde
	de cea replicata. Fara asta, clientul si-ar cladi propria copie si ar avea o
	tabla care arata la fel, dar pe care nimeni altcineva n-o vede — si pe care
	evidentierile ar cadea langa pionii adevarati.

	Nu ancoreaza si nu creeaza nimic: piesele nu sunt ale lui.
]]
function Platform.attach(model: Model): Platform
	local self = setmetatable({}, Platform) :: Platform

	self.Cells = {} :: { [string]: BasePart }
	self.GoalCells = {} :: { [string]: Color3 }
	self.Pulses = {} :: { [string]: Tween }
	self.CellStates = {} :: { [string]: CellState }
	self.Model = model

	indexCells(self, model, false)
	freeTheSurface(self, model)

	self.Sounds = (model:FindFirstChild("Sounds") :: Folder?) or Instance.new("Folder")
	self.Effects = (model:FindFirstChild("Effects") :: Folder?) or Instance.new("Folder")

	return self
end

function Platform.cell(self: Platform, x: number, y: number): BasePart?
	return self.Cells[key(x, y)]
end

-- Centrul unei celule, pe suprafata ei.
function Platform.cellTop(self: Platform, x: number, y: number): Vector3?
	local cell = self.Cells[key(x, y)]
	if not cell then
		return nil
	end
	return cell.Position + Vector3.new(0, cell.Size.Y / 2, 0)
end

--[[
	Unde sta o baricada.

	Intersectia `(X, Y)` e coltul comun al celulelor `(X,Y)`, `(X+1,Y)`,
	`(X,Y+1)` si `(X+1,Y+1)`, deci centrul zidului e media celor patru. Directia
	nu se presupune, se masoara: o orizontala se intinde spre `(X+1, Y)`, o
	verticala spre `(X, Y+1)`. Asa, orice orientare ar avea modelul in lume,
	zidul cade pe granita corecta.
]]
function Platform.cframeForWall(self: Platform, x: number, y: number, orientation: string): CFrame?
	local a = self.Cells[key(x, y)]
	local alongX = self.Cells[key(x + 1, y)]
	local alongY = self.Cells[key(x, y + 1)]
	local diagonal = self.Cells[key(x + 1, y + 1)]
	if not (a and alongX and alongY and diagonal) then
		return nil
	end

	local center = (a.Position + alongX.Position + alongY.Position + diagonal.Position) / 4
	center += Vector3.new(0, a.Size.Y / 2, 0)

	local direction = if orientation == "Horizontal"
		then alongX.Position - a.Position
		else alongY.Position - a.Position

	-- Axa lunga a modelului de zid e X-ul lui local, deci o asezam pe directie.
	return CFrame.fromMatrix(center, direction.Unit, Vector3.yAxis)
end

--[[
	Incotro e o margine a tablei, ca directie in lume.

	Se masoara din pozitiile a doua celule, nu se deduce din axe: tabla importata
	are litera crescatoare pe -X si cifra pe -Z, deci orice presupunere despre
	semne ar intoarce jumatate din jucatori cu spatele la tinta.
]]
function Platform.directionForEdge(self: Platform, edge: string): Vector3?
	local size = GameConfig.BoardSize
	local from, to
	if edge == "Y_MAX" then
		from, to = self:cellTop(1, 1), self:cellTop(1, size)
	elseif edge == "Y_MIN" then
		from, to = self:cellTop(1, size), self:cellTop(1, 1)
	elseif edge == "X_MAX" then
		from, to = self:cellTop(1, 1), self:cellTop(size, 1)
	elseif edge == "X_MIN" then
		from, to = self:cellTop(size, 1), self:cellTop(1, 1)
	else
		return nil
	end
	if not (from and to) then
		return nil
	end
	return (to - from).Unit
end

--[[
	Incotro trebuie sa ajunga un jucator, ca directie in lume.

	Pentru obiectivele de tip margine e directia marginii; pentru cele de tip
	centru, drumul de la celula lui catre centru. Daca e deja in centru, nu are
	incotro sa se intoarca si raspunsul e `nil`.
]]
function Platform.directionForObjective(
	self: Platform,
	objective: any,
	from: { X: number, Y: number }
): Vector3?
	if objective.Kind == "CENTER" and objective.Cell then
		local here = self:cellTop(from.X, from.Y)
		local target = self:cellTop(objective.Cell.X, objective.Cell.Y)
		if not (here and target) or (target - here).Magnitude < 0.01 then
			return nil
		end
		return (target - here).Unit
	end
	return self:directionForEdge(objective.Edge)
end

--[[
	Pune detectoare de clic pe celule, fara sa le si asculte.

	Crearea si ascultarea sunt separate pentru ca se intampla pe parti diferite
	ale retelei: serverul detine tabla, deci tot el creeaza detectoarele, dar cel
	care vrea sa stie unde s-a apasat e clientul. Un detector creat pe client
	n-ar exista pentru ceilalti, iar unul ascultat doar pe server n-ar sti daca
	jucatorul voia sa se mute sau sa puna un zid.
]]
function Platform.enableClicks(self: Platform, maxDistance: number?)
	for _, cell in self.Cells do
		if cell:FindFirstChildOfClass("ClickDetector") then
			continue
		end
		local detector = Instance.new("ClickDetector")
		detector.MaxActivationDistance = maxDistance or 512
		--[[
			Aceeasi icoana pe toate celulele, si anume sageata obisnuita.

			Lasat gol, `CursorIcon` inseamna "icoana implicita de clic", iar Roblox
			o schimba de fiecare data cand cursorul trece de pe o celula pe alta.
			Peste 81 de patrate lipite, asta inseamna zeci de schimbari pe secunda
			si un cursor care pare ca se smuceste. Cu toate detectoarele pe acelasi
			desen, nu mai e nimic de schimbat.
		]]
		detector.CursorIcon = "rbxasset://textures/ArrowCursor.png"
		detector.Parent = cell
	end
end

--[[
	Asculta clicurile pe celule. Se poate chema de pe oricare parte; detectoarele
	trebuie doar sa existe deja.
]]
function Platform.onCellClicked(
	self: Platform,
	callback: (number, number) -> ()
): { RBXScriptConnection }
	local connections = {}
	for _, cell in self.Cells do
		local detector = cell:FindFirstChildOfClass("ClickDetector")
		if not detector then
			continue
		end
		table.insert(
			connections,
			detector.MouseClick:Connect(function()
				callback(cell:GetAttribute("CellX") :: number, cell:GetAttribute("CellY") :: number)
			end)
		)
	end
	return connections
end

--[[
	Randurile-obiectiv raman colorate si cand celula trece prin alte stari, ca
	tinta sa nu dispara in timpul jocului. De aceea se tin separat si nu ca o
	stare obisnuita.
]]
function Platform.paintGoal(
	self: Platform,
	cells: { { X: number, Y: number } },
	color: Color3?,
	strength: number?
)
	for _, coordinate in cells do
		local id = key(coordinate.X, coordinate.Y)
		local cell = self.Cells[id]
		if cell then
			-- Se porneste de la culoarea deja pusa, daca exista: doua margini se pot
			-- suprapune la colturi, iar a doua nu trebuie sa o stearga pe prima.
			local base = self.GoalCells[id]
				or (cell:GetAttribute("BaseColor") :: Color3)
				or cell.Color
			self.GoalCells[id] = base:Lerp(color or TINT.Goal, strength or 0.3)
		end
	end
	self:clearHighlights()
end

local function baseColorOf(self: Platform, id: string, cell: BasePart): Color3
	return self.GoalCells[id] or (cell:GetAttribute("BaseColor") :: Color3) or cell.Color
end

local function stopPulse(self: Platform, id: string)
	local running = self.Pulses[id]
	if running then
		running:Cancel()
		self.Pulses[id] = nil
	end
end

-- Stinge o celula pe loc: fara puls, fara tranzitie, inapoi la culoarea ei.
local function resetCell(self: Platform, id: string)
	stopPulse(self, id)
	local cell = self.Cells[id]
	if cell then
		cell.Color = baseColorOf(self, id, cell)
	end
	self.CellStates[id] = "IDLE"
end

function Platform.setCellState(self: Platform, x: number, y: number, state: CellState)
	local id = key(x, y)
	local cell = self.Cells[id]
	if not cell then
		return
	end

	--[[
		O celula care e deja in starea ceruta se lasa in pace.

		Nu e o optimizare, e corectitudinea pulsului. Serverul replica starea
		intreaga **la fiecare secunda**, pentru ceas (vezi `Match.startClock`), iar
		fiecare replicare ajungea aici si repornea respiratia de la culoarea
		stinsa. Cu o perioada de 0.85s, celula apuca sa se aprinda complet si era
		taiata inainte sa apuce sa scada: se vedea ca o crestere urmata de o
		cadere brusca, in loc de respiratie. Pulsul e continuu doar daca nimeni
		nu il repune pe zero, deci "aceeasi stare" trebuie sa insemne "nu face
		nimic".
	]]
	local running: Tween? = self.Pulses[id]
	if self.CellStates[id] == state and (state ~= "LEGAL" or running ~= nil) then
		return
	end

	--[[
		Orice stare noua opreste animatia celei vechi.

		Fara asta, un puls ramas in urma continua sa scrie culoarea peste ce
		tocmai s-a cerut, si celula clipeste intre doua raspunsuri.
	]]
	stopPulse(self, id)
	self.CellStates[id] = state

	local base = baseColorOf(self, id, cell)

	--[[
		Celulele pe care poti calca respira, nu se aprind.

		Aprinse dintr-o data si tinute asa, cele patru patrate verzi apareau si
		dispareau odata cu tura, ca un intrerupator — ochiul le citea ca pe un
		defect de imagine, nu ca pe o invitatie. Un puls lent spune acelasi lucru
		fara sa sara: verdele creste si scade intre doua nuante, la nesfarsit,
		iar celula ramane verde tot timpul. Miscarea atrage privirea, nu clipitul.

		Se pleaca de la culoarea de baza spre cea aprinsa, ca prima respiratie sa
		inceapa de unde era celula, nu dintr-un salt.
	]]
	if state == "LEGAL" then
		local low = base:Lerp(TINT.Legal, PULSE_LOW)
		local high = base:Lerp(TINT.Legal, PULSE_HIGH)
		cell.Color = low

		local pulse = TweenService:Create(
			cell,
			TweenInfo.new(PULSE_PERIOD, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Color = high }
		)
		self.Pulses[id] = pulse
		pulse:Play()
		return
	end

	local target = base
	if state == "HOVER" then
		target = base:Lerp(TINT.Hover, 0.55)
	elseif state == "SELECTED" then
		target = base:Lerp(TINT.Selected, 0.7)
	end

	TweenService:Create(cell, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Color = target }):Play()
end

-- Readuce toate celulele la culoarea lor, obiectivele incluse.
--[[
	Stinge tot ce era aprins.

	Pulsurile se opresc *inainte* de a scrie culoarea de baza. Lasate sa curga,
	ar rescrie-o la cadrul urmator si celulele ar ramane verzi dupa ce nu mai au
	de ce — un tween care merge e mai puternic decat o atribuire care s-a facut
	o data.
]]
function Platform.clearHighlights(self: Platform)
	for id in self.Cells do
		resetCell(self, id)
	end
end

--[[
	Aprinde exact lista primita si stinge restul, dintr-un singur apel.

	Asta e raspunsul la "pe ce celula pot inainta": jucatorul nu trebuie sa
	deduca nimic, vede direct unde poate calca.

	Se sting **doar** celulele care nu mai sunt in lista, nu toate urmate de
	reaprinderea celor cerute. Stinse si reaprinse, celulele care raman legale
	de la o replicare la alta — adica aproape toate, cat tine o tura — isi
	pierdeau respiratia la fiecare bataie de ceas a serverului.
]]
function Platform.showLegalCells(self: Platform, cells: { { X: number, Y: number } })
	local wanted: { [string]: boolean } = {}
	for _, coordinate in cells do
		wanted[key(coordinate.X, coordinate.Y)] = true
	end

	for id in self.Cells do
		if not wanted[id] and self.CellStates[id] ~= "IDLE" then
			resetCell(self, id)
		end
	end

	for _, coordinate in cells do
		self:setCellState(coordinate.X, coordinate.Y, "LEGAL")
	end
end

--[[
	Sunetele se redau de pe platforma, nu de pe celula apasata: o celula poate
	disparea intre declansare si sfarsitul sunetului. Id-ul 0 inseamna "fara
	sunet" si nu e o eroare.
]]
function Platform.playSound(self: Platform, assetId: number)
	if assetId == 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. assetId
	sound.Parent = self.Sounds
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

function Platform.destroy(self: Platform)
	self.Model:Destroy()
	self.Cells = {} :: { [string]: BasePart }
	self.GoalCells = {} :: { [string]: Color3 }
	self.Pulses = {} :: { [string]: Tween }
	self.CellStates = {} :: { [string]: CellState }
end

return Platform
