--!strict
--[[
	Barricade — punctul de intrare al serverului.

	Aici se leaga toate firele: se creeaza canalele de retea, se asculta
	cererile clientilor si se trimit mai departe catre meciul lor.

	Regula pe care o aplica fisierul asta, fara exceptie: *nimic* din ce vine
	pe un RemoteEvent nu e crezut pe cuvant. Identitatea vine din argumentul
	`player` pe care il pune motorul Roblox, nu din datele trimise; meciul e
	cautat in registru, nu primit; iar continutul e validat de motorul de
	reguli inainte sa schimbe ceva.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Catalog = require(Shared.Catalog)
local Gift = require(Shared.Gift)
local GameConfig = require(Shared.GameConfig)

-- Canalele trebuie sa existe inainte ca vreun client sa le ceara.
Remotes.build()

local MatchManager = require(script.Managers.MatchManager)
local MatchmakingManager = require(script.Managers.MatchmakingManager)
local Rematch = require(script.Managers.Rematch)
local Challenges = require(script.Managers.Challenges)
local Friends = require(script.Services.Friends)

-- Stratul social: cine e prieten cu cine, si provocarile dintre jucatori.
Friends.start()
Challenges.start()
local RateLimiter = require(script.Services.RateLimiter)

--[[
	Personajele se incarca doar in lumea 3D.

	Varianta 2D se petrece in intregime intr-un ScreenGui: nimeni nu are avatar
	pe harta, deci nu exista nici camera de urmarit, nici fizica de replicat,
	nici avatare care sa cada prin tabla. Pe platforma insa, jucatorul *este*
	avatarul, deci fara personaj nu are ce sa se aseze pe celula.

	Semnul dupa care se decide e acelasi pe care il citeste si clientul:
	existenta asseturilor de lume. Asa nu exista doua comutatoare care sa se
	poata contrazice.
]]
local assets = ReplicatedStorage:FindFirstChild("Assets")
local worldMode = assets ~= nil and assets:FindFirstChild("Board") ~= nil

Players.CharacterAutoLoads = worldMode

--[[
	Ce tine de lumea 3D se ridica doar cand exista lume 3D.

	Gardul si soclul de free play presupun amandoua un avatar care se plimba pe
	insula. Pe varianta 2D nu exista niciunul, si atunci un gard n-ar opri pe
	nimeni, iar pe soclu n-ar avea cine sa urce.
]]
if worldMode then
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		local Barrier = require(ReplicatedStorage:WaitForChild("World").Barrier)
		Barrier.build(lobby)
		print("[Barricade] gard ridicat in jurul insulei")
	end

	local FreePlay = require(script.Managers.FreePlay)
	FreePlay.start()
end

--[[
	Banutii nu tin de lumea 3D: se castiga la fel si pe varianta 2D, si se vor
	cheltui la fel. De aceea portofelul porneste in afara comutatorului.
]]
local Wallet = require(script.Services.Wallet)
local Inventory = require(script.Services.Inventory)
local Loadout = require(script.Services.Loadout)
local Social = require(script.Services.Social)

do
	Wallet.start()
	Inventory.start()
	--[[
		Alegerea porneste dupa inventar, pentru ca il intreaba pe el cand cineva
		echipeaza. Ce se incarca din DataStore nu asteapta inventarul — vezi
		`Loadout.restore` din `src/shared/`, care spune de ce.
	]]
	Loadout.start()
	-- Invitatiile au nevoie de portofel: recompensa se da prin el.
	Social.start()
end

--[[
	Grupul de sunete al lumii.

	Se face aici, pe server, ca sa existe unul singur si sa ajunga la toti:
	sunetele zidurilor intra in el, iar fiecare client ii poate da volumul la
	zero cand isi inchide sunetul. Facut pe client, ar fi fost doi cu acelasi
	nume si nu s-ar fi stiut care e al cui.
]]
do
	local SoundService = game:GetService("SoundService")
	if not SoundService:FindFirstChild(GameConfig.WorldSound.Group) then
		local group = Instance.new("SoundGroup")
		group.Name = GameConfig.WorldSound.Group
		group.Volume = 1
		group.Parent = SoundService
	end
end

-- --------------------------------------------------------------- cereri

--[[
	Invelisul comun al oricarei cereri de meci: limitare de rata, apoi
	cautarea meciului in registrul serverului.
]]
local function withMatch(channel: string, handler: (any, any, ...any) -> ())
	return function(player: Player, ...: any)
		if not RateLimiter.consume(player, channel) then
			return
		end

		local match = MatchManager.getForPlayer(player)
		if not match then
			Remotes.get("ActionRejected"):FireClient(player, "NOT_IN_MATCH")
			return
		end

		handler(match, player, ...)
	end
end

Remotes.get("RequestMove").OnServerEvent
	:Connect(withMatch("RequestMove", function(match, player, target)
		match:handleMove(player, target)
	end))

Remotes.get("RequestPlaceWall").OnServerEvent
	:Connect(withMatch("RequestPlaceWall", function(match, player, x, y, orientation)
		match:handleWall(player, x, y, orientation)
	end))

--[[
	Semnul trimis celorlalti de la masa. Trece prin aceeasi poarta ca mutarile —
	esti intr-un meci, si nu apesi mai des decat lasa `RateLimits` — dar de acolo
	incolo `Match` il judeca dupa alte reguli: vezi `handleEmote`.
]]
Remotes.get("RequestEmote").OnServerEvent
	:Connect(withMatch("RequestEmote", function(match, player, emoteId)
		match:handleEmote(player, emoteId)
	end))

--[[
	Darul pentru like.

	Clientul nu trimite nimic: **ce** se da scrie in `Gift`, nu in cerere. Altfel
	ar fi de ajuns sa ceri alt id ca sa primesti alt obiect, si darul ar deveni
	un magazin fara bani.

	Like-ul nu se verifica si nu are cum — vezi `Gift`. Se verifica singurul
	lucru care se poate: ca nu-l are deja, ca sa nu se dea de doua ori.
]]
Remotes.get("RequestGift").OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.consume(player, "RequestGift") then
		return
	end

	if not Gift.canClaim(Inventory.owned(player)) then
		Remotes.get("ActionRejected"):FireClient(player, "GIFT_OWNED")
		return
	end

	Inventory.grant(player, { Gift.key() })
	-- Se si imbraca, ca la o cumparare: nimeni nu ia un skin ca sa-l lase in raft.
	Loadout.equip(player, Gift.Item.Kind, Gift.Item.Id)
end)

Remotes.get("RequestJoinQueue").OnServerEvent:Connect(function(player: Player, modeId: any)
	if not RateLimiter.consume(player, "RequestQueue") then
		return
	end
	MatchmakingManager.join(player, modeId)
end)

Remotes.get("RequestLeaveQueue").OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.consume(player, "RequestQueue") then
		return
	end
	MatchmakingManager.leave(player)
end)

--[[
	Iesirea din meci. Daca meciul inca se joaca, plecarea conteaza exact ca o
	deconectare — altfel ar fi o portita de abandon fara consecinte.
]]
Remotes.get("RequestLeaveMatch").OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.consume(player, "RequestLeave") then
		return
	end

	--[[
		Lobby-ul e raspunsul la cerere, nu o urmare a ei.

		Clientul nu mai sare singur in lobby cand apesi „Leave" — asteapta
		mesajul asta. De aceea pleaca si cand n-ai ce parasi: o cerere fara
		raspuns ar lasa ecranul fara meci si fara meniu.
	]]
	local function sendToLobby()
		Remotes.get("LobbyUpdate"):FireClient(player, { Mode = nil, Needed = 0, Names = {} })
	end

	local match = MatchManager.getForPlayer(player)
	if not match then
		sendToLobby()
		return
	end

	local wasFinished = match.Finished
	if not wasFinished then
		match:handleLeave(player)
	else
		-- Pleaca de pe ecranul de final: revansa deschisa nu mai are loc.
		Rematch.leave(player)
	end

	--[[
		Daca plecarea ta a fost chiar cea care a incheiat meciul, apuci sa vezi
		finalul inainte sa fii scos.

		Pleci pentru ca renunti, nu ca sa ramai cu intrebarea cine a castigat:
		starea finala iti vine personal — `broadcast` nu te mai numara printre
		participanti — iar camera ta face acelasi drum ca a tuturor, pana la
		omul de pe soclu. Dureaza cat tine ceremonia si nicio clipa mai mult:
		peste `VictoryReveal` incepe partea in care ceilalti citesc panoul de
		final, si aia nu mai e a ta.

		Cand meciul era incheiat dinainte — apesi „Leave" de pe ecranul de
		victorie — nu se asteapta nimic: ai vazut deja tot.
	]]
	local ceremony = 0
	if not wasFinished and match.Finished and match.Arena then
		match:sendStateTo(player)
		ceremony = GameConfig.Timing.VictoryReveal
	end

	local function depart()
		if match.Arena then
			match.Arena:release(player)
		end
		MatchManager.forget(player)
		MatchManager.destroyIfEmpty(match)
		sendToLobby()
	end

	if ceremony > 0 then
		task.delay(ceremony, function()
			--[[
				Cine a inchis jocul intre timp nu mai are nevoie nici de masa,
				nici de lobby — dar registrul tot trebuie sa uite de el, altfel
				meciul ramane cu un loc ocupat de nimeni.
			]]
			if player.Parent == nil then
				MatchManager.forget(player)
				MatchManager.destroyIfEmpty(match)
				return
			end
			depart()
		end)
	else
		depart()
	end
end)

--[[
	Revansa la aceeasi masa: cererea deschide votul sau spune da, refuzul il
	inchide pentru toti. Tot ce inseamna ele sta in `Rematch`.
]]
Remotes.get("RequestRematch").OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.consume(player, "RequestRematch") then
		return
	end
	Rematch.request(player)
end)

Remotes.get("RequestRematchDecline").OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.consume(player, "RequestRematch") then
		return
	end
	Rematch.decline(player)
end)

--[[
	Provocarea directa. Ce vine de la client — modul, pe cine, da sau nu, care
	provocare — e doar forma cererii; `Challenges` verifica tot restul.
]]
Remotes.get("RequestChallenge").OnServerEvent
	:Connect(function(player: Player, modeId: any, invitees: any)
		if not RateLimiter.consume(player, "RequestChallenge") then
			return
		end
		Challenges.request(player, modeId, invitees)
	end)

Remotes.get("RequestChallengeAnswer").OnServerEvent
	:Connect(function(player: Player, id: any, accept: any)
		if not RateLimiter.consume(player, "RequestChallengeAnswer") then
			return
		end
		Challenges.answer(player, id, accept)
	end)

Remotes.get("RequestChallengeCancel").OnServerEvent:Connect(function(player: Player, id: any)
	if not RateLimiter.consume(player, "RequestChallengeAnswer") then
		return
	end
	Challenges.cancel(player, id)
end)

--[[
	Cumpararea.

	Clientul trimite felul si id-ul, si nimic altceva. Pretul, ce se detine deja
	si daca obiectul exista se afla toate pe server, din catalog si din
	serviciile lui — un pret venit de la client n-ar insemna nimic, iar un "am
	destui bani" tot de acolo ar insemna si mai putin.

	Ordinea nu e intamplatoare: intai se intreaba catalogul, apoi se iau banii,
	apoi se da obiectul. `Wallet.spend` verifica si scade in aceeasi functie,
	deci intre "are destui" si "s-au luat" nu incape nimic. Daca darea obiectului
	n-ar reusi, banii ar fi deja luati — de aceea `Inventory.grant` nu are cum sa
	esueze: scrie intr-o tabela din memorie, iar salvarea vine dupa.
]]
Remotes.get("RequestPurchase").OnServerEvent
	:Connect(function(player: Player, kind: any, itemId: any)
		if not RateLimiter.consume(player, "RequestPurchase") then
			return
		end

		local item = Catalog.resolve(kind, itemId)
		if not item then
			Remotes.get("ActionRejected"):FireClient(player, "BAD_REQUEST")
			return
		end

		local key = Catalog.keyOf(item)
		local allowed, reason =
			Catalog.canBuyItem(item, Wallet.balance(player), Inventory.owned(player))
		if not allowed then
			Remotes.get("ActionRejected"):FireClient(player, "PURCHASE_" .. (reason or "REFUSED"))
			return
		end

		if not Wallet.spend(player, item.Coins, "store:" .. key) then
			--[[
			Soldul s-a schimbat intre verificare si plata.

			Nu se poate intampla de la doua cereri ale aceluiasi jucator — sunt
			pe acelasi fir — dar se poate de la o salvare care tocmai a intors
			un sold mai mic. Refuzul e corect si ieftin; jucatorul apasa din nou.
		]]
			Remotes.get("ActionRejected"):FireClient(player, "PURCHASE_POOR")
			return
		end

		Inventory.grant(player, { key })

		--[[
			Ce tocmai ai cumparat se si imbraca.

			Nimeni nu da o mie de banuti pe un podium ca sa-l lase in raft. Pana
			acum urma o a doua apasare, pe alt buton, care nu intreba nimic si nu
			putea fi refuzata — adica un pas care nu hotara nimic. Cine vrea
			altceva schimba oricand din magazin, unde scrie negru pe alb ce poarta.

			Echiparea vine dupa `grant`, nu inaintea lui: `Loadout` intreaba
			inventarul daca obiectul e al jucatorului, si inainte de `grant`
			raspunsul ar fi fost „nu".
		]]
		Loadout.equip(player, item.Kind, item.Id)
	end)

--[[
	Echiparea.

	Tot ce vine de la client e felul si id-ul. Daca obiectul e al lui se afla
	din inventar, pe server — acelasi drum ca la cumparare, si din acelasi
	motiv: "il am" spus de client nu inseamna nimic.

	Reusita nu se confirma pe un canal. Serverul scrie atributul, iar clientul
	vede schimbarea odata cu toti ceilalti; ce se trimite inapoi e doar refuzul,
	fiindca el nu se vede nicaieri altundeva.
]]
Remotes.get("RequestEquip").OnServerEvent:Connect(function(player: Player, kind: any, itemId: any)
	if not RateLimiter.consume(player, "RequestEquip") then
		return
	end

	local item = Catalog.resolve(kind, itemId)
	if not item then
		Remotes.get("ActionRejected"):FireClient(player, "BAD_REQUEST")
		return
	end

	local equipped, reason = Loadout.equip(player, item.Kind, item.Id)
	if not equipped then
		Remotes.get("ActionRejected"):FireClient(player, "EQUIP_" .. (reason or "REFUSED"))
	end
end)

-- ------------------------------------------------------- intrari si iesiri

--[[
	Viteza de umblat prin lobby, pusa la fiecare aparitie a personajului.

	La fiecare, nu o data: personajul e facut din nou la fiecare respawn, si
	vine de fiecare data cu valorile din `StarterPlayer` — adica cele implicite
	ale Roblox-ului. Scrise o singura data, s-ar fi pierdut la prima cadere in
	apa.

	Cine e pe o masa nu primeste nimic: acolo `Arena` taie mersul dinadins, iar
	o viteza data peste ea l-ar dezlega pe jucator de celula pe care sta.
]]
local function applyLobbyPace(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player and player:GetAttribute("ArenaId") ~= nil then
		return
	end
	humanoid.WalkSpeed = GameConfig.Lobby.WalkSpeed
	humanoid.JumpPower = GameConfig.Lobby.JumpPower
	humanoid.JumpHeight = GameConfig.Lobby.JumpHeight
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(applyLobbyPace)
	if player.Character then
		applyLobbyPace(player.Character)
	end

	-- Poate s-a intors intr-un meci pus pe pauza pentru el.
	for _, match in MatchManager.getAll() do
		if match:tryReconnect(player) then
			return
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	MatchmakingManager.leave(player)

	local match = MatchManager.getForPlayer(player)
	if match then
		Rematch.leave(player)
		match:handleDisconnect(player)
		MatchManager.forget(player)
		MatchManager.destroyIfEmpty(match)
	end
end)

print("[Barricade] server pornit")
