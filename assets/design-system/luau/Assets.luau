--!strict
-- Barricade Design System -> harta de asseturi Roblox.
-- GENERAT de mkassets.js din manifest.json + ids.json. Nu edita manual.
-- Regenereaza cu: node mkassets.js
--
-- Reguli de export (sectiunea 16 a design system-ului):
--   * placile si baricadele se intind prin 9-slice, fara text ars in textura;
--     pune un TextLabel separat peste ele
--   * inset de referinta 18px la 1x / 36px la 2x; formele subtiri folosesc raza lor
--   * token-urile, baricadele si icoanele sunt PNG transparent la 1x/2x
--   * textura de lemn e un singur 256px tileabil, reutilizat la trei nuante

local Assets = {}

-- Scala incarcata in Roblox. Asseturile @2x arata mai bine la scalare in jos,
-- deci implicit folosim 2x si lasam motorul sa reduca.
Assets.Scale = "2x" :: "1x" | "2x"

-- ---------- plate ----------
Assets.plate = {
	button_l = {
		id1x = nil,
		id2x = "rbxassetid://81339455939561",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	button_m = {
		id1x = nil,
		id2x = "rbxassetid://91988087944826",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	button_s = {
		id1x = nil,
		id2x = "rbxassetid://121714518979409",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	button_disabled = {
		id1x = nil,
		id2x = "rbxassetid://130146431597322",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	button_green = {
		id1x = nil,
		id2x = "rbxassetid://131941107163037",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	panel = {
		id1x = nil,
		id2x = "rbxassetid://78313856397703",
		size = Vector2.new(120, 120),
		slice1x = Rect.new(24, 24, 96, 96),
		slice2x = Rect.new(48, 48, 192, 192),
	},
	card_paper = {
		id1x = nil,
		id2x = "rbxassetid://76367558578065",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(14, 14, 82, 82),
		slice2x = Rect.new(28, 28, 164, 164),
	},
	flat_l = {
		id1x = nil,
		id2x = "rbxassetid://99460863755172",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	flat_m = {
		id1x = nil,
		id2x = "rbxassetid://127705370769313",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	flat_s = {
		id1x = nil,
		id2x = "rbxassetid://122531410899099",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	flat_disabled = {
		id1x = nil,
		id2x = "rbxassetid://87431084954685",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
	flat_green = {
		id1x = nil,
		id2x = "rbxassetid://137475878813893",
		size = Vector2.new(96, 96),
		slice1x = Rect.new(18, 18, 78, 78),
		slice2x = Rect.new(36, 36, 156, 156),
	},
}

-- ---------- token ----------
Assets.token = {
	blue = {
		id1x = nil,
		id2x = "rbxassetid://110855189699055",
		size = Vector2.new(96, 96),
	},
	blue_active = {
		id1x = nil,
		id2x = "rbxassetid://135760893307529",
		size = Vector2.new(96, 96),
	},
	red = {
		id1x = nil,
		id2x = "rbxassetid://114107745898202",
		size = Vector2.new(96, 96),
	},
	red_active = {
		id1x = nil,
		id2x = "rbxassetid://88068196856378",
		size = Vector2.new(96, 96),
	},
	green = {
		id1x = nil,
		id2x = "rbxassetid://71348727869282",
		size = Vector2.new(96, 96),
	},
	green_active = {
		id1x = nil,
		id2x = "rbxassetid://129498354017998",
		size = Vector2.new(96, 96),
	},
	yellow = {
		id1x = nil,
		id2x = "rbxassetid://136038308721017",
		size = Vector2.new(96, 96),
	},
	yellow_active = {
		id1x = nil,
		id2x = "rbxassetid://112475239783312",
		size = Vector2.new(96, 96),
	},
	eliminated = {
		id1x = nil,
		id2x = "rbxassetid://105930516034494",
		size = Vector2.new(96, 96),
	},
	crown_pip = {
		id1x = nil,
		id2x = "rbxassetid://130157377920395",
		size = Vector2.new(28, 20),
	},
}

-- ---------- barricade ----------
Assets.barricade = {
	horizontal = {
		id1x = nil,
		id2x = "rbxassetid://117499290501346",
		size = Vector2.new(130, 24),
		slice1x = Rect.new(12, 0, 118, 24),
		slice2x = Rect.new(24, 0, 236, 48),
	},
	vertical = {
		id1x = nil,
		id2x = "rbxassetid://108370254912490",
		size = Vector2.new(24, 130),
		slice1x = Rect.new(0, 12, 24, 118),
		slice2x = Rect.new(0, 24, 48, 236),
	},
	valid = {
		id1x = nil,
		id2x = "rbxassetid://79613103854680",
		size = Vector2.new(136, 30),
	},
	invalid = {
		id1x = nil,
		id2x = "rbxassetid://78681838022361",
		size = Vector2.new(136, 30),
	},
}

-- ---------- texture ----------
Assets.texture = {
	wood_grain_256 = {
		id1x = nil,
		id2x = "rbxassetid://76795381854493",
		size = Vector2.new(256, 256),
	},
}

-- ---------- icon ----------
Assets.icon = {
	home = {
		id1x = nil,
		id2x = "rbxassetid://80548198284283",
		size = Vector2.new(64, 64),
	},
	settings = {
		id1x = nil,
		id2x = "rbxassetid://121703120941696",
		size = Vector2.new(64, 64),
	},
	sound = {
		id1x = nil,
		id2x = "rbxassetid://74649486616815",
		size = Vector2.new(64, 64),
	},
	mute = {
		id1x = nil,
		id2x = "rbxassetid://84111608235438",
		size = Vector2.new(64, 64),
	},
	music = {
		id1x = nil,
		id2x = "rbxassetid://140579249131095",
		size = Vector2.new(64, 64),
	},
	back = {
		id1x = nil,
		id2x = "rbxassetid://74475653693512",
		size = Vector2.new(64, 64),
	},
	next = {
		id1x = nil,
		id2x = "rbxassetid://89705125299300",
		size = Vector2.new(64, 64),
	},
	close = {
		id1x = nil,
		id2x = "rbxassetid://80354790272609",
		size = Vector2.new(64, 64),
	},
	check = {
		id1x = nil,
		id2x = "rbxassetid://136706122965770",
		size = Vector2.new(64, 64),
	},
	player = {
		id1x = nil,
		id2x = "rbxassetid://124139590529867",
		size = Vector2.new(64, 64),
	},
	team = {
		id1x = nil,
		id2x = "rbxassetid://127762608141720",
		size = Vector2.new(64, 64),
	},
	trophy = {
		id1x = nil,
		id2x = "rbxassetid://129841673277890",
		size = Vector2.new(64, 64),
	},
	crown = {
		id1x = nil,
		id2x = "rbxassetid://80808988854830",
		size = Vector2.new(64, 64),
	},
	timer = {
		id1x = nil,
		id2x = "rbxassetid://113886057783682",
		size = Vector2.new(64, 64),
	},
	help = {
		id1x = nil,
		id2x = "rbxassetid://124765034849100",
		size = Vector2.new(64, 64),
	},
	rotate = {
		id1x = nil,
		id2x = "rbxassetid://120425651178639",
		size = Vector2.new(64, 64),
	},
	horizontal = {
		id1x = nil,
		id2x = "rbxassetid://74147368130241",
		size = Vector2.new(64, 64),
	},
	vertical = {
		id1x = nil,
		id2x = "rbxassetid://108057633041498",
		size = Vector2.new(64, 64),
	},
	lock = {
		id1x = nil,
		id2x = "rbxassetid://135832320049066",
		size = Vector2.new(64, 64),
	},
	shop = {
		id1x = nil,
		id2x = "rbxassetid://75198337192296",
		size = Vector2.new(64, 64),
	},
	inventory = {
		id1x = nil,
		id2x = "rbxassetid://79119959739975",
		size = Vector2.new(64, 64),
	},
	leave = {
		id1x = nil,
		id2x = "rbxassetid://117872720220468",
		size = Vector2.new(64, 64),
	},
}

-- Returneaza ID-ul pentru scala activa, cu revenire pe cealalta daca lipseste.
function Assets.id(entry: { id1x: string?, id2x: string? }): string?
	if Assets.Scale == "2x" then
		return entry.id2x or entry.id1x
	end
	return entry.id1x or entry.id2x
end

-- Returneaza SliceCenter potrivit scalei active (doar pentru placi si baricade).
function Assets.slice(entry: { slice1x: Rect?, slice2x: Rect? }): Rect?
	if Assets.Scale == "2x" then
		return entry.slice2x or entry.slice1x
	end
	return entry.slice1x or entry.slice2x
end

-- Cate asseturi asteapta inca un ID real.
function Assets.missing(): { string }
	local out = {}
	for categoryName, category in pairs(Assets) do
		if typeof(category) ~= "table" then
			continue
		end
		for entryName, entry in pairs(category) do
			if typeof(entry) == "table" and entry.id1x == nil and entry.id2x == nil then
				table.insert(out, categoryName .. "/" .. entryName)
			end
		end
	end
	table.sort(out)
	return out
end

return Assets
