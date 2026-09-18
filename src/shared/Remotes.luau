--!strict
--[[
	Remotes — singurul loc unde se scriu numele canalelor de retea.

	Serverul le creeaza la boot, clientul le asteapta. Nimeni nu scrie
	string-uri de remote prin alta parte.

	Ce trimite clientul sunt *cereri*, nu comenzi: RequestMove nu muta pe
	nimeni, doar intreaba. Raspunsul adevarat vine intotdeauna prin
	GameStateUpdate, dupa ce serverul a decis.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

-- Client -> server. Fiecare e o cerere care poate fi refuzata.
local REQUESTS = {
	"RequestMove",
	"RequestPlaceWall",
	"RequestJoinQueue",
	"RequestLeaveQueue",
	"RequestLeaveMatch",
	"RequestRematch",
	-- Cererea de cumparare. Trimite doar id-ul articolului: pretul il stie
	-- serverul din catalog, si un pret venit de la client n-ar insemna nimic.
	"RequestPurchase",
}

-- Server -> client. Fapte deja intamplate.
local BROADCASTS = {
	"GameStateUpdate",
	"LobbyUpdate",
	"ActionRejected",
	"MatchEvent",
	-- Soldul jucatorului. Merge numai spre client: banii se dau de pe server.
	"WalletUpdate",
	-- Ce detine jucatorul. La fel, numai spre client.
	"InventoryUpdate",
}

local Remotes = {}

Remotes.Requests = REQUESTS
Remotes.Broadcasts = BROADCASTS

--[[
	Creeaza dosarul si evenimentele. Se cheama o singura data, din server.
]]
function Remotes.build(): Folder
	assert(RunService:IsServer(), "Remotes.build se cheama doar de pe server")

	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for _, name in REQUESTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	for _, name in BROADCASTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	folder.Parent = ReplicatedStorage
	return folder
end

function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	assert(folder, "Remotes: dosarul nu a aparut in ReplicatedStorage")
	local remote = folder:WaitForChild(name, 30)
	assert(remote, "Remotes: lipseste " .. name)
	return remote :: RemoteEvent
end

return Remotes
