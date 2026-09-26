--!strict
--[[
	RematchVote — votul pentru revansa la aceeasi masa, si seria care iese din el.

	O masina de stari fara ceas: timpul vine ca argument, iar fiecare functie
	spune in ce stare a ajuns votul. Serverul aduce ora si jucatorii; decizia o
	ia modulul asta, si el nu stie nici ce e un `Player`, nici ce e un meci.

	Trei stari, si din primele doua nu se mai iese:

	  Accepted  — toti de la masa au spus da
	  Cancelled — cineva a refuzat, a plecat, sau a trecut timpul
	  Pending   — inca se asteapta

	Cine cere revansa a acceptat-o deja. Un vot dublu nu schimba nimic si nu e o
	greseala: cineva apasa de doua ori pe acelasi buton. Un vot de la cineva din
	afara mesei e refuzat — altfel un strain ar putea anula revansa altora.

	Tot aici: in ce ordine se asaza jucatorii la masa noua, si scorul seriei
	dintre aceiasi oameni — „Rematch #3 · 2–1".
]]

local RematchVote = {}

export type Status = "Pending" | "Accepted" | "Cancelled"
export type Reason = "DECLINED" | "LEFT" | "EXPIRED"

export type Vote = {
	-- Cine voteaza: userId-urile celor de la masa, in ordinea sloturilor.
	Seats: { number },
	Accepted: { [number]: boolean },
	Requester: number,
	Deadline: number,
	Status: Status,
	-- De ce s-a anulat, si din cauza cui. Lipsesc cat votul e deschis.
	Reason: Reason?,
	By: number?,
}

local function seated(vote: Vote, userId: number): boolean
	return table.find(vote.Seats, userId) ~= nil
end

local function cancel(vote: Vote, reason: Reason, by: number?)
	vote.Status = "Cancelled"
	vote.Reason = reason
	vote.By = by
end

--[[
	Deschide votul. Cine il cere a acceptat deja.

	Intoarce `nil` si motivul cand nu se poate: nu e la masa, sau e singur la
	ea — o revansa cu nimeni nu e revansa.
]]
function RematchVote.open(
	seats: { number },
	requester: number,
	now: number,
	window: number
): (Vote?, string?)
	if table.find(seats, requester) == nil then
		return nil, "NOT_SEATED"
	end
	if #seats < 2 then
		return nil, "ALONE"
	end

	local copy = table.clone(seats)
	return {
		Seats = copy,
		Accepted = { [requester] = true },
		Requester = requester,
		Deadline = now + window,
		Status = "Pending",
	},
		nil
end

--[[
	Expira votul daca i-a trecut timpul. Se cheama inainte de orice alta
	decizie, ca un „da" venit dupa termen sa nu mai conteze.
]]
function RematchVote.tick(vote: Vote, now: number): Status
	if vote.Status == "Pending" and now >= vote.Deadline then
		cancel(vote, "EXPIRED", nil)
	end
	return vote.Status
end

--[[
	Un „da". Intoarce `false` si motivul cand nu conteaza: votul nu mai e
	deschis, sau cel care voteaza nu e la masa.
]]
function RematchVote.accept(vote: Vote, userId: number, now: number): (boolean, string?)
	if RematchVote.tick(vote, now) ~= "Pending" then
		return false, "CLOSED"
	end
	if not seated(vote, userId) then
		return false, "NOT_SEATED"
	end

	vote.Accepted[userId] = true

	for _, seat in vote.Seats do
		if not vote.Accepted[seat] then
			return true, nil
		end
	end
	vote.Status = "Accepted"
	return true, nil
end

-- Un „nu": anuleaza pentru toti.
function RematchVote.decline(vote: Vote, userId: number, now: number): (boolean, string?)
	if RematchVote.tick(vote, now) ~= "Pending" then
		return false, "CLOSED"
	end
	if not seated(vote, userId) then
		return false, "NOT_SEATED"
	end
	cancel(vote, "DECLINED", userId)
	return true, nil
end

--[[
	Cineva a plecat de la masa. Nu mai poate juca revansa, deci ea nu mai are
	loc — chiar daca acceptase.
]]
function RematchVote.leave(vote: Vote, userId: number, now: number): boolean
	if RematchVote.tick(vote, now) ~= "Pending" then
		return false
	end
	if not seated(vote, userId) then
		return false
	end
	cancel(vote, "LEFT", userId)
	return true
end

-- Cati au spus da, si cat timp mai are votul — pentru bara care se goleste.
function RematchVote.progress(vote: Vote, now: number): (number, number)
	local count = 0
	for _, seat in vote.Seats do
		if vote.Accepted[seat] then
			count += 1
		end
	end
	return count, math.max(0, vote.Deadline - now)
end

--[[
	Ordinea la masa noua: se rotesc cu `step` locuri, ca sa nu inceapa mereu
	acelasi.

	`step` e cat are o echipa. In 1v1 si in modurile de trei-patru e unu: primul
	trece la coada. In 2v2 e doi: echipele raman aceleasi — locurile 1-2 sunt o
	echipa, 3-4 cealalta — dar incepe cealalta echipa.
]]
function RematchVote.rotate<T>(seats: { T }, step: number): { T }
	local count = #seats
	local rotated = {}
	if count == 0 then
		return rotated
	end
	local shift = step % count
	for index = 1, count do
		rotated[index] = seats[(index - 1 + shift) % count + 1]
	end
	return rotated
end

--[[
	Seria dintre aceiasi jucatori. `Games` numara meciurile jucate, iar `Wins`
	victoriile fiecaruia, dupa userId scris ca text — asa trece si prin retea,
	unde o tabela cu chei numerice rare nu ajunge intreaga.
]]
export type Series = {
	Games: number,
	Wins: { [string]: number },
}

function RematchVote.newSeries(): Series
	return { Games = 0, Wins = {} }
end

-- Un meci incheiat intra in serie. `winners` sunt userId-urile echipei castigatoare.
function RematchVote.record(series: Series, winners: { number })
	series.Games += 1
	for _, userId in winners do
		local key = tostring(userId)
		series.Wins[key] = (series.Wins[key] or 0) + 1
	end
end

--[[
	„Rematch #3 · 2–1": al treilea meci dintre ei, doua la unu. `nil` inainte
	de prima revansa.

	`sides` sunt taberele, cu a jucatorului local prima: in 1v1 cate un om, in
	2v2 cate o echipa, in modurile de trei-patru cate un om. O tabara are cate
	victorii are cel mai bun dintre ai ei — coechipierii castiga impreuna.
]]
function RematchVote.label(series: Series, sides: { { number } }): string?
	if series.Games < 2 then
		return nil
	end

	local scores = {}
	for _, side in sides do
		local best = 0
		for _, userId in side do
			best = math.max(best, series.Wins[tostring(userId)] or 0)
		end
		table.insert(scores, tostring(best))
	end

	return string.format("Rematch #%d · %s", series.Games, table.concat(scores, "–"))
end

return RematchVote
