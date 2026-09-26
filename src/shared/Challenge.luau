--!strict
--[[
	Challenge — provocarea directa dintre jucatori, fara coada.

	Cineva alege unul sau mai multi oameni din server si un mod; ei primesc
	invitatia si raspund. Toti accepta → meci direct. Oricine refuza, iese din
	joc, intra in alt meci sau lasa timpul sa treaca → provocarea se inchide
	pentru toti.

	Masina de stari fara ceas, ca `RematchVote`: timpul vine ca argument, iar
	fiecare functie spune unde a ajuns provocarea. Serverul aduce jucatorii si
	ora; decizia e aici, testata.

	  Requested → Accepted   toti invitatii au spus da
	            → Declined   unul a spus nu (si porneste cooldown-ul)
	            → Expired    a trecut timpul
	            → Cancelled  a renuntat cel care a provocat, sau cineva nu mai e
	                         disponibil
]]

local Challenge = {}

export type Status = "Requested" | "Accepted" | "Declined" | "Expired" | "Cancelled"

export type Challenge = {
	Id: string,
	From: number,
	Invitees: { number },
	Mode: string,
	Deadline: number,
	Status: Status,
	Accepted: { [number]: boolean },
	-- Din cauza cui s-a inchis, si de ce, cand nu e evident din stare.
	By: number?,
	Reason: string?,
}

--[[
	Tot ce trebuie stiut ca sa se decida daca o provocare poate pleca.

	`Busy` spune unde e fiecare: "MATCH", "QUEUE" sau nimic. `Engaged` spune cine
	e deja intr-o provocare deschisa — ca cel care provoaca, sau ca invitat.
	`Cooldowns` tine, pe perechea „cine provoaca → pe cine", pana cand nu se mai
	poate, dupa un refuz.
]]
export type Request = {
	From: number,
	Invitees: { number },
	-- Cati joaca in modul ales, cu tot cu cel care provoaca.
	Players: number,
	Present: { [number]: boolean },
	Busy: { [number]: string? },
	Engaged: { [number]: boolean },
	Cooldowns: { [string]: number },
	Now: number,
}

function Challenge.cooldownKey(from: number, to: number): string
	return string.format("%d>%d", from, to)
end

--[[
	Poate pleca provocarea? Intoarce motivul refuzului, ca cheie; clientul il
	traduce. Ordinea verificarilor e cea in care le-ar pune un om: intai ce tine
	de tine, apoi de ceilalti.
]]
function Challenge.validate(request: Request): (boolean, string?)
	local from = request.From
	if request.Busy[from] ~= nil then
		return false, "YOU_BUSY"
	end
	if request.Engaged[from] then
		return false, "YOU_ENGAGED"
	end
	if #request.Invitees ~= request.Players - 1 then
		return false, "WRONG_COUNT"
	end

	local seen: { [number]: boolean } = {}
	for _, userId in request.Invitees do
		if userId == from then
			return false, "SELF"
		end
		if seen[userId] then
			return false, "DUPLICATE"
		end
		seen[userId] = true

		if not request.Present[userId] then
			return false, "ABSENT"
		end
		local busy = request.Busy[userId]
		if busy == "MATCH" then
			return false, "BUSY_MATCH"
		elseif busy == "QUEUE" then
			return false, "BUSY_QUEUE"
		end
		if request.Engaged[userId] then
			return false, "ENGAGED"
		end
		local blockedUntil = request.Cooldowns[Challenge.cooldownKey(from, userId)]
		if blockedUntil and request.Now < blockedUntil then
			return false, "COOLDOWN"
		end
	end

	return true, nil
end

function Challenge.new(
	id: string,
	from: number,
	invitees: { number },
	mode: string,
	now: number,
	window: number
): Challenge
	return {
		Id = id,
		From = from,
		Invitees = table.clone(invitees),
		Mode = mode,
		Deadline = now + window,
		Status = "Requested",
		Accepted = {},
	}
end

function Challenge.isOpen(challenge: Challenge): boolean
	return challenge.Status == "Requested"
end

-- Toti cei implicati: cel care provoaca, apoi invitatii.
function Challenge.members(challenge: Challenge): { number }
	local list = { challenge.From }
	for _, userId in challenge.Invitees do
		table.insert(list, userId)
	end
	return list
end

-- Expira daca i-a trecut timpul. Se cheama inaintea oricarei decizii.
function Challenge.tick(challenge: Challenge, now: number): Status
	if challenge.Status == "Requested" and now >= challenge.Deadline then
		challenge.Status = "Expired"
	end
	return challenge.Status
end

local function invited(challenge: Challenge, userId: number): boolean
	return table.find(challenge.Invitees, userId) ~= nil
end

-- Un „da" de la un invitat. Cand au spus toti, provocarea e acceptata.
function Challenge.accept(challenge: Challenge, userId: number, now: number): (boolean, string?)
	if Challenge.tick(challenge, now) ~= "Requested" then
		return false, "CLOSED"
	end
	if not invited(challenge, userId) then
		return false, "NOT_INVITED"
	end
	challenge.Accepted[userId] = true
	for _, invitee in challenge.Invitees do
		if not challenge.Accepted[invitee] then
			return true, nil
		end
	end
	challenge.Status = "Accepted"
	return true, nil
end

-- Un „nu" de la un invitat: se inchide pentru toti.
function Challenge.decline(challenge: Challenge, userId: number, now: number): (boolean, string?)
	if Challenge.tick(challenge, now) ~= "Requested" then
		return false, "CLOSED"
	end
	if not invited(challenge, userId) then
		return false, "NOT_INVITED"
	end
	challenge.Status = "Declined"
	challenge.By = userId
	return true, nil
end

-- Cel care a provocat renunta. Numai el poate.
function Challenge.cancel(challenge: Challenge, userId: number, now: number): (boolean, string?)
	if Challenge.tick(challenge, now) ~= "Requested" then
		return false, "CLOSED"
	end
	if userId ~= challenge.From then
		return false, "NOT_YOURS"
	end
	challenge.Status = "Cancelled"
	challenge.Reason = "CANCELLED"
	challenge.By = userId
	return true, nil
end

--[[
	Cineva din provocare nu mai e disponibil: a iesit din joc, a intrat in coada
	sau intr-un meci. Nu mai are cu cine sa se joace, deci se inchide.
]]
function Challenge.drop(challenge: Challenge, userId: number, now: number): boolean
	if Challenge.tick(challenge, now) ~= "Requested" then
		return false
	end
	if userId ~= challenge.From and not invited(challenge, userId) then
		return false
	end
	challenge.Status = "Cancelled"
	challenge.Reason = "UNAVAILABLE"
	challenge.By = userId
	return true
end

--[[
	Cooldown-ul care porneste dupa un refuz: cel care a provocat nu-l mai poate
	provoca pe cel care a refuzat pana la ora intoarsa. Nimic in celelalte cazuri
	— o provocare expirata nu e un „nu", poate omul nici n-a vazut-o.
]]
function Challenge.cooldownAfter(
	challenge: Challenge,
	now: number,
	seconds: number
): (string?, number?)
	if challenge.Status ~= "Declined" or challenge.By == nil then
		return nil, nil
	end
	return Challenge.cooldownKey(challenge.From, challenge.By), now + seconds
end

return Challenge
