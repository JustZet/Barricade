--!strict
--[[
	Skins — cum arata o baricada, descris ca date, nu ca ramuri de cod.

	Fiecare skin isi poarta mesh-ul, culorile si, mai tarziu, sunetele si
	efectele. `Barricade` citeste de aici si nu stie ce skinuri exista; ca sa
	adaugi unul nou, adaugi o intrare, nu un `if`.

	`MeshId` gol nu e o eroare, ci starea normala pana cand mesh-urile ajung pe
	Roblox: baricada se construieste atunci din Part-uri, cu aceleasi dimensiuni
	si culori. Jocul e complet jucabil asa, iar cand pui id-ul aici, acelasi
	obiect incepe sa foloseasca mesh-ul fara nicio alta modificare.

	Valorile de culoare vin din `materials.txt`, livrat impreuna cu asseturile.
]]

local Catalog = require(game:GetService("ReplicatedStorage").Shared.Catalog)

export type Skin = {
	Id: string,
	DisplayName: string,
	-- "rbxassetid://..." dupa import; gol inseamna constructie din Part-uri.
	MeshId: string,
	-- Culoarea corpului si cea a muchiei, ca lumina sa vina tot de sus.
	Color: Color3,
	EdgeColor: Color3,
	Material: Enum.Material,
	--[[
		Transparenta corpului cand zidul e asezat. Aproape toate skinurile sunt
		opace, dar `crystal` si `portal` isi pierd complet caracterul daca sunt
		randate plin — de aceea e proprietate de skin, nu o constanta in
		`Barricade`.
	]]
	Transparency: number,
	-- Accentul e optional: doar skinurile care au o parte distincta il folosesc.
	AccentColor: Color3?,
	-- Cand e adevarat, accentul se randeaza Neon si chiar lumineaza.
	Glow: boolean?,
	-- Sloturi pentru mai tarziu. 0 inseamna "fara", exact ca in GameConfig.Sounds.
	PlaceSound: number,
	BlockedSound: number,
}

local Skins = {}

Skins.Default = "wood"

Skins.List = {
	wood = {
		Id = "wood",
		DisplayName = "Oak",
		MeshId = "",
		Color = Color3.fromHex("c68e50"),
		EdgeColor = Color3.fromHex("5c3a23"),
		Material = Enum.Material.Wood,
		Transparency = 0,
		AccentColor = Color3.fromHex("d9b166"),
		Glow = false,
		PlaceSound = 0,
		BlockedSound = 0,
	},

	castle = {
		Id = "castle",
		DisplayName = "Castle",
		MeshId = "",
		Color = Color3.fromHex("9b9589"),
		EdgeColor = Color3.fromHex("6f6a61"),
		Material = Enum.Material.Slate,
		Transparency = 0,
		AccentColor = Color3.fromHex("7a8a5e"),
		Glow = false,
		PlaceSound = 0,
		BlockedSound = 0,
	},

	tree = {
		Id = "tree",
		DisplayName = "Grove",
		MeshId = "",
		Color = Color3.fromHex("6a4830"),
		EdgeColor = Color3.fromHex("4b3222"),
		Material = Enum.Material.Wood,
		Transparency = 0,
		AccentColor = Color3.fromHex("7ea154"),
		Glow = false,
		PlaceSound = 0,
		BlockedSound = 0,
	},

	dragon = {
		Id = "dragon",
		DisplayName = "Dragon",
		MeshId = "",
		Color = Color3.fromHex("94302a"),
		EdgeColor = Color3.fromHex("6b1f1d"),
		Material = Enum.Material.Slate,
		Transparency = 0,
		AccentColor = Color3.fromHex("ffa552"),
		Glow = true,
		PlaceSound = 0,
		BlockedSound = 0,
	},

	energy = {
		Id = "energy",
		DisplayName = "Energy",
		MeshId = "",
		Color = Color3.fromHex("4c545f"),
		EdgeColor = Color3.fromHex("2e343c"),
		Material = Enum.Material.Metal,
		Transparency = 0,
		AccentColor = Color3.fromHex("5fdcff"),
		Glow = true,
		PlaceSound = 0,
		BlockedSound = 0,
	},

	thunder = {
		Id = "thunder",
		DisplayName = "Thunder",
		MeshId = "",
		Color = Color3.fromHex("6b6660"),
		EdgeColor = Color3.fromHex("4a4642"),
		Material = Enum.Material.Metal,
		Transparency = 0,
		AccentColor = Color3.fromHex("d8f0ff"),
		Glow = true,
		PlaceSound = 0,
		BlockedSound = 0,
	},

	crystal = {
		Id = "crystal",
		DisplayName = "Crystal",
		MeshId = "",
		Color = Color3.fromHex("6fb6ff"),
		EdgeColor = Color3.fromHex("5a34c8"),
		Material = Enum.Material.Glass,
		-- Cristalul e translucid prin definitie; opac ar arata ca plastic vopsit.
		Transparency = 0.35,
		AccentColor = Color3.fromHex("f2f8ff"),
		Glow = true,
		PlaceSound = 0,
		BlockedSound = 0,
	},

	portal = {
		Id = "portal",
		DisplayName = "Portal",
		MeshId = "",
		Color = Color3.fromHex("0e0a16"),
		EdgeColor = Color3.fromHex("2b1a52"),
		Material = Enum.Material.Slate,
		Transparency = 0.15,
		AccentColor = Color3.fromHex("8e6bff"),
		Glow = true,
		PlaceSound = 0,
		BlockedSound = 0,
	},
} :: { [string]: Skin }

--[[
	Ordinea in care apar in interfata de selectie vine din `Catalog`, impreuna cu
	restul listei de obiecte. Aici nu se scrie a doua oara: daca ar exista doua
	liste, un skin adaugat intr-una si uitat in cealalta ar disparea din magazin
	fara ca nimic sa se plana.
]]
Skins.Order = Catalog.Order

--[[
	Intoarce intotdeauna un skin valid. Un id necunoscut — salvat de un jucator
	inainte ca skinul sa fie retras, sau venit stricat din retea — nu are voie
	sa lase o baricada nedesenata pe tabla.
]]
function Skins.get(id: string?): Skin
	local skin = if id then Skins.List[id] else nil
	return skin or Skins.List[Skins.Default]
end

-- Cate skinuri asteapta inca un mesh importat.
function Skins.missingMeshes(): { string }
	local pending = {}
	for _, id in Skins.Order do
		if Skins.List[id].MeshId == "" then
			table.insert(pending, id)
		end
	end
	return pending
end

return Skins
