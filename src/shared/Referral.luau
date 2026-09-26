--!strict
--[[
	Referral — cine primeste banuti cand cineva intra printr-o invitatie, si cat.

	Regula, fara nimic din Roblox in ea: serverul afla faptele (cine a invitat,
	daca cel venit e nou, daca perechea a mai fost platita, cate recompense a
	luat azi cel care a invitat) si le da aici; raspunsul spune cui i se da.

	Cine a invitat se citeste intai din `ReferredByPlayerId`, pe care il pune
	Roblox singur in `GetJoinData()` la orice invitatie — clientul nu-l poate
	scrie. Numai daca lipseste se cade pe `LaunchData`, scris de invitatia
	noastra ca „barricade-invite:<userId>".

	Regulile, in ordine:
	  fara cine a invitat, sau invitat de el insusi → nimic
	  cel venit nu e nou                             → nimic
	  perechea a mai fost platita                    → nimic
	  cel care a invitat a atins plafonul de azi     → doar cel venit
	  altfel                                         → amandoi
]]

local Referral = {}

local PREFIX = "barricade-invite:"

-- Ce scrie invitatia noastra in `LaunchData`.
function Referral.launchData(inviter: number): string
	return PREFIX .. tostring(inviter)
end

--[[
	Cine a invitat, din datele de intrare. Orice forma stricata intoarce `nil`:
	datele vin de la client, iar o invitatie de neinteles nu e o invitatie.
]]
function Referral.inviterFrom(joinData: any): number?
	if type(joinData) ~= "table" then
		return nil
	end

	local referred = joinData.ReferredByPlayerId
	if type(referred) == "number" and referred > 0 and referred % 1 == 0 then
		return referred
	end

	local launch = joinData.LaunchData
	if type(launch) ~= "string" or #launch > 200 then
		return nil
	end
	-- Prefixul se compara ca text, nu ca tipar: „-" din el ar fi citit ca operator.
	if string.sub(launch, 1, #PREFIX) ~= PREFIX then
		return nil
	end
	local digits = string.match(string.sub(launch, #PREFIX + 1), "^(%d+)$")
	local inviter = if digits then tonumber(digits) else nil
	if inviter and inviter > 0 then
		return inviter
	end
	return nil
end

export type Facts = {
	Invitee: number,
	Inviter: number?,
	-- A mai intrat cel venit vreodata?
	InviteeIsNew: boolean,
	-- A mai fost platita perechea asta?
	AlreadyPaid: boolean,
	-- Cate recompense a luat azi cel care a invitat.
	InviterToday: number,
	Cap: number,
	Reward: number,
}

export type Verdict = {
	InviteeCoins: number,
	InviterCoins: number,
	-- De ce nu s-a dat tot, cand nu s-a dat tot.
	Reason: string?,
}

function Referral.decide(facts: Facts): Verdict
	local inviter = facts.Inviter
	if inviter == nil then
		return { InviteeCoins = 0, InviterCoins = 0, Reason = "NO_INVITER" }
	end
	if inviter == facts.Invitee then
		return { InviteeCoins = 0, InviterCoins = 0, Reason = "SELF" }
	end
	if not facts.InviteeIsNew then
		return { InviteeCoins = 0, InviterCoins = 0, Reason = "RETURNING" }
	end
	if facts.AlreadyPaid then
		return { InviteeCoins = 0, InviterCoins = 0, Reason = "ALREADY_PAID" }
	end
	if facts.InviterToday >= facts.Cap then
		return { InviteeCoins = facts.Reward, InviterCoins = 0, Reason = "CAP_REACHED" }
	end
	return { InviteeCoins = facts.Reward, InviterCoins = facts.Reward, Reason = nil }
end

-- Ziua, ca numar, dupa ora UTC: plafonul se socoteste pe zile intregi.
function Referral.day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

return Referral
