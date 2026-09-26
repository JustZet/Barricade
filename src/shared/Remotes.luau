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
	--[[
		Revansa la aceeasi masa. Primul care o cere deschide votul; ceilalti
		raspund cu aceeasi cerere (da) sau cu refuzul de dedesubt (nu). Nu se
		trimite nimic altceva: masa si cine sta la ea le stie serverul.
	]]
	"RequestRematch",
	"RequestRematchDecline",
	--[[
		Provocarea directa. Pleaca modul si userId-urile celor provocati; cine
		sunt, daca sunt liberi si daca nu te-au refuzat de curand afla serverul.
		Raspunsul (da/nu) si renuntarea duc id-ul provocarii.
	]]
	"RequestChallenge",
	"RequestChallengeAnswer",
	"RequestChallengeCancel",
	-- Cererea de cumparare. Trimite doar id-ul articolului: pretul il stie
	-- serverul din catalog, si un pret venit de la client n-ar insemna nimic.
	"RequestPurchase",
	"RequestGift",
	--[[
		Cererea de echipare. Trimite felul si id-ul, atat: daca obiectul e al
		lui se afla pe server, din inventar.

		Raspunsul nu se intoarce pe un canal, ci ca atribut pe `Player` — vezi
		`Loadout`. Alegerea trebuie vazuta si de ceilalti jucatori, nu doar de
		proprietar, iar un atribut ajunge la toti dintr-o singura scriere.
	]]
	"RequestEquip",
	--[[
		Un emote. Pleaca doar id-ul din `Emotes`; ce inseamna el — semn, sunet —
		il stie si clientul celuilalt, din acelasi catalog. Raspunsul vine inapoi
		ca `MatchEvent`, la toata masa, inclusiv la cel care l-a trimis: asa toti
		vad acelasi lucru in aceeasi clipa, si nimeni nu-si deseneaza singur un
		balon pe care ceilalti nu-l au.
	]]
	"RequestEmote",
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
	--[[
		Tot ce e social si nu tine de un meci: prietenii din server, provocarile,
		recompensele pentru invitatii. Un singur canal, cu `Type` in el, ca
		`MatchEvent`.
	]]
	"SocialEvent",
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
