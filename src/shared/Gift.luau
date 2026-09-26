--!strict
--[[
	Gift — obiectul primit pentru un like, si regula care il da.

	**Like-ul nu se poate verifica.** Roblox nu expune votul nimanui: nu exista
	nicio metoda despre like-uri sau voturi, nici pe server, nici pe client — se
	pot citi doar totalurile publice ale unei experiente, nu ce a apasat un om
	anume. Toate jocurile care scriu "like for a reward" dau recompensa oricui
	apasa butonul; asta e intelegerea, si e bine sa fie spusa pe fata aici, in
	cod, nu descoperita peste un an de cineva care cauta verificarea.

	Ce ramane e increderea, si un indemn: jocul cere un like si da darul. Costa
	zero si urca ratingul, iar ratingul e ce hotaraste cui ii mai e aratat jocul.

	Regula sta insa **intr-un singur loc**, tocmai ca sa poata deveni intr-o zi
	altceva — "e in grupul nostru", "are insigna de zece meciuri" — fara sa se
	umble si prin lobby, si prin server. Placa din lume si serverul care da
	obiectul intreaba amandoua aici.

	Modulul e pur, ca tot ce sta in `src/shared/`: doar id-uri si o socoteala.
	Verificarile care cer API-ul Roblox — apartenenta la grup, insignele — se fac
	pe server si se aduc aici ca raspuns, nu se cheama de aici.
]]

local Catalog = require(script.Parent.Catalog)

local Gift = {}

-- Ce se da. Un singur obiect, deocamdata.
Gift.Item = {
	Kind = "Barricade" :: Catalog.Kind,
	Id = "dragon",
}

-- Ce scrie pe placa cat timp darul nu e al tau.
Gift.Call = "LIKE TO UNLOCK"

-- Ce scrie pe panglica de sus a placii.
Gift.Title = "GIFT"

-- Cheia sub care obiectul intra in inventar.
function Gift.key(): string
	return Catalog.key(Gift.Item.Kind, Gift.Item.Id)
end

--[[
	Poate jucatorul asta sa ceara darul?

	Azi: oricine nu-l are deja. Primeste `owned` — ce detine — fiindca singura
	conditie de acum se citeste din el; cand va fi si una din afara, serverul o
	va socoti acolo si o va aduce ca al doilea argument.
]]
function Gift.canClaim(owned: { [string]: boolean }): boolean
	return not Catalog.owns(owned, Gift.Item.Kind, Gift.Item.Id)
end

return Gift
