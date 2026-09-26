--!strict
--[[
	ConfirmView — intrebarea de dinaintea unei actiuni care nu se poate lua inapoi.

	Exista pentru „Leave": butonul sta in coltul de jos, langa sunet si
	perspectiva, si il apesi din greseala cu un deget pe telefon sau cu cursorul
	dus in colt. Iar plecarea dintr-un meci nu e o setare — e o partida pierduta
	pentru tine si castigata pentru celalalt, si nu se intoarce.

	Fereastra nu e a lui `HudView`, desi butonul e acolo. HUD-ul deseneaza ce se
	intampla in meci; asta intrerupe meciul si asteapta un raspuns. Tinuta
	inauntru, ar fi crescut cu inca o stare un fisier care are deja destule, si
	n-ar fi putut fi folosita de nimeni altcineva.

	E o singura fereastra, refolosita: `ask` ii schimba textul si cui ii
	raspunde. Doua ferestre identice cu texte diferite ar fi fost doua locuri in
	care se strica acelasi lucru.
]]

local Theme = require(script.Parent.Theme)

local ConfirmView = {}
ConfirmView.__index = ConfirmView

type ConfirmFields = {
	Screen: Frame,
	Panel: Frame,
	Title: TextLabel,
	Body: TextLabel,
	Accept: TextButton,
	Cancel: TextButton,
	--[[
		Cui i se raspunde acum. Se sterge inainte sa fie chemat, nu dupa: altfel
		o a doua apasare pe acelasi buton, cat tine inca apelul, ar trimite
		raspunsul de doua ori.
	]]
	Answer: ((boolean) -> ())?,
}

export type ConfirmView = typeof(setmetatable({} :: ConfirmFields, ConfirmView))

export type Question = {
	Title: string,
	Body: string,
	Accept: string,
	Cancel: string,
}

function ConfirmView.new(parent: Instance): ConfirmView
	local self = setmetatable({}, ConfirmView) :: ConfirmView
	self.Answer = nil :: ((boolean) -> ())?

	--[[
		Valul de intuneric e si el parte din intrebare, nu doar decor: cat timp
		e acolo, nu se poate apasa nimic din spate. Intrebarea asteapta un
		raspuns, deci nu are voie sa lase meciul sa mearga mai departe pe sub ea.

		`Active` e ce face din el o usa inchisa si nu un geam colorat. Un `Frame`
		obisnuit nu ia parte la cautarea tintei: apasarea trece prin el si
		ajunge la butonul de dedesubt, deci START s-ar fi putut apasa prin
		fereastra, iar in meci s-ar fi pus ziduri pe tabla de sub ea. Cu `Active`
		oprit acolo, apasarea e si „prelucrata" pentru `UserInputService`, deci
		nici `WorldController` nu o mai primeste.
	]]
	local screen = Theme.create("Frame", {
		Name = "Confirm",
		Active = true,
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		-- Peste carduri, butoane si tabla, dar sub ecranul de incarcare.
		ZIndex = 20,
		Parent = parent,
	}) :: Frame
	self.Screen = screen

	local panel = Theme.create("Frame", {
		Name = "Panel",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 220),
		ZIndex = 21,
		Parent = screen,
	}, {
		Theme.corner(Theme.Radius.Large),
		Theme.stroke(Theme.Color.Line, 1),
		Theme.padding(24),
	}) :: Frame
	self.Panel = panel

	self.Title = Theme.text({
		Name = "Title",
		Text = "",
		Font = Theme.Font.Bold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 22,
		Parent = panel,
	})

	self.Body = Theme.text({
		Name = "Body",
		Text = "",
		TextColor3 = Theme.Color.TextMuted,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 60),
		ZIndex = 22,
		Parent = panel,
	})

	local actions = Theme.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 46),
		ZIndex = 22,
		Parent = panel,
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
		„Ramai" sta primul si e cel colorat.

		Intrebarea se pune tocmai fiindca raspunsul sigur e „nu". Butonul care
		duce inapoi in meci trebuie sa fie cel pe care cade ochiul si degetul;
		cel care incheie partida are voie sa arate ca orice alt buton.
	]]
	self.Cancel = Theme.button({
		Name = "Cancel",
		Text = "",
		Skin = "Primary",
		Size = UDim2.fromOffset(160, 46),
		LayoutOrder = 1,
		ZIndex = 22,
		Parent = actions,
	})

	self.Accept = Theme.button({
		Name = "Accept",
		Text = "",
		Skin = "Secondary",
		Size = UDim2.fromOffset(160, 46),
		LayoutOrder = 2,
		ZIndex = 22,
		Parent = actions,
	})

	self.Cancel.MouseButton1Click:Connect(function()
		self:resolve(false)
	end)

	self.Accept.MouseButton1Click:Connect(function()
		self:resolve(true)
	end)

	return self
end

--[[
	Pune intrebarea. `answer` primeste `true` pentru butonul de accept si
	`false` pentru cel de anulare — inclusiv cand fereastra e inchisa din afara,
	prin `dismiss`.

	O a doua intrebare peste una deschisa o inlocuieste, iar celei dintai i se
	raspunde „nu": ramasa fara fereastra, n-are cum sa mai primeasca un da.
]]
function ConfirmView.ask(self: ConfirmView, question: Question, answer: (boolean) -> ())
	self:resolve(false)

	self.Title.Text = question.Title
	self.Body.Text = question.Body
	self.Accept.Text = question.Accept
	self.Cancel.Text = question.Cancel
	self.Answer = answer
	self.Screen.Visible = true
end

function ConfirmView.isOpen(self: ConfirmView): boolean
	return self.Screen.Visible
end

--[[
	Inchide fara raspuns din partea jucatorului — pentru cand se schimba lumea
	sub intrebare: meciul s-a terminat singur, sau te-a scos serverul. Cel care
	astepta primeste „nu", fiindca nimeni n-a apasat da.
]]
function ConfirmView.dismiss(self: ConfirmView)
	self:resolve(false)
end

function ConfirmView.resolve(self: ConfirmView, accepted: boolean)
	local answer = self.Answer
	self.Answer = nil
	self.Screen.Visible = false
	if answer then
		answer(accepted)
	end
end

return ConfirmView
