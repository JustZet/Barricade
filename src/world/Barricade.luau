--!strict
--[[
	Barricade — un zid, ca obiect.

	Isi ia corpul din modelul skinului, se aseaza unde ii spune platforma si isi
	tine singur starile: previzualizare valida, previzualizare respinsa, asezare
	definitiva. Platforma nu stie ce e inauntru, iar `Skins` nu stie nimic despre
	animatie — fiecare parte se poate schimba fara sa o atinga pe cealalta.

	Un skin nou inseamna un model in `ReplicatedStorage.Assets.Barricades` si o
	intrare in `Skins`, nu o ramura aici.

	Pozitia nu se calculeaza in fisierul asta. Se cere de la platforma, care
	detine grila; altfel ar exista doua locuri care stiu unde cade un zid, si
	s-ar desincroniza la prima ajustare.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Audio = require(script.Parent.Audio)
local Hover = require(script.Parent.Hover)
local ModelFit = require(script.Parent.ModelFit)
local Skins = require(script.Parent.Skins)

type Skin = Skins.Skin

export type PreviewState = "VALID" | "INVALID" | "PLACED"

-- Culorile de verdict sunt ale interactiunii, nu ale skinului: raspunsul
-- "se poate / nu se poate" trebuie sa arate la fel indiferent cu ce joci.
local VERDICT = {
	Valid = Color3.fromHex("4BA63C"),
	Invalid = Color3.fromHex("D9443F"),
}

local Barricade = {}
Barricade.__index = Barricade

type BarricadeFields = {
	Model: Model,
	Skin: Skin,
	State: PreviewState,
	X: number,
	Y: number,
	Orientation: string,
	Target: CFrame,
	-- Oprirea plutirii, cand zidul e expus in vitrina. Nimic in meci.
	Hovering: (() -> ())?,
}

export type Barricade = typeof(setmetatable({} :: BarricadeFields, Barricade))

--[[
	Modelul skinului. Un id fara model nu are voie sa lase tabla fara zid, deci
	cadem pe skinul implicit si spunem de ce — un zid invizibil ar face jocul de
	necitit, iar jucatorul n-ar intelege ce s-a intamplat.
]]
local function sourceModel(skin: Skin): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Barricades")
	if not folder then
		return nil
	end

	local model = folder:FindFirstChild(skin.Id)
	if not model then
		warn(
			string.format(
				"Barricade: skinul %q nu are model importat; folosesc %q",
				skin.Id,
				Skins.Default
			)
		)
		model = folder:FindFirstChild(Skins.Default)
	end
	return if model and model:IsA("Model") then model else nil
end

--[[
	Culorile pieselor vin din modelul importat si raman ale lui. Ce salvam aici
	e starea de pornire, ca previzualizarea sa poata colora totul in verde sau
	rosu si apoi sa dea inapoi exact cum era.
]]
local function rememberOriginal(model: Model)
	for _, piece in ipairs(model:GetDescendants()) do
		if piece:IsA("BasePart") then
			piece:SetAttribute("OriginalColor", piece.Color)
			piece:SetAttribute("OriginalTransparency", piece.Transparency)
		end
	end
end

--[[
	Corpul gata de folosit: clonat, tintuit pe loc si cu culorile memorate.

	`solid` face diferenta dintre un zid de pe tabla, care chiar blocheaza, si
	unul din vitrina, prin care jucatorul trebuie sa poata trece: o piesa de
	expozitie care te opreste din drum e o piedica, nu o reclama.
]]
local function buildBody(source: Model, name: string, solid: boolean): Model
	local model = source:Clone()
	model.Name = name

	for _, piece in ipairs(model:GetDescendants()) do
		if piece:IsA("BasePart") then
			piece.Anchored = true
			piece.CanCollide = solid
			piece.CanQuery = false
		end
	end

	rememberOriginal(model)
	return model
end

function Barricade.new(
	platform: any,
	wall: { X: number, Y: number, Orientation: string },
	skinId: string?
): Barricade?
	local skin = Skins.get(skinId)
	local source = sourceModel(skin)
	if not source then
		warn("Barricade: nu exista niciun model de zid importat")
		return nil
	end

	local target = platform:cframeForWall(wall.X, wall.Y, wall.Orientation)
	if not target then
		warn(string.format("Barricade: intersectia (%d,%d) nu exista pe tabla", wall.X, wall.Y))
		return nil
	end

	local self = setmetatable({}, Barricade) :: Barricade
	self.Skin = skin
	self.X = wall.X
	self.Y = wall.Y
	self.Orientation = wall.Orientation
	self.State = "PLACED"
	self.Target = target

	local model = buildBody(
		source,
		string.format("Barricade_%d_%d_%s", wall.X, wall.Y, wall.Orientation),
		true
	)
	self.Model = model
	self.Target = ModelFit.onSurface(model, target)

	model.Parent = platform.Model
	return self
end

--[[
	Acelasi zid, dar ca piesa de expozitie: fara tabla si fara coliziune.

	Vitrina din lobby are nevoie de exact acelasi obiect ca meciul — altfel s-ar
	ajunge, inevitabil, la doua variante ale aceluiasi zid care se despart la
	prima modificare. De aceea corpul vine tot din `ReplicatedStorage.Assets`,
	nu dintr-o copie asezata de mana in lobby.

	`span` e lungimea la care se arata, in studs; fara el ramane la marimea din
	meci, care e prea mare pentru un soclu de lobby.
]]
function Barricade.display(
	skinId: string?,
	parent: Instance,
	surface: CFrame,
	span: number?
): Barricade?
	local skin = Skins.get(skinId)
	local source = sourceModel(skin)
	if not source then
		warn("Barricade: nu exista niciun model de zid importat")
		return nil
	end

	local self = setmetatable({}, Barricade) :: Barricade
	self.Skin = skin
	-- Un zid expus nu sta pe nicio intersectie; campurile raman declarate.
	self.X, self.Y, self.Orientation = 0, 0, "Horizontal"
	self.State = "PLACED"

	local model = buildBody(source, "Display_" .. skin.Id, false)
	if span then
		ModelFit.toSpan(model, span)
	end
	self.Target = ModelFit.onSurface(model, surface)
	self.Model = model

	model.Parent = parent
	return self
end

--[[
	Plutirea din vitrina. Sta in obiect, nu in vitrina, pentru ca e
	comportamentul zidului: cine vrea un zid care se arata il cere de aici, nu
	isi scrie propria animatie.
]]
function Barricade.hover(self: Barricade, options: Hover.Options?)
	self:stopHover()
	self.Hovering = Hover.attach(self.Model, self.Target, options)
end

function Barricade.stopHover(self: Barricade)
	local stop = self.Hovering
	if stop then
		self.Hovering = nil
		stop()
	end
end

--[[
	Muta zidul pe alta intersectie, fara sa-l reconstruiasca.

	Exista pentru fantoma care urmareste cursorul: un skin are pana la 76 de
	piese, iar clonarea lui la fiecare miscare de mouse s-ar simti. Asa se misca
	acelasi model, iar clonarea ramane pentru zidurile chiar asezate.
]]
function Barricade.relocate(
	self: Barricade,
	platform: any,
	x: number,
	y: number,
	orientation: string
): boolean
	local target = platform:cframeForWall(x, y, orientation)
	if not target then
		return false
	end

	self.X, self.Y, self.Orientation = x, y, orientation
	self.Target = ModelFit.onSurface(self.Model, target)
	return true
end

function Barricade.setVisible(self: Barricade, visible: boolean)
	for _, piece in ipairs(self.Model:GetDescendants()) do
		if piece:IsA("BasePart") then
			piece.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

--[[
	Previzualizarea. Verdictul se arata prin culoare *si* prin transparenta: un
	zid respins trebuie sa se distinga si de unul asezat, si de unul valid, fara
	sa te bazezi doar pe nuanta.
]]
function Barricade.setPreview(self: Barricade, state: PreviewState)
	self.State = state

	--[[
		Starea se scrie si pe model, ca atribut.

		Unele skinuri isi poarta miscarea in ele — `portal` si `thunder` au
		fiecare un script care le invarte si le aprinde, chiar in modelul din
		`ReplicatedStorage.Assets`. Scripturile alea coloreaza aceleasi piese pe
		care le coloreaza si verdictul de mai jos, iar daca ar merge mai departe
		peste el, fantoma ar clipi intre verde si fulger. Atributul le spune sa
		se dea la o parte: cat e previzualizare, culoarea zidului e un raspuns,
		nu un efect.
	]]
	self.Model:SetAttribute("Preview", state ~= "PLACED")

	for _, piece in ipairs(self.Model:GetDescendants()) do
		if not piece:IsA("BasePart") then
			continue
		end
		piece.CanCollide = state == "PLACED"

		if state == "PLACED" then
			piece.Color = (piece:GetAttribute("OriginalColor") :: Color3) or piece.Color
			piece.Transparency = (piece:GetAttribute("OriginalTransparency") :: number) or 0
		else
			piece.Color = if state == "VALID" then VERDICT.Valid else VERDICT.Invalid
			piece.Transparency = 0.5
		end
	end
end

--[[
	Asezarea: cade de sus si se turteste scurt la impact.

	Cifrele vin din design system (sectiunea 16): 180ms de cadere si o turtire de
	4% pe 40ms. Turtirea e ce face diferenta dintre un obiect care apare si unul
	care chiar aterizeaza.
]]
function Barricade.play(self: Barricade)
	self:setPreview("PLACED")

	local model = self.Model
	local landed = self.Target
	local _, size = model:GetBoundingBox()
	model:PivotTo(landed * CFrame.new(0, size.Y * 2.5, 0))

	local proxy = Instance.new("CFrameValue")
	proxy.Value = model:GetPivot()
	local connection = proxy.Changed:Connect(function(value)
		model:PivotTo(value)
	end)

	local drop = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(proxy, drop, { Value = landed })
	tween.Completed:Connect(function()
		connection:Disconnect()
		proxy:Destroy()
		if model.Parent then
			model:PivotTo(landed)
			self:squash()
		end
	end)
	tween:Play()

	self:playSound(self.Skin.PlaceSound)
end

-- Turtirea de la aterizare, ca zidul sa aiba greutate.
function Barricade.squash(self: Barricade)
	local model = self.Model
	local scale = model:GetScale()
	local squash = TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local proxy = Instance.new("NumberValue")
	proxy.Value = scale
	local connection = proxy.Changed:Connect(function(value)
		if model.Parent then
			model:ScaleTo(value)
		end
	end)

	local out = TweenService:Create(proxy, squash, { Value = scale * 0.96 })
	out.Completed:Connect(function()
		local back = TweenService:Create(proxy, squash, { Value = scale })
		back.Completed:Connect(function()
			connection:Disconnect()
			proxy:Destroy()
		end)
		back:Play()
	end)
	out:Play()
end

-- Zidul respins: se vede ca a fost refuzat, apoi dispare singur.
function Barricade.rejectAndVanish(self: Barricade)
	self:setPreview("INVALID")
	self:playSound(self.Skin.BlockedSound)
	Debris:AddItem(self.Model, 0.45)
end

--[[
	Sunetul iese din corpul zidului, ca sa se auda din directia lui.

	Dar raza in care se aude intreg se intinde cat tot cadrul: ascultatorul e
	camera, iar camera sta sus, departe de tabla. Vezi `GameConfig.WorldSound`.
]]
function Barricade.playSound(self: Barricade, assetId: number)
	--[[
		Sunetele skinurilor sunt oprite dintr-un singur loc, nu sterse din fiecare
		skin: vezi `GameConfig.WorldSound.SkinSounds`. Aici e locul in care trec
		toate, deci aici se opresc.
	]]
	if assetId == 0 or not GameConfig.WorldSound.SkinSounds then
		return
	end
	local anchor = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. assetId
	sound.Volume = GameConfig.WorldSound.Volume
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.RollOffMinDistance = GameConfig.WorldSound.FullRange
	sound.RollOffMaxDistance = GameConfig.WorldSound.FadeRange

	--[[
		Prin grup, ca sa poata fi taiat de butonul de sunet al fiecaruia. Daca
		grupul lipseste — un test care porneste doar lumea, fara server — sunetul
		merge mai departe fara el.
	]]
	local group = SoundService:FindFirstChild(GameConfig.WorldSound.Group)
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end

	sound.Parent = anchor
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	Audio.play(sound)
end

function Barricade.destroy(self: Barricade)
	self:stopHover()
	self.Model:Destroy()
end

return Barricade
