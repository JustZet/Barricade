--!strict
--[[
	Pocket — ce stie clientul despre buzunarul lui: banutii si ce are cumparat.

	Serverul le trimite prin `WalletUpdate` si `InventoryUpdate`: o data la
	intrare, si apoi la fiecare schimbare. Cine se leaga **dupa** ce au venit nu
	mai prinde nimic, iar canalele nu tin minte nimic in urma lor.

	Exact asta pateau vitrinele din lobby. Ele se construiesc tarziu — asteapta
	replicarea arenei, cu rabdare de cateva secunde — iar pana atunci soldul
	ajunsese demult la client. Ascultatorul lor prindea abia urmatoarea
	schimbare, care intr-un lobby linistit nu mai venea niciodata: toate
	ofertele scriau "NOT ENOUGH" desi jucatorul avea cinci mii in buzunar, iar
	interfata de sus arata cinci mii, fiindca ea se legase la timp.

	De aceea starea sta aici, intr-un singur loc, si se tine minte. Cine se
	aboneaza tarziu primeste pe loc ce e acum, nu tacere. Canalele se asculta o
	singura data, la primul abonat, oricati ar veni dupa.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Pocket = {}

local coins = 0
local items: { string } = {}
local owned: { [string]: boolean } = {}

--[[
	A vorbit serverul pana acum?

	Zero banuti inainte de primul mesaj si zero banuti dupa el arata la fel, dar
	nu inseamna acelasi lucru: primul e "nu stiu inca", al doilea e "chiar n-are".
	Cine numara de la vechea suma la cea noua trebuie sa stie diferenta, altfel
	urca de la zero la intrare si pare un castig.
]]
local heard = false

local watchers: { () -> () } = {}
local bound = false

local function announce()
	for _, watcher in watchers do
		watcher()
	end
end

local function bind()
	if bound then
		return
	end
	bound = true

	Remotes.get("WalletUpdate").OnClientEvent:Connect(function(payload: any)
		local balance = if typeof(payload) == "table" then payload.Coins else nil
		if type(balance) ~= "number" then
			return
		end
		coins = balance
		heard = true
		announce()
	end)

	Remotes.get("InventoryUpdate").OnClientEvent:Connect(function(payload: any)
		local list = if typeof(payload) == "table" then payload.Items else nil
		if typeof(list) ~= "table" then
			return
		end

		local fresh: { [string]: boolean } = {}
		local keys: { string } = {}
		for _, key in list do
			if type(key) == "string" then
				fresh[key] = true
				table.insert(keys, key)
			end
		end
		owned = fresh
		items = keys
		announce()
	end)
end

function Pocket.coins(): number
	return coins
end

-- Ce are cumparat, ca multime gata de intrebat: `owned[Catalog.key(kind, id)]`.
function Pocket.owned(): { [string]: boolean }
	return owned
end

-- Aceleasi obiecte, in forma in care vin de pe server. Magazinul le vrea asa.
function Pocket.items(): { string }
	return items
end

function Pocket.known(): boolean
	return heard
end

--[[
	Se cheama acum, cu ce e acum, si apoi la fiecare schimbare.

	Chemarea de la inceput nu e o politete: ea e tot rostul modulului. Fara ea,
	cine se leaga tarziu ar astepta o schimbare care poate nu mai vine.
]]
function Pocket.watch(callback: () -> ())
	bind()
	table.insert(watchers, callback)
	callback()
end

return Pocket
