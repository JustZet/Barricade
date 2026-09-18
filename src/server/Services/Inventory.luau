--!strict
--[[
	Inventory — ce detine fiecare jucator, tinut de server.

	Fratele lui `Wallet`, si construit dupa acelasi tipar: nu stie ce e un meci,
	nu stie ce inseamna articolele pe care le tine si nu hotaraste cine primeste
	ceva. Tine o multime de id-uri pe jucator, o pastreaza intre sesiuni si o
	trimite proprietarului ei.

	Clientul nu poate scrie aici. Singurul drum e de la server spre client, prin
	`InventoryUpdate`; ce se vede pe ecran e o copie a ce stie serverul.

	Se salveaza prin **reuniune**, nu prin inlocuire.

	`UpdateAsync` primeste ce s-a adaugat de la ultima salvare si adauga acolo,
	in loc sa scrie lista pe care o crede serverul asta. Doua servere care au
	acelasi jucator — la un teleport, sau la o reconectare rapida — si-ar sterge
	unul altuia cumparaturile daca fiecare ar pune lista lui. Reunite, nu se
	pierde nimic. Un obiect nu se ia niciodata inapoi, deci reuniunea e de ajuns:
	nu exista stergere pe care ar trebui s-o propagam.

	Cand DataStore-ul nu raspunde, jocul merge mai departe cu inventare care
	traiesc doar cat sesiunea. Se spune o data si nu se mai insista.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Inventory = {}

local STORE_NAME = "Inventory_v1"

local AUTOSAVE_SECONDS = 60
local ATTEMPTS = 3
local RETRY_SECONDS = 6

--[[
	Ce are acum, si ce s-a scris deja in DataStore.

	Diferenta dintre cele doua e ce ramane de salvat. La fel ca la portofel, se
	tine separat tocmai ca o salvare care intarzie sa nu piarda ce s-a cumparat
	intre timp.
]]
local owned: { [number]: { [string]: boolean } } = {}
local persisted: { [number]: { [string]: boolean } } = {}

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
			"Inventory: %s a esuat, cumparaturile raman doar pe sesiunea asta.\nMotiv: %s",
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

	Daca da, inventarul nu scrie si nu citeste nimic: obiectele cumparate cu
	banii de test ar ramane in contul adevarat, si nici n-ar fi drept sa se
	amestece cu ce ai cumparat cinstit. Comutatorul e acelasi pe care il citeste
	si portofelul, din `GameConfig.Debug` — un singur loc de stins.
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
	Trimite inventarul proprietarului lui.

	Ca lista, nu ca tabela cu chei: prin remote o tabela cu chei string ajunge
	tot ca tabela, dar o lista se citeste la fel de usor si nu depinde de
	ordinea in care Luau enumera cheile.
]]
local function publish(player: Player)
	if not player.Parent then
		return
	end
	local mine: { [string]: boolean } = owned[player.UserId] or {}
	local ids: { string } = {}
	for id in mine do
		table.insert(ids, id)
	end
	table.sort(ids)
	Remotes.get("InventoryUpdate"):FireClient(player, { Items = ids })
end

local function readInto(target: { [string]: boolean }, stored: any)
	if typeof(stored) ~= "table" then
		return
	end
	for _, id in stored do
		if typeof(id) == "string" then
			target[id] = true
		end
	end
end

--[[
	Aduce inventarul unui jucator care tocmai a intrat.

	Pana raspunde DataStore-ul nu are nimic si vede ca nu are nimic. Ce cumpara
	intre timp nu se pierde: se adauga peste ce vine de la DataStore, nu invers.
]]
function Inventory.load(player: Player)
	local userId = player.UserId
	owned[userId] = owned[userId] or {}
	persisted[userId] = persisted[userId] or {}
	publish(player)

	-- Sesiune de test: porneste cu inventarul gol, ca sa se vada cumpararea.
	if testing() then
		return
	end

	local kept = store
	if not kept then
		giveUp("deschiderea magaziei", "DataStoreService nu e disponibil")
		return
	end

	local saved = retry("citirea inventarului", function()
		return kept:GetAsync(keyFor(userId))
	end)

	local base: { [string]: boolean } = {}
	readInto(base, saved)

	-- Ce a cumparat cat se astepta raspunsul ramane al lui.
	local mine = owned[userId] or {}
	for id in base do
		mine[id] = true
	end
	owned[userId] = mine
	persisted[userId] = base
	publish(player)
end

-- Ce detine, ca tabela de cautat direct. Copie: nimeni nu scrie in ea din afara.
function Inventory.owned(player: Player): { [string]: boolean }
	return table.clone(owned[player.UserId] or {})
end

function Inventory.has(player: Player, itemId: string): boolean
	local mine = owned[player.UserId]
	return mine ~= nil and mine[itemId] == true
end

--[[
	Da articolele unui jucator. Intoarce cate erau intr-adevar noi.

	Cine da hotaraste *ce*; inventarul doar tine socoteala — la fel ca portofelul.
]]
function Inventory.grant(player: Player, itemIds: { string }): number
	local userId = player.UserId
	local mine = owned[userId] or {}
	owned[userId] = mine

	local added = 0
	for _, id in itemIds do
		if not mine[id] then
			mine[id] = true
			added += 1
		end
	end

	if added > 0 then
		publish(player)
	end
	return added
end

--[[
	Scrie in DataStore ce s-a adaugat de la ultima salvare.

	Daca nu s-a adaugat nimic, nu se cheama nimeni: o cerere goala consuma din
	acelasi buget de cereri ca una adevarata.
]]
function Inventory.save(userId: number)
	-- Ce s-a cumparat cu bani de test nu are ce cauta in contul adevarat.
	if testing() then
		return
	end

	local kept = store
	if not kept then
		return
	end

	local mine: { [string]: boolean } = owned[userId] or {}
	local written: { [string]: boolean } = persisted[userId] or {}

	local fresh: { string } = {}
	for id in mine do
		if not written[id] then
			table.insert(fresh, id)
		end
	end
	if #fresh == 0 then
		return
	end

	local result = retry("salvarea inventarului", function()
		return kept:UpdateAsync(keyFor(userId), function(stored: any): { string }
			local union: { [string]: boolean } = {}
			readInto(union, stored)
			for _, id in fresh do
				union[id] = true
			end

			local list: { string } = {}
			for id in union do
				table.insert(list, id)
			end
			table.sort(list)
			return list
		end)
	end)

	if result == nil then
		return
	end

	--[[
		Se marcheaza ca scris fix ce s-a trimis, nu tot ce are acum.

		Intre clipa in care s-a calculat lista si raspunsul DataStore-ului
		jucatorul putea cumpara din nou; socotit ca salvat, s-ar pierde.
	]]
	for _, id in fresh do
		written[id] = true
	end
	persisted[userId] = written
end

--[[
	Jucatorul a plecat: se salveaza si se uita. Se uita dupa salvare, altfel
	cumparaturile nesalvate ar disparea impreuna cu el.
]]
function Inventory.release(player: Player)
	local userId = player.UserId
	Inventory.save(userId)
	owned[userId] = nil
	persisted[userId] = nil
end

local started = false

function Inventory.start()
	if started then
		return
	end
	started = true

	for _, player in Players:GetPlayers() do
		task.spawn(Inventory.load, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(Inventory.load, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.spawn(Inventory.release, player)
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				task.spawn(Inventory.save, player.UserId)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			Inventory.save(player.UserId)
		end
	end)
end

return Inventory
