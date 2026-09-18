--!strict
--[[
	GameConfig — singurul loc unde se regleaza jocul.

	Nimic din ce e aici nu are voie sa fie duplicat in alta parte. Daca un
	numar apare in doua fisiere, locul lui e aici.
]]

local Types = require(script.Parent.Types)

type Objective = Types.Objective

export type SlotConfig = {
	Team: number,
	Start: Types.Cell,
	Objective: Objective,
}

export type ModeConfig = {
	Id: string,
	DisplayName: string,
	Players: number,
	Barricades: number,
	ObjectiveKind: Types.ObjectiveKind,
	-- Ordinea in care se muta sloturile. Pentru 2v2 alterneaza echipele.
	TurnOrder: { number },
	Slots: { SlotConfig },
}

local CENTER_CELL: Types.Cell = { X = 5, Y = 5 }

local function center(): Objective
	return { Kind = "CENTER", Cell = CENTER_CELL }
end

local function side(edge: "Y_MAX" | "Y_MIN" | "X_MAX" | "X_MIN"): Objective
	return { Kind = "OPPOSITE_SIDE", Edge = edge }
end

local GameConfig = {}

GameConfig.BoardSize = 9

--[[
	Modurile de joc. Motorul e unul singur; modul schimba doar numarul de
	jucatori, pozitiile de start, obiectivul si stocul de baricade.
]]
GameConfig.Modes = {
	["1v1"] = {
		Id = "1v1",
		DisplayName = "1v1",
		Players = 2,
		Barricades = 10,
		ObjectiveKind = "OPPOSITE_SIDE" :: Types.ObjectiveKind,
		TurnOrder = { 1, 2 },
		Slots = {
			{ Team = 1, Start = { X = 5, Y = 1 }, Objective = side("Y_MAX") },
			{ Team = 2, Start = { X = 5, Y = 9 }, Objective = side("Y_MIN") },
		},
	},

	["1v1v1"] = {
		Id = "1v1v1",
		DisplayName = "3 Players",
		Players = 3,
		Barricades = 6,
		ObjectiveKind = "CENTER" :: Types.ObjectiveKind,
		TurnOrder = { 1, 2, 3 },
		Slots = {
			{ Team = 1, Start = { X = 5, Y = 1 }, Objective = center() },
			{ Team = 2, Start = { X = 9, Y = 5 }, Objective = center() },
			{ Team = 3, Start = { X = 1, Y = 5 }, Objective = center() },
		},
	},

	["1v1v1v1"] = {
		Id = "1v1v1v1",
		DisplayName = "4 Players",
		Players = 4,
		Barricades = 5,
		ObjectiveKind = "CENTER" :: Types.ObjectiveKind,
		TurnOrder = { 1, 2, 3, 4 },
		Slots = {
			{ Team = 1, Start = { X = 5, Y = 1 }, Objective = center() },
			{ Team = 2, Start = { X = 9, Y = 5 }, Objective = center() },
			{ Team = 3, Start = { X = 5, Y = 9 }, Objective = center() },
			{ Team = 4, Start = { X = 1, Y = 5 }, Objective = center() },
		},
	},

	["2v2"] = {
		Id = "2v2",
		DisplayName = "2v2",
		Players = 4,
		Barricades = 5,
		ObjectiveKind = "OPPOSITE_SIDE" :: Types.ObjectiveKind,
		-- Echipele alterneaza: A, B, A, B.
		TurnOrder = { 1, 3, 2, 4 },
		Slots = {
			{ Team = 1, Start = { X = 5, Y = 1 }, Objective = side("Y_MAX") },
			{ Team = 1, Start = { X = 4, Y = 1 }, Objective = side("Y_MAX") },
			{ Team = 2, Start = { X = 5, Y = 9 }, Objective = side("Y_MIN") },
			{ Team = 2, Start = { X = 6, Y = 9 }, Objective = side("Y_MIN") },
		},
	},
} :: { [string]: ModeConfig }

-- Ordinea in care apar modurile in lobby.
GameConfig.ModeOrder = { "1v1", "1v1v1", "1v1v1v1", "2v2" }

--[[
	Culorile jucatorilor. Nu se comunica nimic *doar* prin culoare — tokenul
	are si avatar si nume — dar culoarea leaga tokenul de cardul din UI.
	Pentru 2v2 coechipierii primesc nuante apropiate din aceeasi familie.

	Valorile sunt cele din Barricade Design System (sectiunea 02) si trebuie sa
	ramana in pas cu asseturile `Theme.Assets.Token`: fiecare culoare are acolo un
	token desenat, iar o nepotrivire s-ar vedea intre pionul de pe tabla si cardul
	din HUD. Design system-ul cere si o forma per culoare — cerc, romb, patrat,
	triunghi — tocmai ca jocul sa ramana lizibil pentru daltonisti.

	Raman numere hex, nu `Color3`: `src/shared/` nu atinge API-ul Roblox.
]]
GameConfig.SlotColors = {
	0x2F7FD1, -- 1 albastru · cerc
	0xD9443F, -- 2 rosu · romb
	0x4BA63C, -- 3 verde · patrat
	0xE8B32B, -- 4 galben · triunghi
}

GameConfig.TeamColors = {
	-- 2v2: slot 1 si 2 sunt echipa albastra, 3 si 4 echipa rosie.
	["2v2"] = { 0x2F7FD1, 0x6BA6E0, 0xD9443F, 0xE8837F },
}

GameConfig.Timing = {
	-- Ceasul fiecarui jucator, in secunde. Se consuma doar in tura proprie.
	PlayerClock = 300,
	-- Numaratoarea inversa dinainte de start, in secunde.
	StartCountdown = 3,
	-- Cat dureaza animatia de mutare a unui token.
	MoveTween = 0.28,
	-- Cat dureaza animatia de asezare a unei baricade.
	WallTween = 0.18,
	-- Cat sta pe ecran mesajul de tura noua.
	TurnBannerHold = 1.1,
	--[[
		Cat ramane masa in lume dupa fluierul final, in secunde.

		Nu zero: castigatorul are dreptul sa vada tabla pe care a castigat. Dar
		nici la nesfarsit — pana acum masa ramanea pana cand *toti* apasau
		"Leave", iar cine inchidea ecranul de victorie fara sa apese ramanea
		intepenit pe o platforma din care nu-l mai scotea nimeni.
	]]
	VictoryHold = 6,
}

--[[
	Camera de deasupra mesei.

	Unghiul si distanta nu sunt gust, sunt lizibilitate: tabla trebuie sa incapa
	intreaga, dar piesele trebuie sa ramana destul de mari cat sa se vada care e
	pion si care e baricada.
]]
GameConfig.Camera = {
	--[[
		Camp vizual ingust, si dinadins.

		Cu cel implicit al Roblox-ului, tabla incapea dar arata ca privita
		printr-un ochean intors: capatul departat fugea, iar piesele de acolo se
		faceau de doua ori mai mici decat cele de aproape. Ingustat, camera se
		retrage mai mult dar imaginea se aplatizeaza — tabla arata ca o tabla, nu
		ca un coridor.
	]]
	FieldOfView = 45,
	-- Inclinarea fata de orizontala. La 90 piesele isi pierd volumul.
	Pitch = 55,
	-- Cat aer ramane in jurul tablei. 1 = incape fix, fara rama.
	Margin = 1.02,
	--[[
		Se intoarce camera dupa cine e la mutare?

		Implicit nu. Privesti mereu dinspre marginea ta, si asta e felul in care
		se joaca un joc de masa: tabla sta, tu stai, se muta doar piesele. Rotita
		la fiecare tura, jumatate din partida o petreci reinvatand unde iti e
		pionul, si mutarea adversarului nu se vede ca mutare, ci ca o rasturnare
		a lumii. Cine vrea totusi, pune `true` si camera trece de partea celui
		aflat la rand.
	]]
	FollowTurn = false,
	-- Inclinarea pentru privirea de sus. Nu 90: la fix vertical se pierde orice
	-- reper de adancime si nu se mai vede pe ce fata sta o baricada.
	TopPitch = 84,
	--[[
		Cat dureaza trecerea dintre cele doua perspective, in secunde.

		Sub o treime de secunda miscarea nu se mai citeste ca miscare, ci tot ca
		o taietura; peste trei sferturi, butonul VIEW incepe sa para lenes.
	]]
	ViewSeconds = 0.55,
}

--[[
	Banutii dati la finalul unui meci.

	`Participation` se da tuturor celor care au jucat, indiferent cum s-a
	terminat; `WinBonus` se adauga doar celor din echipa castigatoare. Vezi
	`Rewards` pentru de ce se plateste si la pierdere.

	Raportul conteaza mai mult decat cifrele: castigul trebuie sa se simta clar
	mai bun, dar pierderea sa nu fie zero. Doi la unu spune amandoua.
]]
GameConfig.Rewards = {
	Participation = 25,
	WinBonus = 50,
}

--[[
	Ajutoare pentru testat, active **numai in Studio**.

	`StudioCoins` umple portofelul pana la suma asta la intrarea in joc, ca sa
	poti incerca magazinul fara sa joci treizeci de meciuri. Banii sunt de
	minciuna, si de aceea cat timp valoarea nu e zero nici portofelul si nici
	inventarul nu mai scriu in DataStore: altfel ai ramane in contul adevarat cu
	bani pe care nu i-ai castigat si cu obiecte pe care nu le-ai cumparat.

	Pune 0 ca sa testezi salvarea adevarata din Studio. Pe un server publicat
	valoarea e ignorata oricum.
]]
GameConfig.Debug = {
	StudioCoins = 5000,
}

GameConfig.Reconnect = {
	-- "FORFEIT" = ceilalti castiga imediat.
	-- "PAUSE"   = meciul asteapta GraceSeconds, apoi forfait.
	Mode = "PAUSE" :: "FORFEIT" | "PAUSE",
	GraceSeconds = 45,
}

--[[
	Free play — meciul care porneste din lume, nu din meniu.

	Urci pe soclul din arena si astepti. Numaratoarea merge indiferent cati sunt:
	cand ajunge la zero si s-au strans destui, meciul pleaca; cand ajunge la zero
	si esti singur, o ia de la capat, fiindca n-ai cu cine juca. Cand soclul se
	umple, numaratoarea nu mai conteaza — n-are rost sa astepti pe altcineva cand
	nu mai e loc pentru el.

	Cati incap nu se scrie aici: se citeste din `Modes[Mode].Players`. Doua
	numere care spun acelasi lucru ajung mai devreme sau mai tarziu sa nu-l mai
	spuna la fel. Cand vor exista si variantele de trei si patru, modul se va
	alege dupa cati asteapta, si tot de acolo va veni si numarul.
]]
GameConfig.FreePlay = {
	Mode = "1v1",
	-- De la cati in sus se poate juca. Sub atat, numaratoarea o ia de la capat.
	Minimum = 2,
	-- Secundele numaratorii, si cat asteapta inainte sa o ia de la capat.
	Countdown = 15,
	-- Cat de des se uita serverul cine sta pe soclu.
	PollInterval = 0.5,
	-- Numele piesei din Workspace care arata unde se aseaza masa meciului.
	ArenaMarker = "FreePlayArena",
}

-- Limitare de rata pe RemoteEvent, per jucator. Vezi Services/RateLimiter.
GameConfig.RateLimits = {
	RequestMove = { Interval = 0.25, Burst = 4 },
	RequestPlaceWall = { Interval = 0.25, Burst = 4 },
	RequestQueue = { Interval = 1.0, Burst = 3 },
	RequestLeave = { Interval = 1.0, Burst = 3 },
	--[[
		Cumpararea e rara si scumpa: fiecare cerere atinge portofelul si
		inventarul. O secunda intre apasari e larg pentru un om si strans pentru
		un client care ar incerca sa prinda aceeasi cumparatura de doua ori.
	]]
	RequestPurchase = { Interval = 1.0, Burst = 2 },
}

--[[
	Sunete. Pune aici id-urile tale de asset; 0 inseamna "fara sunet" si
	SoundController il ignora fara sa arunce eroare.
]]
GameConfig.Sounds = {
	Move = 0,
	WallPlaced = 0,
	WallInvalid = 0,
	TurnChange = 0,
	Victory = 0,
	Countdown = 0,
} :: { [string]: number }

return GameConfig
