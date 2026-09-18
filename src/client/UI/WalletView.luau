--!strict
--[[
	WalletView — banutii, pe ecran.

	O moneda si o cifra mare, la mijlocul marginii din stanga. Acolo pentru ca in
	lobby privirea sta in mijlocul ecranului si jos, unde sunt butoanele; stanga
	la mijloc e langa, fara sa fie peste. Sus stanga e ocupat de meniul si
	chatul Roblox, care apar pe orice ecran.

	Nu scrie "COINS". Cuvantul ar spune ce inseamna numarul, dar moneda desenata
	spune acelasi lucru fara sa fie citita, in orice limba, si lasa toata
	greutatea vizuala cifrei — care e singura informatie care se schimba.

	Bara e un singur desen, din aceeasi plansa ca restul interfetei: moneda de
	aici si moneda din magazin sunt acelasi obiect, nu doua desene care seamana.
	Inainte moneda era construita din Frame-uri cu gradient, si se vedea ca vine
	din alta parte decat jocul.

	Nu stie de unde vin banii si nici ce se poate face cu ei. Primeste un numar
	si il arata — la fel ca restul interfetei, care nu hotaraste niciodata nimic.

	Numarul nu sare la valoarea noua, ci urca pana la ea. Douazeci si cinci de
	banuti aparuti dintr-o data se pot pierde cu vederea; aceiasi douazeci si
	cinci numarati in doua zecimi se vad, si se simt castigati. E singurul loc
	din interfata unde asta conteaza mai mult decat raspunsul instantaneu.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local WalletView = {}
WalletView.__index = WalletView

-- Cat dureaza urcarea pana la valoarea noua, in secunde.
local COUNT_SECONDS = 0.45

--[[
	Marimea barii pe ecran, in pixeli.

	Desenul are 244x92; raportul de aici e acelasi (188/71 = 2.65), ca sa nu
	ramana dungi goale sus si jos din `ScaleType.Fit`. Daca se schimba unul,
	se schimba amandoua.
]]
local BAR_WIDTH = 188
local BAR_HEIGHT = 71

--[[
	Unde incepe si unde se termina jgheabul cifrei, ca fractiuni din latime.

	Sunt citite din desen: moneda tine cam pana la 38%, iar capatul din dreapta
	se rotunjeste dupa 93%. Cifra se centreaza intre ele, deci un sold de o
	cifra si unul de cinci arata amandoua asezate, nu lipite de un capat.
]]
local TROUGH_LEFT = 0.38
local TROUGH_RIGHT = 0.93

type WalletFields = {
	Root: Frame,
	Bar: ImageLabel,
	Amount: TextLabel,
	-- Ce se vede acum. Poate ramane in urma tinta cat timp urca.
	Shown: number,
	Target: number,
	Counting: boolean,
}

export type WalletView = typeof(setmetatable({} :: WalletFields, WalletView))

function WalletView.new(parent: Instance): WalletView
	local self = setmetatable({}, WalletView) :: WalletView
	self.Shown = 0
	self.Target = 0
	self.Counting = false

	--[[
		Un loc de marime fixa, si abia inauntrul lui bara.

		Saltul de la castig schimba marimea barii; daca bara ar fi ea insasi
		elementul asezat pe ecran, fiecare cadru al saltului i-ar muta coltul si
		toata bucata ar aluneca in loc sa pulseze pe loc. Locul nu se misca.
	]]
	local root = Theme.create("Frame", {
		Name = "Wallet",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
		Parent = parent,
	}) :: Frame
	self.Root = root

	local bar = Theme.create("ImageLabel", {
		Name = "Bar",
		BackgroundTransparency = 1,
		Image = Theme.Assets.Store.currencyBar,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	}) :: ImageLabel
	self.Bar = bar

	--[[
		Cifra sta in jgheabul din dreapta monedei, nu peste toata bara.

		Marimea textului e in scara, nu in pixeli: cand bara sare, cifra creste
		cu ea, in loc sa ramana mica intr-un jgheab care s-a marit sub ea.
	]]
	self.Amount = Theme.text({
		Name = "Amount",
		Text = "0",
		Font = Theme.Font.Bold,
		TextScaled = true,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromScale(TROUGH_LEFT, 0.30),
		Size = UDim2.fromScale(TROUGH_RIGHT - TROUGH_LEFT, 0.40),
		Parent = bar,
	})

	return self
end

--[[
	Grupeaza miile, ca "12500" sa se citeasca dintr-o privire.

	Se face de la coada spre cap, si se opreste cand nu mai schimba nimic — un
	numar de trei cifre iese neatins dupa o singura trecere.
]]
local function grouped(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1 %2")
		text = replaced
		if count == 0 then
			break
		end
	end
	return text
end

--[[
	Saltul barii la castig.

	Numaratoarea spune *cat*; saltul spune *acum*. Fara el, o crestere inceputa
	in timp ce privesti in alta parte a ecranului trece complet neobservata.
	`Back` pentru ca ceva care revine putin sub marimea lui la aterizare pare un
	obiect, nu o imagine care se mareste.
]]
local function bounce(bar: ImageLabel)
	bar.Size = UDim2.fromScale(1.14, 1.14)
	TweenService:Create(
		bar,
		TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, 1) }
	):Play()
end

--[[
	Arata un sold nou.

	Prima valoare primita nu se numara, se pune: la intrarea in joc soldul vine
	de la DataStore, si o urcare de la zero pana la cat ai stranse in zile ar
	arata ca un castig de acum.
]]
function WalletView.set(self: WalletView, coins: number, animate: boolean?)
	local previous = self.Target
	self.Target = math.max(0, math.floor(coins))

	if animate == false or self.Shown == self.Target then
		self.Shown = self.Target
		self.Amount.Text = grouped(self.Shown)
		return
	end

	if self.Target > previous then
		bounce(self.Bar)
	end

	if self.Counting then
		return
	end
	self.Counting = true

	task.spawn(function()
		local from = self.Shown
		local started = os.clock()
		while true do
			local progress = (os.clock() - started) / COUNT_SECONDS
			if progress >= 1 then
				break
			end
			self.Shown = from + (self.Target - from) * progress
			self.Amount.Text = grouped(self.Shown)
			task.wait()
		end
		self.Shown = self.Target
		self.Amount.Text = grouped(self.Shown)
		self.Counting = false
	end)
end

function WalletView.setVisible(self: WalletView, visible: boolean)
	self.Root.Visible = visible
end

return WalletView
