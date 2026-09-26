--!strict
--[[
	Callouts — ce scrie pe ecran dupa o mutare care merita strigata.

	E catalog, ca `Emotes`: o lista de lucruri care exista, cu textul, culorile,
	marimea si sunetul fiecaruia. Cand se aprind nu se decide aici, ci in
	`MoveCommentary`, pe server; pragurile lui stau in `GameConfig.Callouts`.

	Ramane pur — culorile sunt numere hex, sunetul e un nume din
	`GameConfig.Sounds`. `CalloutView` le imbraca in `Color3` si `Sound`.

	Acelasi verdict se citeste diferit dupa cine esti la masa. `format` alege
	textul si culorile din perspectiva jucatorului local:

	  AUTHOR — tu ai facut mutarea: textul de baza, culorile calde ale lui
	  VICTIM — mutarea te-a lovit pe tine: textul de victima, paleta rece
	  OTHER  — te uiti la altii: textul cu numele celui care a facut-o

	Textele sunt in engleza, fiindca asta citeste jucatorul. `{amount}` e
	numarul care se numara pe ecran, `{name}` e numele autorului.
]]

export type Entry = {
	Id: string,
	-- 1 mic, 2 mediu, 3 epic. Hotaraste animatia, marimea si sunetul.
	Tier: number,
	-- Cand o actiune aprinde mai multe, se arata intai cele cu numar mai mare.
	Priority: number,
	Text: string,
	-- Cand tinta e jucatorul local. Lipsa inseamna `Text`.
	VictimText: string?,
	-- Cand jucatorul local doar priveste. Lipsa inseamna `Text`.
	OtherText: string?,
	-- Gradientul, doua culori hex.
	Colors: { number },
	-- Numele din `GameConfig.Sounds`, pentru autor.
	Sound: string,
	-- Cand tinta e jucatorul local: „Fuhhhh", nu fanfara celui care l-a blocat.
	VictimSound: string?,
	-- Cand vestea e buna pentru un adversar si rea pentru tine. Lipsa inseamna `Sound`.
	OtherSound: string?,
}

export type Perspective = "AUTHOR" | "VICTIM" | "OTHER"

-- Ce ajunge la ecran: textul deja ales, taiat in jurul numarului care se numara.
export type Presented = {
	Id: string,
	Tier: number,
	Perspective: Perspective,
	-- Textul dinaintea numarului si cel de dupa. Fara numar, totul e in `Prefix`.
	Prefix: string,
	Suffix: string,
	Amount: number?,
	Colors: { number },
	Sound: string,
}

local Callouts = {}

Callouts.All = {
	BLOCK = {
		Id = "BLOCK",
		Tier = 1,
		Priority = 30,
		Text = "BLOCKED! +{amount}",
		VictimText = "YOU'RE BLOCKED! +{amount}",
		Colors = { 0xFFD166, 0xF77F00 },
		Sound = "CalloutSmall",
		VictimSound = "CalloutBlocked",
	},
	BLOCK_BIG = {
		Id = "BLOCK_BIG",
		Tier = 2,
		Priority = 60,
		Text = "NICE BLOCK! +{amount}",
		VictimText = "YOU'RE BLOCKED! +{amount}",
		Colors = { 0xFFB703, 0xFB5607 },
		Sound = "CalloutBig",
		VictimSound = "CalloutBlocked",
	},
	BLOCK_HUGE = {
		Id = "BLOCK_HUGE",
		Tier = 3,
		Priority = 80,
		Text = "HUGE BLOCK! +{amount}",
		VictimText = "YOU'RE BLOCKED! +{amount}",
		Colors = { 0xFF006E, 0xFFBE0B },
		Sound = "CalloutEpic",
		VictimSound = "CalloutBlocked",
	},
	BLOCK_MEGA = {
		Id = "BLOCK_MEGA",
		Tier = 3,
		Priority = 90,
		Text = "BRICKED IN! +{amount}",
		VictimText = "YOU'RE BRICKED IN! +{amount}",
		Colors = { 0xFF006E, 0x8338EC },
		Sound = "CalloutPerfect",
		VictimSound = "CalloutBlocked",
	},
	DOUBLE_BLOCK = {
		Id = "DOUBLE_BLOCK",
		Tier = 2,
		Priority = 65,
		Text = "DOUBLE TROUBLE!",
		Colors = { 0xFF9F1C, 0xFF3C38 },
		Sound = "CalloutBig",
	},
	JUMP = {
		Id = "JUMP",
		Tier = 2,
		Priority = 55,
		Text = "LEAPFROG!",
		VictimText = "LEAPFROGGED!",
		Colors = { 0x4CC9F0, 0xF72585 },
		Sound = "CalloutBig",
		VictimSound = "CalloutOhNo",
	},
	SIDESTEP = {
		Id = "SIDESTEP",
		Tier = 2,
		Priority = 55,
		Text = "SIDESTEP!",
		Colors = { 0xF72585, 0x7209B7 },
		Sound = "CalloutBig",
	},
	ONE_STEP = {
		Id = "ONE_STEP",
		Tier = 3,
		Priority = 85,
		Text = "ONE STEP AWAY!",
		OtherText = "{name}: ONE STEP AWAY!",
		Colors = { 0xFFD60A, 0xFF4D6D },
		Sound = "CalloutEpic",
		OtherSound = "CalloutOhNo",
	},
	TAKE_LEAD = {
		Id = "TAKE_LEAD",
		Tier = 1,
		Priority = 40,
		Text = "YOU TAKE THE LEAD!",
		OtherText = "{name} TAKES THE LEAD!",
		Colors = { 0xFFD60A, 0xFFA200 },
		Sound = "CalloutSmall",
	},
	COMEBACK = {
		Id = "COMEBACK",
		Tier = 3,
		Priority = 95,
		Text = "COMEBACK!",
		OtherText = "{name}'S COMEBACK!",
		Colors = { 0xFF4D6D, 0xFFD60A },
		Sound = "CalloutPerfect",
		OtherSound = "CalloutOhNo",
	},
	LAST_WALL = {
		Id = "LAST_WALL",
		Tier = 1,
		Priority = 20,
		Text = "LAST BARRICADE!",
		OtherText = "{name}: LAST BARRICADE!",
		Colors = { 0xFFE8A3, 0xE9A23B },
		Sound = "CalloutSmall",
	},
	NECK_AND_NECK = {
		Id = "NECK_AND_NECK",
		Tier = 2,
		Priority = 50,
		Text = "NECK AND NECK!",
		Colors = { 0xFF7B00, 0xFF0054 },
		Sound = "CalloutBig",
	},
	UNSTOPPABLE = {
		Id = "UNSTOPPABLE",
		Tier = 2,
		Priority = 70,
		Text = "NOTHING CAN STOP YOU!",
		OtherText = "{name} IS UNSTOPPABLE!",
		Colors = { 0xFFD60A, 0xFF006E },
		Sound = "CalloutBig",
		OtherSound = "CalloutOhNo",
	},
} :: { [string]: Entry }

-- Paleta rece pentru cand tu esti cel lovit: aceeasi veste, alta culoare.
Callouts.VictimColors = { 0x9AD1FF, 0x4361EE }

-- Curcubeul marimii 3, rotit continuu. Nu si pentru victima: acolo nu e sarbatoare.
Callouts.Rainbow = { 0xFF006E, 0xFB5607, 0xFFBE0B, 0x3A86FF, 0x8338EC }

-- Conturul gros din jurul literelor: lemnul cel mai inchis din paleta.
Callouts.Stroke = 0x2A1A0E

function Callouts.get(id: any): Entry?
	if type(id) ~= "string" then
		return nil
	end
	return Callouts.All[id]
end

--[[
	Din cine a facut mutarea si pe cine a lovit, cum se vede ea de la locul
	jucatorului local. `localSlot` e `nil` pentru cine priveste fara sa joace.
]]
function Callouts.perspective(slot: number, target: number?, localSlot: number?): Perspective
	if localSlot ~= nil and target == localSlot then
		return "VICTIM"
	end
	if localSlot ~= nil and slot == localSlot then
		return "AUTHOR"
	end
	return "OTHER"
end

--[[
	Un callout venit de la server, gata de desenat.

	`nil` pentru un id necunoscut: serverul si clientul pot rula versiuni
	diferite ale catalogului, iar un callout nestiut se sare, nu se ghiceste.
	`{name}` se inlocuieste dupa taiere, ca un nume care contine „{amount}"
	sa nu poata muta numarul, si printr-o functie, ca un „%" din nume sa nu fie
	citit ca tipar.

	`allied` spune ca autorul e coechipierul jucatorului local. Textul ramane
	cel cu numele lui, dar sunetul e al autorului: in 2v2 pasul final al
	partenerului e o veste buna, nu un „oh no".
]]
function Callouts.format(
	callout: { Id: any, Slot: any, Target: any, Amount: any },
	localSlot: number?,
	name: string?,
	allied: boolean?
): Presented?
	local entry = Callouts.get(callout.Id)
	if not entry or type(callout.Slot) ~= "number" then
		return nil
	end

	local target = if type(callout.Target) == "number" then callout.Target else nil
	local amount = if type(callout.Amount) == "number" then callout.Amount else nil
	local perspective: Perspective = Callouts.perspective(callout.Slot, target, localSlot)

	local text = entry.Text
	if perspective == "VICTIM" and entry.VictimText then
		text = entry.VictimText
	elseif perspective == "OTHER" and entry.OtherText then
		text = entry.OtherText
	end

	local start, finish = string.find(text, "{amount}", 1, true)
	local prefix, suffix = text, ""
	if start and finish then
		prefix = string.sub(text, 1, start - 1)
		suffix = string.sub(text, finish + 1)
	else
		amount = nil
	end

	local shown = string.upper(name or "PLAYER")
	prefix = (string.gsub(prefix, "{name}", function()
		return shown
	end))
	suffix = (string.gsub(suffix, "{name}", function()
		return shown
	end))

	local presented: Presented = {
		Id = entry.Id,
		Tier = entry.Tier,
		Perspective = perspective,
		Prefix = prefix,
		Suffix = suffix,
		Amount = amount,
		Colors = if perspective == "VICTIM" then Callouts.VictimColors else entry.Colors,
		Sound = entry.Sound,
	}
	if perspective == "VICTIM" and entry.VictimSound then
		presented.Sound = entry.VictimSound
	elseif perspective == "OTHER" and entry.OtherSound and not allied then
		presented.Sound = entry.OtherSound
	end
	return presented
end

return Callouts
