--!strict
-- Barricade Design System -> tokens de design.
-- Sursa: "Barricade Design System.dc.html", sectiunile 02 (Color), 03 (Type),
-- 16 (Responsive & export) si 17 (Component spec sheet).
-- Toate valorile numerice sunt date la 1080p; foloseste Tokens.scale(viewport) pentru restul.

local Tokens = {}

-- ---------- 02 · Culori ----------
Tokens.Color = {
	-- Baza lemn & hartie
	wood100 = Color3.fromHex("EFD9AE"),
	wood300 = Color3.fromHex("D9A566"),
	wood500 = Color3.fromHex("B5763C"),
	wood700 = Color3.fromHex("7A4A22"),
	ink900 = Color3.fromHex("3B2412"),
	paper50 = Color3.fromHex("FBF3E2"),
	paper200 = Color3.fromHex("EBD9BC"),

	-- Accente & feedback
	accentOrange = Color3.fromHex("E87A2C"),
	accentTeal = Color3.fromHex("2FA89B"),
	accentPurple = Color3.fromHex("8B5FC4"),
	highlight = Color3.fromHex("FFD666"),

	-- Stari dezactivate (spec sheet, Button)
	disabledFill = Color3.fromHex("CFC0A4"),
	disabledText = Color3.fromHex("A08A6A"),
}

-- Culorile de jucator. Perechea culoare + forma este OBLIGATORIE (joc accesibil daltonistilor).
export type PlayerColor = "blue" | "red" | "green" | "yellow"
Tokens.Player = {
	blue = { color = Color3.fromHex("2F7FD1"), dark = Color3.fromHex("1D5590"), shape = "circle" },
	red = { color = Color3.fromHex("D9443F"), dark = Color3.fromHex("99241F"), shape = "diamond" },
	green = { color = Color3.fromHex("4BA63C"), dark = Color3.fromHex("2F6B25"), shape = "square" },
	yellow = { color = Color3.fromHex("E8B32B"), dark = Color3.fromHex("A8791A"), shape = "triangle" },
}

-- ---------- 03 · Tipografie ----------
-- Fredoka pentru display, Nunito pentru UI.
-- Nota: Roblox expune Fredoka doar ca FredokaOne (o singura grosime, ~700);
-- nivelurile Fredoka 600 din design sunt aproximate cu aceasta.
Tokens.Font = {
	display = Font.fromEnum(Enum.Font.FredokaOne),
	ui = Font.fromEnum(Enum.Font.Nunito),
}

Tokens.Type = {
	gameTitle = { size = 96, font = "display", tracking = 0.01 },
	pageTitle = { size = 56, font = "display" },
	sectionTitle = { size = 36, font = "display" },
	buttonTitle = { size = 28, font = "display", tracking = 0.06, upper = true },
	body = { size = 24, font = "ui" }, -- niciodata sub 24px in gameplay
	small = { size = 18, font = "ui", tracking = 0.16 },
}

-- ---------- 17 · Raze ----------
Tokens.Radius = { panel = 20, button = 16, card = 12, chip = 10, pill = 999 }

-- ---------- 17 · Butoane ----------
Tokens.Button = {
	L = { height = 96, radius = 18, edge = 8, padX = 46, padY = 20, textSize = 28 },
	M = { height = 72, radius = 14, edge = 6, padX = 32, padY = 15, textSize = 20 },
	S = { height = 48, radius = 11, edge = 4, padX = 20, padY = 10, textSize = 15 },
	minWidth = 180,
	hoverOffset = -2, -- px
	pressOffset = 5, -- px
	selectionRing = 4, -- px, culoarea Tokens.Color.highlight
}

-- ---------- 17 · Token jucator ----------
Tokens.PlayerToken = {
	sizeBoard = 96,
	sizeHud = 72,
	sizeList = 48,
	rim = 7, -- gradient lemn
	innerRing = 4, -- inel de hartie
	shapeRatio = 0.34, -- marca de forma, ca fractie din discul interior
}

-- ---------- 17 · Baricada ----------
Tokens.Barricade = {
	lengthCells = 2,
	thicknessCells = 0.4,
	previewTransparency = 0.6, -- "preview 40%" opacitate
	outline = 3,
}

-- ---------- 16 · Timpi de animatie ----------
Tokens.Motion = {
	buttonHover = 0.08,
	buttonPress = 0.06,
	buttonRelease = 0.10,
	tokenBobPeriod = 1.6,
	tokenBobAmplitude = 7,
	barricadeDrop = 0.18,
	barricadeSquash = 0.04,
	victoryScaleIn = 0.14,
	confettiBurst = 0.90,
	menuFade = 0.12,
	menuSlide = 12,
	notificationSlide = 0.12,
	notificationDwell = 2.4,
}

-- ---------- 16 · Reguli de consistenta ----------
-- Lumina vine intotdeauna de sus: highlight sus, inset jos, muchie dura in nuanta -30%.
Tokens.Surface = {
	topHighlight = Color3.new(1, 1, 1),
	topHighlightTransparency = 0.6, -- rgba(255,255,255,.4)
	bottomInset = Color3.new(0, 0, 0),
	bottomInsetTransparency = 0.82, -- rgba(0,0,0,.18)
}

-- Zona minima de atingere, niciodata sub 44x44 (spec sheet).
Tokens.MinTouchTarget = 44

-- ---------- Scalare ----------
-- Toate valorile sunt la 1080p. Pe alte rezolutii, inmulteste cu factorul asta.
function Tokens.scale(viewportSize: Vector2): number
	return viewportSize.Y / 1080
end

return Tokens
