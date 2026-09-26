--!strict
--[[
	Friends — cine e prieten cu cine, printre cei aflati acum in server.

	Se intreaba Roblox o singura data per pereche, cand intra al doilea dintre
	ei, si se tine minte pana pleaca unul. `IsFriendsWithAsync` e o cerere de retea
	care poate sa dureze si sa pice; intrebata la fiecare desenare a listei, ar
	fi lenta si ar da cand da, cand nu.

	Fiecare jucator primeste lista prietenilor lui din server pe `SocialEvent`,
	la intrare si de fiecare data cand se schimba. Clientul n-o afla singur:
	pentru el, un prieten e doar un id pe care i l-a spus serverul.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Friends = {}

-- Perechile cunoscute, dupa cheia „mic-mare". Lipsa inseamna „nu" sau „inca nu stim".
local known: { [string]: boolean } = {}

local function key(a: number, b: number): string
	if a > b then
		a, b = b, a
	end
	return string.format("%d-%d", a, b)
end

--[[
	Singurul loc care intreaba Roblox. In Studio jucatorii de test au id-uri
	negative si nu au prieteni: raspunsul e „nu", fara cerere.
]]
local function isFriendsWith(a: Player, b: Player): boolean
	if a.UserId <= 0 or b.UserId <= 0 then
		return false
	end
	local ok, result = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	return ok and result == true
end

function Friends.areFriends(a: number, b: number): boolean
	return known[key(a, b)] == true
end

-- Prietenii din server ai cuiva, ca userId-uri.
function Friends.of(userId: number): { number }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.UserId ~= userId and Friends.areFriends(userId, other.UserId) then
			table.insert(list, other.UserId)
		end
	end
	return list
end

local function push(player: Player)
	if player.Parent then
		Remotes.get("SocialEvent")
			:FireClient(player, { Type = "Friends", UserIds = Friends.of(player.UserId) })
	end
end

--[[
	Intrarea cuiva: se afla cu cine e prieten dintre cei deja aici. Fiecare
	prieten afla si el ca a intrat — de aici vine notificarea din lobby, cu
	CHALLENGE direct pe el.
]]
local function arrived(player: Player)
	local remote = Remotes.get("SocialEvent")
	for _, other in Players:GetPlayers() do
		if other ~= player and isFriendsWith(player, other) then
			known[key(player.UserId, other.UserId)] = true
			push(other)
			if other.Parent and player.Parent then
				remote:FireClient(
					other,
					{ Type = "FriendJoined", UserId = player.UserId, Name = player.DisplayName }
				)
			end
		end
	end
	push(player)
end

function Friends.start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(arrived, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(arrived, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		for pair in known do
			local a, b = string.match(pair, "^(%-?%d+)%-(%-?%d+)$")
			if tonumber(a) == player.UserId or tonumber(b) == player.UserId then
				known[pair] = nil
			end
		end
	end)
end

return Friends
