--!strict
--[[
	PreviewRig — cabina in care obiectele isi fac poza pentru magazin.

	Cartonasele din magazin au nevoie de o imagine a fiecarui zid si a fiecarui
	soclu. Imaginile alea nu se deseneaza de mana: se randeaza din **exact**
	modelele pe care le joci, clonate din `ReplicatedStorage.Assets` prin
	`Barricade` si `Podium`, ca sa nu apara niciodata un magazin care arata alt
	obiect decat cel pe care il primesti.

	Cabina se ridica la cerere si se strange la loc dupa poza. Nu sta in place:
	lumea 3D din Studio nu e sincronizata de Rojo, iar o cabina facuta de mana
	acolo ar fi inca un lucru de intretinut in afara repo-ului si de reconstruit
	dupa fiecare publicare.

	**Cabina se aseaza dupa camera, nu invers.** Pare pe dos, si e singurul lucru
	surprinzator de aici. In Studio, camera din editor nu se lasa mutata din cod:
	scrii `CurrentCamera.CFrame` si peste o clipa Studio o intoarce de unde a
	luat-o. Ce se poate face e sa i se ceara lui Studio sa incadreze un obiect.
	Deci cabina se construieste in doi timpi: `build` pune obiectul, Studio
	indreapta camera spre el, iar `frame` ridica fundalul si rama **perpendicular
	pe camera aia**, oricare ar fi ea. Asa poza iese la fel indiferent din ce
	unghi a ales editorul sa priveasca.

	Trei piese, si fiecare are un motiv:

	**Fundalul** e `CardColor`-ul skinului si e Neon. Neon iese din randare cu
	exact culoarea ceruta, neatinsa de soare si de umbre, deci poza are un fundal
	plat identic cu al casetei din magazin. Asa marginile imaginii se pierd in
	caseta, indiferent cat o intinde interfata.

	**Rama** sunt patru bare Neon magenta in jurul cadrului. Nu ajung in poza
	finala — sunt reperul dupa care se decupeaza captura ferestrei Studio. Fara
	ele ar trebui ghicit unde cade viewportul in fereastra, iar raspunsul s-ar
	schimba la prima mutare de panou. Magenta pur nu apare nicaieri in temele
	jocului, deci nu se confunda cu obiectul. Barele stau intr-un plan
	perpendicular pe camera: punctele de la aceeasi adancime se proiecteaza
	intr-un dreptunghi adevarat, deci decupajul are exact raportul cerut.

	**Luminile** sunt doua, principala din stanga-sus si umplerea din dreapta,
	amandoua asezate fata de camera. Cabina nu inchide cerul, deci soarele
	place-ului tot ajunge la obiect; astea doua doar il scot din plat.

	Raportul cadrului nu e ales din ochi: e raportul casetei scobite din
	`card_wood.png`, 125 pe 79. Randate asa, pozele intra in caseta fara dungi.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

local Barricade = require(script.Parent.Barricade)
local Podium = require(script.Parent.Podium)
local Skins = require(script.Parent.Skins)

type Kind = Catalog.Kind

local PreviewRig = {}
PreviewRig.__index = PreviewRig

-- Raportul casetei din cartonas: 125 pe 79.
local FRAME_ASPECT = 125 / 79

--[[
	Cat din inaltimea vederii ocupa cadrul, si cat din cadru ocupa obiectul.

	Cadrul nu umple ecranul: ii trebuie loc pentru rama de reper, si inca putin
	peste ea, altfel o bara cade pe marginea viewportului si decuparea nu mai
	gaseste patru laturi intregi. Obiectul, la randul lui, nu umple cadrul —
	fara aer in jur pare taiat chiar si cand nu e.
]]
local FRAME_FILL = 0.82
local ITEM_FILL = 0.84

-- Cat de departe sta fundalul in spatele obiectului, si cat il facem mai mare.
local BACKDROP_DISTANCE = 40
local BACKDROP_OVERSIZE = 3

--[[
	Rama de reper: grosimea unei bare, ca fractiune din inaltimea cadrului.

	Proportional, nu in studi: cadrul isi ia marimea din cat de departe a pus
	Studio camera, iar o grosime fixa ar iesi cand o dunga de un pixel, cand o
	bara groasa cat obiectul. Randarea subtiaza liniile mici pana dispar pe
	alocuri, si atunci decuparea pierde o latura.
]]
local MARK_THICKNESS = 0.035
local MARK_COLOR = Color3.fromRGB(255, 0, 255)

type RigFields = {
	-- Tot ce a ridicat cabina: obiectul, fundalul, rama, luminile.
	Model: Model,
	-- Obiectul expus, `Barricade` sau `Podium`: aceleasi doua clase ca in vitrina.
	Item: any,
	Kind: Kind,
	Id: string,
	-- Punctul in jurul caruia se construieste totul si spre care priveste camera.
	Center: CFrame,
}

export type Rig = typeof(setmetatable({} :: RigFields, PreviewRig))

local function part(name: string, parent: Instance, props: { [string]: any }): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(piece :: any)[key] = value
	end
	piece.Parent = parent
	return piece
end

--[[
	Cat de lat si cat de inalt se vede un model dintr-o anumita directie.

	Nu `GetExtentsSize`: aia da cutia aliniata cu axele lumii, care raspunde la
	intrebarea "cat ocupa pe X" — nu la "cat ocupa pe ecran" cand camera priveste
	piezis. Aici se proiecteaza toate cele opt colturi ale fiecarei piese pe axele
	camerei si se ia intinderea lor. Un zid intors la 28 de grade masoara altceva
	decat latimea lui, si asta e valoarea dupa care trebuie incadrat.
]]
local function planarSpan(model: Model, plane: CFrame): (number, number, Vector3)
	local right, up = plane.RightVector, plane.UpVector
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge

	for _, piece in model:GetDescendants() do
		if not piece:IsA("BasePart") then
			continue
		end
		local cf, size = piece.CFrame, piece.Size
		for corner = 0, 7 do
			local point = cf
				* Vector3.new(
					(if corner % 2 < 1 then -0.5 else 0.5) * size.X,
					(if corner % 4 < 2 then -0.5 else 0.5) * size.Y,
					(if corner < 4 then -0.5 else 0.5) * size.Z
				)
			local px, py = point:Dot(right), point:Dot(up)
			minX, maxX = math.min(minX, px), math.max(maxX, px)
			minY, maxY = math.min(minY, py), math.max(maxY, py)
		end
	end

	if minX > maxX then
		return 0, 0, Vector3.zero
	end

	-- Centrul cutiei vazute, ca punct in lume: mijlocul pe fiecare axa a camerei,
	-- plus adancimea lasata asa cum e — deplasarea pe adancime ar schimba marimea.
	local middle = right * ((minX + maxX) / 2) + up * ((minY + maxY) / 2)
	return maxX - minX, maxY - minY, middle
end

--[[
	Aseaza obiectul, si atat.

	`origin` e locul cabinei. Implicit sta departe deasupra hartii, ca sa nu se
	amestece cu lobby-ul. Intoarce `nil` daca obiectul nu are model importat:
	cabina goala nu se deosebeste de una reusita decat uitandu-te la poza, iar
	asteptarea e ca fisierele iesite de aici sa fie bune fara verificare.
]]
function PreviewRig.build(kind: Kind, id: string, parent: Instance, origin: CFrame?): Rig?
	local center = origin or CFrame.new(0, 3000, 0)

	local model = Instance.new("Model")
	model.Name = string.format("PreviewRig_%s_%s", kind, id)

	local item: any = if kind == "Podium"
		then Podium.new(id, model, center, 12)
		else Barricade.display(id, model, center, 20)

	if not item then
		model:Destroy()
		return nil
	end

	if kind == "Podium" then
		item:setSolid(false)
	end

	model.Parent = parent

	local self = setmetatable({}, PreviewRig) :: Rig
	self.Model = model
	self.Item = item
	self.Kind = kind
	self.Id = id
	self.Center = center
	return self
end

--[[
	Ridica fundalul, rama si luminile fata de camera data, si incadreaza obiectul
	in ele.

	Se poate chema de cate ori vrei: ce a pus data trecuta se strange intai, ca
	doua rame suprapuse ar da un decupaj care nu inseamna nimic.

	`fov` e unghiul **vertical** al camerei, cum il tine Roblox. Din el si din cat
	de departe a ramas camera iese inaltimea cadrului; latimea vine din raportul
	casetei. Nu se verifica daca latimea incape pe orizontala, si nu are de ce:
	viewportul Studio e mult mai lat decat inalt, iar un cadru de 1.58 pe 1 e
	limitat de inaltime in orice fereastra rezonabila.
]]
function PreviewRig.frame(self: Rig, camera: CFrame, fov: number)
	for _, child in self.Model:GetChildren() do
		if child:GetAttribute("RigFixture") then
			child:Destroy()
		end
	end

	local skin = Skins.get(self.Id)

	--[[
		Centrul cadrului se ia de pe axa camerei, nu din locul unde a fost ridicata
		cabina.

		Studio incadreaza mijlocul cutiei obiectului, iar obiectul sta cu **talpa**
		in centrul cabinei, nu cu mijlocul — deci camera priveste cu cateva studi
		mai sus. Un cadru construit in jurul cabinei iese atunci descentrat pe
		verticala si o latura cade sub marginea viewportului. Punctul cautat e cel
		de pe axa camerei, la adancimea obiectului: acolo se uita camera, deci
		acolo trebuie sa fie mijlocul pozei.
	]]
	local seen = self.Item.Model:GetBoundingBox().Position
	local depth = (seen - camera.Position):Dot(camera.LookVector)
	local focus = camera.Position + camera.LookVector * depth
	self.Center = CFrame.new(focus)

	--[[
		Planul cadrului: prin centru, cu fata spre camera. `LookVector` al lui
		arata spre camera, deci deplasarile pe `-Z` se apropie de ea si cele pe
		`+Z` se departeaza.
	]]
	local plane = CFrame.lookAt(self.Center.Position, camera.Position)
	local distance = (camera.Position - self.Center.Position).Magnitude

	local height = 2 * distance * math.tan(math.rad(fov) / 2) * FRAME_FILL
	local width = height * FRAME_ASPECT

	local function fixture(name: string, props: { [string]: any }): Part
		local piece = part(name, self.Model, props)
		piece:SetAttribute("RigFixture", true)
		return piece
	end

	--[[
		Fundalul e in spatele obiectului si mult mai mare decat cadrul: cat timp
		umple tot ce prinde camera, marginile lui nu ajung niciodata in poza.

		Fata lui e un `SurfaceGui` cu `LightInfluence = 0`, nu culoarea piesei:
		suprafata trebuie sa ramana perfect plata, aceeasi in fiecare pixel,
		fiindca din doua randari pe fundaluri diferite se scoate transparenta
		obiectului. O suprafata umbrita, cat de putin, ar da o transparenta
		diferita in fiecare colt.

		Culoarea se schimba pe urma, prin `backdrop`. Aici doar exista.
	]]
	local backdropReach = 2
		* (distance + BACKDROP_DISTANCE)
		* math.tan(math.rad(fov) / 2)
		* BACKDROP_OVERSIZE
	local wall = fixture("Backdrop", {
		Size = Vector3.new(backdropReach * FRAME_ASPECT, backdropReach, 1),
		CFrame = plane * CFrame.new(0, 0, BACKDROP_DISTANCE),
		Color = Color3.new(0, 0, 0),
		Material = Enum.Material.SmoothPlastic,
	})

	local surface = Instance.new("SurfaceGui")
	--[[
		Fata dinspre camera e `Front`, nu `Back`.

		Peretele mosteneste orientarea planului, iar `LookVector` al unui CFrame e
		axa **-Z**. Planul priveste spre camera, deci -Z-ul lui arata spre ea, si
		fata numita `Front` — tot cea de pe -Z — e singura pe care o vede. Pe
		`Back`, panza sta in spatele peretelui si nu se vede niciodata: fundalul
		ramane culoarea piesei, luminata, deci nici plat si nici cel cerut.
	]]
	surface.Face = Enum.NormalId.Front
	surface.LightInfluence = 0
	surface.CanvasSize = Vector2.new(64, 64)
	surface.Parent = wall

	local sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.BorderSizePixel = 0
	sheet.BackgroundColor3 = skin.CardColor
	sheet.Parent = surface

	local t = height * MARK_THICKNESS
	local lift = t * 2
	local bars = {
		{
			name = "MarkTop",
			size = Vector3.new(width + 2 * t, t, t),
			at = Vector3.new(0, (height + t) / 2, -lift),
		},
		{
			name = "MarkBottom",
			size = Vector3.new(width + 2 * t, t, t),
			at = Vector3.new(0, -(height + t) / 2, -lift),
		},
		{
			name = "MarkLeft",
			size = Vector3.new(t, height, t),
			at = Vector3.new(-(width + t) / 2, 0, -lift),
		},
		{
			name = "MarkRight",
			size = Vector3.new(t, height, t),
			at = Vector3.new((width + t) / 2, 0, -lift),
		},
	}
	for _, bar in bars do
		fixture(bar.name, {
			Size = bar.size,
			CFrame = plane * CFrame.new(bar.at),
			Color = MARK_COLOR,
			Material = Enum.Material.Neon,
		})
	end

	--[[
		Incadrarea obiectului, in doi timpi: intai se scaleaza pana umple cadrul,
		apoi se muta cu centrul vazut in centrul cadrului. Mutarea e numai in
		planul camerei — impinsa si pe adancime, ar strica scara tocmai calculata.
	]]
	local model = self.Item.Model
	local spanX, spanY = planarSpan(model, plane)
	if spanX > 0 and spanY > 0 then
		local fit = math.min(width * ITEM_FILL / spanX, height * ITEM_FILL / spanY)
		model:ScaleTo(model:GetScale() * fit)
	end

	local _, _, middle = planarSpan(model, plane)
	local target = self.Center.Position
	local offset = plane.RightVector
			* (target:Dot(plane.RightVector) - middle:Dot(plane.RightVector))
		+ plane.UpVector * (target:Dot(plane.UpVector) - middle:Dot(plane.UpVector))
	model:PivotTo(model:GetPivot() + offset)

	for _, lamp in
		{
			{
				name = "Key",
				at = Vector3.new(-width * 0.6, height * 0.8, -distance * 0.5),
				brightness = 2.4,
			},
			{ name = "Fill", at = Vector3.new(width * 0.7, 0, -distance * 0.45), brightness = 1 },
		}
	do
		local bulb = fixture("Lamp" .. lamp.name, {
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = plane * CFrame.new(lamp.at),
			Transparency = 1,
		})
		local light = Instance.new("PointLight")
		light.Brightness = lamp.brightness
		light.Range = distance * 3
		light.Shadows = true
		light.Parent = bulb
	end
end

--[[
	Schimba culoarea fundalului, fara sa atinga nimic altceva.

	Exista pentru ca poza se face de doua ori: o data pe negru, o data pe alb.
	Obiectul se randeaza identic in amandoua — nimic din cabina nu lumineaza, iar
	bloom-ul si adancimea de camp sunt oprite de `stage` — deci singura diferenta
	dintre cele doua imagini vine din cat fundal se vede prin fiecare pixel. De
	acolo se scoate transparenta, si cu ea un decupaj cu margini adevarate, nu
	unul taiat dupa o culoare-cheie.

	Asta e si motivul pentru care nu se incearca randarea fundalului direct in
	`CardColor`: motorul trece tot prin tonemapping, iar o culoare ceruta nu iese
	niciodata identica din randare. Un obiect decupat nu are nevoie sa iasa: se
	aseaza peste caseta magazinului, care are chiar culoarea ceruta.
]]
function PreviewRig.backdrop(self: Rig, color: Color3)
	local wall = self.Model:FindFirstChild("Backdrop")
	local sheet = wall and wall:FindFirstChild("Sheet", true)
	if sheet and sheet:IsA("Frame") then
		sheet.BackgroundColor3 = color
	end
end

--[[
	Pune pe pauza tot ce coloreaza randarea, si intoarce functia care da inapoi.

	Place-ul are expunerea trasa cu jumatate de treapta in jos, ceata de
	atmosfera, bloom, raze de soare si adancime de camp. Toate sunt bune in joc si
	toate strica o poza de produs: fundalul Neon iesea maro-rosu in loc de culoarea
	ceruta, pentru ca ceata il atingea la patruzeci de studi departare, iar
	expunerea ii mai lua din lumina.

	Nu e o setare schimbata pe furis. E imprumutata pe durata pozei si data
	inapoi: apelantul primeste functia de restaurare si e dator sa o cheme, si o
	cheama chiar daca poza a esuat. De aceea starea veche se tine in closure, nu
	intr-un tabel global — nu exista drum prin care sa se piarda intre timp.
]]
function PreviewRig.stage(): () -> ()
	local Lighting = game:GetService("Lighting")
	local undo: { () -> () } = {}

	local exposure = Lighting.ExposureCompensation
	Lighting.ExposureCompensation = 0
	table.insert(undo, function()
		Lighting.ExposureCompensation = exposure
	end)

	for _, effect in Lighting:GetChildren() do
		if effect:IsA("PostEffect") then
			local was = effect.Enabled
			effect.Enabled = false
			table.insert(undo, function()
				effect.Enabled = was
			end)
		elseif effect:IsA("Atmosphere") then
			local density, haze = effect.Density, effect.Haze
			effect.Density, effect.Haze = 0, 0
			table.insert(undo, function()
				effect.Density, effect.Haze = density, haze
			end)
		end
	end

	return function()
		for _, step in undo do
			step()
		end
	end
end

function PreviewRig.destroy(self: Rig)
	if self.Item then
		self.Item:destroy()
		self.Item = nil
	end
	self.Model:Destroy()
end

return PreviewRig
