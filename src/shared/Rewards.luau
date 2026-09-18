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
	Cat iese dintr-un meci incheiat.

	`WIN` ia participarea plus bonusul; `LOSS` ia doar participarea. Numerele
	stau in `GameConfig.Rewards`, ca toate celelalte numere reglabile.
]]
function Rewards.forMatch(outcome: Outcome): number
	local settings = GameConfig.Rewards
	if outcome == "WIN" then
		return settings.Participation + settings.WinBonus
	end
	return settings.Participation
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
