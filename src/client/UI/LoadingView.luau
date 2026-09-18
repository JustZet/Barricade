--!strict
--[[
	LoadingView — ecranul de pornire, cat se aduc asseturile.

	Exista pentru un motiv concret, nu de decor: mesh-urile tablei sunt sute de
	piese, iar daca nu sunt cerute din timp, Roblox le aduce **in timpul
	meciului** — celulele apar una cate una sub picioarele jucatorilor, iar
	zidurile se materializeaza dupa ce au fost deja puse. Ecranul asta tine
	jocul acoperit exact cat dureaza aducerea lor.

	Sigla nu e o imagine incarcata separat: e chiar emblema de pe mijlocul
	tablei, scoasa din model si pusa intr-un `ViewportFrame`. Asa, ce vezi cat
	astepti e chiar obiectul care se incarca.

	Litera cu litera, nu tot deodata: asteptarea are nevoie de ceva care sa se
	miste, altfel un ecran fix de cateva secunde pare inghetat.
]]

local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local TITLE = "BARRICADE"
local LETTER_DELAY = 0.06
local FADE = 0.45

--[[
	Cat sta ecranul pe loc, cel putin.

	Cand asseturile sunt deja in cache — a doua pornire, sau un jucator care
	revine — preincarcarea se termina intr-o clipa, iar ecranul ar clipi si ar
	disparea. Un fulger de o zecime de secunda deranjeaza mai mult decat o
	asteptare scurta, si oricum titlul are nevoie de atat cat sa se scrie.
]]
local MIN_DISPLAY = #TITLE * LETTER_DELAY + 1.1

local LoadingView = {}
LoadingView.__index = LoadingView

type LoadingFields = {
	Screen: ScreenGui,
	Letters: { TextLabel },
	Status: TextLabel,
	Fill: Frame,
	Emblem: ViewportFrame?,
	Spinning: boolean,
	OpenedAt: number,
}

export type LoadingView = typeof(setmetatable({} :: LoadingFields, LoadingView))

--[[
	Scoate emblema din tabla si o pregateste pentru `ViewportFrame`.

	Se ia o copie, nu originalul: modelul din `Assets` e sursa din care se
	cladesc mesele, si nu are voie sa ramana ciuntit dupa ecranul de incarcare.
]]
local function buildEmblem(parent: Instance): ViewportFrame?
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local board = assets and assets:FindFirstChild("Board")
	if not board then
		return nil
	end

	local pieces = {}
	for _, piece in ipairs(board:GetDescendants()) do
		if piece:IsA("BasePart") and string.find(piece.Name, "^emblem") then
			table.insert(pieces, piece)
		end
	end
	if #pieces == 0 then
		return nil
	end

	local holder = Instance.new("Model")
	holder.Name = "Emblem"
	local center = Vector3.zero
	for _, piece in pieces do
		local copy = piece:Clone()
		copy.Anchored = true
		copy.Parent = holder
		center += piece.Position
	end
	center /= #pieces

	local viewport = Theme.create("ViewportFrame", {
		Name = "EmblemViewport",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(190, 190),
		Ambient = Color3.fromHex("8A6034"),
		LightColor = Color3.fromHex("FFF3DC"),
		Parent = parent,
	}) :: ViewportFrame

	holder:PivotTo(CFrame.new(center))
	holder.Parent = viewport

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 26, 0.01), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	return viewport
end

function LoadingView.new(parent: Instance): LoadingView
	local self = setmetatable({}, LoadingView) :: LoadingView
	self.Letters = {}
	self.Spinning = true
	self.OpenedAt = os.clock()

	local screen = Theme.create("ScreenGui", {
		Name = "Loading",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		-- Peste orice altceva: acopera si lumea, si interfata de meci.
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	}) :: ScreenGui
	self.Screen = screen

	local backdrop = Theme.create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Backdrop,
		BorderSizePixel = 0,
		Parent = screen,
	}, {
		Theme.create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromHex("46331E"), Theme.Color.Backdrop),
		}),
	}) :: Frame

	self.Emblem = buildEmblem(backdrop)

	--[[
		Fiecare litera e propriul `TextLabel`, asezat de un layout orizontal.
		Un singur label nu s-ar putea anima pe bucati, iar taierea textului
		caracter cu caracter ar face randul sa salte la fiecare adaugare.
	]]
	local row = Theme.create("Frame", {
		Name = "Title",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(620, 96),
		Parent = backdrop,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	for index = 1, #TITLE do
		local letter = Theme.text({
			Name = "L" .. index,
			Text = string.sub(TITLE, index, index),
			Font = Theme.Font.Bold,
			TextSize = 64,
			TextColor3 = Theme.Color.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = 1,
			Size = UDim2.fromOffset(46, 92),
			LayoutOrder = index,
			Parent = row,
		})
		table.insert(self.Letters, letter)
	end

	self.Status = Theme.text({
		Name = "Status",
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromOffset(420, 22),
		Parent = backdrop,
	})

	-- Bara de progres: aceeasi pastila de lemn ca in restul interfetei.
	local track = Theme.create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromOffset(360, 10),
		BackgroundColor3 = Color3.fromHex("3B2412"),
		BorderSizePixel = 0,
		Parent = backdrop,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	self.Fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Color.Highlight,
		BorderSizePixel = 0,
		Parent = track,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	return self
end

-- Literele apar una cate una, cu o mica ridicare.
function LoadingView.animateTitle(self: LoadingView)
	task.spawn(function()
		for _, letter in self.Letters do
			if not letter.Parent then
				return
			end
			letter.Position = UDim2.fromOffset(0, 10)
			TweenService
				:Create(
					letter,
					TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{
						TextTransparency = 0,
						Position = UDim2.fromOffset(0, 0),
					}
				)
				:Play()
			task.wait(LETTER_DELAY)
		end
	end)
end

-- Emblema se roteste incet, ca ecranul sa nu para inghetat.
function LoadingView.spinEmblem(self: LoadingView)
	local viewport = self.Emblem
	if not viewport then
		return
	end
	local model = viewport:FindFirstChildOfClass("Model")
	if not model then
		return
	end

	task.spawn(function()
		local pivot = model:GetPivot()
		while self.Spinning and viewport.Parent do
			model:PivotTo(pivot * CFrame.Angles(0, math.rad(0.6), 0))
			pivot = model:GetPivot()
			task.wait()
		end
	end)
end

function LoadingView.setProgress(self: LoadingView, done: number, total: number, label: string?)
	local ratio = if total > 0 then math.clamp(done / total, 0, 1) else 0
	TweenService:Create(self.Fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(ratio, 1) }):Play()
	if label then
		self.Status.Text = label
	end
end

--[[
	Cere asseturile din timp.

	`PreloadAsync` primeste instantele si se ocupa de tot ce atarna de ele, deci
	un singur folder acopera si tabla, si toate skinurile. Se merge pe bucati ca
	sa existe progres: o singura chemare ar sta pana la capat fara sa spuna cat
	a mai ramas.
]]
function LoadingView.preload(self: LoadingView, roots: { Instance })
	local queue = {}
	for _, root in roots do
		table.insert(queue, root)
		for _, descendant in ipairs(root:GetDescendants()) do
			if
				descendant:IsA("BasePart")
				or descendant:IsA("Decal")
				or descendant:IsA("Texture")
			then
				table.insert(queue, descendant)
			end
		end
	end

	local total = #queue
	local done = 0
	local batch = {}

	for index, item in queue do
		table.insert(batch, item)
		if #batch >= 40 or index == total then
			pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			done += #batch
			batch = {}
			self:setProgress(
				done,
				total,
				string.format("Se incarca tabla · %d%%", math.floor(done / total * 100))
			)
		end
	end

	self:setProgress(total, total, "Gata")
end

function LoadingView.finish(self: LoadingView)
	local shown = os.clock() - self.OpenedAt
	if shown < MIN_DISPLAY then
		task.wait(MIN_DISPLAY - shown)
	end

	self.Spinning = false
	local backdrop = self.Screen:FindFirstChild("Backdrop")
	if not backdrop then
		self.Screen:Destroy()
		return
	end

	for _, descendant in ipairs(self.Screen:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, TweenInfo.new(FADE), { TextTransparency = 1 }):Play()
		elseif descendant:IsA("Frame") or descendant:IsA("ViewportFrame") then
			TweenService:Create(descendant, TweenInfo.new(FADE), { BackgroundTransparency = 1 })
				:Play()
		end
	end

	task.delay(FADE + 0.05, function()
		self.Screen:Destroy()
	end)
end

return LoadingView
