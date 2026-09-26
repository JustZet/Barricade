--!strict
--[[
	Social — ce trebuie tinut minte despre invitatii, intre sesiuni si intre servere.

	Doua feluri de inregistrari, dupa tiparul lui `Wallet` si `Inventory`:

	  profil  (social_<id>)    — l-am mai vazut? prin cine a venit?
	  registru (referral_<id>) — cate recompense de invitatie a luat azi, si ce
	                             asteapta sa primeasca la urmatoarea intrare

	Registrul celui care a invitat se scrie de pe serverul celui venit, cu
	`UpdateAsync`, deci doua servere care il ating deodata nu-si sterg una
	alteia munca. Daca el nu e in acelasi server, recompensa lui asteapta acolo
	si o primeste cand intra, cu aceeasi notificare.

	Regula — cine primeste si cat — e in `Referral`. Banii se dau numai prin
	`Wallet.award`.

	Mod de test, ca la `Wallet`: in Studio cu banuti de test, sau fara acces la
	DataStore, totul traieste doar cat sesiunea, intr-o memorie a serverului.
	Se spune o data, si nu se insista.

	`GetJoinData` nu intoarce nimic in Studio. Sta intr-o functie mica, iar
	`Social.simulateJoin` lasa aceeasi cale sa fie incercata din Studio, cu date
	de intrare date de mana.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Referral = require(Shared.Referral)
local Remotes = require(Shared.Remotes)

local Wallet = require(script.Parent.Wallet)

local Social = {}

local STORE_NAME = "Social_v1"
local ATTEMPTS = 3
local RETRY_SECONDS = 6

local SETTINGS = GameConfig.Social

type Profile = {
	Seen: boolean,
	ReferredBy: number?,
}

type Pending = { UserId: number, Name: string, Coins: number }

type Ledger = {
	Day: number,
	Count: number,
	Pending: { Pending },
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = if ok then result else nil
end

-- Memoria de sesiune: folosita in mod de test sau cand DataStore-ul nu raspunde.
local memory: { [string]: any } = {}
local complained = false

local function giveUp(action: string, reason: any)
	if complained then
		return
	end
	complained = true
	warn(
		string.format(
			"Social: %s a esuat; invitatiile se tin minte doar pe sesiunea asta.\n  Motiv: %s",
			action,
			tostring(reason)
		)
	)
end

-- Ca la `Wallet`: banuti de test in Studio inseamna ca nu se scrie nimic adevarat.
local function testing(): boolean
	return RunService:IsStudio() and GameConfig.Debug.StudioCoins > 0
end

local function retry<T>(action: string, work: () -> T): (boolean, T?)
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(work)
		if ok then
			return true, result
		end
		if attempt == ATTEMPTS then
			giveUp(action, result)
			return false, nil
		end
		task.wait(RETRY_SECONDS)
	end
	return false, nil
end

--[[
	Citeste si scrie o cheie. In DataStore cand se poate, in memorie altfel —
	aceeasi functie de transformare in amandoua, deci regula nu stie unde
	ajunge.
]]
local function update(key: string, transform: (any) -> any): any
	local kept = store
	if kept and not testing() then
		local ok, result = retry("scrierea lui " .. key, function()
			return kept:UpdateAsync(key, transform)
		end)
		if ok then
			return result
		end
	end
	local value = transform(memory[key])
	memory[key] = value
	return value
end

local function read(key: string): any
	local kept = store
	if kept and not testing() then
		local ok, result = retry("citirea lui " .. key, function()
			return kept:GetAsync(key)
		end)
		if ok then
			return result
		end
	end
	return memory[key]
end

local function profileKey(userId: number): string
	return string.format("social_%d", userId)
end

local function ledgerKey(userId: number): string
	return string.format("referral_%d", userId)
end

local function asLedger(stored: any): Ledger
	if type(stored) ~= "table" then
		return { Day = 0, Count = 0, Pending = {} }
	end
	return {
		Day = if type(stored.Day) == "number" then stored.Day else 0,
		Count = if type(stored.Count) == "number" then stored.Count else 0,
		Pending = if type(stored.Pending) == "table" then stored.Pending else {},
	}
end

--[[
	Datele de intrare ale jucatorului. Singurul loc care le cere Roblox-ului; in
	Studio vin goale, deci acolo invitatia nu se poate verifica decat prin
	`simulateJoin`.
]]
local function getJoinData(player: Player): any
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)
	return if ok then data else nil
end

local function nameOf(userId: number): string
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return online.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return if ok and type(name) == "string" then name else "a friend"
end

local function notify(player: Player, role: string, name: string, coins: number)
	if player.Parent then
		Remotes.get("SocialEvent")
			:FireClient(player, { Type = "Referral", Role = role, Name = name, Coins = coins })
	end
end

--[[
	E prima intrare a jucatorului? Nou inseamna: n-are profil social si nici
	sold salvat. Portofelul e mai vechi decat serviciul asta, deci fara el
	oricine a jucat inainte de lansarea lui ar parea nou o data.
]]
local function isNew(userId: number, profile: any): boolean
	if type(profile) == "table" and profile.Seen then
		return false
	end
	local history = Wallet.hasHistory(userId)
	return history == false or (history == nil and profile == nil and testing())
end

--[[
	Recompensele care il asteptau pe jucator: invitatii reusite cat nu era in
	server. Se iau si se sterg in aceeasi scriere, ca sa nu se dea de doua ori.
]]
local function collect(player: Player)
	local taken: { Pending } = {}
	update(ledgerKey(player.UserId), function(stored: any): any
		local ledger = asLedger(stored)
		taken = ledger.Pending
		ledger.Pending = {}
		return ledger
	end)

	for _, entry in taken do
		if type(entry) == "table" and type(entry.Coins) == "number" and entry.Coins > 0 then
			Wallet.award(player, entry.Coins, "referral:inviter")
			notify(player, "Inviter", tostring(entry.Name), entry.Coins)
		end
	end
end

--[[
	Intrarea unui jucator. `joinData` lipseste pe drumul obisnuit — se citeste
	de la Roblox — si se da de mana numai din `simulateJoin`.
]]
function Social.arrive(player: Player, joinData: any?)
	local userId = player.UserId
	local profile = read(profileKey(userId))
	local fresh = isNew(userId, profile)
	local inviter = Referral.inviterFrom(if joinData ~= nil then joinData else getJoinData(player))

	if inviter and fresh then
		local verdict: Referral.Verdict = { InviteeCoins = 0, InviterCoins = 0 }
		local inviterHere = Players:GetPlayerByUserId(inviter)
		local today = Referral.day(os.time())

		--[[
			Decizia se ia in aceeasi scriere care mareste numaratoarea de azi a
			celui care a invitat: doua intrari deodata, pe doua servere, nu pot
			trece amandoua de acelasi loc liber sub plafon.
		]]
		update(ledgerKey(inviter), function(stored: any): any
			local ledger = asLedger(stored)
			if ledger.Day ~= today then
				ledger.Day = today
				ledger.Count = 0
			end
			verdict = Referral.decide({
				Invitee = userId,
				Inviter = inviter,
				InviteeIsNew = true,
				AlreadyPaid = type(profile) == "table" and profile.ReferredBy ~= nil,
				InviterToday = ledger.Count,
				Cap = SETTINGS.ReferralDailyCap,
				Reward = SETTINGS.ReferralReward,
			})
			if verdict.InviterCoins > 0 then
				ledger.Count += 1
				if not inviterHere then
					table.insert(
						ledger.Pending,
						{ UserId = userId, Name = player.DisplayName, Coins = verdict.InviterCoins }
					)
				end
			end
			return ledger
		end)

		if verdict.InviteeCoins > 0 then
			Wallet.award(player, verdict.InviteeCoins, "referral:invitee")
			notify(player, "Invitee", nameOf(inviter), verdict.InviteeCoins)
		end
		if verdict.InviterCoins > 0 and inviterHere then
			Wallet.award(inviterHere, verdict.InviterCoins, "referral:inviter")
			notify(inviterHere, "Inviter", player.DisplayName, verdict.InviterCoins)
		end
	end

	-- De acum e un jucator vazut; iar daca a venit printr-o invitatie platita, perechea e inchisa.
	update(profileKey(userId), function(stored: any): any
		local saved: Profile = if type(stored) == "table" then stored else { Seen = false }
		saved.Seen = true
		if inviter and fresh and saved.ReferredBy == nil then
			saved.ReferredBy = inviter
		end
		return saved
	end)

	collect(player)
end

--[[
	Pentru Studio: aceeasi intrare, cu date de intrare date de mana, ca sa se
	poata vedea recompensa fara o invitatie adevarata. Ex. din bara de comenzi:
	`Social.simulateJoin(player, { ReferredByPlayerId = 123 })`.
]]
function Social.simulateJoin(player: Player, joinData: any, asNew: boolean?)
	assert(RunService:IsStudio(), "Social.simulateJoin e doar pentru Studio")
	-- `asNew` uita profilul din memoria sesiunii, ca jucatorul de test sa para la prima intrare.
	if asNew then
		memory[profileKey(player.UserId)] = nil
	end
	Social.arrive(player, joinData)
end

-- ------------------------------------------------------------ grupul

-- Cine e in grupul jocului, aflat o data la intrare.
local members: { [number]: boolean } = {}

--[[
	Singurul loc care intreaba Roblox de grup. Fara grup setat (`GroupId = 0`)
	nu intreaba nimic; in Studio jucatorii de test nu sunt in niciun grup.
]]
local function isInGroup(player: Player): boolean
	local groupId = SETTINGS.GroupId
	if groupId == 0 or player.UserId <= 0 then
		return false
	end
	local ok, result = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	return ok and result == true
end

--[[
	E jucatorul in grup? Din memorie; raspunsul se afla la intrare si se pune
	si ca atribut, ca clientul sa stie daca sa-i arate indemnul din lobby.
]]
function Social.inGroup(player: Player): boolean
	return members[player.UserId] == true
end

local function checkGroup(player: Player)
	local member = isInGroup(player)
	members[player.UserId] = member
	player:SetAttribute("InGroup", member)
end

local started = false

function Social.start()
	if started then
		return
	end
	started = true

	for _, player in Players:GetPlayers() do
		task.spawn(checkGroup, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(checkGroup, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		members[player.UserId] = nil
	end)

	--[[
		Asteapta o clipa dupa intrare: `GetJoinData` poate intarzia cateva
		secunde dupa ce prietenul a intrat din invitatie, iar portofelul trebuie
		sa fie deja incarcat cand vin banii.
	]]
	local function later(player: Player)
		task.wait(3)
		if player.Parent then
			Social.arrive(player)
		end
	end

	for _, player in Players:GetPlayers() do
		task.spawn(later, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(later, player)
	end)
end

return Social
