--!strict
--[[
	MatchManager — registrul meciurilor de pe server.

	Stie cine joaca unde. Un jucator poate fi in cel mult un meci, iar
	cautarea dupa jucator trece mereu pe aici: niciun alt modul nu tine
	perechea jucator-meci, ca sa nu existe doua adevaruri.
]]

local Match = require(script.Parent.Match)

type Match = Match.Match

local MatchManager = {}

local matches: { [string]: Match } = {}
local matchByUserId: { [number]: Match } = {}

function MatchManager.create(modeId: string, players: { Player }, origin: CFrame?): Match
	local match = Match.new(modeId, players, origin)

	matches[match.Id] = match
	for _, player in players do
		matchByUserId[player.UserId] = match
	end

	-- Meciul incheiat ramane in registru pana cand jucatorii parasesc ecranul
	-- de victorie; abia atunci destroyIfEmpty il elibereaza.
	match:start()
	return match
end

function MatchManager.getForPlayer(player: Player): Match?
	return matchByUserId[player.UserId]
end

function MatchManager.getById(id: string): Match?
	return matches[id]
end

-- Scoate un jucator din evidenta, fara sa atinga meciul in sine.
function MatchManager.forget(player: Player)
	matchByUserId[player.UserId] = nil
end

function MatchManager.destroy(match: Match)
	for userId, tracked in matchByUserId do
		if tracked == match then
			matchByUserId[userId] = nil
		end
	end
	matches[match.Id] = nil
	match:destroy()
end

--[[
	Un meci mai are rost doar cat timp mai e cineva legat de el. Cand ultimul
	jucator pleaca sau iese din ecranul de final, dispare.
]]
function MatchManager.destroyIfEmpty(match: Match)
	for _, tracked in matchByUserId do
		if tracked == match then
			return
		end
	end
	MatchManager.destroy(match)
end

function MatchManager.getAll(): { [string]: Match }
	return matches
end

return MatchManager
