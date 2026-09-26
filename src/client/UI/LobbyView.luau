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
local TweenService = game:GetService("TweenService")

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
	HelpButton: TextButton,
	-- Pagina de alegere a modului.
	Panel: Frame,
	Modes: Frame,
	BackButton: TextButton,
	-- Pagina cu regulile.
	Help: Frame,
	HelpClose: TextButton,
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

--[[
	Regulile, asa cum se spun la masa cuiva care nu le stie.

	Jocul e Quoridor, si asta e problema: doi din trei oameni care intra n-au
	auzit de el niciodata. Vad o tabla, un pion si un buton pe care scrie
	BARRICADE, si singurul fel de a afla ce fac e sa piarda o partida. Pana si
	regula care tine tot jocul in picioare — ca poti incetini pe cineva dar nu-l
	poti zidi — nu se poate ghici din nimic de pe ecran: se afla din refuzul
	primit dupa ce ai incercat.

	Textul e scris pe pasi, nu ca regulament, si spune la fiecare si *ce apesi*.
	Partea a treia e cea pentru care exista panoul asta.
]]
local HELP_STEPS = {
	{
		Title = "1 · Move",
		Body = "On your turn you step one square — up, down, left or right. "
			.. "The squares you may enter light up green; tap one and you are there. "
			.. "If another player stands right next to you, you hop over them.",
	},
	{
		Title = "2 · Or drop a barricade",
		Body = "Instead of moving, you may spend one barricade. It sits <b>between</b> two "
			.. "squares and nobody can cross it — not even you. "
			.. "Tap BARRICADE, aim at the seam between the squares, R (or the rotate button) "
			.. "turns it, and a tap puts it down. You only get a handful for the whole match.",
	},
	{
		Title = "3 · You may block, never seal",
		Body = "A barricade is allowed to send someone the long way round. It is "
			.. "<b>never</b> allowed to leave a player with no way through at all. "
			.. "The board checks every player before it accepts one, so a barricade that "
			.. "would shut somebody in is refused — and you keep it.",
	},
	{
		Title = "4 · Win the race",
		Body = "Reach the far side of the board, or the middle square, depending on the "
			.. "mode. Everyone has their own five-minute clock, and it only runs on their "
			.. "own turn.",
	},
}

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
		Regulile, la stanga lui START.

		Simetric cu magazinul din dreapta, si pentru acelasi motiv: mijlocul
		ramane al singurei actiuni principale. Butonul nu se ascunde niciodata si
		nu depinde de niciun asset — un jucator care nu stie jocul trebuie sa dea
		peste el din prima privire, nu sa-l caute intr-un meniu de setari.
	]]
	self.HelpButton = Theme.button({
		Name = "Help",
		Text = "HOW TO PLAY",
		TextSize = 15,
		Skin = "Secondary",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -16, 0.5, 0),
		Size = UDim2.fromOffset(148, 56),
		Parent = home,
	})

	self.HelpButton.MouseButton1Click:Connect(function()
		self:showHelp()
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

	-- ------------------------------------------------------------- regulile
	--[[
		Panoul cu regulile e mai inalt decat celelalte si are derulare.

		Restul paginilor din lobby au continut de dimensiune stiuta — patru
		moduri, patru locuri in coada — si incap intr-o inaltime fixa. Regulile
		nu: pe un telefon intors pe lat, patru pasi de text nu au unde sa stea.
		`AutomaticCanvasSize` lasa lista sa-si spuna singura inaltimea, iar
		panoul se opreste la cat ecran e.
	]]
	local help = Theme.create("Frame", {
		Name = "Help",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 520, 0.86, 0),
		Visible = false,
		Parent = root,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 1),
		Theme.padding(24),
		Theme.create("UISizeConstraint", { MaxSize = Vector2.new(520, 560) }),
	}) :: Frame
	self.Help = help

	Theme.text({
		Name = "HelpTitle",
		Text = "HOW TO PLAY",
		Font = Theme.Font.Bold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = help,
	})

	Theme.text({
		Name = "HelpLead",
		Text = "A race across the board. Everyone runs for their own goal, and everyone "
			.. "may get in everyone else's way.",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = help,
	})

	local steps = Theme.create("ScrollingFrame", {
		Name = "Steps",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 1, -136),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = help,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		-- Bara de derulare nu are voie sa stea peste text.
		Theme.create("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	}) :: ScrollingFrame

	for index, step in HELP_STEPS do
		local entry = Theme.create("Frame", {
			Name = "Step" .. index,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = index,
			Parent = steps,
		}, {
			Theme.create("UIListLayout", {
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}) :: Frame

		Theme.text({
			Name = "Title",
			Text = step.Title,
			Font = Theme.Font.Bold,
			TextSize = 17,
			TextColor3 = Theme.Color.Highlight,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1,
			Parent = entry,
		})

		Theme.text({
			Name = "Body",
			Text = step.Body,
			TextSize = 14,
			TextColor3 = Theme.Color.TextMuted,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = 2,
			Parent = entry,
		})
	end

	self.HelpClose = Theme.button({
		Name = "HelpClose",
		Text = "GOT IT",
		Skin = "Primary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(180, 42),
		Parent = help,
	})

	self.HelpClose.MouseButton1Click:Connect(function()
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
--[[
	Pagina care tocmai s-a deschis creste pana la marimea ei.

	Panourile lobby-ului apareau taiate: intr-un cadru nu era nimic, in
	urmatorul era o placa de lemn cat jumatate din ecran. Nu e o problema de
	frumusete — o aparitie instantanee nu spune de unde a venit fereastra, si
	ochiul are nevoie de un cadru-doua ca sa o lege de butonul pe care tocmai
	l-ai apasat.

	Nu si la inchidere: acolo ai apasat deja „inapoi" si vrei sa fii in spate,
	nu sa te uiti cum pleaca ceva.
]]
local PAGE_POP = 0.18

local function popIn(page: GuiObject)
	--[[
		Scara se face o singura data si ramane a paginii. Facuta din nou la
		fiecare deschidere, ar fi lasat in urma cate un `UIScale` mort la fiecare
		intrare in meniu.
	]]
	local existing = page:FindFirstChildOfClass("UIScale")
	local scale: UIScale
	if existing then
		scale = existing
	else
		scale = Instance.new("UIScale")
		scale.Parent = page
	end

	scale.Scale = 0.88
	TweenService
		:Create(scale, TweenInfo.new(PAGE_POP, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		:Play()
end

function LobbyView.setPage(self: LobbyView, page: string)
	--[[
		Cresterea se face doar pentru pagina care *se deschide acum*. Pusa la
		fiecare `setPage`, s-ar fi repornit si cand pagina era deja pe ecran — iar
		lista din coada se redeseneaza la fiecare jucator care intra, deci panoul
		ar fi tresarit la fiecare nume nou.
	]]
	local pages: { [string]: GuiObject } = {
		HOME = self.Home,
		MODES = self.Panel,
		HELP = self.Help,
		QUEUE = self.Queue,
		COUNTDOWN = self.Countdown,
	}

	for name, frame in pages do
		local wanted = name == page
		if wanted and not frame.Visible and name ~= "HOME" then
			popIn(frame)
		end
		frame.Visible = wanted
	end

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
	Regulile. Se inchid inapoi in „acasa", nu in pagina din care s-a venit:
	panoul se deschide doar de acolo, si nu are rost sa tina minte un drum de
	un singur pas.
]]
function LobbyView.showHelp(self: LobbyView)
	self:setPage("HELP")
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
