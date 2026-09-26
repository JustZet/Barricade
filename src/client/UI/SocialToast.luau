--!strict
--[[
	SocialToast — notificarile mici din coltul de sus-dreapta.

	„{name} joined the server", „You joined through {name}! +100", „Ana
	declined". Intra glisand din dreapta cu un mic salt, stau cateva secunde si
	pleaca singure. Pot purta un buton — „Challenge" pe prietenul care tocmai a
	intrat — mare cat sa se apese cu degetul.

	Se strang in coloana, cel mult cateva deodata; cel mai vechi pleaca primul
	cand vine altul peste limita.
]]

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local Theme = require(script.Parent.Theme)

local SocialToast = {}
SocialToast.__index = SocialToast

local WIDTH, HEIGHT = 320, 64
local LIMIT = 3

type ToastFields = {
	Stack: Frame,
	Live: { Frame },
}

export type SocialToast = typeof(setmetatable({} :: ToastFields, SocialToast))

export type Options = {
	-- Textul butonului, daca are unul.
	Action: string?,
	OnAction: (() -> ())?,
	Seconds: number?,
	-- Culoarea dungii din stanga: verde pentru vesti bune, rosu pentru refuzuri.
	Tone: ("good" | "bad" | "info")?,
}

function SocialToast.new(parent: Instance): SocialToast
	local self = setmetatable({}, SocialToast) :: SocialToast
	self.Live = {}

	self.Stack = Theme.create("Frame", {
		Name = "SocialToasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 70),
		Size = UDim2.fromOffset(WIDTH, (HEIGHT + 8) * LIMIT),
		ZIndex = 30,
		Parent = parent,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	return self
end

local function dismiss(self: SocialToast, toast: Frame)
	local index = table.find(self.Live, toast)
	if index then
		table.remove(self.Live, index)
	end
	if toast.Parent then
		AnimationController.forget(toast)
		toast:Destroy()
	end
end

function SocialToast.show(self: SocialToast, text: string, options: Options?)
	local opts: Options = options or {}

	while #self.Live >= LIMIT do
		dismiss(self, self.Live[1])
	end

	local tone = opts.Tone or "info"
	local stripe = if tone == "good"
		then Theme.Color.Valid
		elseif tone == "bad" then Theme.Color.Invalid
		else Theme.Color.Highlight

	local holder = Theme.create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		LayoutOrder = os.clock() * 1000 // 1,
		ZIndex = 30,
		Parent = self.Stack,
	}) :: Frame

	-- Cartonasul glisat; `holder` ii tine locul in coloana cat intra.
	local card = Theme.create("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(WIDTH + 40, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 31,
		Parent = holder,
	}, {
		Theme.corner(Theme.Radius.Medium),
		Theme.stroke(stripe, 2),
	}) :: Frame

	Theme.create("Frame", {
		Name = "Stripe",
		BackgroundColor3 = stripe,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 6, 1, 0),
		ZIndex = 32,
		Parent = card,
	}, { Theme.corner(Theme.Radius.Small) })

	local hasAction = opts.Action ~= nil and opts.OnAction ~= nil
	Theme.text({
		Name = "Text",
		Text = text,
		Font = Theme.Font.Bold,
		TextSize = 16,
		TextWrapped = true,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, if hasAction then -140 else -26, 1, 0),
		ZIndex = 32,
		Parent = card,
	})

	if hasAction then
		local button = Theme.button({
			Name = "Action",
			Text = opts.Action,
			Skin = "Primary",
			TextSize = 14,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(116, 46),
			ZIndex = 33,
			Parent = card,
		})
		button.MouseButton1Click:Connect(function()
			local callback = opts.OnAction
			dismiss(self, holder)
			if callback then
				callback()
			end
		end)
	end

	table.insert(self.Live, holder)
	SoundController.play("SocialToast")
	AnimationController.tween(
		card,
		{ Position = UDim2.fromOffset(0, 0) },
		0.35,
		"slide",
		Enum.EasingStyle.Back
	)

	task.delay(opts.Seconds or 4.5, function()
		if not holder.Parent then
			return
		end
		local out = AnimationController.tween(
			card,
			{ Position = UDim2.fromOffset(WIDTH + 40, 0) },
			0.25,
			"slide"
		)
		out.Completed:Once(function()
			dismiss(self, holder)
		end)
	end)
end

return SocialToast
