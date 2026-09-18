--!strict
--[[
	Theme — vocabularul vizual al jocului, intr-un singur loc.

	Roblox are un look implicit foarte recognoscibil, si nu in bine: gri,
	colturi drepte, Legacy font. Tot ce e aici exista ca sa nu semene jocul
	cu un template: paleta rece si adanca, contrast controlat, colturi
	rotunjite constant, o singura familie de font cu doua greutati.

	Culorile nu poarta singure informatie. Fiecare jucator are si avatar, si
	nume, si o pozitie proprie in jurul tablei; culoarea doar leaga tokenul
	de card.
]]

local Theme = {}

Theme.Color = {
	-- Fundal, de la cel mai adanc la cel mai ridicat plan.
	Backdrop = Color3.fromHex("0E1017"),
	Surface = Color3.fromHex("161A26"),
	SurfaceRaised = Color3.fromHex("1E2433"),
	Board = Color3.fromHex("141824"),

	-- Celulele au doua nuante foarte apropiate: se citeste grila fara sa tipe.
	CellLight = Color3.fromHex("222839"),
	CellDark = Color3.fromHex("1D2231"),
	CellHover = Color3.fromHex("2E3750"),
	CellTarget = Color3.fromHex("2A3A52"),

	Line = Color3.fromHex("2A3145"),
	Wall = Color3.fromHex("F0C674"),
	WallShadow = Color3.fromHex("8A6E2F"),

	Valid = Color3.fromHex("4CC38A"),
	Invalid = Color3.fromHex("E2574A"),
	Accent = Color3.fromHex("4A90E2"),

	Text = Color3.fromHex("E8ECF5"),
	TextMuted = Color3.fromHex("8C93A8"),
	TextInverse = Color3.fromHex("0E1017"),
}

Theme.Font = {
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Regular = Enum.Font.Gotham,
}

Theme.Radius = {
	Small = UDim.new(0, 6),
	Medium = UDim.new(0, 10),
	Large = UDim.new(0, 16),
	Round = UDim.new(1, 0),
}

--[[
	Constructor declarativ. Fara el, fiecare ecran ar fi trei sute de linii de
	`Instance.new` urmate de atribuiri, si structura ar disparea sub ele.

	create("Frame", { ... }, { copii })
]]
function Theme.create(
	className: string,
	properties: { [string]: any }?,
	children: { Instance }?
): Instance
	local instance = Instance.new(className)

	if properties then
		for key, value in properties do
			(instance :: any)[key] = value
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	return instance
end

function Theme.corner(radius: UDim?): Instance
	return Theme.create("UICorner", { CornerRadius = radius or Theme.Radius.Medium }) :: UICorner
end

function Theme.stroke(color: Color3?, thickness: number?, transparency: number?): Instance
	return Theme.create("UIStroke", {
		Color = color or Theme.Color.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(all: number): Instance
	return Theme.create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	})
end

function Theme.text(properties: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font.Medium,
		TextColor3 = Theme.Color.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	}
	for key, value in properties do
		defaults[key] = value
	end
	return Theme.create("TextLabel", defaults) :: TextLabel
end

--[[
	Buton cu starile de interactiune deja legate. Roblox nu ofera hover si
	pressed din oficiu, iar un buton fara ele se simte mort.
]]
function Theme.button(properties: { [string]: any }): TextButton
	local base = properties.BackgroundColor3 or Theme.Color.SurfaceRaised
	local hover = properties.HoverColor or base:Lerp(Color3.new(1, 1, 1), 0.12)
	properties.HoverColor = nil

	local defaults: { [string]: any } = {
		BackgroundColor3 = base,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextColor3 = Theme.Color.Text,
		TextSize = 16,
		BorderSizePixel = 0,
	}
	for key, value in properties do
		defaults[key] = value
	end

	local button = Theme.create("TextButton", defaults) :: TextButton

	--[[
		Culoarea de baza sta intr-un atribut, nu intr-o variabila prinsa in
		closure: butoanele isi schimba culoarea cand devin inactive, si
		hover-ul trebuie sa se intoarca la culoarea de *acum*, nu la cea de
		la constructie.
	]]
	button:SetAttribute("BaseColor", base)
	button:SetAttribute("HoverColor", hover)

	button.MouseEnter:Connect(function()
		if button.Active then
			button.BackgroundColor3 = button:GetAttribute("HoverColor") :: Color3
		end
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = button:GetAttribute("BaseColor") :: Color3
	end)

	return button
end

-- Schimba culoarea de baza a unui buton impreuna cu cea de hover.
function Theme.recolorButton(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("HoverColor", color:Lerp(Color3.new(1, 1, 1), 0.12))
	button.BackgroundColor3 = color
end

return Theme
