--!strict
--[[
	BoardView — tabla desenata.

	Nu stie nicio regula. Primeste o stare si o deseneaza; cand jucatorul
	atinge ceva, anunta prin callback. Toate deciziile — ce mutare e legala,
	ce baricada e valida — vin gata luate din controller, care le cere
	motorului comun.

	GEOMETRIA
	Tabla e un patrat impartit in unitati: fiecare celula are 10 unitati,
	fiecare sant dintre celule are 2. Pe 9 celule si 8 santuri ies 106
	unitati pe latura, si totul se pozitioneaza in fractiuni din 106. Asa
	tabla ramane corecta la orice rezolutie, fara niciun calcul in pixeli.

	Y-ul logic creste in sus, ca pe o tabla de joc privita normal. Inversarea
	pentru ecran se face doar aici, intr-un singur loc.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local BoardUtils = require(Shared.BoardUtils)
local GameConfig = require(Shared.GameConfig)
local Types = require(Shared.Types)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local Avatars = require(script.Parent.Avatars)
local Theme = require(script.Parent.Theme)

type BoardState = Types.BoardState
type Cell = Types.Cell

local SIZE = GameConfig.BoardSize
local CELL_UNITS = 10
local GAP_UNITS = 2
local TOTAL_UNITS = SIZE * CELL_UNITS + (SIZE - 1) * GAP_UNITS

local CELL = CELL_UNITS / TOTAL_UNITS
local GAP = GAP_UNITS / TOTAL_UNITS
local WALL_LENGTH = (2 * CELL_UNITS + GAP_UNITS) / TOTAL_UNITS
local TOKEN = CELL * 0.82

local BoardView = {}
BoardView.__index = BoardView

type BoardFields = {
	Cells: { [string]: TextButton },
	MoveHints: { [string]: Frame },
	WallSlots: { [string]: TextButton },
	Walls: { [string]: Frame },
	Tokens: { [number]: Frame },
	Callbacks: { [string]: any },
	Orientation: string,
	Container: Frame,
	Grid: Frame,
	TargetLayer: Frame,
	WallLayer: Frame,
	TokenLayer: Frame,
	SlotLayer: Frame,
	Preview: Frame,
}

export type BoardView = typeof(setmetatable({} :: BoardFields, BoardView))

-- Coltul din stanga-sus al celulei cu indicele dat pe o axa de ecran.
local function axisStart(index: number): number
	return ((index - 1) * (CELL_UNITS + GAP_UNITS)) / TOTAL_UNITS
end

-- Y-ul logic (1 = jos) devine rand de ecran (1 = sus).
local function renderRow(y: number): number
	return SIZE + 1 - y
end

local function cellPosition(x: number, y: number): UDim2
	return UDim2.fromScale(axisStart(x), axisStart(renderRow(y)))
end

--[[
	Dreptunghiul unei baricade. O orizontala sta in santul dintre randurile
	y si y+1 si acopera coloanele x si x+1; o verticala, invers.
]]
local function wallRect(x: number, y: number, orientation: string): (UDim2, UDim2)
	if orientation == "Horizontal" then
		return UDim2.fromScale(axisStart(x), axisStart(renderRow(y)) - GAP),
			UDim2.fromScale(WALL_LENGTH, GAP)
	end
	return UDim2.fromScale(axisStart(x) + CELL, axisStart(renderRow(y + 1))),
		UDim2.fromScale(GAP, WALL_LENGTH)
end

function BoardView.new(parent: Instance): BoardView
	local self = setmetatable({}, BoardView) :: BoardView

	self.Cells = {} :: { [string]: TextButton }
	self.MoveHints = {} :: { [string]: Frame }
	self.WallSlots = {} :: { [string]: TextButton }
	self.Walls = {} :: { [string]: Frame }
	self.Tokens = {} :: { [number]: Frame }
	self.Callbacks = {} :: { [string]: any }
	self.Orientation = "Horizontal"

	local container = Theme.create("Frame", {
		Name = "BoardContainer",
		BackgroundColor3 = Theme.Color.Board,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 2),
		Theme.create("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Theme.padding(14),
	}) :: Frame

	local grid = Theme.create("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = container,
	}) :: Frame

	self.Container = container
	self.Grid = grid

	-- Straturi, de jos in sus: celule, marcaje de tinta, baricade, pioni, previzualizare.
	self.TargetLayer = Theme.create("Frame", {
		Name = "Targets",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = grid,
	}) :: Frame

	self.WallLayer = Theme.create("Frame", {
		Name = "Walls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = grid,
	}) :: Frame

	self.TokenLayer = Theme.create("Frame", {
		Name = "Tokens",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = grid,
	}) :: Frame

	self.SlotLayer = Theme.create("Frame", {
		Name = "WallSlots",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 8,
		Parent = grid,
	}) :: Frame

	self.Preview = Theme.create("Frame", {
		Name = "Preview",
		BackgroundColor3 = Theme.Color.Valid,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 9,
		Parent = grid,
	}, { Theme.corner(Theme.Radius.Small) }) :: Frame

	self:buildCells()
	self:buildWallSlots()

	return self
end

function BoardView.buildCells(self: BoardView)
	for x = 1, SIZE do
		for y = 1, SIZE do
			local isLight = (x + y) % 2 == 0
			local cell = Theme.button({
				Name = string.format("Cell_%d_%d", x, y),
				BackgroundColor3 = if isLight then Theme.Color.CellLight else Theme.Color.CellDark,
				Position = cellPosition(x, y),
				Size = UDim2.fromScale(CELL, CELL),
				Text = "",
				ZIndex = 1,
				Active = false,
				Parent = self.Grid,
			})
			Theme.corner(Theme.Radius.Small).Parent = cell

			-- Punctul care arata unde se poate muta; ascuns pana cand e cazul.
			local hint = Theme.create("Frame", {
				Name = "Hint",
				BackgroundColor3 = Theme.Color.Accent,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.3, 0.3),
				Visible = false,
				ZIndex = 3,
				Parent = cell,
			}, { Theme.corner(Theme.Radius.Round) }) :: Frame

			local key = string.format("%d,%d", x, y)
			self.Cells[key] = cell
			self.MoveHints[key] = hint

			cell.MouseButton1Click:Connect(function()
				local callback = self.Callbacks.onCell
				if callback and cell.Active then
					callback({ X = x, Y = y })
				end
			end)
		end
	end
end

--[[
	Zonele de clic pentru baricade. Sunt 128 (8x8 intersectii x 2 orientari),
	construite o singura data si doar aratate sau ascunse dupa aceea.

	Zona de clic e mai groasa decat baricada desenata: un sant de 2 unitati e
	corect vizual, dar imposibil de nimerit cu mouse-ul.
]]
function BoardView.buildWallSlots(self: BoardView)
	for x = 1, BoardUtils.WallSlots do
		for y = 1, BoardUtils.WallSlots do
			for _, orientation in { "Horizontal", "Vertical" } do
				local position, size = wallRect(x, y, orientation)
				local thicker = if orientation == "Horizontal"
					then UDim2.fromScale(size.X.Scale, GAP * 3)
					else UDim2.fromScale(GAP * 3, size.Y.Scale)
				local nudged = if orientation == "Horizontal"
					then UDim2.fromScale(position.X.Scale, position.Y.Scale - GAP)
					else UDim2.fromScale(position.X.Scale - GAP, position.Y.Scale)

				local slot = Theme.create("TextButton", {
					Name = string.format("Slot_%s_%d_%d", orientation, x, y),
					BackgroundTransparency = 1,
					Text = "",
					Position = nudged,
					Size = thicker,
					Visible = false,
					ZIndex = 8,
					Parent = self.SlotLayer,
				}) :: TextButton

				self.WallSlots[string.format("%s:%d,%d", orientation, x, y)] = slot

				slot.MouseEnter:Connect(function()
					local callback = self.Callbacks.onWallHover
					if callback then
						callback(x, y, orientation)
					end
				end)

				slot.MouseButton1Click:Connect(function()
					local callback = self.Callbacks.onWallSlot
					if callback then
						callback(x, y, orientation)
					end
				end)
			end
		end
	end
end

function BoardView.setCallbacks(self: BoardView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

-- ------------------------------------------------------------ marcaje tinta

--[[
	Arata unde trebuie sa ajunga jucatorul local. Fara asta, un nou-venit
	nu are de unde sti incotro joaca.
]]
function BoardView.renderTarget(self: BoardView, objective: Types.Objective?)
	self.TargetLayer:ClearAllChildren()
	if not objective then
		return
	end

	if objective.Kind == "CENTER" then
		local cell = objective.Cell or { X = 5, Y = 5 }
		Theme.create("Frame", {
			BackgroundTransparency = 1,
			Position = cellPosition(cell.X, cell.Y),
			Size = UDim2.fromScale(CELL, CELL),
			ZIndex = 2,
			Parent = self.TargetLayer,
		}, {
			Theme.corner(Theme.Radius.Small),
			Theme.stroke(Theme.Color.Accent, 2, 0.2),
		})
		return
	end

	for index = 1, SIZE do
		local cell: Cell = if objective.Edge == "Y_MAX"
			then { X = index, Y = SIZE }
			elseif objective.Edge == "Y_MIN" then { X = index, Y = 1 }
			elseif objective.Edge == "X_MAX" then { X = SIZE, Y = index }
			else { X = 1, Y = index }

		Theme.create("Frame", {
			BackgroundColor3 = Theme.Color.Accent,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Position = cellPosition(cell.X, cell.Y),
			Size = UDim2.fromScale(CELL, CELL),
			ZIndex = 2,
			Parent = self.TargetLayer,
		}, { Theme.corner(Theme.Radius.Small) })
	end
end

-- --------------------------------------------------------------- baricade

function BoardView.renderWalls(self: BoardView, state: BoardState)
	local seen: { [string]: boolean } = {}

	for key, wall in state.Walls do
		seen[key] = true
		if not self.Walls[key] then
			local position, size = wallRect(wall.X, wall.Y, wall.Orientation)
			local frame = Theme.create("Frame", {
				Name = key,
				BackgroundColor3 = Theme.Color.Wall,
				BorderSizePixel = 0,
				Position = position,
				Size = size,
				ZIndex = 5,
				Parent = self.WallLayer,
			}, { Theme.corner(Theme.Radius.Small) }) :: Frame

			self.Walls[key] = frame
			AnimationController.dropWall(frame, size, GameConfig.Timing.WallTween)
		end
	end

	-- Baricadele nu dispar in joc, dar un meci nou reseteaza tabla.
	for key, frame in self.Walls do
		if not seen[key] then
			AnimationController.forget(frame)
			frame:Destroy()
			self.Walls[key] = nil
		end
	end
end

-- ----------------------------------------------------------------- pioni

local function tokenColor(state: BoardState, slot: number): Color3
	local perMode = GameConfig.TeamColors[state.GameMode]
	local hex = if perMode then perMode[slot] else GameConfig.SlotColors[slot]
	return Color3.fromHex(string.format("%06X", hex or 0x888888))
end

function BoardView.renderTokens(self: BoardView, state: BoardState, currentSlot: number?)
	for slot, player in state.Players do
		local token = self.Tokens[slot]
		local color = tokenColor(state, slot)

		if not token then
			local created = Theme.create("Frame", {
				Name = "Token_" .. slot,
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(TOKEN, TOKEN),
				Position = UDim2.fromScale(
					axisStart(player.Position.X) + (CELL - TOKEN) / 2,
					axisStart(renderRow(player.Position.Y)) + (CELL - TOKEN) / 2
				),
				ZIndex = 6,
				Parent = self.TokenLayer,
			}, {
				Theme.corner(Theme.Radius.Round),
				Theme.stroke(color, 3),
				Theme.create("ImageLabel", {
					Name = "Avatar",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(0.84, 0.84),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					ZIndex = 7,
					Parent = nil,
				}, { Theme.corner(Theme.Radius.Round) }),
				Theme.text({
					Name = "Initial",
					Size = UDim2.fromScale(1, 1),
					Text = string.sub(player.Name, 1, 1):upper(),
					TextSize = 18,
					Font = Theme.Font.Bold,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 6,
				}),
			}) :: Frame

			self.Tokens[slot] = created

			local avatar = created:FindFirstChild("Avatar") :: ImageLabel
			Avatars.fetch(player.UserId, function(image)
				if avatar.Parent then
					avatar.Image = image
				end
			end)
		end

		-- Dupa blocul de mai sus tokenul exista sigur; legarea asta o spune si tipului.
		local drawn = self.Tokens[slot] :: Frame

		-- Pozitia se anima mereu, ca sa nu sara pionul dintr-o celula in alta.
		AnimationController.moveToken(
			drawn,
			UDim2.fromScale(
				axisStart(player.Position.X) + (CELL - TOKEN) / 2,
				axisStart(renderRow(player.Position.Y)) + (CELL - TOKEN) / 2
			),
			GameConfig.Timing.MoveTween
		)

		-- Cine e la mutare are contur luminos si e putin mai mare.
		local stroke = drawn:FindFirstChildOfClass("UIStroke") :: UIStroke
		local isCurrent = currentSlot == slot
		stroke.Color = if isCurrent then Theme.Color.Text else color
		stroke.Thickness = if isCurrent then 4 else 2
		drawn.BackgroundTransparency = if player.Connected then 0 else 0.55

		AnimationController.tween(drawn, {
			Size = if isCurrent
				then UDim2.fromScale(TOKEN * 1.08, TOKEN * 1.08)
				else UDim2.fromScale(TOKEN, TOKEN),
		}, 0.18, "size")
	end
end

-- ------------------------------------------------------------ interactiune

--[[
	Pregateste tabla pentru un anumit fel de actiune.

	mode = "MOVE" aprinde celulele unde se poate muta,
	mode = "WALL" aprinde santurile pentru orientarea aleasa,
	orice altceva stinge tot: nu e randul jucatorului.
]]
function BoardView.setInteraction(
	self: BoardView,
	mode: string,
	legalMoves: { Cell },
	orientation: string
)
	self.Orientation = orientation

	for key, cell in self.Cells do
		cell.Active = false
		local hint = self.MoveHints[key]
		hint.Visible = false
	end

	if mode == "MOVE" then
		for _, move in legalMoves do
			local key = string.format("%d,%d", move.X, move.Y)
			local cell = self.Cells[key]
			if cell then
				cell.Active = true
				self.MoveHints[key].Visible = true
			end
		end
	end

	for key, slot in self.WallSlots do
		slot.Visible = mode == "WALL" and string.sub(key, 1, #orientation) == orientation
	end

	if mode ~= "WALL" then
		self:hidePreview()
	end
end

function BoardView.showPreview(
	self: BoardView,
	x: number,
	y: number,
	orientation: string,
	isValid: boolean
)
	local position, size = wallRect(x, y, orientation)
	self.Preview.Position = position
	self.Preview.Size = size
	self.Preview.BackgroundColor3 = if isValid then Theme.Color.Valid else Theme.Color.Invalid
	self.Preview.Visible = true
end

function BoardView.hidePreview(self: BoardView)
	self.Preview.Visible = false
end

function BoardView.flashInvalid(self: BoardView)
	AnimationController.shake(self.Container)
end

--[[
	Sterge tot ce apartinea meciului precedent.

	Baricadele si pionii sunt create o singura data si apoi doar mutate, deci
	un meci nou pe aceeasi tabla trebuie sa le ia de la zero — altfel raman
	zidurile partidei trecute peste tabla curata.
]]
function BoardView.reset(self: BoardView)
	for _, wall in self.Walls do
		AnimationController.forget(wall)
		wall:Destroy()
	end
	self.Walls = {}

	for _, token in self.Tokens do
		AnimationController.forget(token)
		token:Destroy()
	end
	self.Tokens = {}

	self:hidePreview()
	self.TargetLayer:ClearAllChildren()
end

function BoardView.render(self: BoardView, state: BoardState, localSlot: number?)
	self:renderWalls(state)
	self:renderTokens(state, state.TurnOrder[state.TurnIndex])
	if localSlot and state.Players[localSlot] then
		self:renderTarget(state.Players[localSlot].Objective)
	end
end

return BoardView
