--!strict
--[[
	EmoteView — butonul de emote si raftul care se desface din el.

	Sta in coltul de jos-dreapta, langa setari, si e singurul buton din meci care
	nu are de-a face cu tabla. De aceea arata altfel decat MOVE si BARRICADE: e
	patrat, are un semn in loc de cuvant, si nu se stinge niciodata cand nu e
	randul tau — un semn se da tocmai **cat astepti** sa mute celalalt.

	Raftul creste din buton in sus, nu peste mijlocul ecranului: tabla ramane
	vizibila cat alegi, iar degetul e deja in coltul ala. Se inchide singur dupa
	ce ai ales, fiindca alegerea era tot ce aveai de facut acolo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Emotes = require(ReplicatedStorage.Shared.Emotes)

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local EmoteView = {}
EmoteView.__index = EmoteView

type EmoteFields = {
	Root: Frame,
	Button: TextButton,
	Shelf: Frame,
	--[[
		Scara raftului, tinuta separat ca sa nu fie cautata la fiecare
		deschidere. Raftul creste din butonul lui — vezi `setOpen`.
	]]
	ShelfScale: UIScale,
	Callbacks: { [string]: any },
	Open: boolean,
}

export type EmoteView = typeof(setmetatable({} :: EmoteFields, EmoteView))

-- Trei pe rand, doua randuri. Vezi `Emotes.Order` pentru de ce in ordinea asta.
local COLUMNS = 3
local CELL = 56
local GAP = 8
local PADDING = 10

local SHELF_W = COLUMNS * CELL + (COLUMNS - 1) * GAP + PADDING * 2
local ROWS = math.ceil(#Emotes.Order / COLUMNS)
local SHELF_H = ROWS * CELL + (ROWS - 1) * GAP + PADDING * 2

function EmoteView.new(parent: Instance): EmoteView
	local self = setmetatable({}, EmoteView) :: EmoteView
	self.Callbacks = {} :: { [string]: any }
	self.Open = false

	--[[
		Radacina are exact marimea butonului, iar raftul iese din ea in sus.

		Asa pozitia se da o singura data — coltul din dreapta-jos — si raftul o
		urmeaza oriunde ar fi mutat butonul. Fara `ClipsDescendants`, fiindca
		tocmai iesirea din margini e ce trebuie sa se vada.
	]]
	local root = Theme.create("Frame", {
		Name = "Emotes",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(56, 56),
		--[[
			Vizibil de la inceput: HUD-ul in care sta se aprinde si se stinge
			intreg, iar butonul urmeaza soarta lui. `setVisible` ramane pentru
			cine vrea sa-l ascunda si cat timp HUD-ul e deschis.
		]]
		Parent = parent,
	}) :: Frame
	self.Root = root

	local shelf = Theme.create("Frame", {
		Name = "Shelf",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 1),
		-- Deasupra butonului, cu o palma intre ele.
		Position = UDim2.new(1, 0, 0, -10),
		Size = UDim2.fromOffset(SHELF_W, SHELF_H),
		Visible = false,
		Parent = root,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 1),
		Theme.padding(PADDING),
		Theme.create("UIGridLayout", {
			CellSize = UDim2.fromOffset(CELL, CELL),
			CellPadding = UDim2.fromOffset(GAP, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	self.Shelf = shelf

	--[[
		Raftul se desface din coltul lui de jos-dreapta — adica exact din buton —
		nu din mijlocul lui. Cu originea in centru ar fi parut ca apare de
		nicaieri si abia apoi se aseaza; asa se vede de unde vine.
	]]
	local shelfScale = Instance.new("UIScale")
	shelfScale.Parent = shelf
	self.ShelfScale = shelfScale

	for index, id in Emotes.Order do
		local emote = Emotes.All[id]

		local cell = Theme.button({
			Name = "Emote_" .. id,
			Text = emote.Symbol,
			--[[
				Fontul de sistem, ca in balon: fonturile jocului n-au emoji, iar
				un caracter lipsa dintr-un font se deseneaza ca dreptunghi gol.
			]]
			Font = Enum.Font.Legacy,
			TextSize = 30,
			Skin = "Square",
			Size = UDim2.fromOffset(CELL, CELL),
			LayoutOrder = index,
			Parent = shelf,
		})

		cell.MouseButton1Click:Connect(function()
			self:choose(id)
		end)
	end

	self.Button = Theme.button({
		Name = "Toggle",
		Text = "🙂",
		Font = Enum.Font.Legacy,
		TextSize = 28,
		Skin = "Square",
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})

	self.Button.MouseButton1Click:Connect(function()
		self:setOpen(not self.Open)
	end)

	return self
end

function EmoteView.setCallbacks(self: EmoteView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

--[[
	Butonul exista doar cat tine meciul.

	In lobby n-are cui sa-i faci semn: emote-ul se trimite catre masa, iar in
	afara ei serverul l-ar refuza oricum. Un buton care nu face nimic e mai rau
	decat unul care lipseste.
]]
function EmoteView.setVisible(self: EmoteView, visible: boolean)
	self.Root.Visible = visible
	if not visible then
		self:setOpen(false)
	end
end

function EmoteView.setOpen(self: EmoteView, open: boolean)
	if self.Open == open then
		return
	end
	self.Open = open
	self.Shelf.Visible = open
	if open then
		self.ShelfScale.Scale = 0.6
		TweenService:Create(
			self.ShelfScale,
			TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
end

function EmoteView.choose(self: EmoteView, id: string)
	self:setOpen(false)
	local callback = self.Callbacks.onEmote
	if callback then
		callback(id)
	end
end

return EmoteView
