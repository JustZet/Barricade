--!strict
--[[
	MoveCommentary — ce merita strigat dupa o mutare.

	Primeste starea de dinainte, starea de dupa si actiunea, si spune ce s-a
	intamplat in cuvinte de meci: blocaj mare, saritura, un pas pana la tinta.
	Intoarce doar date — id-ul din `Callouts`, cine, pe cine, cat si unde. Textul
	si culorile le alege clientul, din perspectiva lui.

	Ruleaza pe server, o data per actiune, iar verdictul pleaca in evenimentul
	care exista deja. Asa toti de la masa vad acelasi lucru: doi clienti care
	l-ar socoti fiecare pentru el ar putea sa nu fie de acord.

	Nu rescrie nimic din reguli. Distantele vin din `BoardState.getDistanceToGoal`,
	iar saritura se recunoaste din cat de departe a ajuns pionul, nu refacand
	`MovementRules`: o mutare aplicata e deja legala, trebuie doar citita.

	„Adversar" inseamna alta echipa. In 2v2 coechipierul nu se numara: o
	baricada care il incetineste pe el nu e un blocaj, e o greseala.
]]

local BoardState = require(script.Parent.BoardState)
local Callouts = require(script.Parent.Callouts)
local GameConfig = require(script.Parent.GameConfig)
local Types = require(script.Parent.Types)

type BoardState = Types.BoardState
type Cell = Types.Cell
type Wall = Types.Wall

export type Action = {
	Kind: "Move" | "Wall",
	Slot: number,
	-- Doar pentru `Move`.
	From: Cell?,
	To: Cell?,
	-- Doar pentru `Wall`.
	Wall: Wall?,
}

export type Callout = {
	Id: string,
	Tier: number,
	-- Cine a facut actiunea.
	Slot: number,
	-- Pe cine a lovit, cand e cineva anume.
	Target: number?,
	-- Numarul din text, cand are unul.
	Amount: number?,
	-- Unde se arata: pionul, sau coltul baricadei.
	Cell: Cell,
	-- Cand callout-ul tine de o baricada, ea insasi; clientul il asaza pe ea.
	Wall: Wall?,
	--[[
		Al catelea blocaj la rand al aceluiasi jucator, de la doi in sus. Pus
		doar pe blocajul actiunii; rama tablei il arata ca „x2", „x3".
	]]
	Streak: number?,
}

--[[
	Ce tine minte meciul intre actiuni. Traieste in `Match`, nu in motor: aici
	doar se citeste si se aduce la zi, ca sa poata fi testat.
]]
export type History = {
	-- Cat de in urma a fost fiecare, cel mai rau, de cand n-a mai condus.
	Deficit: { [number]: number },
	-- Ce s-a strigat deja o data pe meci si nu se mai repeta.
	Shown: { [string]: boolean },
	--[[
		Cate blocaje la rand are fiecare. Creste la fiecare baricada care
		strica drumul cuiva, si cade la zero la prima actiune a lui care nu o
		face — o mutare, sau o baricada pusa degeaba.
	]]
	Streak: { [number]: number },
}

local SETTINGS = GameConfig.Callouts

-- Ce se numara la seria de blocaje.
local BLOCKS = {
	BLOCK = true,
	BLOCK_BIG = true,
	BLOCK_HUGE = true,
	BLOCK_MEGA = true,
	DOUBLE_BLOCK = true,
}

local MoveCommentary = {}

function MoveCommentary.newHistory(): History
	return { Deficit = {}, Shown = {}, Streak = {} }
end

-- Are actiunea asta vreun blocaj? E ce tine seria in viata.
function MoveCommentary.isBlock(id: string): boolean
	return BLOCKS[id] == true
end

-- Cei inca in joc: in ordinea turelor si neajunsi. Cine a plecat a iesit din ea.
local function activeSlots(state: BoardState): { number }
	local slots = {}
	for _, slot in state.TurnOrder do
		local player = state.Players[slot]
		if player and not player.Finished then
			table.insert(slots, slot)
		end
	end
	return slots
end

local function distances(state: BoardState): { [number]: number }
	local result: { [number]: number } = {}
	for _, slot in activeSlots(state) do
		local steps = BoardState.getDistanceToGoal(state, slot)
		if steps ~= nil then
			result[slot] = steps
		end
	end
	return result
end

local function opponentsOf(state: BoardState, slot: number): { number }
	local team = state.Players[slot].Team
	local list = {}
	for _, other in activeSlots(state) do
		if state.Players[other].Team ~= team then
			table.insert(list, other)
		end
	end
	return list
end

--[[
	Cu cati pasi e in urma celui mai bun adversar. Negativ inseamna ca e in
	fata, zero ca e la egalitate. `nil` cand n-are cu cine se compara.
]]
local function deficitOf(state: BoardState, dist: { [number]: number }, slot: number): number?
	local own = dist[slot]
	if own == nil then
		return nil
	end
	local best: number? = nil
	for _, other in opponentsOf(state, slot) do
		local theirs = dist[other]
		if theirs ~= nil and (best == nil or theirs < best) then
			best = theirs
		end
	end
	if best == nil then
		return nil
	end
	return own - best
end

-- Toti aproape de tinta si la un pas unul de altul.
local function isNeckAndNeck(state: BoardState, dist: { [number]: number }): boolean
	local slots = activeSlots(state)
	if #slots < 2 then
		return false
	end
	local low, high = math.huge, -math.huge
	for _, slot in slots do
		local d = dist[slot]
		if d == nil or d > SETTINGS.NeckMaxDistance then
			return false
		end
		low, high = math.min(low, d), math.max(high, d)
	end
	return high - low <= SETTINGS.NeckMaxSpread
end

-- Niciun adversar nu mai are baricade, iar el e in fata tuturor.
local function isUnstoppable(state: BoardState, dist: { [number]: number }, slot: number): boolean
	local opponents = opponentsOf(state, slot)
	if #opponents == 0 then
		return false
	end
	for _, other in opponents do
		if state.Players[other].BarricadesRemaining > 0 then
			return false
		end
	end
	local deficit = deficitOf(state, dist, slot)
	return deficit ~= nil and deficit < 0
end

local function blockId(amount: number): string?
	if amount >= SETTINGS.BlockMegaMin then
		return "BLOCK_MEGA"
	elseif amount >= SETTINGS.BlockHugeMin then
		return "BLOCK_HUGE"
	elseif amount >= SETTINGS.BlockBigMin then
		return "BLOCK_BIG"
	elseif amount >= SETTINGS.BlockMin then
		return "BLOCK"
	end
	return nil
end

local function copyCell(cell: Cell): Cell
	return { X = cell.X, Y = cell.Y }
end

--[[
	Callout-urile unei actiuni, cel mai important primul, cel mult
	`MaxPerAction`.

	`history` e optional. Fara el, revenirea se masoara doar fata de starea de
	dinainte, iar ce se strig o data pe meci se strig la fiecare trecere.
]]
function MoveCommentary.analyze(
	before: BoardState,
	after: BoardState,
	action: Action,
	history: History?
): { Callout }
	local result: { Callout } = {}
	if after.Status == "FINISHED" then
		return result
	end

	local slot = action.Slot
	local author = after.Players[slot]
	if not author then
		return result
	end

	local distBefore = distances(before)
	local distAfter = distances(after)
	local here = copyCell(author.Position)

	type Extra = { Target: number?, Amount: number?, Cell: Cell?, Wall: Wall? }
	local function add(id: string, fields: Extra?)
		local extra: Extra = fields or {}
		table.insert(result, {
			Id = id,
			Tier = Callouts.All[id].Tier,
			Slot = slot,
			Target = extra.Target,
			Amount = extra.Amount,
			Cell = extra.Cell or here,
			Wall = extra.Wall,
		})
	end

	if action.Kind == "Wall" and action.Wall then
		local placed = action.Wall
		local wall: Wall = { X = placed.X, Y = placed.Y, Orientation = placed.Orientation }
		local corner: Cell = { X = placed.X, Y = placed.Y }

		local worst, victim, slowed = 0, nil :: number?, 0
		for _, other in opponentsOf(after, slot) do
			local was, now = distBefore[other], distAfter[other]
			if was ~= nil and now ~= nil then
				local added = now - was
				if added >= SETTINGS.DoubleBlockMin then
					slowed += 1
				end
				if added > worst then
					worst, victim = added, other
				end
			end
		end

		local id = blockId(worst)
		if id then
			add(id, { Target = victim, Amount = worst, Cell = corner, Wall = wall })
		end
		if slowed >= 2 then
			add("DOUBLE_BLOCK", { Cell = corner, Wall = wall })
		end
		if author.BarricadesRemaining == 0 then
			add("LAST_WALL", { Cell = corner, Wall = wall })
		end
	elseif action.Kind == "Move" and action.From and action.To then
		local dx = math.abs(action.To.X - action.From.X)
		local dy = math.abs(action.To.Y - action.From.Y)
		if dx + dy == 2 and (dx == 0 or dy == 0) then
			-- Peste cine: pionul care statea la mijloc, inainte de saritura.
			local middle: Cell =
				{ X = (action.From.X + action.To.X) / 2, Y = (action.From.Y + action.To.Y) / 2 }
			local jumped: number? = nil
			for other, player in before.Players do
				if
					other ~= slot
					and player.Position.X == middle.X
					and player.Position.Y == middle.Y
				then
					jumped = other
				end
			end
			add("JUMP", { Target = jumped })
		elseif dx == 1 and dy == 1 then
			add("SIDESTEP")
		end

		if distAfter[slot] == 1 and distBefore[slot] ~= 1 then
			add("ONE_STEP")
		end
	end

	--[[
		Clasamentul. Preluarea conducerii cere o depasire, nu doar un pas: de la
		cel putin unu in urma la cel putin unu in fata. Altfel, in 1v1 cine muta
		primul ar „prelua conducerea" la fiecare tura, doar fiindca a mutat.
	]]
	local deficitBefore = deficitOf(before, distBefore, slot)
	local deficitAfter = deficitOf(after, distAfter, slot)
	local worstDeficit = deficitBefore
	local remembered = history and history.Deficit[slot]
	if remembered ~= nil and (worstDeficit == nil or remembered > worstDeficit) then
		worstDeficit = remembered
	end

	if
		deficitAfter ~= nil
		and deficitAfter <= 0
		and worstDeficit ~= nil
		and worstDeficit >= SETTINGS.ComebackDeficit
	then
		add("COMEBACK")
	elseif
		deficitAfter ~= nil
		and deficitAfter < 0
		and deficitBefore ~= nil
		and deficitBefore > 0
	then
		add("TAKE_LEAD")
	end

	local shown: { [string]: boolean } = if history then history.Shown else {}
	if
		isNeckAndNeck(after, distAfter)
		and not isNeckAndNeck(before, distBefore)
		and not shown.NECK_AND_NECK
	then
		add("NECK_AND_NECK")
	end

	local unstoppableKey = "UNSTOPPABLE:" .. slot
	if
		isUnstoppable(after, distAfter, slot)
		and not isUnstoppable(before, distBefore, slot)
		and not shown[unstoppableKey]
	then
		add("UNSTOPPABLE")
	end

	table.sort(result, function(a: Callout, b: Callout): boolean
		local pa, pb = Callouts.All[a.Id].Priority, Callouts.All[b.Id].Priority
		if pa ~= pb then
			return pa > pb
		end
		return a.Id < b.Id
	end)

	while #result > SETTINGS.MaxPerAction do
		table.remove(result)
	end

	--[[
		Seria: primul blocaj din lista poarta numarul, daca e al doilea la rand
		sau mai departe. Se pune dupa taiere, ca sa ajunga pe unul care chiar
		pleaca spre clienti.
	]]
	local previous = if history then history.Streak[slot] or 0 else 0
	for _, callout in result do
		if MoveCommentary.isBlock(callout.Id) then
			if previous + 1 >= 2 then
				callout.Streak = previous + 1
			end
			break
		end
	end

	return result
end

--[[
	Aduce istoria la zi dupa o actiune, cu starea de dupa ea si ce s-a strigat.

	Fiecare jucator isi tine cel mai mare deficit de cand n-a mai condus; cand
	ajunge din nou in fata sau la egalitate, se sterge. De aici vine COMEBACK:
	o revenire facuta in mai multe ture nu se vede comparand doar doua stari
	vecine.

	`actor` e cine a facut actiunea: seria lui creste daca a blocat pe cineva,
	si cade la zero daca nu.
]]
function MoveCommentary.record(
	history: History,
	after: BoardState,
	callouts: { Callout },
	actor: number?
)
	if actor ~= nil then
		local blocked = false
		for _, callout in callouts do
			if callout.Slot == actor and MoveCommentary.isBlock(callout.Id) then
				blocked = true
			end
		end
		history.Streak[actor] = if blocked then (history.Streak[actor] or 0) + 1 else 0
	end

	local dist = distances(after)
	for _, slot in activeSlots(after) do
		local deficit = deficitOf(after, dist, slot)
		if deficit == nil or deficit <= 0 then
			history.Deficit[slot] = nil
		else
			history.Deficit[slot] = math.max(history.Deficit[slot] or 0, deficit)
		end
	end

	for _, callout in callouts do
		if callout.Id == "NECK_AND_NECK" then
			history.Shown.NECK_AND_NECK = true
		elseif callout.Id == "UNSTOPPABLE" then
			history.Shown["UNSTOPPABLE:" .. callout.Slot] = true
		end
	end
end

return MoveCommentary
