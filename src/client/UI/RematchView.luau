--!strict
--[[
	RematchView — bannerul votului de revansa.

	Sta sus, peste ecranul de final, si spune tot din starea trimisa de server:
	cine a cerut, cat mai e (bara care se goleste), cine a acceptat (avatarele se
	aprind pe rand, fiecare cu saltul lui) si ce mai ai de facut — Accept sau
	Decline, daca n-ai raspuns inca.

	Nu decide nimic. Butoanele doar cer; starea adevarata vine inapoi de la
	server si abia atunci se schimba ce se vede. De aceea acelasi `update`
	deseneaza si cererea ta, si raspunsul celorlalti.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local Avatars = require(script.Parent.Avatars)
local Theme = require(script.Parent.Theme)

local RematchView = {}
RematchView.__index = RematchView

local WIDTH, HEIGHT = 480, 230
local AVATAR = 58

type Seat = {
	Frame: Frame,
	Image: ImageLabel,
	Scale: UIScale,
	Stroke: UIStroke,
	Lit: boolean,
}

type RematchFields = {
	Callbacks: { [string]: any },
	Root: Frame,
	Scale: UIScale,
	Title: TextLabel,
	Subtitle: TextLabel,
	Bar: Frame,
	Fill: Frame,
	Row: Frame,
	Buttons: Frame,
	AcceptButton: TextButton,
	DeclineButton: TextButton,
	Seats: { [number]: Seat },
	-- Semnatura mesei din votul de acum: cand se schimba, avatarele se refac.
	Table: string?,
	-- Starea desenata ultima oara, ca sa nu se reia intrarea la fiecare mesaj.
	Status: string?,
	Hider: thread?,
}

export type RematchView = typeof(setmetatable({} :: RematchFields, RematchView))

function RematchView.new(parent: Instance): RematchView
	local self = setmetatable({}, RematchView) :: RematchView
	self.Callbacks = {} :: { [string]: any }
	self.Seats = {} :: { [number]: Seat }

	local root = Theme.create("Frame", {
		Name = "Rematch",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Highlight, 3),
		Theme.padding(16),
	}) :: Frame
	self.Root = root
	self.Scale = Theme.create("UIScale", { Scale = 1, Parent = root }) :: UIScale

	self.Title = Theme.text({
		Name = "Title",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 28,
		TextColor3 = Theme.Color.Highlight,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 21,
		Parent = root,
	})

	self.Subtitle = Theme.text({
		Name = "Subtitle",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 21,
		Parent = root,
	})

	-- Bara care se goleste: cat mai sta votul deschis.
	self.Bar = Theme.create("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.Color.Backdrop,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 10),
		ZIndex = 21,
		Parent = root,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	self.Fill = Theme.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Color.Highlight,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 22,
		Parent = self.Bar,
	}, { Theme.corner(Theme.Radius.Round) }) :: Frame

	self.Row = Theme.create("Frame", {
		Name = "Seats",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 0, AVATAR + 6),
		ZIndex = 21,
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	--[[
		Butoanele sunt mari: pe telefon se apasa cu degetul mare, uneori din
		mers, si un „Decline" nimerit in loc de „Accept" nu se mai poate lua
		inapoi.
	]]
	self.Buttons = Theme.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 50),
		ZIndex = 21,
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	self.AcceptButton = Theme.button({
		Name = "Accept",
		Text = "ACCEPT",
		Skin = "Primary",
		Size = UDim2.fromOffset(180, 50),
		LayoutOrder = 1,
		ZIndex = 22,
		Parent = self.Buttons,
	})
	self.DeclineButton = Theme.button({
		Name = "Decline",
		Text = "DECLINE",
		Skin = "Secondary",
		Size = UDim2.fromOffset(180, 50),
		LayoutOrder = 2,
		ZIndex = 22,
		Parent = self.Buttons,
	})

	self.AcceptButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onAccept
		if callback then
			callback()
		end
	end)
	self.DeclineButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onDecline
		if callback then
			callback()
		end
	end)

	return self
end

function RematchView.setCallbacks(self: RematchView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

-- Pe ecrane inguste bannerul se strange, ca sa nu iasa din margini.
local function fitScale(): number
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1000
	return math.min(1, (width - 24) / WIDTH)
end

-- Avatarele celor de la masa, in ordinea sloturilor. Se refac doar cand se schimba masa.
local function buildSeats(self: RematchView, seats: { any })
	local signature = {}
	for _, seat in seats do
		table.insert(signature, tostring(seat.UserId))
	end
	local key = table.concat(signature, ",")
	if self.Table == key then
		return
	end
	self.Table = key

	for _, seat in self.Seats do
		seat.Frame:Destroy()
	end
	self.Seats = {}

	for index, seat in seats do
		local frame = Theme.create("Frame", {
			Name = "Seat",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(AVATAR, AVATAR),
			LayoutOrder = index,
			ZIndex = 22,
			Parent = self.Row,
		}) :: Frame
		local scale = Theme.create("UIScale", { Scale = 1, Parent = frame }) :: UIScale
		local image = Theme.create("ImageLabel", {
			Name = "Avatar",
			BackgroundColor3 = Theme.Color.Backdrop,
			BorderSizePixel = 0,
			Image = "",
			ImageTransparency = 0.6,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 23,
			Parent = frame,
		}, { Theme.corner(Theme.Radius.Round) }) :: ImageLabel
		local stroke = Theme.create("UIStroke", {
			Color = Theme.Color.Line,
			Thickness = 3,
			Parent = image,
		}) :: UIStroke

		local userId = seat.UserId
		if type(userId) == "number" then
			Avatars.fetch(userId, function(content: string)
				if image.Parent then
					image.Image = content
				end
			end)
		end

		self.Seats[userId] =
			{ Frame = frame, Image = image, Scale = scale, Stroke = stroke, Lit = false }
	end
end

-- Aprinde avatarele celor care au acceptat; cele noi sar, cu un „pop".
local function lightSeats(self: RematchView, accepted: { any })
	local yes: { [number]: boolean } = {}
	for _, userId in accepted do
		if type(userId) == "number" then
			yes[userId] = true
		end
	end

	for userId, seat in self.Seats do
		local lit = yes[userId] == true
		if lit and not seat.Lit then
			seat.Scale.Scale = 1.35
			AnimationController.tween(seat.Scale, { Scale = 1 }, 0.35, "pop", Enum.EasingStyle.Back)
			SoundController.play("RematchAccept")
		end
		seat.Lit = lit
		seat.Image.ImageTransparency = if lit then 0 else 0.6
		seat.Stroke.Color = if lit then Theme.Color.Valid else Theme.Color.Line
	end
end

local function cancelHider(self: RematchView)
	local hider = self.Hider
	if hider then
		self.Hider = nil
		task.cancel(hider)
	end
end

local function open(self: RematchView)
	if self.Root.Visible then
		return
	end
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

--[[
	Deseneaza starea votului. `localUserId` hotaraste ce vede jucatorul asta:
	butoanele, daca n-a raspuns; „waiting", daca a raspuns.

	La anulare, bannerul spune de ce si pleaca singur dupa `RematchNotice`; apoi
	`onClosed` afla daca jucatorul acceptase, ca sa fie intrebat de coada.
]]
function RematchView.update(self: RematchView, payload: any, localUserId: number)
	local status = payload.Status
	local seats = if type(payload.Seats) == "table" then payload.Seats else {}
	local accepted = if type(payload.Accepted) == "table" then payload.Accepted else {}

	local mine = table.find(accepted, localUserId) ~= nil
	local requester = if type(payload.RequesterName) == "string"
		then payload.RequesterName
		else "A player"

	cancelHider(self)
	buildSeats(self, seats)
	lightSeats(self, accepted)
	open(self)

	if status == "Pending" then
		if self.Status ~= "Pending" then
			SoundController.play("RematchAsk")
		end
		self.Title.Text = string.format("%s wants a rematch!", requester)
		self.Title.TextColor3 = Theme.Color.Highlight
		self.Subtitle.Text = if mine
			then "Waiting for the others…"
			else "Same table, same players."
		self.Bar.Visible = true
		self.Buttons.Visible = not mine

		local window = if type(payload.Window) == "number"
			then payload.Window
			else GameConfig.Timing.RematchWindow
		local remaining = if type(payload.Remaining) == "number" then payload.Remaining else window
		self.Fill.Size = UDim2.fromScale(math.clamp(remaining / window, 0, 1), 1)
		AnimationController.tween(
			self.Fill,
			{ Size = UDim2.fromScale(0, 1) },
			remaining,
			"drain",
			Enum.EasingStyle.Linear
		)
	elseif status == "Accepted" then
		self.Title.Text = "Rematch!"
		self.Title.TextColor3 = Theme.Color.Valid
		self.Subtitle.Text = "Get ready…"
		self.Bar.Visible = false
		self.Buttons.Visible = false
		self.Hider = task.delay(1.4, function()
			self.Hider = nil
			self:hide()
		end)
	else
		SoundController.play("RematchCancel")
		local who = if type(payload.ByName) == "string" then payload.ByName else "A player"
		local reason = payload.Reason
		self.Title.Text = if reason == "DECLINED"
			then string.format("%s declined", who)
			elseif reason == "LEFT" then string.format("%s left", who)
			else "Rematch expired"
		self.Title.TextColor3 = Theme.Color.Invalid
		self.Subtitle.Text = ""
		self.Bar.Visible = false
		self.Buttons.Visible = false

		self.Hider = task.delay(GameConfig.Timing.RematchNotice, function()
			self.Hider = nil
			self:hide()
			local callback = self.Callbacks.onClosed
			if callback then
				callback(mine)
			end
		end)
	end

	self.Status = status
end

function RematchView.isOpen(self: RematchView): boolean
	return self.Root.Visible
end

function RematchView.hide(self: RematchView)
	cancelHider(self)
	AnimationController.forget(self.Fill)
	self.Root.Visible = false
	self.Status = nil
	self.Table = nil
	for _, seat in self.Seats do
		seat.Frame:Destroy()
	end
	self.Seats = {}
end

return RematchView
