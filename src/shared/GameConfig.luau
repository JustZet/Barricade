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

	Abatere de la design system: slotul 3 era verde, dar verdele e deja culoarea
	celulelor pe care te poti muta, iar un pion verde pe o tabla care se aprinde
	verde spune doua lucruri deodata. A trecut pe roz. Asseturile `green` din
	`Theme.Assets.Token` nu sunt folosite de cod; daca vor fi, trebuie redesenate.

	Raman numere hex, nu `Color3`: `src/shared/` nu atinge API-ul Roblox.
]]
GameConfig.SlotColors = {
	0x2F7FD1, -- 1 albastru · cerc
	0xD9443F, -- 2 rosu · romb
	0xE0529C, -- 3 roz · patrat
	0xE8B32B, -- 4 galben · triunghi
}

--[[
	Culoarea celulelor pe care se termina meciul, aceeasi in toate modurile: in
	1v1 si 2v2 e randul de pe partea cealalta, in 1v1v1 si 1v1v1v1 celula din
	centru. O singura culoare inseamna o singura regula de invatat — „mergi la
	turcoaz" — oricati ar fi la masa.

	Turcoaz sters, spre verde-marin: verdele mutarilor legale (`7FD06A`) bate spre
	galben, deci cele doua se despart prin nuanta chiar si amestecate cu lemnul.
	Violetul de dinainte se pierdea pe tabla, iar galbenul dinaintea lui era
	chiar culoarea slotului 4.
]]
GameConfig.GoalColor = 0x6ED8B6

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

		Nu zero: castigatorul are dreptul sa vada tabla pe care a castigat, si
		soclul care iese din ea sub el. Dar nici la nesfarsit — pana acum masa
		ramanea pana cand *toti* apasau "Leave", iar cine inchidea ecranul de
		victorie fara sa apese ramanea intepenit pe o platforma din care nu-l mai
		scotea nimeni.

		Trebuie sa acopere toata ceremonia plus rasfoirea panoului de la final:
		`VictoryReveal + VictoryAutoLeave`. Mai scurt, masa s-ar darama sub un
		jucator care inca se uita la ea. Cat tine masa tin si artificiile.

		Si inca un vot de revansa intreg: el se poate deschide in ultima secunda
		a panoului, iar numaratoarea panoului sta pe loc cat se voteaza. Masa
		trebuie sa fie in picioare pana la capatul votului, apoi cat se vede vestea
		ca s-a anulat si cat mai sta panoul dupa ea: 7 + 8 + 10 + 2.2 + 3 = 30.2,
		cu rezerva pana la 32. Un test tine socoteala.
	]]
	VictoryHold = 32,
	--[[
		Cat dureaza urcarea soclului de sub castigator, in secunde.

		E inceputul ceremoniei, nu toata: soclul iese repede din celula si apoi
		ramane acolo, cu omul pe el, cat spune `VictoryReveal`. Mai scurta ar
		parea o teleportare, mai lunga ar tine imaginea in loc chiar in clipa in
		care jucatorul vrea sa vada ce a castigat.
	]]
	PodiumRise = 1.2,
	--[[
		Cat asteapta ecranul de victorie dupa fluierul final, in lumea 3D.

		E timpul in care se vede doar ce s-a intamplat: camera ajunge in fata
		castigatorului in `Camera.WinnerSeconds`, soclul iese din celula in
		`PodiumRise`, si raman vreo cinci secunde bune in care el sta pe podium,
		cu artificii deasupra, si nimic nu-i acopera fata. Panoul vine dupa.

		Numarul asta e singurul de reglat daca sarbatoarea pare scurta sau lunga
		— dar creste-l impreuna cu `VictoryHold`, altfel masa se darama sub el.
		Pe tabla 2D nu exista nici camera, nici soclu, si panoul apare imediat.
	]]
	VictoryReveal = 7,
	--[[
		Dupa cate secunde pleaca singur ecranul de victorie in lobby.

		Ecranul de final nu e o intrebare care asteapta raspuns: meciul s-a
		terminat oricum. Cine vrea revansa o cere in secundele alea; cine s-a
		ridicat de la calculator nu trebuie sa gaseasca la intoarcere aceeasi
		fereastra peste o tabla moarta.

		Sta langa `VictoryHold` fiindca cele doua se conditioneaza: masa trebuie
		sa tina pana pleaca panoul, adica `VictoryReveal + VictoryAutoLeave`
		trebuie sa incapa in `VictoryHold`. Altfel jucatorul e trimis in lobby cu
		ecranul de victorie inca deschis peste el.
	]]
	VictoryAutoLeave = 8,
	--[[
		Cat asteapta votul de revansa, in secunde, de la prima cerere. Bara din
		banner se goleste in timpul asta. Creste-l impreuna cu `VictoryHold`.
	]]
	RematchWindow = 10,
	-- Cat sta pe ecran vestea ca revansa s-a anulat, inainte de intrebarea despre coada.
	RematchNotice = 2.2,
	-- Cat mai sta panoul de final dupa un vot anulat, pentru cine n-a acceptat.
	RematchResume = 3,
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

	--[[
		Cadrul castigatorului, la finalul meciului.

		Camera pleaca de deasupra mesei si coboara in fata celui care a castigat,
		cat urca soclul sub el. Distanta si inaltimea sunt alese ca sa se vada
		omul, nu tabla: de la paisprezece studi si cinci inaltime intra in cadru
		avatarul intreg si soclul de sub el, fara ca linia orizontului sa fie
		chiar in spatele capului.

		Drumul dureaza ceva mai mult decat o schimbare de perspectiva. Nu e o
		reasezare a aceleiasi imagini, ci o plecare din ea, si are voie sa se
		simta ca atare — dar tot trebuie sa se termine inainte ca jucatorul sa
		caute butonul de revansa.
	]]
	WinnerDistance = 14,
	--[[
		Inaltimea camerei de final, si de ce tocmai atat.

		Masurat in meci: un zid urca 7,2 studi peste fata tablei, iar trunchiul
		jucatorului sta la 2,2. Camera priveste trunchiul de la distanta
		`WinnerDistance`, deci linia dintre ele urca uniform de la om spre camera.
		La cinci studi inaltime, linia aia ramane sub varful zidurilor pe toata
		lungimea ei — adica orice zid de pe drum taie cadrul, si asta se si vedea:
		un turn de piatra peste tot ecranul.

		La zece, ochiul sta la 12,2 peste tabla, bine peste ziduri, iar linia
		trece pe deasupra oricarui zid aflat mai departe de vreo patru studi de
		castigator. Mai sus de-atat, cadrul devine o vedere de sus si se pierde
		omul din el.
	]]
	WinnerHeight = 10,
	WinnerSeconds = 1.6,
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
	Cum se umbla prin lobby.

	Lobby-ul e o insula de vreo suta douazeci de studi, cu vitrinele intr-un
	capat si arena in celalalt, iar la viteza implicita a Roblox-ului drumul
	dintre ele se simte lung — nu greu, doar lung, ceea ce e mai rau: pana
	ajungi la soclu ai avut timp sa te razgandesti. Douazeci si doi e viteza
	implicita crescuta cu o treime: se simte ca mers grabit, nu ca alergare, si
	nu trece de pragul de la care pasii nu mai tin ritmul cu deplasarea si
	personajul pare ca patineaza.

	Valorile stau aici, nu in `StarterPlayer` din place, tocmai ca sa existe un
	singur loc in care se schimba. Place-ul isi pastreaza valorile lui
	implicite; serverul le suprascrie la fiecare aparitie a personajului,
	inainte ca jucatorul sa apuce sa faca un pas.

	Saritura ramane cea implicita. Aici nu se sare peste nimic, si o saritura
	mai inalta ar cere si un lobby gandit pentru ea.
]]
GameConfig.Lobby = {
	WalkSpeed = 22,
	JumpPower = 50,
	JumpHeight = 7.2,
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

	Modul se alege dupa cati s-au strans cand pleaca meciul: doi joaca 1v1, trei
	1v1v1, patru 1v1v1v1. Nici minimul, nici cati incap nu se scriu aici — se
	citesc din `Modes[...].Players`. Doua numere care spun acelasi lucru ajung
	mai devreme sau mai tarziu sa nu-l mai spuna la fel.
]]
GameConfig.FreePlay = {
	Modes = { "1v1", "1v1v1", "1v1v1v1" },
	-- Secundele numaratorii, si cat asteapta inainte sa o ia de la capat.
	Countdown = 15,
	-- Cat de des se uita serverul cine sta pe soclu.
	PollInterval = 0.5,
	-- Numele piesei din Workspace care arata unde se aseaza masa meciului.
	ArenaMarker = "FreePlayArena",
}

--[[
	Callout-urile de dupa fiecare mutare: pragurile dupa care se aleg, in
	`MoveCommentary`, si ritmul lor pe ecran, in `CalloutView`.

	Pragurile sunt in pasi de drum — cu cat a crescut drumul cel mai scurt al
	cuiva pana la tinta. Un pas in plus se intampla la aproape orice baricada si
	nu merita strigat; de aceea blocajul incepe de la doi.
]]
GameConfig.Callouts = {
	-- De la cati pasi in plus pentru un adversar e BLOCK, BLOCK_BIG, BLOCK_HUGE, BLOCK_MEGA.
	BlockMin = 2,
	BlockBigMin = 3,
	BlockHugeMin = 4,
	BlockMegaMin = 6,
	-- Cati pasi in plus trebuie sa ia fiecare dintre adversari ca sa fie DOUBLE_BLOCK.
	DoubleBlockMin = 2,
	-- Cat de in urma trebuie sa fi fost cineva ca revenirea sa fie COMEBACK.
	ComebackDeficit = 3,
	-- NECK_AND_NECK: toti cel mult la atatia pasi, si diferenta cel mult atat.
	NeckMaxDistance = 3,
	NeckMaxSpread = 1,
	-- Cate callout-uri se arata dupa o singura actiune; restul se taie.
	MaxPerAction = 2,

	-- Cat sta pe ecran, pe marimi (1 mic, 2 mediu, 3 epic), in secunde.
	Lifetime = { 1.2, 1.6, 2.2 },
	-- Marimea textului pe marimi, in pixeli, la un ecran inalt de 900.
	TextSize = { 34, 44, 56 },
	-- Cat urca textul pana dispare, in pixeli.
	Float = 40,
	-- Cat asteapta al doilea callout al aceleiasi actiuni dupa primul.
	Stagger = 0.35,
	-- Intarzierea dintre litere la intrarea pe marimea 3.
	LetterStagger = 0.03,
	-- Cat dureaza fiecare cifra din numaratoarea lui „+4".
	CountStep = 0.09,
	-- Cat de sus peste celula, in studi, sta textul in lumea 3D: peste avatar.
	WorldLift = 6,
	-- Tremurul camerei pe marimea 3, in studi si secunde.
	ShakeAmount = 0.35,
	ShakeSeconds = 0.3,
}

--[[
	Rama care se aprinde pe marginea tablei 3D la callout-uri; vezi `BoardRim`.

	Pozitia se da in pasi de celula, nu in studi, ca sa urmeze tabla daca se
	scaleaza vreodata: la tabla de acum un pas e 7.2 studi, zona de joc se
	termina la 4.53 pasi de centru, iar rama la 5.46; mijlocul ei e la 5.
]]
--[[
	Masa meciului 3D.

	`PlateUnderPawn` pune sub fiecare pion plinta podiumului ales (vezi
	`Arena.placePlate`). Oprita deocamdata: codul ramane, gata de repornit
	cu `true`, iar la victorie podiumul urca la fel ca inainte.
]]
GameConfig.Arena = {
	PlateUnderPawn = false,
}

GameConfig.Rim = {
	-- Cat de departe de centru sta bara, in pasi de celula: pe mijlocul ramei, unde erau liniutele.
	Offset = 5.0,
	-- Cat de jos fata de fata celulelor e suprafata ramei, in pasi de celula.
	Drop = -0.151,
	-- Grosimea barei rotunde (diametrul pastilelor), si cat se ridica placa nevazuta a particulelor, in studi.
	Width = 0.55,
	Thickness = 0.3,
	-- Cum arata bara cand nu se intampla nimic: un sant inchis, abia vazut.
	RestColor = 0x3B2412,
	RestTransparency = 0.35,
	-- Cat tine fiecare efect, in secunde.
	Seconds = { Small = 1.1, Big = 1.9, Mega = 3.2, Combo = 3.0, Frost = 2.4, Victory = 6.0 },
	Palettes = {
		-- Margele aurii, cu coada mandarina.
		Small = { 0xFFE066, 0xFFB627, 0xFF7A1A },
		-- Valul: roz aprins, portocaliu, galben.
		Big = { 0xFF3CAC, 0xFF8C42, 0xFFE45E },
		Rainbow = { 0xFF006E, 0xFB5607, 0xFFBE0B, 0x3AFF8A, 0x3A86FF, 0x8338EC },
		-- Flacarile seriei: magenta, cyan, lime, violet.
		Combo = { 0xFF3CAC, 0x3DE8FF, 0xA8FF3D, 0x9B5DE5 },
		-- Ce ingheata pe partea celui blocat.
		Frost = { 0x9AD1FF, 0xC8B6FF, 0xEAF6FF },
	},
}

--[[
	Stratul social: provocari, invitatii, bonusuri. Vezi `Challenge`,
	`Referral`, `Rewards` si serviciile de pe server.
]]
GameConfig.Social = {
	-- Cat asteapta o provocare raspunsul, in secunde.
	ChallengeWindow = 15,
	-- Dupa un refuz, cat nu-l mai poti provoca pe acelasi om, in secunde.
	ChallengeCooldown = 30,
	-- Cat de des se uita serverul unde e fiecare (meci, coada) si ce provocari au expirat.
	PresenceInterval = 0.5,
	--[[
		Banutii pentru o invitatie reusita: cel venit (daca e nou) si cel care l-a
		invitat primesc fiecare atat. Vezi `Referral`.
	]]
	ReferralReward = 100,
	-- Cate recompense de invitatie poate lua acelasi om intr-o zi (UTC).
	ReferralDailyCap = 5,
	--[[
		Bonusurile sociale la banutii de meci, ca parte din baza (castig sau
		participare). Se aduna, dar impreuna nu trec de `SocialBonusCap`.
		`GroupId = 0` opreste bonusul de grup si indemnul din lobby.
	]]
	GroupId = 0,
	GroupBonus = 0.10,
	FriendBonus = 0.10,
	SocialBonusCap = 0.20,
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
	--[[
		Echiparea e ieftina — se scrie un atribut — dar tot atinge inventarul si
		ajunge la toti jucatorii din server. Patru pe doua secunde acopera pe
		cineva care isi incearca skinurile pe rand, si taie bucla.
	]]
	RequestEquip = { Interval = 0.5, Burst = 4 },
	-- Votul de revansa: cerere, acceptare, refuz. Rar, dar trebuie sa raspunda pe loc.
	RequestRematch = { Interval = 0.5, Burst = 3 },
	--[[
		O provocare noua ajunge pe ecranul altcuiva, deci e singura care se poate
		face hartuiala. Doua secunde intre ele, plus cooldown-ul de dupa refuz.
	]]
	RequestChallenge = { Interval = 2, Burst = 2 },
	-- Raspunsul la o provocare, sau renuntarea la ea.
	RequestChallengeAnswer = { Interval = 0.5, Burst = 3 },
	--[[
		Darul se cere o data in viata, dar butonul se poate apasa de zece ori
		pana raspunde serverul. O secunda intre cereri ajunge.
	]]
	RequestGift = { Interval = 1, Burst = 3 },
	--[[
		Emote-urile sunt singura cerere facuta ca sa fie *auzita* de altcineva,
		si de aceea singura care se poate transforma in bataie de joc. O secunda
		si jumatate intre ele lasa loc unei reactii adevarate — rade, apoi se
		miră — dar taie sirul de zece la rand cu care se acopera adversarul.

		Rafala e doua, nu una: doua semne trimise repede unul dupa altul chiar
		spun ceva impreuna, si n-are rost sa fie oprit al doilea.
	]]
	RequestEmote = { Interval = 1.5, Burst = 2 },
}

--[[
	Sunete. Pune aici id-urile tale de asset; 0 inseamna "fara sunet" si
	SoundController il ignora fara sa arunce eroare.
]]
--[[
	Mutarea si zidul suna diferit dupa **cine** le-a facut.

	Intr-un joc pe ture, cel mai des pui o intrebare din doua: a mutat? si eu
	sau el? La un singur sunet pentru amandoi, a doua intrebare cere sa te uiti
	pe ecran — iar daca tocmai te uitai in alta parte, n-ai de unde sti daca
	zgomotul ala a fost al tau, cu o clipa in urma, sau al lui, acum.

	Doua sunete o raspund fara sa se uite nimeni nicaieri. Ale tale sunt
	confirmarea a ceea ce tocmai ai apasat; ale lui sunt vestea ca s-a intamplat
	ceva cat timp asteptai.

	„Adversarul" inseamna aici oricine altcineva de la masa. In 2v2, mutarea
	coechipierului suna tot ca a adversarului — nu e ideal, dar diferenta care
	conteaza cand astepti e intre „a mutat cineva" si „am mutat eu".
]]
GameConfig.Sounds = {
	MoveSelf = 9117488478,
	MoveOther = 9119981671,
	WallSelf = 9120917438,
	WallOther = 9120917813,
	-- „bass.wav": bufnitura surda de la Roblox, pentru mutarea refuzata.
	WallInvalid = 12221944,
	TurnChange = 0,
	-- „victory.wav", sunetul vechi de la Roblox.
	Victory = 12222253,
	Countdown = 0,
	--[[
		Callout-urile de dupa mutare; vezi `Callouts`. Trei trepte de combo pe
		cele trei marimi, iar „perfect" doar pentru cele doua momente rare:
		BRICKED IN si COMEBACK.
	]]
	CalloutSmall = 121389566348526, -- „combo 1"
	CalloutBig = 90404118421297, -- „combo 2"
	CalloutEpic = 133069312286739, -- „combo 3"
	CalloutPerfect = 115129368164581, -- „perfect combo"
	-- Cand blocajul te loveste pe tine. „Fuhhhh".
	CalloutBlocked = 84452117506909,
	-- Cand vestea e a adversarului: ti-a sarit peste pion, e la un pas, a revenit.
	CalloutOhNo = 125512319549502,
	-- Tick-ul numaratorii din „+4", la fiecare cifra. Inca tacut.
	CalloutCount = 0,
	-- Stratul social; toate tacute deocamdata.
	RematchAsk = 0, -- bannerul „{name} wants a rematch!"
	RematchAccept = 0, -- pop-ul unui avatar care a acceptat
	RematchCancel = 0, -- revansa s-a anulat
	SocialToast = 0, -- o notificare sociala: provocare, prieten intrat, recompensa
} :: { [string]: number }

--[[
	Cat de des poate un sunet sa o ia de la capat, in secunde.

	Refuzul e singurul care se cere in rafala: apesi de cinci ori la rand pe un
	rost in care zidul nu intra, si serverul raspunde de cinci ori. Un sunet
	repornit la fiecare apasare se aude ca o bataie in usa, nu ca un raspuns —
	si fiindca e acelasi obiect `Sound`, nici macar nu apuca sa se termine o
	data. O jumatate de secunda e cat tine partea folositoare din el.

	Ce nu apare aici nu are pauza: mutarea, tura si victoria vin oricum rar.
]]
GameConfig.SoundCooldown = {
	WallInvalid = 0.45,
} :: { [string]: number }

--[[
	Cat de tare suna fiecare, intre 0 si 1. Ce nu apare aici merge cu 0.45.

	Mutarea si refuzul sunt raspunsuri la ce tocmai ai apasat, si trebuie auzite
	ca atare; restul sunt intamplari ale meciului si pot sta mai in spate.
]]
--[[
	Cat se sare de la inceputul fiecarui sunet, in secunde, dupa id-ul lui.

	Multe fisiere incep cu o zecime-doua de liniste sau de scartait inainte de
	lovitura. Sunetul porneste la timp, dar se **aude** tarziu, si la un zid care
	cade in 0,18 secunde asta se simte ca o intarziere.

	Cat de mult se sare se afla ascultand, nu socotind: pornesti sunetul cu
	cateva valori la rand si te opresti la prima care incepe direct cu lovitura.
	Peste ea, se taie din atac si sunetul devine subtire.

	Valorile de aici sunt **masurate**, nu ghicite: fiecare fisier a fost trecut
	printr-un `AudioAnalyzer` si s-a citit de unde incepe semnalul. Din zece
	sunete, trei aveau liniste in fata; celelalte sapte pornesc din primul cadru
	si nu apar aici.
]]
GameConfig.SoundStart = {
	-- lemn: liniste pana la 200 ms, lovitura la 233
	[9120796401] = 0.19,
	-- fulger: liniste pana la 420 ms, descarcarea la 450
	[92090867642655] = 0.41,
	--[[
		copac: incepe pe la 165 ms, dar nu are lovitura — creste incet, si abia
		pe la 800 de milisecunde ajunge unde e mai tare. Sarim pana unde incepe,
		atat cat sa nu porneasca din nimic; restul tine de fisier, nu de cod.
	]]
	[87388390529602] = 0.15,
	--[[
		Ultimele doua au sub cinci milisecunde de liniste in fata — sub o
		miime de secunda masurabila cu rigla noastra, care citeste o data pe
		cadru. Cu ele sarite, sunetul e prezent din **primul** cadru in loc de al
		doilea, si nu se pierde nimic: la cinci milisecunde amandoua sunt deja la
		varful lor. Mai mult de-atat n-are rost, fiindca dincolo de un cadru
		nimeni n-are cum sa auda diferenta.
	]]
	-- piatra
	[9125869504] = 0.005,
	-- refuzul
	[12221944] = 0.005,
} :: { [number]: number }

GameConfig.SoundVolume = {
	-- Ce ai facut tu se aude ca raspuns: tare si sec.
	MoveSelf = 0.85,
	WallSelf = 0.85,
	--[[
		Ce a facut celalalt se aude ca veste, nu ca raspuns, deci sta cu un pas
		in spate. Diferenta de volum lucreaza si ea impotriva confuziei: chiar
		daca cineva n-ar deosebi cele doua sunete, deosebeste care e al lui.
	]]
	MoveOther = 0.6,
	WallOther = 0.6,
	WallInvalid = 0.75,
} :: { [string]: number }

--[[
	Muzica de fundal, in bucla, de la intrarea in joc pana la iesire.

	Sta mult sub sunetele meciului: e decor, nu informatie. O mutare sau un zid
	trebuie sa se auda peste ea, nu sa se amestece in ea. Butonul de sunet o
	opreste odata cu restul. `Id = 0` o stinge de tot.
]]
GameConfig.Music = {
	Id = 1848354536,
	Volume = 0.2,
}

--[[
	Sunetele care ies din lume, nu din interfata: zidul cand se aseaza, zidul
	cand e respins.

	Un sunet legat de o piesa e un sunet 3D, iar ascultatorul e camera. Camera
	insa sta sus, deasupra tablei, la vreo saizeci-optzeci de studi — si cu raza
	implicita de zece studi a motorului, zidul pus in capatul celalalt se auzea
	de sase-sapte ori mai incet decat ar fi trebuit. Nu era prea incet sunetul,
	era prea departe ascultatorul.

	`FullRange` e raza in care se aude intreg: o intindem cat tot cadrul, deci
	oriunde pe tabla zidul suna la fel de tare. Abia dincolo de ea scade, si
	asta ramane bun pentru vitrinele din lobby, care chiar sunt departe.

	Numarul nu e ghicit: masurat in meci, camera sta intre 84 si 119 studi de
	celulele tablei, deci 130 acopera si coltul cel mai departat. Cu raza
	implicita, acelasi zid se auzea la 13% din volumul lui.
]]
GameConfig.WorldSound = {
	Volume = 0.9,
	FullRange = 130,
	FadeRange = 400,
	--[[
		Grupul prin care trec toate sunetele lumii.

		Sunetul zidului e facut de server, pe obiectul lui, si de acolo se aude
		la toata lumea. Butonul de sunet e insa al fiecarui jucator in parte si
		n-are cum sa opreasca ceva ce nu a pornit el — dar poate da la zero
		volumul grupului, la el pe client, fara sa atinga pe nimeni altcineva.
	]]
	Group = "BarricadeWorld",

	--[[
		Se aud sunetele pe care si le poarta skinurile?

		Fiecare skin are in `Skins` sunetul lui de asezare — lemn, piatra, fulger
		— si se auzea de pe zidul insusi, deci de la locul lui de pe masa. E o
		idee buna si ramane in date: `Skins.PlaceSound` nu se sterge, iar
		`Barricade.playSound` e neatins.

		Cat timp e `false`, nu se aude. Zidul are acum doua sunete care spun ceva
		mai important decat din ce e facut — al tau si al lui, vezi
		`GameConfig.Sounds` — iar peste ele sunetul skinului nu adauga o
		informatie, ci un al doilea zgomot in aceeasi clipa. Pus pe `true`, se
		aud amandoua.
	]]
	SkinSounds = false,
}

return GameConfig
