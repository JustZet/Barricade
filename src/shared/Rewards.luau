--!strict
--[[
	Rewards — cat iei pentru un meci.

	E o regula, deci sta in motorul pur, langa celelalte: se poate rula de teste
	fara Studio si raspunde la fel pe server si pe client. Clientul nu o
	foloseste ca sa-si dea bani — banii ii da serverul — ci ca sa poata *spune*
	dinainte cat face un meci, fara sa existe doua socoteli care se pot
	contrazice.

	Nu stie ce e un Player, ce e un DataStore si ce e un meci. Primeste un
	rezultat, intoarce un numar. Din cauza asta poate fi folosita oriunde: la
	final de partida, intr-un ecran care explica recompensele, sau intr-un test.

	Se plateste si la pierdere, si asta e o hotarare, nu o scapare. Un joc pe
	ture se pierde des si din motive care nu tin de tine — cineva se deconecteaza,
	iti expira ceasul, adversarul joaca mai bine. Daca pierderea n-ar aduce
	nimic, al doilea meci pierdut la rand ar fi motiv sa inchizi jocul. Castigul
	ramane vizibil mai bun, doar ca partea de jos nu e zero.
]]

local GameConfig = require(script.Parent.GameConfig)

local Rewards = {}

export type Outcome = "WIN" | "LOSS"

--[[
	Bonusurile sociale ale unui jucator, aflate de server si date aici ca
	argument. `Rewards` nu stie singur nimic despre grupuri sau prieteni.
]]
export type Modifiers = {
	-- E in grupul jocului?
	Group: boolean?,
	-- E la masa cu macar un prieten, adversar sau coechipier?
	Friend: boolean?,
}

export type Line = {
	Kind: "Win" | "Played" | "Group" | "Friend",
	-- Ce scrie pe ecranul de final, in engleza.
	Label: string,
	Coins: number,
}

export type Breakdown = {
	Lines: { Line },
	Total: number,
}

--[[
	Recompensa desfacuta pe randuri: baza, apoi fiecare bonus.

	Bonusurile se socotesc din baza, nu unul din altul, si se aduna pana la
	`SocialBonusCap`: ce ar trece de plafon se taie din ultimul care a intrat.
	Fiecare rand se rotunjeste la banut intreg, ca pe ecran sa se adune exact
	ce se vede.
]]
function Rewards.breakdown(outcome: Outcome, modifiers: Modifiers?): Breakdown
	local settings = GameConfig.Rewards
	local social = GameConfig.Social
	local base = if outcome == "WIN"
		then settings.Participation + settings.WinBonus
		else settings.Participation

	local lines: { Line } = {
		{
			Kind = if outcome == "WIN" then "Win" else "Played",
			Label = if outcome == "WIN" then "Win" else "Match played",
			Coins = base,
		},
	}

	--[[
		Procentele se socotesc in zecimi de mii, ca numere intregi. In virgula
		mobila 0.20 - 0.10 iese 0.0999…, iar un bonus de 7.5 s-ar rotunji la 7 in
		loc de 8 — pe ecran s-ar vedea doua bonusuri egale cu sume diferite.
	]]
	local function points(share: number): number
		return math.floor(share * 10000 + 0.5)
	end

	local mods: Modifiers = modifiers or {}
	local room = points(social.SocialBonusCap)
	local function add(kind: "Group" | "Friend", label: string, share: number)
		local used = math.min(points(share), room)
		if used <= 0 then
			return
		end
		room -= used
		local coins = math.floor(base * used / 10000 + 0.5)
		if coins > 0 then
			table.insert(lines, { Kind = kind, Label = label, Coins = coins })
		end
	end
	if mods.Group then
		add("Group", "Group bonus", social.GroupBonus)
	end
	if mods.Friend then
		add("Friend", "Playing with a friend", social.FriendBonus)
	end

	local total = 0
	for _, line in lines do
		total += line.Coins
	end
	return { Lines = lines, Total = total }
end

--[[
	Cat iese dintr-un meci incheiat.

	`WIN` ia participarea plus bonusul; `LOSS` ia doar participarea. Numerele
	stau in `GameConfig.Rewards`, ca toate celelalte numere reglabile. Fara
	modificatori, e exact socoteala de dinaintea bonusurilor sociale.
]]
function Rewards.forMatch(outcome: Outcome, modifiers: Modifiers?): number
	return Rewards.breakdown(outcome, modifiers).Total
end

--[[
	Rezultatul unui slot, citit dintr-o stare incheiata.

	Se uita la echipa, nu la jucator: in 2v2 castiga amandoi din echipa care a
	ajuns prima, nu doar cel care a facut ultimul pas. Daca meciul n-a numit
	nicio echipa — s-a anulat, au plecat toti — nu exista castigator, deci toata
	lumea iese pe `LOSS` si isi ia participarea.
]]
function Rewards.outcomeFor(winningTeam: number?, team: number): Outcome
	if winningTeam ~= nil and winningTeam == team then
		return "WIN"
	end
	return "LOSS"
end

return Rewards
