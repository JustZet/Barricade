--!strict
--[[
	ChallengeView — bannerul unei provocari, primite sau trimise.

	Primita: „Ana challenges you!", modul si cu cine, bara care se goleste si
	ACCEPT / DECLINE. Trimisa: „Challenge sent", pe cine asteptam si CANCEL.
	Dupa inchidere, un rand scurt spune ce s-a intamplat („Ana declined",
	„Challenge expired") si bannerul pleaca singur.

	Ca `RematchView`, nu decide nimic: deseneaza starea venita de la server,
	iar butoanele doar cer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local Theme = require(script.Parent.Theme)

local ChallengeView = {}
ChallengeView.__index = ChallengeView

local WIDTH, HEIGHT = 460, 190

type ChallengeFields = {
	Callbacks: { [string]: any },
	Root: Frame,
	Scale: UIScale,
	Title: TextLabel,
	Subtitle: TextLabel,
	Bar: Frame,
	Fill: Frame,
	Buttons: Frame,
	AcceptButton: TextButton,
	DeclineButton: TextButton,
	CancelButton: TextButton,
	-- Provocarea desenata acum, dupa id.
	Current: string?,
	Hider: thread?,
}

export type ChallengeView = typeof(setmetatable({} :: ChallengeFields, ChallengeView))

local function fitScale(): number
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1000
	return math.min(1, (width - 24) / WIDTH)
end

function ChallengeView.new(parent: Instance): ChallengeView
	local self = setmetatable({}, ChallengeView) :: ChallengeView
	self.Callbacks = {} :: { [string]: any }

	local root = Theme.create("Frame", {
		Name = "Challenge",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Visible = false,
		ZIndex = 35,
		Parent = parent,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Accent, 3),
		Theme.padding(16),
	}) :: Frame
	self.Root = root
	self.Scale = Theme.create("UIScale", { Scale = 1, Parent = root }) :: UIScale

	self.Title = Theme.text({
		Name = "Title",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 26,
		TextColor3 = Theme.Color.Highlight,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 32),
		ZIndex = 36,
		Parent = root,
	})

	self.Subtitle = Theme.text({
		Name = "Subtitle",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 38),
		ZIndex = 36,
		Parent = root,
	})

	self.Bar = Theme.create("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.Color.Backdrop,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 10),
		ZIndex = 36,
		Parent = root,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	self.Fill = Theme.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Color.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 37,
		Parent = self.Bar,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	self.Buttons = Theme.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 50),
		ZIndex = 36,
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	local function button(
		name: string,
		text: string,
		skin: string,
		order: number,
		event: string
	): TextButton
		local made = Theme.button({
			Name = name,
			Text = text,
			Skin = skin,
			Size = UDim2.fromOffset(170, 50),
			LayoutOrder = order,
			ZIndex = 37,
			Parent = self.Buttons,
		})
		made.MouseButton1Click:Connect(function()
			local callback = self.Callbacks[event]
			local id = self.Current
			if callback and id then
				callback(id)
			end
		end)
		return made
	end

	self.AcceptButton = button("Accept", "ACCEPT", "Primary", 1, "onAccept")
	self.DeclineButton = button("Decline", "DECLINE", "Secondary", 2, "onDecline")
	self.CancelButton = button("Cancel", "CANCEL", "Secondary", 3, "onCancel")

	return self
end

function ChallengeView.setCallbacks(self: ChallengeView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

local function cancelHider(self: ChallengeView)
	local hider = self.Hider
	if hider then
		self.Hider = nil
		task.cancel(hider)
	end
end

local function names(list: { any }, except: number?): string
	local out = {}
	for _, entry in list do
		if type(entry) == "table" and entry.UserId ~= except and type(entry.Name) == "string" then
			table.insert(out, entry.Name)
		end
	end
	return table.concat(out, ", ")
end

--[[
	Deseneaza o provocare. `localUserId` hotaraste daca e a ta (trimisa) sau
	pentru tine (primita), si ce butoane vezi.
]]
function ChallengeView.update(self: ChallengeView, payload: any, localUserId: number)
	local from = if type(payload.From) == "table" then payload.From else {}
	local invitees = if type(payload.Invitees) == "table" then payload.Invitees else {}
	local accepted = if type(payload.Accepted) == "table" then payload.Accepted else {}
	local mine = from.UserId == localUserId
	local answered = table.find(accepted, localUserId) ~= nil
	local mode = GameConfig.Modes[payload.Mode]
	local modeName = if mode then mode.DisplayName else tostring(payload.Mode)

	cancelHider(self)
	self.Current = payload.Id

	if not self.Root.Visible then
		self.Root.Visible = true
		self.Scale.Scale = fitScale() * 0.6
		AnimationController.tween(
			self.Scale,
			{ Scale = fitScale() },
			0.35,
			"enter",
			Enum.EasingStyle.Back
		)
	end

	local status = payload.Status
	if status == "Requested" then
		if mine then
			self.Title.Text = "Challenge sent"
			self.Subtitle.Text = string.format("%s · waiting for %s", modeName, names(invitees))
		else
			self.Title.Text = string.format("%s challenges you!", tostring(from.Name))
			local others = names(invitees, localUserId)
			self.Subtitle.Text = if others ~= ""
				then string.format("%s · with %s", modeName, others)
				else modeName
			SoundController.play("SocialToast")
		end
		if answered then
			self.Subtitle.Text = "Accepted · waiting for the others…"
		end
		self.Title.TextColor3 = Theme.Color.Highlight
		self.Bar.Visible = true
		self.Buttons.Visible = true
		self.AcceptButton.Visible = not mine and not answered
		self.DeclineButton.Visible = not mine and not answered
		self.CancelButton.Visible = mine

		local window = if type(payload.Window) == "number"
			then payload.Window
			else GameConfig.Social.ChallengeWindow
		local remaining = if type(payload.Remaining) == "number" then payload.Remaining else window
		self.Fill.Size = UDim2.fromScale(math.clamp(remaining / window, 0, 1), 1)
		AnimationController.tween(
			self.Fill,
			{ Size = UDim2.fromScale(0, 1) },
			remaining,
			"drain",
			Enum.EasingStyle.Linear
		)
		return
	end

	self.Bar.Visible = false
	self.Buttons.Visible = false
	local who = if type(payload.ByName) == "string" then payload.ByName else "A player"
	if status == "Accepted" then
		self.Title.Text = "Challenge accepted!"
		self.Title.TextColor3 = Theme.Color.Valid
		self.Subtitle.Text = "Get ready…"
	else
		self.Title.TextColor3 = Theme.Color.Invalid
		self.Title.Text = if status == "Declined"
			then string.format("%s declined", who)
			elseif status == "Expired" then "Challenge expired"
			elseif payload.Reason == "UNAVAILABLE" then string.format(
				"%s isn't available",
				who
			)
			else "Challenge cancelled"
		self.Subtitle.Text = ""
	end

	self.Hider = task.delay(2.2, function()
		self.Hider = nil
		self:hide()
	end)
end

function ChallengeView.hide(self: ChallengeView)
	cancelHider(self)
	AnimationController.forget(self.Fill)
	self.Root.Visible = false
	self.Current = nil
end

return ChallengeView
