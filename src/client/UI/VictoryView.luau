--!strict
--[[
	VictoryView — ecranul de final.

	Apare peste tabla, nu in locul ei: jucatorii vor sa vada pozitia finala
	in care s-a incheiat partida.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Types = require(Shared.Types)

local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local Theme = require(script.Parent.Theme)

type BoardState = Types.BoardState

local VictoryView = {}
VictoryView.__index = VictoryView

--[[
	Dupa cate secunde se inchide singur, daca nu apesi nimic.

	Ecranul de final nu e o intrebare care asteapta raspuns: meciul s-a terminat
	oricum. Cine vrea revansa o cere in secundele alea; cine s-a ridicat de la
	calculator nu trebuie sa gaseasca la intoarcere aceeasi fereastra peste o
	tabla moarta. Tacerea inseamna "gata", deci se pleaca in lobby.
]]
local AUTO_LEAVE_SECONDS = GameConfig.Timing.VictoryAutoLeave

type VictoryFields = {
	Callbacks: { [string]: any },
	Root: Frame,
	Panel: Frame,
	Headline: TextLabel,
	Detail: TextLabel,
	Countdown: TextLabel,
	AgainButton: TextButton,
	LeaveButton: TextButton,
	-- Firul care numara pana la inchiderea singura. Lipseste cat ecranul e ascuns.
	Timer: thread?,
}

export type VictoryView = typeof(setmetatable({} :: VictoryFields, VictoryView))

function VictoryView.new(parent: Instance): VictoryView
	local self = setmetatable({}, VictoryView) :: VictoryView

	self.Callbacks = {} :: { [string]: any }

	local root = Theme.create("Frame", {
		Name = "Victory",
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	}) :: Frame
	self.Root = root

	local panel = Theme.create("Frame", {
		Name = "Panel",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 300),
		Parent = root,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 1),
		Theme.padding(28),
	}) :: Frame
	self.Panel = panel

	Theme.text({
		Name = "Trophy",
		Text = "🏆",
		TextSize = 48,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60),
		Parent = panel,
	})

	self.Headline = Theme.text({
		Name = "Headline",
		Text = "VICTORY",
		Font = Theme.Font.Bold,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = panel,
	})

	self.Detail = Theme.text({
		Name = "Detail",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 106),
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		Parent = panel,
	})

	--[[
		Randul care spune cat mai sta fereastra. O fereastra care dispare fara sa
		fi anuntat ca dispare se citeste ca o defectiune, iar cine tocmai a
		castigat vrea sa stie ca mai are o clipa sa apese "PLAY AGAIN".
	]]
	self.Countdown = Theme.text({
		Name = "Countdown",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 13,
		TextTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -54),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = panel,
	})

	local buttons = Theme.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = panel,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	}) :: Frame

	self.AgainButton = Theme.button({
		Name = "Again",
		Text = "PLAY AGAIN",
		Skin = "Primary",
		Size = UDim2.fromOffset(190, 46),
		LayoutOrder = 1,
		Parent = buttons,
	})

	self.LeaveButton = Theme.button({
		Name = "Leave",
		Text = "MAIN MENU",
		Skin = "Secondary",
		Size = UDim2.fromOffset(190, 46),
		LayoutOrder = 2,
		Parent = buttons,
	})

	self.AgainButton.MouseButton1Click:Connect(function()
		--[[
			Si aici, nu doar pe aspect: `Active = false` opreste input-ul, dar un
			clic aflat deja in zbor cand butonul s-a stins tot ar ajunge.
		]]
		if not self.AgainButton.Active then
			return
		end
		local callback = self.Callbacks.onRematch
		if callback then
			callback()
		end
	end)

	self.LeaveButton.MouseButton1Click:Connect(function()
		local callback = self.Callbacks.onLeave
		if callback then
			callback()
		end
	end)

	return self
end

function VictoryView.setCallbacks(self: VictoryView, callbacks: { [string]: any })
	self.Callbacks = callbacks
end

function VictoryView.stopTimeout(self: VictoryView)
	local timer = self.Timer
	if timer then
		self.Timer = nil
		task.cancel(timer)
	end
	self.Countdown.Text = ""
end

--[[
	Numara cu voce tare pana la plecarea in lobby.

	`self.Timer` se sterge **inainte** de a chema callback-ul, nu dupa. Plecarea
	trece prin `hide`, care opreste numaratoarea; daca firul ar fi inca inscris
	acolo, `task.cancel` ar fi cerut chiar pe firul care ruleaza in clipa aia, si
	Luau nu lasa un fir sa se anuleze singur.
]]
function VictoryView.startTimeout(self: VictoryView)
	self:stopTimeout()

	self.Timer = task.spawn(function()
		for remaining = AUTO_LEAVE_SECONDS, 1, -1 do
			self.Countdown.Text = string.format("Back to the lobby in %d…", remaining)
			task.wait(1)
		end

		self.Timer = nil
		self.Countdown.Text = ""

		local callback = self.Callbacks.onLeave
		if callback then
			callback()
		end
	end)
end

--[[
	Textul spune cine a castigat si de ce. In modurile pe echipe conteaza
	echipa, chiar daca un singur jucator a facut pasul final.
]]
function VictoryView.show(self: VictoryView, state: BoardState, localSlot: number?)
	--[[
		A doua chemare pe acelasi ecran deja deschis nu il redeschide.

		`GameController` cheama `show` la fiecare stare primita cat meciul e
		incheiat, iar serverul mai trimite stari si dupa ultima mutare. Fara
		garda, panoul si-ar rejuca animatia de intrare la fiecare mesaj, si —
		mai rau — numaratoarea de cinci secunde ar porni de la capat de fiecare
		data, deci ecranul nu s-ar inchide niciodata singur. Textul se pune in
		continuare, ca sa urmeze starea daca ea se schimba.
	]]
	local opening = not self.Root.Visible

	local winner = if state.Winner then state.Players[state.Winner] else nil
	local mode = GameConfig.Modes[state.GameMode]
	local isTeamMode = mode ~= nil and mode.Id == "2v2"

	local localPlayer = if localSlot then state.Players[localSlot] else nil
	local localWon = localPlayer ~= nil and state.WinningTeam == localPlayer.Team

	self.Headline.Text = if localWon then "YOU WIN" else "YOU LOST"
	self.Headline.TextColor3 = if localWon then Theme.Color.Valid else Theme.Color.Invalid

	if isTeamMode and state.WinningTeam then
		local names = {}
		for _, player in state.Players do
			if player.Team == state.WinningTeam then
				table.insert(names, player.Name)
			end
		end
		table.sort(names)
		self.Detail.Text = string.format("Team %s made it across.", table.concat(names, " and "))
	elseif winner then
		self.Detail.Text = string.format("%s reached the goal.", winner.Name)
	else
		self.Detail.Text = "The match is over."
	end

	--[[
		Revansa are nevoie de cineva cu care sa o joci.

		Cand toti ceilalti au parasit meciul, "PLAY AGAIN" te-ar pune inapoi in
		coada — o actiune valida, dar nu e ce promite butonul. Ramane stins, iar
		randul de dedesubt spune de ce, ca sa nu para o defectiune.
	]]
	local hasOpponent = false
	for slot, player in state.Players do
		if slot ~= localSlot and player.Connected then
			hasOpponent = true
			break
		end
	end

	Theme.setButtonEnabled(self.AgainButton, hasOpponent)
	if not hasOpponent then
		self.Detail.Text ..= "  The other players have left."
	end

	if not opening then
		return
	end

	self.Root.Visible = true
	self.Root.BackgroundTransparency = 1
	AnimationController.tween(self.Root, { BackgroundTransparency = 0.35 }, 0.35, "fade")

	self.Panel.Size = UDim2.fromOffset(420, 280)
	AnimationController.tween(
		self.Panel,
		{ Size = UDim2.fromOffset(420, 300) },
		0.3,
		"size",
		Enum.EasingStyle.Back
	)

	self:startTimeout()
end

--[[
	E deschis acum?

	`GameController` intreaba inainte sa programeze deschiderea intarziata de la
	finalul meciului: daca panoul e deja pe ecran, nu mai are ce sa astepte.
]]
function VictoryView.isOpen(self: VictoryView): boolean
	return self.Root.Visible
end

function VictoryView.hide(self: VictoryView)
	self:stopTimeout()
	self.Root.Visible = false
end

return VictoryView
