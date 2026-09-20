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
	--[[
		Fundalul casetei de previzualizare, si in magazin, si in cabina de
		randare.

		Nu e `Color` mai inchis calculat pe loc, ci o culoare aleasa: `portal` are
		corpul aproape negru si ar da o caseta care pare stricata, iar `crystal` e
		deschis si ar innegri previzualizarea. Sta aici, pe skin, si nu in
		`StoreView`, pentru ca e o insusire a obiectului — acelasi fundal trebuie
		sa apara si pe cartonas, si in spatele modelului cand ii facem poza, altfel
		previzualizarea s-ar decupa cu un halou de alta culoare.

		Zidul si soclul aceluiasi skin impart culoarea, ca si restul temei:
		`dragon` inseamna acelasi lucru pe amandoua.
	]]
	CardColor: Color3,
	--[[
		Pozele randate din cabina, pe fel de obiect.

		Sunt randate din **chiar modelele pe care le joci**, clonate din
		`ReplicatedStorage.Assets`, si decupate cu alfa adevarat din perechea
		negru/alb — vezi `assets/previews/crop.js` si `PreviewRig`. De aceea nu
		poarta niciun fundal: se aseaza peste caseta colorata a magazinului, care
		are deja culoarea obiectului, si peste cartonasul de langa vitrina.

		Cine schimba un model reface poza; cat timp un slot e `""`, ecranele
		arata caseta colorata, nu o imagine lipsa.
	]]
	Preview: { Barricade: string, Podium: string },
	--[[
		Aceleasi obiecte, dar fotografiate **in lume**: pe dala din lobby, cu
		copacii si cerul in spate.

		Sunt a doua poza a aceluiasi lucru, nu un inlocuitor. Pe cartonasul mic
		din raft merge decupajul: acolo obiectul are un centimetru, si un peisaj
		in spatele lui s-ar face terci. In panoul mare, unde te uiti la obiect
		inainte sa dai banii, decupajul plutea intr-o caseta goala — poza cu
		fundal ii da scara, umbra si un loc in care sta.
	]]
	Scene: { Barricade: string, Podium: string },
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
		CardColor = Color3.fromHex("5A3A1E"),
		Preview = {
			Barricade = "rbxassetid://72633085418249",
			Podium = "rbxassetid://101087478451641",
		},
		Scene = {
			Barricade = "rbxassetid://117618708283776",
			Podium = "rbxassetid://123799746040654",
		},
		-- butoi de lemn cazut pe pamant
		PlaceSound = 9120796401,
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
		CardColor = Color3.fromHex("46433C"),
		Preview = {
			Barricade = "rbxassetid://107349011148223",
			Podium = "rbxassetid://112520114211419",
		},
		Scene = {
			Barricade = "rbxassetid://117367366028714",
			Podium = "rbxassetid://71034584110857",
		},
		-- piatra lovind piatra
		PlaceSound = 9125869504,
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
		CardColor = Color3.fromHex("2E3D23"),
		Preview = {
			Barricade = "rbxassetid://105924497486876",
			Podium = "rbxassetid://97281085853496",
		},
		Scene = {
			Barricade = "rbxassetid://109057960197448",
			Podium = "rbxassetid://118179467093049",
		},
		-- planta care creste
		PlaceSound = 87388390529602,
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
		CardColor = Color3.fromHex("4B1A17"),
		Preview = {
			Barricade = "rbxassetid://92456445979475",
			Podium = "rbxassetid://134008680484938",
		},
		Scene = {
			Barricade = "rbxassetid://111416099328103",
			Podium = "rbxassetid://86601195493851",
		},
		-- usa de piatra trantita
		PlaceSound = 182306090,
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
		CardColor = Color3.fromHex("1E2A33"),
		Preview = {
			Barricade = "rbxassetid://103942457963377",
			Podium = "rbxassetid://93281891788030",
		},
		Scene = {
			Barricade = "rbxassetid://116808231650470",
			Podium = "rbxassetid://138802712299240",
		},
		-- orb de energie care se inchide
		PlaceSound = 128374335209792,
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
		CardColor = Color3.fromHex("3A3733"),
		Preview = {
			Barricade = "rbxassetid://130992462293056",
			Podium = "rbxassetid://96995245239859",
		},
		Scene = {
			Barricade = "rbxassetid://124438765304862",
			Podium = "rbxassetid://134489616012544",
		},
		-- descarcare electrica
		PlaceSound = 92090867642655,
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
		CardColor = Color3.fromHex("1D3448"),
		Preview = {
			Barricade = "rbxassetid://94351177766917",
			Podium = "rbxassetid://70583023662299",
		},
		Scene = {
			Barricade = "rbxassetid://86866495164225",
			Podium = "rbxassetid://112413871700788",
		},
		-- gheata care se sparge
		PlaceSound = 77180791455569,
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
		CardColor = Color3.fromHex("1A1030"),
		Preview = {
			Barricade = "rbxassetid://110830829863318",
			Podium = "rbxassetid://134964213352356",
		},
		Scene = {
			Barricade = "rbxassetid://73741733916011",
			Podium = "rbxassetid://71124294966239",
		},
		-- portal care se deschide
		PlaceSound = 75393796265224,
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

--[[
	Poza randata a unui obiect, sau "" cat timp nu e urcata.

	Felul intra in cerere pentru ca acelasi skin are doua poze: un zid lung si un
	soclu patrat nu se pot arata cu aceeasi imagine, chiar daca poarta aceeasi
	tema si acelasi fundal.
]]
function Skins.preview(id: string?, kind: string): string
	local previews = Skins.get(id).Preview
	return if kind == "Podium" then previews.Podium else previews.Barricade
end

--[[
	Aceeasi poza, dar cea facuta in lume. Vezi `Scene` de sus pentru cand se
	foloseste una si cand cealalta.
]]
function Skins.scene(id: string?, kind: string): string
	local shots = Skins.get(id).Scene
	return if kind == "Podium" then shots.Podium else shots.Barricade
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
