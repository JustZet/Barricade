--!strict
--[[
	FreePlayRules — ce se intampla cand numaratoarea de pe soclu ajunge la zero.

	E o regula, nu o bucata de server, si de aceea sta aici: in motorul pur, unde
	poate fi rulata de teste fara Studio. Serverul aduce ceasul si jucatorii;
	decizia o ia functia asta, si ea nu stie nici ce e un Player, nici ce e un
	soclu.

	Cele patru cazuri, in ordinea in care se cerne:

	  soclul plin        -> START, si numaratoarea nu mai conteaza
	  zero, destui       -> START
	  zero, prea putini  -> RESTART, fiindca n-are cu cine
	  in rest            -> WAIT

	Soclul plin se verifica primul dinadins. Cand nu mai e loc pentru inca
	cineva, a astepta nu mai are niciun rost — si ar fi ciudat sa stai pe un loc
	plin uitandu-te la un ceas care numara pentru un jucator care n-are unde sa
	incapa.
]]

local FreePlayRules = {}

export type Decision = "WAIT" | "START" | "RESTART"

--[[
	`waiting` — cati stau pe soclu acum.
	`minimum` — de la cati in sus se poate juca.
	`capacity` — cati incap.
	`remaining` — cate secunde mai are numaratoarea.
]]
function FreePlayRules.decide(
	waiting: number,
	minimum: number,
	capacity: number,
	remaining: number
): Decision
	if waiting >= capacity then
		return "START"
	end

	if remaining > 0 then
		return "WAIT"
	end

	if waiting >= minimum then
		return "START"
	end

	--[[
		Zero cu prea putini nu e un esec, ci inca o tura de asteptare. Daca
		numaratoarea s-ar opri, cine sta pe soclu n-ar mai avea de unde sti daca
		jocul il mai asteapta sau l-a uitat acolo.
	]]
	return "RESTART"
end

return FreePlayRules
