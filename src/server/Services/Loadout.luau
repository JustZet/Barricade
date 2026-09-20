--!strict
--[[
	Loadout — ce poarta fiecare jucator, tinut de server.

	Al treilea din familia lui `Wallet` si `Inventory`, si construit dupa acelasi
	tipar: nu stie ce e un meci, nu stie cum arata obiectele pe care le tine si
	nu hotaraste cine ce are voie sa cumpere. Tine cate un id pe fel de obiect,
	il pastreaza intre sesiuni si il face vazut.

	Clientul nu poate scrie aici. Trimite `RequestEquip`, iar serverul intreaba
	inventarul si abia apoi scrie — altfel oricine si-ar echipa orice.

	**Alegerea se vede ca atribut pe `Player`**, nu pe un canal de retea. Un
	atribut scris pe server ajunge la toti clientii dintr-o singura scriere, si
	asta chiar trebuie: zidul tau il vad si ceilalti. Numele atributului sta in
	`Loadout`-ul din `src/shared/`, ca sa nu existe doua parerii despre el.

	Se salveaza prin **inlocuire**, si aici e deosebirea fata de `Inventory`.
	Inventarul aduna, deci se reuneste; alegerea nu se aduna — ultima apasare a
	jucatorului e adevarul, oricare server ar fi scris inainte.

	Cand DataStore-ul nu raspunde, jocul merge mai departe cu alegeri care
	traiesc doar cat sesiunea. Se spune o data si nu se mai insista.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local GameConfig = require(Shared.GameConfig)
local SharedLoadout = require(Shared.Loadout)

local Inventory = require(script.Parent.Inventory)

local Loadout = {}

type Kind = Catalog.Kind
type Set = SharedLoadout.Set

local STORE_NAME = "Loadout_v1"

local AUTOSAVE_SECONDS = 60
local ATTEMPTS = 3
local RETRY_SECONDS = 6

-- Ce poarta acum, si ce s-a scris deja in DataStore.
local worn: { [number]: Set } = {}
local dirty: { [number]: boolean } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = if ok then result else nil
end

local complained = false

local function giveUp(action: string, reason: any)
	if complained then
		return
	end
	complained = true
	warn(
		string.format(
			"Loadout: %s a esuat, alegerile raman doar pe sesiunea asta.\nMotiv: %s",
			action,
			tostring(reason)
		)
	)
end

local function keyFor(userId: number): string
	return string.format("player_%d", userId)
end

--[[
	Se testeaza acum cu bani de minciuna?

	Acelasi comutator pe care il citesc portofelul si inventarul: daca obiectele
	cumparate in Studio nu ajung in contul adevarat, n-are nici ce sa poarte
	acolo. Un singur loc de stins.
]]
local function testing(): boolean
	return RunService:IsStudio() and GameConfig.Debug.StudioCoins > 0
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
	Scrie alegerea in atribute, de unde o citeste toata lumea.

	Se scrie chiar si cand nu s-a schimbat nimic: `SetAttribute` cu aceeasi
	valoare nu replica nimic, iar asa functia are o singura treaba si niciun
	"daca".
]]
local function publish(player: Player)
	local mine = worn[player.UserId]
	if not mine or not player.Parent then
		return
	end
	for _, kind: Kind in Catalog.Kinds do
		player:SetAttribute(SharedLoadout.attribute(kind), mine[kind])
	end
end

--[[
	Aduce alegerea unui jucator care tocmai a intrat.

	Pana raspunde DataStore-ul poarta obiectele de start. Ce echipeaza intre
	timp nu se pierde: ce vine de la DataStore se pune doar peste ce nu s-a
	atins, nu peste tot.
]]
function Loadout.load(player: Player)
	local userId = player.UserId
	worn[userId] = worn[userId] or SharedLoadout.defaults()
	publish(player)

	-- Sesiune de test: porneste cu obiectele de start, ca inventarul.
	if testing() then
		return
	end

	local kept = store
	if not kept then
		giveUp("deschiderea magaziei", "DataStoreService nu e disponibil")
		return
	end

	local saved = retry("citirea alegerii", function()
		return kept:GetAsync(keyFor(userId))
	end)
	if saved == nil then
		return
	end

	local stored = SharedLoadout.restore(saved)
	local mine = worn[userId] or SharedLoadout.defaults()

	--[[
		Ce a echipat cat se astepta raspunsul ramane echipat.

		`dirty` spune exact asta: ca jucatorul a ales ceva in sesiunea asta. Fara
		verificarea aia, alegerea facuta in primele secunde ar fi stearsa de
		raspunsul care vine dupa ea.
	]]
	if not dirty[userId] then
		for kind, id in stored do
			mine[kind] = id
		end
	end

	worn[userId] = mine
	publish(player)
end

-- Ce poarta acum, pe un fel. Intotdeauna un id valid.
function Loadout.get(player: Player, kind: Kind): string
	local mine = worn[player.UserId]
	return (mine and mine[kind]) or Catalog.default(kind)
end

--[[
	Echipeaza un obiect. Intoarce `true`, sau `false` plus motivul.

	Verificarea e cea din `src/shared/`, aceeasi pe care o ruleaza si magazinul
	cand isi deseneaza butonul: daca ar fi doua, butonul ar putea fi aprins
	peste un refuz.
]]
function Loadout.equip(player: Player, kind: Kind, id: string): (boolean, string?)
	local allowed, reason = SharedLoadout.canEquip(Inventory.owned(player), kind, id)
	if not allowed then
		return false, reason
	end

	local userId = player.UserId
	local mine = worn[userId] or SharedLoadout.defaults()
	worn[userId] = mine

	if mine[kind] == id then
		return true
	end

	mine[kind] = id
	dirty[userId] = true
	publish(player)
	return true
end

--[[
	Scrie alegerea in DataStore, daca s-a schimbat de la ultima salvare.

	Fara schimbare nu se cheama nimeni: o cerere goala consuma din acelasi buget
	de cereri ca una adevarata.
]]
function Loadout.save(userId: number)
	if testing() then
		return
	end

	local kept = store
	if not kept or not dirty[userId] then
		return
	end

	local mine = worn[userId]
	if not mine then
		return
	end

	--[[
		Se sterge *inainte* de scriere, nu dupa.

		Daca jucatorul echipeaza altceva cat dureaza cererea, steagul se ridica
		la loc si urmatoarea salvare il prinde. Sters dupa, alegerea aia s-ar
		pierde.
	]]
	dirty[userId] = nil

	local snapshot = table.clone(mine)
	local result = retry("salvarea alegerii", function()
		return kept:UpdateAsync(keyFor(userId), function(): Set
			return snapshot
		end)
	end)

	if result == nil then
		dirty[userId] = true
	end
end

-- Jucatorul a plecat: se salveaza si se uita, in ordinea asta.
function Loadout.release(player: Player)
	local userId = player.UserId
	Loadout.save(userId)
	worn[userId] = nil
	dirty[userId] = nil
end

local started = false

function Loadout.start()
	if started then
		return
	end
	started = true

	for _, player in Players:GetPlayers() do
		task.spawn(Loadout.load, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(Loadout.load, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.spawn(Loadout.release, player)
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				task.spawn(Loadout.save, player.UserId)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			Loadout.save(player.UserId)
		end
	end)
end

return Loadout
