--!strict
--[[
	Wallet — banutii jucatorilor, tinuti de server.

	Modulul asta nu stie ce e un meci, ce e o baricada si de ce ar primi cineva
	bani. Stie doar sa tina o suma pe jucator, sa o creasca, sa o scada si sa o
	pastreze intre sesiuni. De aceea poate fi folosit de orice altceva care va
	avea nevoie de bani — magazin, skinuri, recompense zilnice — fara sa fie
	atins. Cine da banii hotaraste *cat*; portofelul doar tine socoteala.

	Clientul nu are niciun cuvant aici. Nu exista remote prin care sa ceara bani,
	si nici prin care sa-si spuna soldul: singurul drum e de la server spre
	client, prin `WalletUpdate`. Ce vede jucatorul pe ecran e o copie a ce stie
	serverul, nu invers.

	Se salveaza prin **diferenta**, nu prin valoare.

	`UpdateAsync` primeste cat s-a schimbat de la ultima salvare si aduna acolo,
	in loc sa scrie suma pe care o crede serverul asta. Nu e pedanterie: doua
	servere care au acelasi jucator — la un teleport, sau la o reconectare rapida
	inainte ca primul sa fi salvat — isi scriu unul peste altul daca fiecare pune
	valoarea lui, si cineva pierde bani castigati cinstit. Cu diferente, cele
	doua se aduna si nimeni nu pierde nimic.

	Cand DataStore-ul nu raspunde — in Studio fara "Enable Studio Access to API
	Services", de exemplu — jocul merge mai departe cu portofele care traiesc doar
	cat sesiunea. Se spune o data, ca sa se stie, si nu se mai insista.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Wallet = {}

local STORE_NAME = "Wallet_v1"

-- Cat de des se duc la DataStore banii castigati intre timp.
local AUTOSAVE_SECONDS = 60

--[[
	De cate ori se reincearca o cerere si cat se asteapta intre incercari.

	DataStore-ul cade rar, dar cade, si aproape mereu scurt. Trei incercari la
	sase secunde acopera o pana obisnuita fara sa tina firul minute intregi.
]]
local ATTEMPTS = 3
local RETRY_SECONDS = 6

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = if ok then result else nil
end

-- Soldul din sesiunea asta, si cat din el a ajuns deja in DataStore.
local balances: { [number]: number } = {}
local persisted: { [number]: number } = {}

local complained = false

local function giveUp(action: string, reason: any)
	if complained then
		return
	end
	complained = true
	warn(
		string.format(
			"Wallet: %s a esuat, banutii raman doar pe sesiunea asta.\n  Motiv: %s\n"
				.. "  In Studio se deschide din Game Settings -> Security -> "
				.. "Enable Studio Access to API Services.",
			action,
			tostring(reason)
		)
	)
end

local function keyFor(userId: number): string
	return string.format("player_%d", userId)
end

--[[
	Cati banuti de test sunt in joc acum. Zero peste tot in afara de Studio.

	Cat timp nu e zero, portofelul nu mai scrie in DataStore. E singurul lucru
	care tine banii de minciuna separati de cei adevarati, si de aceea se
	intreaba in amandoua locurile — la incarcare si la salvare — in loc sa fie
	citit o data intr-o variabila.
]]
local warnedTesting = false

local function testingCoins(): number
	if not RunService:IsStudio() then
		return 0
	end
	local amount = GameConfig.Debug.StudioCoins
	if amount > 0 and not warnedTesting then
		warnedTesting = true
		warn(
			string.format(
				"Wallet: banuti de test in Studio (%d). Nu se salveaza nimic in DataStore "
					.. "cat timp GameConfig.Debug.StudioCoins nu e 0.",
				amount
			)
		)
	end
	return amount
end

--[[
	Trimite soldul clientului lui.

	Nu tuturor: cat are cineva in buzunar il priveste pe el. Un client care ar
	primi soldurile celorlalti ar putea sa le arate, iar noi n-am castiga nimic
	din asta.
]]
local function publish(player: Player)
	if not player.Parent then
		return
	end
	Remotes.get("WalletUpdate"):FireClient(player, { Coins = balances[player.UserId] or 0 })
end

local function retry<T>(action: string, work: () -> T): T?
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(work)
		if ok then
			return result
		end
		if attempt == ATTEMPTS then
			giveUp(action, result)
			return nil
		end
		task.wait(RETRY_SECONDS)
	end
	return nil
end

--[[
	Aduce soldul unui jucator care tocmai a intrat.

	Pana raspunde DataStore-ul, jucatorul are zero si vede zero — nu o cifra
	ghicita care s-ar corecta sub ochii lui. Daca nu raspunde deloc, ramane cu un
	portofel de sesiune: poate castiga si poate cheltui, doar ca la plecare nu se
	scrie nicaieri.
]]
function Wallet.load(player: Player)
	local userId = player.UserId
	balances[userId] = balances[userId] or 0
	persisted[userId] = persisted[userId] or 0

	--[[
		Banii de test se dau inaintea DataStore-ului, si atat.

		Nu se cheama `Wallet.award`, ca sa nu intre pe drumul obisnuit al
		castigurilor; iar `Wallet.save` se opreste singur cat timp comutatorul e
		pornit, deci suma asta nu ajunge niciodata in contul adevarat. Nu se mai
		citeste nici soldul salvat: amestecat cu banii de minciuna, n-ar mai
		spune nimic despre cat ai cu adevarat.
	]]
	if testingCoins() > 0 then
		balances[userId] = math.max(balances[userId] or 0, testingCoins())
		persisted[userId] = balances[userId]
		publish(player)
		return
	end

	publish(player)

	local kept = store
	if not kept then
		giveUp("deschiderea magaziei", "DataStoreService nu e disponibil")
		return
	end

	local saved = retry("citirea soldului", function()
		return kept:GetAsync(keyFor(userId))
	end)

	-- Jucatorul putea castiga ceva cat se astepta raspunsul; aia nu se pierde.
	local earnedMeanwhile = (balances[userId] or 0) - (persisted[userId] or 0)
	local base = if typeof(saved) == "number" then saved else 0

	balances[userId] = base + earnedMeanwhile
	persisted[userId] = base
	publish(player)
end

function Wallet.balance(player: Player): number
	return balances[player.UserId] or 0
end

--[[
	Adauga bani. Intoarce soldul nou.

	`reason` nu se foloseste la nimic acum, si e acolo dinadins: cand va exista
	un jurnal de tranzactii sau o statistica, apelurile nu trebuie schimbate,
	doar modulul asta.
]]
function Wallet.award(player: Player, amount: number, _reason: string?): number
	if amount <= 0 then
		return Wallet.balance(player)
	end

	local userId = player.UserId
	balances[userId] = (balances[userId] or 0) + math.floor(amount)
	publish(player)
	return balances[userId]
end

--[[
	Scade bani, daca are de unde. Intoarce `false` si nu atinge nimic daca n-are.

	Verificarea si scaderea stau in aceeasi functie tocmai ca sa nu poata exista
	cod care intreaba intai si scade dupa: intre cele doua incape orice.
]]
function Wallet.spend(player: Player, amount: number, _reason: string?): boolean
	if amount <= 0 then
		return false
	end

	local userId = player.UserId
	local have = balances[userId] or 0
	local cost = math.floor(amount)
	if have < cost then
		return false
	end

	balances[userId] = have - cost
	publish(player)
	return true
end

--[[
	Scrie in DataStore cat s-a schimbat de la ultima salvare.

	Daca nu s-a schimbat nimic, nu se cheama nimeni: o cerere goala consuma din
	acelasi buget de cereri ca una adevarata.
]]
function Wallet.save(userId: number)
	-- Banii de test nu au ce cauta in contul adevarat.
	if testingCoins() > 0 then
		return
	end

	local kept = store
	if not kept then
		return
	end

	local delta = (balances[userId] or 0) - (persisted[userId] or 0)
	if delta == 0 then
		return
	end

	local written = retry("salvarea soldului", function()
		return kept:UpdateAsync(keyFor(userId), function(stored: any): number
			return (if typeof(stored) == "number" then stored else 0) + delta
		end)
	end)

	if written == nil then
		return
	end

	--[[
		Se scade fix ce s-a scris, nu se pune soldul curent.

		Intre clipa in care s-a calculat diferenta si clipa in care a raspuns
		DataStore-ul, jucatorul putea castiga din nou. Pus soldul curent, cat a
		castigat intre timp ar fi socotit ca deja salvat, si s-ar pierde.
	]]
	persisted[userId] = (persisted[userId] or 0) + delta
end

--[[
	Jucatorul a plecat: se salveaza si se uita.

	Se uita *dupa* salvare, si numai daca a mers. Sters mai devreme, diferenta
	nesalvata ar disparea impreuna cu el.
]]
function Wallet.release(player: Player)
	local userId = player.UserId
	Wallet.save(userId)
	balances[userId] = nil
	persisted[userId] = nil
end

--[[
	Porneste serviciul: intrari, iesiri, salvare periodica si la inchidere.

	Se cheama o singura data, de la pornirea serverului.
]]
local started = false

function Wallet.start()
	if started then
		return
	end
	started = true

	for _, player in Players:GetPlayers() do
		task.spawn(Wallet.load, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(Wallet.load, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.spawn(Wallet.release, player)
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				Wallet.save(player.UserId)
			end
		end
	end)

	--[[
		Ultima salvare, la inchiderea serverului.

		Roblox asteapta ce se face aici, pana intr-o limita. In Studio nu se
		cheama la fel de sigur ca pe un server adevarat, de aceea nu e singura
		plasa, ci ultima.
	]]
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		for _, player in Players:GetPlayers() do
			Wallet.save(player.UserId)
		end
	end)
end

return Wallet
