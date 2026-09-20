--!strict
--[[
	Loadout — cu ce joaca un jucator din tot ce detine.

	`Inventory` raspunde la "ce ai", `Loadout` la "cu ce joci". Sunt doua
	intrebari diferite: poti avea opt baricade cumparate, dar cazi cu una
	singura, si aia trebuie sa se vada pe masa, la tine si la ceilalti.

	Modulul e pur, ca tot ce sta in `src/shared/`: numai siruri si verificari.
	De aceea il citesc la fel serverul care primeste cererea de echipare,
	clientul care deseneaza magazinul si fantoma de sub cursor, si testele.

	Alegerea calatoreste prin retea ca **atribut pe `Player`**, nu pe un canal
	al ei. Serverul o scrie o data, iar de acolo o citesc toti deodata: arena
	care ridica zidul, clientul proprietarului care isi deseneaza fantoma si
	clientii celorlalti, care vad acelasi zid. Un remote ar fi ajuns doar la
	proprietar, si ar fi cerut oricum un al doilea drum pentru restul — adica
	doua adevaruri despre acelasi lucru. Numele atributului se scrie aici, o
	singura data, exact ca numele canalelor in `Remotes`.

	Ce se intampla cand alegerea nu se poate onora — un id retras din catalog,
	sau unul pe care jucatorul nu-l detine — nu e o eroare: se cade pe obiectul
	de start. Un zid nedesenat ar face tabla de necitit, iar un jucator fara
	podium ar sta in aer.
]]

local Catalog = require(script.Parent.Catalog)

local Loadout = {}

type Kind = Catalog.Kind

--[[
	Ce poarta un jucator, pe feluri. Cheile sunt felurile din `Catalog`, deci
	`{ Barricade = "dragon", Podium = "wood" }`.
]]
export type Set = { [string]: string }

--[[
	Numele atributului sub care sta alegerea pe `Player`.

	Poarta felul in nume din acelasi motiv pentru care il poarta si cheia de
	inventar: baricada `dragon` si podiumul `dragon` sunt doua obiecte diferite,
	si se echipeaza separat.
]]
function Loadout.attribute(kind: Kind): string
	return "Equipped" .. kind
end

-- Ce poarta cineva care n-a ales inca nimic: obiectele de start.
function Loadout.defaults(): Set
	local set: Set = {}
	for _, kind: Kind in Catalog.Kinds do
		set[kind] = Catalog.default(kind)
	end
	return set
end

--[[
	Poate echipa?

	Intoarce `true` singur, sau `false` plus motivul, ca `Catalog.canBuy`:
	codul scurt e pentru server, textul pentru om il alege interfata. Aceeasi
	functie o cheama si serverul inainte sa scrie atributul, si magazinul cand
	isi deseneaza butonul — altfel butonul ar putea fi aprins peste un refuz.
]]
function Loadout.canEquip(owned: { [string]: boolean }?, kind: Kind, id: string): (boolean, string?)
	if not Catalog.get(kind, id) then
		return false, "UNKNOWN"
	end
	if not Catalog.owns(owned, kind, id) then
		return false, "LOCKED"
	end
	return true
end

--[[
	Alegerea, adusa la ce se poate purta chiar acum.

	Se cheama pe ce vine din salvare sau din retea, adica pe ceva ce nu s-a
	verificat inca. Un id necunoscut sau nedetinut nu lasa jucatorul fara
	obiect: intoarce obiectul de start.
]]
function Loadout.sanitize(owned: { [string]: boolean }?, kind: Kind, id: any): string
	if typeof(id) == "string" and Loadout.canEquip(owned, kind, id) then
		return id
	end
	return Catalog.default(kind)
end

--[[
	Alegerea intreaga, asa cum vine din salvare.

	Aici se verifica doar ca obiectul *exista*, nu si ca e detinut, si e o
	deosebire voita. Salvarea si inventarul se citesc din DataStore pe doua
	fire, si nu se stie care raspunde primul; verificata cu un inventar care
	inca n-a sosit, orice alegere ar cadea inapoi pe stejar exact la oamenii
	care si-au cumparat altceva. Ce s-a salvat echipat a fost odata detinut, iar
	un obiect nu se ia niciodata inapoi — vezi `Inventory`.

	Ce lipseste ramane obiectul de start, deci raspunsul are intotdeauna cate un
	id pentru fiecare fel: cine il citeste nu are de ce sa se intrebe daca
	lipseste ceva.
]]
function Loadout.restore(set: any): Set
	local clean: Set = {}
	for _, kind: Kind in Catalog.Kinds do
		local chosen = if typeof(set) == "table" then (set :: any)[kind] else nil
		clean[kind] = if typeof(chosen) == "string" and Catalog.get(kind, chosen)
			then chosen
			else Catalog.default(kind)
	end
	return clean
end

return Loadout
