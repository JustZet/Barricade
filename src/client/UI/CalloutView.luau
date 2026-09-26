--!strict
--[[
	CalloutView — textul care explodeaza pe tabla dupa o mutare.

	Primeste un callout deja formatat (`Callouts.format`) si un punct pe ecran,
	si il aseaza acolo: pe baricada care tocmai a cazut, sau deasupra pionului
	care a sarit. Nu stie de reguli, de sloturi sau de lumea 3D — cine il cheama
	ii spune ce sa scrie si unde.

	Trei marimi, trei feluri de a intra:

	  1 — apare cu un mic salt, urca si se stinge
	  2 — la fel, plus o clatinare la intrare si un gradient care curge
	  3 — literele intra una dupa alta, cu un pumn de scala, un curcubeu care se
	      roteste si un fulger scurt peste tot ecranul

	Are `ScreenGui`-ul lui, peste interfata jocului: textul trebuie sa treaca
	peste tabla si peste carduri, dar nu are voie sa prinda niciun clic. Nimic de
	aici nu e `Active`, iar stratul nu primeste intrare.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Callouts = require(ReplicatedStorage.Shared.Callouts)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local Theme = require(script.Parent.Theme)

local SETTINGS = GameConfig.Callouts

local CalloutView = {}
CalloutView.__index = CalloutView

type CalloutFields = {
	Screen: ScreenGui,
	Layer: Frame,
	Flash: Frame,
	-- Buclele pornite de callout-urile vii, oprite la `clear`.
	Loops: { [RBXScriptConnection]: boolean },
	--[[
		Creste la fiecare `clear`. O intarziere programata inainte de curatare
		isi compara numarul cu cel de acum si, daca s-a schimbat, nu mai deseneaza
		nimic: altfel un callout al meciului trecut ar aparea in lobby.
	]]
	Generation: number,
}

export type CalloutView = typeof(setmetatable({} :: CalloutFields, CalloutView))

export type ShowOptions = {
	-- Cat asteapta inainte sa apara, in secunde.
	Delay: number?,
	-- Al catelea callout al aceleiasi actiuni: urmatoarele se asaza mai sus.
	Index: number?,
	-- Chemat in clipa impactului pe marimea 3, pentru tremurul camerei.
	OnImpact: (() -> ())?,
}

local function hex(value: number): Color3
	return Color3.fromHex(string.format("%06X", value))
end

-- Un gradient din culori hex, la distante egale.
local function sequence(colors: { number }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(hex(colors[1]))
	end
	local points = {}
	for index, value in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), hex(value)))
	end
	return ColorSequence.new(points)
end

-- O culoare din curcubeu, la pozitia `t` (0..1, circular).
local function rainbowAt(t: number): Color3
	local colors = Callouts.Rainbow
	local count = #colors
	local position = (t % 1) * count
	local index = math.floor(position)
	local a = hex(colors[index + 1])
	local b = hex(colors[(index + 1) % count + 1])
	return a:Lerp(b, position - index)
end

function CalloutView.new(parent: Instance): CalloutView
	local self = setmetatable({}, CalloutView) :: CalloutView

	self.Screen = Theme.create("ScreenGui", {
		Name = "BarricadeCallouts",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Peste interfata jocului (0) si butonul de muzica (5), sub cortina (100).
		DisplayOrder = 6,
		Parent = parent,
	}) :: ScreenGui

	self.Layer = Theme.create("Frame", {
		Name = "Callouts",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = self.Screen,
	}) :: Frame

	self.Flash = Theme.create("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = self.Screen,
	}) :: Frame

	self.Loops = {}
	self.Generation = 0
	return self
end

-- O eticheta de text cu conturul gros si, daca e cazul, gradientul ei.
local function label(text: string, size: number, order: number, colors: ColorSequence?): TextLabel
	local stroke = Theme.create("UIStroke", {
		Color = hex(Callouts.Stroke),
		Thickness = math.max(2, math.floor(size * 0.1)),
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})

	local part = Theme.text({
		Name = "Part",
		Text = text,
		Font = Theme.Font.Bold,
		TextSize = size,
		TextColor3 = Color3.new(1, 1, 1),
		RichText = false,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = order,
		Active = false,
	})
	stroke.Parent = part
	Theme.create("UIScale", { Scale = 1, Parent = part })
	if colors then
		Theme.create("UIGradient", { Color = colors, Parent = part })
	end
	return part
end

-- Taie un sir UTF-8 in caractere, ca literele sa poata intra una cate una.
local function characters(text: string): { string }
	local list = {}
	for _, code in utf8.codes(text) do
		table.insert(list, utf8.char(code))
	end
	return list
end

--[[
	Stinge tot ce e text in callout: litera si conturul ei, impreuna. Un contur
	lasat plin peste o litera stinsa ar ramane ca o umbra goala pe ecran.
]]
local function fadeOut(root: Frame, seconds: number)
	for _, node in root:GetDescendants() do
		if node:IsA("TextLabel") then
			AnimationController.tween(node, { TextTransparency = 1 }, seconds, "calloutFade")
		elseif node:IsA("UIStroke") then
			AnimationController.tween(node, { Transparency = 1 }, seconds, "calloutFade")
		end
	end
end

--[[
	Aseaza punctul in ecran. Un text pus pe o baricada de pe margine s-ar taia
	jumatate in afara; se strange spre interior doar cat trebuie.
]]
local function clampPoint(self: CalloutView, point: Vector2?): Vector2
	local size = self.Layer.AbsoluteSize
	local fallback = Vector2.new(size.X / 2, size.Y * 0.4)
	local at = point or fallback
	return Vector2.new(
		math.clamp(at.X, size.X * 0.14, size.X * 0.86),
		math.clamp(at.Y, size.Y * 0.2, size.Y * 0.92)
	)
end

function CalloutView.show(
	self: CalloutView,
	presented: Callouts.Presented,
	point: Vector2?,
	options: ShowOptions?
)
	local opts: ShowOptions = options or {}
	local generation = self.Generation

	task.delay(opts.Delay or 0, function()
		if self.Generation ~= generation then
			return
		end
		self:spawn(presented, point, opts)
	end)
end

function CalloutView.spawn(
	self: CalloutView,
	presented: Callouts.Presented,
	point: Vector2?,
	opts: ShowOptions
)
	local tier = math.clamp(presented.Tier, 1, 3)
	local screenHeight = math.max(self.Layer.AbsoluteSize.Y, 1)
	local factor = math.clamp(screenHeight / 900, 0.6, 1.4)
	local textSize = math.floor(SETTINGS.TextSize[tier] * factor)
	local lifetime = SETTINGS.Lifetime[tier]

	local at = clampPoint(self, point)
	at -= Vector2.new(0, (opts.Index or 0) * textSize * 1.3)

	local isVictim = presented.Perspective == "VICTIM"
	local rainbow = tier == 3 and not isVictim
	local colors = if rainbow then nil else sequence(presented.Colors)

	local scale = Theme.create("UIScale", { Scale = 0 }) :: UIScale
	local root = Theme.create("Frame", {
		Name = presented.Id,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(at.X, at.Y),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Active = false,
		Parent = self.Layer,
	}, {
		scale :: Instance,
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	-- Textul: pe marimea 3 litera cu litera, altfel dintr-o bucata.
	local letters: { TextLabel } = {}
	local order = 0
	local function addText(text: string)
		if text == "" then
			return
		end
		if tier == 3 then
			for _, char in characters(text) do
				order += 1
				local part = label(char, textSize, order, colors)
				part.Parent = root
				table.insert(letters, part)
			end
		else
			order += 1
			local part = label(text, textSize, order, colors)
			part.Parent = root
			table.insert(letters, part)
		end
	end

	addText(presented.Prefix)
	local amountLabel: TextLabel? = nil
	if presented.Amount then
		order += 1
		local part = label("1", textSize, order, colors)
		part.Parent = root
		amountLabel = part
		table.insert(letters, part)
	end
	addText(presented.Suffix)

	SoundController.play(presented.Sound)

	-- ------------------------------------------------------------ intrarea

	local peak = if tier == 3 then 1.35 else 1.15
	local popIn = if tier == 3 then 0.22 else 0.18
	AnimationController.tween(scale, { Scale = peak }, popIn, "calloutPop", Enum.EasingStyle.Back).Completed
		:Once(function()
			AnimationController.tween(scale, { Scale = 1 }, 0.14, "calloutPop")
		end)

	if tier >= 2 then
		--[[
			Clatinarea: stanga, dreapta, la loc. Rotirea radacinii roteste si
			literele, fiindca se deseneaza impreuna.
		]]
		root.Rotation = -6
		local swing = TweenService:Create(
			root,
			TweenInfo.new(0.09, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true),
			{ Rotation = 6 }
		)
		swing.Completed:Once(function()
			AnimationController.tween(root, { Rotation = 0 }, 0.08, "calloutSwing")
		end)
		swing:Play()
	end

	if tier == 2 then
		-- Gradientul curge dintr-o parte in alta cat sta textul pe ecran.
		for _, part in letters do
			local gradient = part:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Offset = Vector2.new(-0.5, 0)
				TweenService
					:Create(
						gradient,
						TweenInfo.new(
							0.6,
							Enum.EasingStyle.Sine,
							Enum.EasingDirection.InOut,
							-1,
							true
						),
						{ Offset = Vector2.new(0.5, 0) }
					)
					:Play()
			end
		end
	end

	if tier == 3 then
		-- Literele intra una dupa alta, fiecare cu saltul ei.
		for index, part in letters do
			local own = part:FindFirstChildOfClass("UIScale")
			if own then
				own.Scale = 0
				task.delay((index - 1) * SETTINGS.LetterStagger, function()
					if own.Parent then
						AnimationController.tween(
							own,
							{ Scale = 1 },
							0.16,
							"calloutLetter",
							Enum.EasingStyle.Back
						)
					end
				end)
			end
		end

		-- Fulgerul: alb aproape transparent, stins repede.
		self.Flash.BackgroundTransparency = 0.85
		AnimationController.tween(self.Flash, { BackgroundTransparency = 1 }, 0.35, "calloutFlash")

		if opts.OnImpact then
			opts.OnImpact()
		end

		if rainbow then
			--[[
				Curcubeul se roteste: fiecare litera ia culoarea de la pozitia ei,
				iar pozitiile curg cu timpul. Se scrie `TextColor3`, nu un
				gradient per litera — un gradient nu se poate intinde peste
				mai multe etichete, iar litere cu curcubeie separate ar arata
				ca bucati, nu ca un cuvant.
			]]
			local began = os.clock()
			local loop: RBXScriptConnection
			loop = RunService.RenderStepped:Connect(function()
				if not root.Parent then
					loop:Disconnect()
					self.Loops[loop] = nil
					return
				end
				local phase = (os.clock() - began) * 0.8
				for index, part in letters do
					part.TextColor3 = rainbowAt(phase + index / math.max(#letters, 1))
				end
			end)
			self.Loops[loop] = true
		end
	end

	-- ------------------------------------------------------------ numaratoarea

	local amount = presented.Amount
	local counter = amountLabel
	if amount and counter and amount > 1 then
		local counterScale = counter:FindFirstChildOfClass("UIScale")
		local startDelay = popIn + (if tier == 3 then #letters * SETTINGS.LetterStagger else 0)
		for value = 2, amount do
			task.delay(startDelay + (value - 2) * SETTINGS.CountStep, function()
				if not counter.Parent then
					return
				end
				counter.Text = tostring(value)
				SoundController.play("CalloutCount", 1 + (value - 2) * 0.08)
				if counterScale then
					counterScale.Scale = 1.3
					AnimationController.tween(
						counterScale,
						{ Scale = 1 },
						SETTINGS.CountStep,
						"calloutTick"
					)
				end
			end)
		end
	end

	-- ------------------------------------------------------------ plecarea

	local target = UDim2.fromOffset(at.X, at.Y - SETTINGS.Float)
	AnimationController.tween(
		root,
		{ Position = target },
		lifetime,
		"calloutFloat",
		Enum.EasingStyle.Sine
	)

	local fadeSeconds = lifetime * 0.3
	task.delay(lifetime - fadeSeconds, function()
		if root.Parent then
			fadeOut(root, fadeSeconds)
		end
	end)
	task.delay(lifetime, function()
		if root.Parent then
			for _, node in root:GetDescendants() do
				AnimationController.forget(node)
			end
			AnimationController.forget(root)
			root:Destroy()
		end
	end)
end

--[[
	Sterge tot: callout-urile vii, cele programate si buclele lor. Se cheama la
	plecarea din meci si la fluierul final, ca nimic sa nu ramana plutind peste
	ecranul de victorie sau prin lobby.
]]
function CalloutView.clear(self: CalloutView)
	self.Generation += 1
	for loop in self.Loops do
		loop:Disconnect()
	end
	table.clear(self.Loops)
	for _, node in self.Layer:GetDescendants() do
		AnimationController.forget(node)
	end
	self.Layer:ClearAllChildren()
	AnimationController.forget(self.Flash)
	self.Flash.BackgroundTransparency = 1
end

return CalloutView
