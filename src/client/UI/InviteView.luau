--!strict
--[[
	InviteView — prietenii tai, ca sa-i chemi in joc.

	O lista a jocului, nu fereastra Roblox-ului: prietenii online primii, cu ce
	fac acum („Online", „Playing Barricade", „In this server"), si un INVITE pe
	fiecare. Pe fila ALL apar si cei offline — invitatia ii asteapta ca
	notificare. Jos, INVITE ANY FRIEND deschide totusi alegerea Roblox-ului,
	pentru cine vrea sa trimita mai multora deodata.

	Vederea nu afla nimic singura: lista vine gata de la `SocialController`,
	care o cere Roblox-ului; butoanele doar cer.
]]

local Workspace = game:GetService("Workspace")

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local Avatars = require(script.Parent.Avatars)
local Theme = require(script.Parent.Theme)

local InviteView = {}
InviteView.__index = InviteView

local WIDTH = 460

-- "HERE": in serverul asta; "PLAYING": in Barricade, in alt server.
export type Status = "ONLINE" | "PLAYING" | "HERE" | "OFFLINE"

export type Friend = {
	UserId: number,
	Name: string,
	Status: Status,
}

type InviteFields = {
	Callbacks: { [string]: any },
	Root: Frame,
	Scale: UIScale,
	List: ScrollingFrame,
	Note: TextLabel,
	OnlineTab: TextButton,
	AllTab: TextButton,
	Friends: { Friend },
	OnlineOnly: boolean,
	-- Cui i s-a trimis deja invitatie in sesiunea asta.
	Invited: { [number]: boolean },
	-- "LOADING", "ERROR" sau "READY".
	Phase: string,
	ErrorText: string,
}

export type InviteView = typeof(setmetatable({} :: InviteFields, InviteView))

local ORDER: { [Status]: number } = { ONLINE = 1, PLAYING = 2, HERE = 3, OFFLINE = 4 }

local STATUS_TEXT: { [Status]: string } = {
	ONLINE = "Online",
	PLAYING = "Playing Barricade",
	HERE = "In this server",
	OFFLINE = "Offline",
}

local function fitScale(): number
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1000
	return math.min(1, (width - 24) / WIDTH)
end

function InviteView.new(parent: Instance): InviteView
	local self = setmetatable({}, InviteView) :: InviteView
	self.Callbacks = {} :: { [string]: any }
	self.Friends = {}
	self.OnlineOnly = true
	self.Invited = {}
	self.Phase = "LOADING"
	self.ErrorText = ""

	local root = Theme.create("Frame", {
		Name = "Invite",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, 500),
		Visible = false,
		Active = true,
		ZIndex = 40,
		Parent = parent,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 2),
		Theme.padding(16),
	}) :: Frame
	self.Root = root
	self.Scale = Theme.create("UIScale", { Scale = 1, Parent = root }) :: UIScale

	Theme.text({
		Name = "Title",
		Text = "INVITE FRIENDS",
		Font = Theme.Font.Bold,
		TextSize = 22,
		Size = UDim2.new(1, -56, 0, 30),
		ZIndex = 41,
		Parent = root,
	})

	local close = Theme.button({
		Name = "Close",
		Text = "X",
		Skin = "Secondary",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(44, 44),
		ZIndex = 41,
		Parent = root,
	})
	close.MouseButton1Click:Connect(function()
		self:close()
	end)

	self.Note = Theme.text({
		Name = "Note",
		Text = "A friend new to Barricade gets you both bonus coins.",
		TextColor3 = Theme.Color.Highlight,
		TextSize = 14,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, -56, 0, 20),
		ZIndex = 41,
		Parent = root,
	})

	local tabs = Theme.create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 41,
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	local function tab(name: string, text: string, order: number, onlineOnly: boolean): TextButton
		local button = Theme.button({
			Name = name,
			Text = text,
			Skin = "Secondary",
			TextSize = 14,
			Size = UDim2.fromOffset(110, 40),
			LayoutOrder = order,
			ZIndex = 42,
			Parent = tabs,
		})
		button.MouseButton1Click:Connect(function()
			self.OnlineOnly = onlineOnly
			self:redraw()
		end)
		return button
	end
	self.OnlineTab = tab("Online", "ONLINE", 1, true)
	self.AllTab = tab("All", "ALL", 2, false)

	self.List = Theme.create("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 110),
		Size = UDim2.new(1, 0, 1, -172),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ZIndex = 41,
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame

	local any = Theme.button({
		Name = "InviteAny",
		Text = "INVITE ANY FRIEND",
		Skin = "Primary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 52),
		ZIndex = 41,
		Parent = root,
	})
	any.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onInviteAny
		if callback then
			callback()
		end
	end)

	return self
end

function InviteView.setCallbacks(self: InviteView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

local function message(self: InviteView, text: string)
	Theme.text({
		Name = "Message",
		Text = text,
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -8, 0, 48),
		ZIndex = 42,
		Parent = self.List,
	})
end

local function row(self: InviteView, friend: Friend, order: number)
	local frame = Theme.create("Frame", {
		Name = "Friend_" .. friend.UserId,
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, 62),
		LayoutOrder = order,
		ZIndex = 42,
		Parent = self.List,
	}, { Theme.corner(Theme.Radius.Medium) }) :: Frame

	local image = Theme.create("ImageLabel", {
		Name = "Avatar",
		BackgroundColor3 = Theme.Color.Backdrop,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(46, 46),
		ZIndex = 43,
		Parent = frame,
	}, { Theme.corner(Theme.Radius.Round) }) :: ImageLabel
	Avatars.fetch(friend.UserId, function(content: string)
		if image.Parent then
			image.Image = content
		end
	end)

	-- Un punct colorat pe avatar spune dintr-o privire cine e online.
	local online = friend.Status ~= "OFFLINE"
	Theme.create("Frame", {
		Name = "Dot",
		BackgroundColor3 = if online then Theme.Color.Valid else Theme.Color.TextMuted,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(40, 40),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 44,
		Parent = frame,
	}, { Theme.corner(Theme.Radius.Round), Theme.stroke(Theme.Color.Surface, 2) })

	Theme.text({
		Name = "Name",
		Text = friend.Name,
		Font = Theme.Font.Bold,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(64, 9),
		Size = UDim2.new(1, -200, 0, 22),
		ZIndex = 43,
		Parent = frame,
	})
	Theme.text({
		Name = "Status",
		Text = STATUS_TEXT[friend.Status],
		TextColor3 = if online then Theme.Color.Valid else Theme.Color.TextMuted,
		TextSize = 13,
		Position = UDim2.fromOffset(64, 33),
		Size = UDim2.new(1, -200, 0, 18),
		ZIndex = 43,
		Parent = frame,
	})

	local invited = self.Invited[friend.UserId] == true
	local here = friend.Status == "HERE"
	local button = Theme.button({
		Name = "Invite",
		Text = if here then "HERE" elseif invited then "INVITED" else "INVITE",
		Skin = if here or invited then "Secondary" else "Primary",
		TextSize = 14,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(116, 46),
		ZIndex = 43,
		Parent = frame,
	})
	Theme.setButtonEnabled(button, not here)
	button.MouseButton1Click:Connect(function()
		if not button.Active then
			return
		end
		local callback = self.Callbacks.onInvite
		if callback then
			callback(friend.UserId)
		end
	end)
end

function InviteView.redraw(self: InviteView)
	for _, child in self.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Placa se inmulteste cu culoarea: alb o lasa cum e, gri o stinge.
	local active, idle = Color3.new(1, 1, 1), Color3.fromRGB(130, 130, 130)
	Theme.recolorButton(self.OnlineTab, if self.OnlineOnly then active else idle)
	Theme.recolorButton(self.AllTab, if self.OnlineOnly then idle else active)

	if self.Phase == "LOADING" then
		message(self, "Loading your friends…")
		return
	elseif self.Phase == "ERROR" then
		message(self, self.ErrorText)
		return
	end

	local shown = 0
	for index, friend in self.Friends do
		if not self.OnlineOnly or friend.Status ~= "OFFLINE" then
			row(self, friend, index)
			shown += 1
		end
	end

	if shown == 0 then
		message(
			self,
			if self.OnlineOnly
				then "None of your friends are online right now. Try ALL, or invite anyone below."
				else "No friends to show yet. Invite anyone below."
		)
	end
end

function InviteView.setLoading(self: InviteView)
	self.Phase = "LOADING"
	self:redraw()
end

function InviteView.setError(self: InviteView, text: string)
	self.Phase = "ERROR"
	self.ErrorText = text
	self:redraw()
end

-- Lista venita de la controller: online primii, apoi dupa nume.
function InviteView.setFriends(self: InviteView, friends: { Friend })
	table.sort(friends, function(a: Friend, b: Friend): boolean
		if a.Status ~= b.Status then
			return ORDER[a.Status] < ORDER[b.Status]
		end
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	self.Friends = friends
	self.Phase = "READY"
	self:redraw()
end

-- Cui a plecat invitatia, dupa ce s-a inchis fereastra Roblox-ului.
function InviteView.markInvited(self: InviteView, userIds: { any })
	for _, userId in userIds do
		if type(userId) == "number" then
			self.Invited[userId] = true
		end
	end
	if self.Root.Visible then
		self:redraw()
	end
end

function InviteView.isOpen(self: InviteView): boolean
	return self.Root.Visible
end

function InviteView.open(self: InviteView)
	if self.Root.Visible then
		return
	end
	self.Root.Visible = true
	self.Scale.Scale = fitScale() * 0.85
	AnimationController.tween(
		self.Scale,
		{ Scale = fitScale() },
		0.25,
		"open",
		Enum.EasingStyle.Back
	)
	self:redraw()
end

function InviteView.close(self: InviteView)
	self.Root.Visible = false
end

return InviteView
