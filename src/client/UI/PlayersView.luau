--!strict
--[[
	PlayersView — „Players in server", si provocarea pornita din ea.

	O lista cu toti ceilalti din server: prietenii primii, cu insigna FRIEND,
	apoi restul. Pe fiecare rand scrie unde e omul („In a match", „In queue")
	si doua butoane: CHALLENGE si ADD FRIEND. Acelasi rand, singur, e si meniul
	mic care se deschide cand apesi pe avatarul cuiva in lume.

	CHALLENGE duce la alegerea modului. 1v1 merge oricand; 2v2, 3 Players si 4
	Players doar daca sunt destui oameni liberi, iar pentru ele alegi si pe
	ceilalti din lista. Ce se trimite e doar o cerere — serverul verifica tot.

	Vederea nu afla nimic singura: primeste lista gata facuta (`refresh`) de la
	`SocialController`, care stie prietenii si prezenta.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local Avatars = require(script.Parent.Avatars)
local Theme = require(script.Parent.Theme)

local PlayersView = {}
PlayersView.__index = PlayersView

local WIDTH = 460
local ROW = 66

export type Entry = {
	UserId: number,
	Name: string,
	-- "MATCH", "QUEUE" sau nimic: unde e acum.
	Presence: string?,
	Friend: boolean,
}

type PlayersFields = {
	Callbacks: { [string]: any },
	Root: Frame,
	Scale: UIScale,
	Title: TextLabel,
	List: ScrollingFrame,
	Picker: Frame,
	PickerTitle: TextLabel,
	Modes: Frame,
	Others: ScrollingFrame,
	SendButton: TextButton,
	Entries: { Entry },
	-- Doar randul asta, cand e deschis ca meniu mic pe un om anume.
	Focus: number?,
	-- Provocarea in lucru: pe cine, in ce mod, cu cine altcineva.
	Target: Entry?,
	Mode: string?,
	Picked: { number },
}

export type PlayersView = typeof(setmetatable({} :: PlayersFields, PlayersView))

local function fitScale(): number
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1000
	return math.min(1, (width - 24) / WIDTH)
end

function PlayersView.new(parent: Instance): PlayersView
	local self = setmetatable({}, PlayersView) :: PlayersView
	self.Callbacks = {} :: { [string]: any }
	self.Entries = {}
	self.Picked = {}

	local root = Theme.create("Frame", {
		Name = "Players",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, 460),
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

	self.Title = Theme.text({
		Name = "Title",
		Text = "PLAYERS IN SERVER",
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

	self.List = Theme.create("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
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

	-- Alegerea modului, peste lista.
	local picker = Theme.create("Frame", {
		Name = "Picker",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Visible = false,
		ZIndex = 41,
		Parent = root,
	}) :: Frame
	self.Picker = picker

	self.PickerTitle = Theme.text({
		Name = "PickerTitle",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 22),
		ZIndex = 42,
		Parent = picker,
	})

	self.Modes = Theme.create("Frame", {
		Name = "Modes",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 104),
		ZIndex = 42,
		Parent = picker,
	}, {
		Theme.create("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 48),
			CellPadding = UDim2.fromOffset(12, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	self.Others = Theme.create("ScrollingFrame", {
		Name = "Others",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 1, -200),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		ZIndex = 42,
		Parent = picker,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame

	local back = Theme.button({
		Name = "Back",
		Text = "BACK",
		Skin = "Secondary",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -6, 0, 50),
		ZIndex = 42,
		Parent = picker,
	})
	back.MouseButton1Click:Connect(function()
		self:showList()
	end)

	self.SendButton = Theme.button({
		Name = "Send",
		Text = "SEND CHALLENGE",
		Skin = "Primary",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -6, 0, 50),
		ZIndex = 42,
		Parent = picker,
	})
	self.SendButton.MouseButton1Click:Connect(function()
		self:send()
	end)

	return self
end

function PlayersView.setCallbacks(self: PlayersView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

local function presenceText(entry: Entry): (string, Color3)
	if entry.Presence == "MATCH" then
		return "In a match", Theme.Color.TextMuted
	elseif entry.Presence == "QUEUE" then
		return "In queue", Theme.Color.TextMuted
	end
	return "Available", Theme.Color.Valid
end

local function avatar(parent: Instance, userId: number, size: number): ImageLabel
	local image = Theme.create("ImageLabel", {
		Name = "Avatar",
		BackgroundColor3 = Theme.Color.Backdrop,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 43,
		Parent = parent,
	}, { Theme.corner(Theme.Radius.Round) }) :: ImageLabel
	Avatars.fetch(userId, function(content: string)
		if image.Parent then
			image.Image = content
		end
	end)
	return image
end

-- Un rand: avatar, nume, insigna, unde e, si cele doua butoane.
local function row(self: PlayersView, entry: Entry, order: number, parent: Instance)
	local frame = Theme.create("Frame", {
		Name = "Row_" .. entry.UserId,
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, ROW),
		LayoutOrder = order,
		ZIndex = 42,
		Parent = parent,
	}, { Theme.corner(Theme.Radius.Medium) }) :: Frame

	local picture = avatar(frame, entry.UserId, 48)
	picture.Position = UDim2.fromOffset(9, 9)

	Theme.text({
		Name = "Name",
		Text = entry.Name,
		Font = Theme.Font.Bold,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(66, 10),
		Size = UDim2.new(1, -300, 0, 22),
		ZIndex = 43,
		Parent = frame,
	})

	local status, color = presenceText(entry)
	Theme.text({
		Name = "Status",
		Text = status,
		TextColor3 = color,
		TextSize = 13,
		Position = UDim2.fromOffset(66, 34),
		Size = UDim2.new(1, -300, 0, 18),
		ZIndex = 43,
		Parent = frame,
	})

	if entry.Friend then
		Theme.create("TextLabel", {
			Name = "FriendBadge",
			BackgroundColor3 = Theme.Color.Highlight,
			BorderSizePixel = 0,
			Font = Theme.Font.Bold,
			Text = "FRIEND",
			TextColor3 = Theme.Color.TextInverse,
			TextSize = 11,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(9, 50),
			Size = UDim2.fromOffset(48, 14),
			ZIndex = 44,
			Parent = frame,
		}, { Theme.corner(Theme.Radius.Round) })
	end

	local challenge = Theme.button({
		Name = "Challenge",
		Text = "CHALLENGE",
		Skin = "Primary",
		TextSize = 13,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, if entry.Friend then -10 else -122, 0.5, 0),
		Size = UDim2.fromOffset(108, 46),
		ZIndex = 43,
		Parent = frame,
	})
	Theme.setButtonEnabled(challenge, entry.Presence == nil)
	challenge.MouseButton1Click:Connect(function()
		if challenge.Active then
			self:showPicker(entry)
		end
	end)

	if not entry.Friend then
		local add = Theme.button({
			Name = "AddFriend",
			Text = "ADD FRIEND",
			Skin = "Secondary",
			TextSize = 13,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(104, 46),
			ZIndex = 43,
			Parent = frame,
		})
		add.MouseButton1Click:Connect(function()
			local callback = self.Callbacks.onAddFriend
			if callback then
				callback(entry.UserId)
			end
		end)
	end
end

local function redrawList(self: PlayersView)
	for _, child in self.List:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local shown = 0
	for index, entry in self.Entries do
		if self.Focus == nil or self.Focus == entry.UserId then
			row(self, entry, index, self.List)
			shown += 1
		end
	end

	if shown == 0 then
		Theme.text({
			Name = "Empty",
			Text = "Nobody else is here yet. Invite a friend!",
			TextColor3 = Theme.Color.TextMuted,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 40),
			ZIndex = 42,
			Parent = self.List,
		})
	end
end

--[[
	Lista noua de la controller. Prietenii primii, apoi dupa nume; asa ii gasesti
	pe ai tai fara sa-i cauti.
]]
function PlayersView.refresh(self: PlayersView, entries: { Entry })
	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.Friend ~= b.Friend then
			return a.Friend
		end
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	self.Entries = entries

	if self.Root.Visible and self.List.Visible then
		redrawList(self)
	end
end

local function openPanel(self: PlayersView)
	if not self.Root.Visible then
		self.Root.Visible = true
		self.Scale.Scale = fitScale() * 0.85
		AnimationController.tween(
			self.Scale,
			{ Scale = fitScale() },
			0.25,
			"open",
			Enum.EasingStyle.Back
		)
	end
end

-- Toata lista.
function PlayersView.open(self: PlayersView)
	self.Focus = nil
	self.Title.Text = "PLAYERS IN SERVER"
	self.Root.Size = UDim2.fromOffset(WIDTH, 460)
	openPanel(self)
	self:showList()
end

-- Meniul mic pe un singur om, deschis din lume.
function PlayersView.openFor(self: PlayersView, userId: number)
	self.Focus = userId
	self.Title.Text = "PLAYER"
	self.Root.Size = UDim2.fromOffset(WIDTH, 150)
	openPanel(self)
	self:showList()
end

--[[
	Direct la alegerea modului pentru un om anume — butonul CHALLENGE din
	notificarea „a intrat un prieten". Daca nu e liber, se deschide doar randul
	lui, ca sa se vada de ce nu.
]]
function PlayersView.challenge(self: PlayersView, userId: number)
	for _, entry in self.Entries do
		if entry.UserId == userId then
			if entry.Presence ~= nil then
				self:openFor(userId)
				return
			end
			self.Focus = nil
			openPanel(self)
			self:showPicker(entry)
			return
		end
	end
end

function PlayersView.isOpen(self: PlayersView): boolean
	return self.Root.Visible
end

function PlayersView.close(self: PlayersView)
	self.Root.Visible = false
	self.Target = nil
	self.Mode = nil
	table.clear(self.Picked)
end

function PlayersView.showList(self: PlayersView)
	self.Picker.Visible = false
	self.List.Visible = true
	self.Target = nil
	redrawList(self)
end

-- Cei liberi, in afara de tine si de cel provocat.
local function available(self: PlayersView, except: number): { Entry }
	local list = {}
	for _, entry in self.Entries do
		if entry.UserId ~= except and entry.Presence == nil then
			table.insert(list, entry)
		end
	end
	return list
end

local function updateSend(self: PlayersView)
	local mode = if self.Mode then GameConfig.Modes[self.Mode] else nil
	local ready = mode ~= nil and #self.Picked == mode.Players - 2
	Theme.setButtonEnabled(self.SendButton, ready)
end

local function redrawOthers(self: PlayersView)
	for _, child in self.Others:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local target = self.Target
	local mode = if self.Mode then GameConfig.Modes[self.Mode] else nil
	if not (target and mode) or mode.Players <= 2 then
		return
	end

	Theme.text({
		Name = "Hint",
		Text = string.format(
			"Pick %d more player%s:",
			mode.Players - 2,
			if mode.Players - 2 == 1 then "" else "s"
		),
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		ZIndex = 43,
		Parent = self.Others,
	})

	for index, entry in available(self, target.UserId) do
		local picked = table.find(self.Picked, entry.UserId) ~= nil
		local toggle = Theme.button({
			Name = "Pick_" .. entry.UserId,
			Text = (if picked then "✓  " else "") .. entry.Name .. (if entry.Friend
				then "  · FRIEND"
				else ""),
			Skin = if picked then "Primary" else "Secondary",
			TextSize = 14,
			Size = UDim2.new(1, -8, 0, 44),
			LayoutOrder = index,
			ZIndex = 43,
			Parent = self.Others,
		})
		toggle.MouseButton1Click:Connect(function()
			local at = table.find(self.Picked, entry.UserId)
			if at then
				table.remove(self.Picked, at)
			elseif #self.Picked < mode.Players - 2 then
				table.insert(self.Picked, entry.UserId)
			end
			redrawOthers(self)
			updateSend(self)
		end)
	end
end

-- Alegerea modului pentru o provocare catre `entry`. Fara mod ales, porneste de la 1v1.
function PlayersView.showPicker(self: PlayersView, entry: Entry, chosen: string?)
	self.Target = entry
	self.Mode = chosen or "1v1"
	table.clear(self.Picked)
	self.List.Visible = false
	self.Picker.Visible = true
	self.Root.Size = UDim2.fromOffset(WIDTH, 460)
	self.Title.Text = "CHALLENGE " .. string.upper(entry.Name)
	self.PickerTitle.Text = "Choose a mode:"

	for _, child in self.Modes:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Cati mai sunt liberi, in afara de tine si de el: de aici se vede ce moduri incap.
	local extra = #available(self, entry.UserId)
	for index, modeId in GameConfig.ModeOrder do
		local mode = GameConfig.Modes[modeId]
		local button = Theme.button({
			Name = "Mode_" .. modeId,
			Text = mode.DisplayName,
			Skin = if modeId == self.Mode then "Primary" else "Secondary",
			TextSize = 15,
			LayoutOrder = index,
			ZIndex = 43,
			Parent = self.Modes,
		})
		Theme.setButtonEnabled(button, mode.Players - 2 <= extra)
		button.MouseButton1Click:Connect(function()
			if button.Active then
				self:showPicker(entry, modeId)
			end
		end)
	end

	redrawOthers(self)
	updateSend(self)
end

function PlayersView.send(self: PlayersView)
	local target = self.Target
	local mode = self.Mode
	if not (target and mode and self.SendButton.Active) then
		return
	end
	local invitees = { target.UserId }
	for _, userId in self.Picked do
		table.insert(invitees, userId)
	end
	local callback = self.Callbacks.onChallenge
	if callback then
		callback(mode, invitees)
	end
	self:close()
end

return PlayersView
