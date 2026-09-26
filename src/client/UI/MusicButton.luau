--!strict
--[[
	MusicButton — comutatorul muzicii de fundal, in bara de sus a Roblox-ului.

	Sta in capatul drept al barei, pe aceeasi linie cu butoanele Roblox-ului din
	stanga (meniu, chat, microfon), si arata ca ele: un
	cerc inchis la culoare, cu o nota alba. Oprit, nota e taiata de o linie
	rosie, la fel cum isi arata si microfonul starea.

	Acolo, si nu langa SOUND din coltul de jos, fiindca muzica merge si in lobby,
	unde HUD-ul meciului nu exista. Bara de sus e singurul loc care se vede
	oriunde ai fi.

	Asezarea se socoteste de la marginile ecranului, cu `DeviceSafeInsets`: tot
	ecranul, bara de sus inclusiv, dar fara decupajele telefoanelor. Zona
	`TopbarSafeInsets` parea locul firesc, dar latimea ei difera de la un ecran
	la altul — uneori se opreste inainte de margine, alteori merge pana in ea —
	si o margine pusa peste ea iesea cand dreapta, cand dubla.
]]

local Theme = require(script.Parent.Theme)

--[[
	Marimea, locul si culoarea cercurilor Roblox-ului din bara de sus.

	Masurate, nu ghicite: butoanele lor sunt de 44 de pixeli si stau la 12 de
	marginea de sus, intr-o bara de 58. Centrat pe inaltimea barei, cercul nostru
	cadea cu cinci pixeli mai sus decat ale lor. Pe orizontala, meniul lor sta la
	16 pixeli de marginea stanga, iar cercul nostru sta la fel de departe de cea
	dreapta.
]]
local SIZE = 44
local TOP = 12
local EDGE = 16
local FILL = Color3.fromRGB(18, 18, 21)
local FILL_TRANSPARENCY = 0.2
local HOVER_TRANSPARENCY = 0.05
local SLASH = Color3.fromHex("E5484D")

local MusicButton = {}
MusicButton.__index = MusicButton

type MusicButtonFields = {
	Screen: ScreenGui,
	Button: TextButton,
	Slash: Frame,
}

export type MusicButton = typeof(setmetatable({} :: MusicButtonFields, MusicButton))

function MusicButton.new(parent: Instance, onToggle: () -> boolean): MusicButton
	local self = setmetatable({}, MusicButton) :: MusicButton

	self.Screen = Theme.create("ScreenGui", {
		Name = "BarricadeTopbar",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		-- Peste cortina de incarcare nu, dar peste restul interfetei jocului da.
		DisplayOrder = 5,
		Parent = parent,
	}) :: ScreenGui

	self.Button = Theme.create("TextButton", {
		Name = "Music",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = FILL,
		BackgroundTransparency = FILL_TRANSPARENCY,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, TOP),
		Size = UDim2.fromOffset(SIZE, SIZE),
		Parent = self.Screen,
	}, {
		Theme.corner(UDim.new(1, 0)),
		Theme.text({
			Name = "Note",
			Text = "♫",
			Font = Enum.Font.GothamBold,
			TextSize = 32,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			RichText = false,
			Size = UDim2.fromScale(1, 1),
		}),
	}) :: TextButton

	--[[
		Linia de oprire, pe diagonala, ca la microfonul de alaturi. Ea singura
		spune starea: o eticheta scrisa n-ar incapea intr-un cerc de 44 de
		pixeli.
	]]
	self.Slash = Theme.create("Frame", {
		Name = "Slash",
		BackgroundColor3 = SLASH,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 3),
		Rotation = -45,
		Visible = false,
		Parent = self.Button,
	}, {
		Theme.corner(UDim.new(1, 0)),
	}) :: Frame

	self.Button.MouseEnter:Connect(function()
		self.Button.BackgroundTransparency = HOVER_TRANSPARENCY
	end)
	self.Button.MouseLeave:Connect(function()
		self.Button.BackgroundTransparency = FILL_TRANSPARENCY
	end)
	self.Button.Activated:Connect(function()
		self:setEnabled(onToggle())
	end)

	return self
end

function MusicButton.setEnabled(self: MusicButton, enabled: boolean)
	self.Slash.Visible = not enabled
end

return MusicButton
