--!strict
--[[
	LobbyView — ecranul de dinaintea meciului.

	Trei stari, nu doua: acasa, alegerea modului, asteptarea in coada. Starea
	"acasa" e un singur buton START, jos in mijloc, pe fundal transparent —
	lobby-ul 3D e de vazut, nu de acoperit. Meniul de moduri se deschide peste
	el, ca o pagina, si se inchide inapoi la START.

	Inainte, lista de moduri statea permanent pe ecran, pe un fundal opac. Nimic
	din lumea din spate nu se vedea vreodata, iar jucatorul nu avea ce face in
	lobby decat sa intre in coada.

	Intunecarea din spatele panourilor e o singura bucata, aprinsa de fiecare
	stare care deschide o pagina. Fara ea, un panou de lemn peste o lume plina de
	culoare se citeste greu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local Theme = require(script.Parent.Theme)

local LobbyView = {}
LobbyView.__index = LobbyView

type LobbyFields = {
	Callbacks: { [string]: any },
	Root: Frame,
	-- Valul de intuneric din spatele paginilor deschise.
	Dim: Frame,
	Home: Frame,
	StartButton: TextButton,
	-- Poate lipsi: se construieste doar cand magazinul are cu ce se desena.
	StoreButton: TextButton?,
	-- Pagina de alegere a modului.
	Panel: Frame,
	Modes: Frame,
	BackButton: TextButton,
	Queue: Frame,
	QueueTitle: TextLabel,
	QueueMode: TextLabel,
	QueueList: Frame,
	CancelButton: TextButton,
	Countdown: TextLabel,
}

export type LobbyView = typeof(setmetatable({} :: LobbyFields, LobbyView))

--[[
	Cat de sus sta butonul START fata de marginea de jos.

	ScreenGui-ul are `IgnoreGuiInset`, deci originea lui urca deasupra viewport-ului
	cu inaltimea barei Roblox; distanta reala pana la marginea de jos a ecranului
	iese cu atat mai mare decat numarul de aici. Valoarea e masurata pe ecran, nu
	calculata.
]]
local HOME_MARGIN = 16

local MODE_SUBTITLES = {
	["1v1"] = "Two players · 10 barricades · reach the far side",
	["1v1v1"] = "Three players · 6 barricades · first to the centre",
	["1v1v1v1"] = "Four players · 5 barricades · first to the centre",
	["2v2"] = "Two teams · 5 barricades · one teammate gets across",
}

function LobbyView.new(parent: Instance): LobbyView
	local self = setmetatable({}, LobbyView) :: LobbyView

	self.Callbacks = {} :: { [string]: any }

	--[[
		Radacina nu mai are fundal. Cand jocul ruleaza in 2D, ecranul de dedesubt
		e oricum opac; cand ruleaza in 3D, lobby-ul se vede prin ea.
	]]
	local root = Theme.create("Frame", {
		Name = "Lobby",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}) :: Frame
	self.Root = root

	self.Dim = Theme.create("Frame", {
		Name = "Dim",
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	}) :: Frame

	--[[
		Acasa e un singur buton, jos in mijloc.

		Titlul si descrierea au plecat de aici: le vezi pe ecranul de incarcare,
		iar in lobby n-au ce spune in plus — stii deja in ce joc esti. Mijlocul
		ecranului e locul in care te uiti cand umbli prin lobby, deci butonul sta
		la marginea de jos, unde nu acopera nimic.
	]]
	local home = Theme.create("Frame", {
		Name = "Home",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -HOME_MARGIN),
		Size = UDim2.fromOffset(260, 66),
		Parent = root,
	}) :: Frame
	self.Home = home

	self.StartButton = Theme.button({
		Name = "Start",
		Text = "START",
		TextSize = 26,
		Skin = "Primary",
		Size = UDim2.fromScale(1, 1),
		Parent = home,
	})

	self.StartButton.MouseButton1Click:Connect(function()
		self:showModes()
	end)

	--[[
		Magazinul, la dreapta butonului de start.

		Nu langa el in acelasi rand: START e singura actiune principala din lobby
		si trebuie sa ramana singura pe mijloc. Magazinul sta alaturi, mai mic si
		mai jos, ca sa se vada ca e altceva decat "joaca".

		Butonul apare doar daca fereastra de magazin poate fi desenata. Un buton
		care deschide un ecran gol e mai rau decat niciun buton.
	]]
	if Theme.Assets.Store.buttonStore ~= "" then
		local store = Theme.create("ImageButton", {
			Name = "Store",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = Theme.Assets.Store.buttonStore,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 16, 0.5, 0),
			Size = UDim2.fromOffset(148, 56),
			Parent = home,
		}) :: ImageButton
		self.StoreButton = store :: any

		store.MouseButton1Click:Connect(function()
			local callback = self.Callbacks.onOpenStore
			if callback then
				callback()
			end
		end)
	end

	-- -------------------------------------------------------- alegerea modului
	local panel = Theme.create("Frame", {
		Name = "Panel",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 470),
		Visible = false,
		Parent = root,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 1),
		Theme.padding(24),
	}) :: Frame
	self.Panel = panel

	Theme.text({
		Name = "PanelTitle",
		Text = "CHOOSE A MODE",
		Font = Theme.Font.Bold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = panel,
	})

	local modes = Theme.create("Frame", {
		Name = "Modes",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 300),
		Parent = panel,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	self.Modes = modes

	for index, modeId in GameConfig.ModeOrder do
		local button = Theme.button({
			Name = "Mode_" .. modeId,
			Text = "",
			Skin = "Secondary",
			Size = UDim2.new(1, 0, 0, 64),
			LayoutOrder = index,
			Parent = modes,
		})

		Theme.text({
			Text = GameConfig.Modes[modeId].DisplayName,
			Font = Theme.Font.Bold,
			TextSize = 20,
			Position = UDim2.fromOffset(18, 8),
			Size = UDim2.new(1, -36, 0, 22),
			Parent = button,
		})

		Theme.text({
			Text = MODE_SUBTITLES[modeId] or "",
			TextColor3 = Theme.Color.TextMuted,
			TextSize = 13,
			Position = UDim2.fromOffset(18, 30),
			Size = UDim2.new(1, -36, 0, 18),
			Parent = button,
		})

		button.MouseButton1Click:Connect(function()
			local callback = self.Callbacks.onSelectMode
			if callback then
				callback(modeId)
			end
		end)
	end

	--[[
		Intoarcerea nu trece prin server: alegerea unui mod nu s-a intamplat inca,
		deci nu e nimic de anulat. E doar pagina care se inchide.
	]]
	self.BackButton = Theme.button({
		Name = "Back",
		Text = "BACK",
		Skin = "Secondary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(180, 42),
		Parent = panel,
	})

	self.BackButton.MouseButton1Click:Connect(function()
		self:showHome()
	end)

	-- ------------------------------------------------------------ coada
	local queue = Theme.create("Frame", {
		Name = "Queue",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 360),
		Visible = false,
		Parent = root,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 1),
		Theme.padding(24),
	}) :: Frame
	self.Queue = queue

	self.QueueTitle = Theme.text({
		Name = "QueueTitle",
		Text = "FINDING PLAYERS...",
		Font = Theme.Font.Bold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = queue,
	})

	self.QueueMode = Theme.text({
		Name = "QueueMode",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = queue,
	})

	self.QueueList = Theme.create("Frame", {
		Name = "QueueList",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 180),
		Parent = queue,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	self.CancelButton = Theme.button({
		Name = "Cancel",
		Text = "CANCEL",
		Skin = "Secondary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(180, 42),
		Parent = queue,
	})

	self.CancelButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onCancel
		if callback then
			callback()
		end
	end)

	-- --------------------------------------------------------- numaratoare
	self.Countdown = Theme.text({
		Name = "Countdown",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 72,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 100),
		Visible = false,
		Parent = root,
	})

	return self
end

function LobbyView.setCallbacks(self: LobbyView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

function LobbyView.setVisible(self: LobbyView, visible: boolean)
	self.Root.Visible = visible
end

--[[
	Toate paginile se inchid, apoi se deschide una singura.

	Starile lobby-ului nu stau niciodata doua deodata pe ecran, iar tinerea lor
	intr-un singur loc e ce impiedica o pagina uitata deschisa sub alta.
]]
function LobbyView.setPage(self: LobbyView, page: string)
	self.Home.Visible = page == "HOME"
	self.Panel.Visible = page == "MODES"
	self.Queue.Visible = page == "QUEUE"
	self.Countdown.Visible = page == "COUNTDOWN"
	self.Dim.Visible = page ~= "HOME"
	self.Root.Visible = true
end

-- Ecranul de pornire: titlul si butonul, cu lumea vizibila in spate.
function LobbyView.showHome(self: LobbyView)
	self:setPage("HOME")
end

function LobbyView.showModes(self: LobbyView)
	self:setPage("MODES")
end

--[[
	Lista celor gasiti pana acum: cerc plin pentru cine e deja in coada,
	cerc gol pentru locurile ramase.
]]
function LobbyView.showQueue(self: LobbyView, modeId: string, names: { string }, needed: number)
	self:setPage("QUEUE")

	self.QueueMode.Text = string.format("%s · %d of %d", modeId, #names, needed)
	self.QueueList:ClearAllChildren()
	Theme.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.QueueList,
	})

	for index = 1, needed do
		local name = names[index]
		Theme.text({
			Text = if name then string.format("● %s", name) else "○ waiting...",
			TextColor3 = if name then Theme.Color.Text else Theme.Color.TextMuted,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = index,
			Parent = self.QueueList,
		})
	end
end

function LobbyView.showCountdown(self: LobbyView, value: number)
	self:setPage("COUNTDOWN")

	self.Countdown.Text = tostring(value)
	self.Countdown.TextTransparency = 0
	AnimationController.tween(self.Countdown, { TextTransparency = 0.7 }, 0.8, "fade")
end

return LobbyView
