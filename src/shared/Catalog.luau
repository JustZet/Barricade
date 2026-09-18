--!strict
--[[
	Catalog — ce poate detine un jucator, intr-un singur loc.

	Aici stau doar faptele comerciale: ce id-uri exista, care vin din start si
	care se cumpara. Cum arata un obiect nu se scrie aici — culorile si mesh-ul
	unei baricade raman in `Skins`, iar modelele in `ReplicatedStorage.Assets`.
	Asa, cand se schimba aspectul unui skin, se schimba peste tot deodata: si in
	meci, si in vitrina din lobby.

	Modulul e pur, ca tot ce sta in `src/shared/`: numai numere si siruri. De
	aceea poate fi citit la fel de serverul care valideaza o cumparare, de
	clientul care deseneaza magazinul si de teste.

	`ProductId = 0` inseamna "inca nelegat de un produs Roblox", exact ca
	`PlaceSound = 0` din `Skins`. Cat timp e 0, obiectul nu e de vanzare: nu e o
	eroare, e starea normala pana cand produsele chiar exista pe platforma.
]]

local Catalog = {}

export type Kind = "Barricade" | "Podium"

export type Item = {
	Id: string,
	Kind: Kind,
	-- Pretul afisat, in Robux. 0 cat timp obiectul nu e inca de vanzare.
	Price: number,
	--[[
		Pretul in banutii castigati jucand. 0 = nu se vinde pe banuti.

		E o a doua cale spre acelasi obiect, nu un al doilea obiect: cine are
		rabdare il stringe, cine n-are il cumpara. De aceea pretul sta langa cel
		in Robux, pe aceeasi linie, si nu intr-o a doua lista care s-ar putea
		desincroniza de asta.
	]]
	Coins: number,
	-- Produsul Roblox din spatele cumpararii. 0 = nelegat inca.
	ProductId: number,
	-- Obiectele de start le are oricine, fara sa cumpere nimic.
	Default: boolean,
}

--[[
	Ordinea canonica a id-urilor: de la cele sobre la cele spectaculoase, ca un
	jucator nou sa nu deschida magazinul direct pe cel mai incarcat. E singura
	lista de id-uri din proiect; `Skins.Order` o imprumuta de aici.
]]
Catalog.Order = { "wood", "castle", "tree", "dragon", "energy", "thunder", "crystal", "portal" }

type Listing = { Price: number, Coins: number, ProductId: number, Default: boolean? }

--[[
	Preturile se scriu pe linii, ca tabelul asta sa ramana lucrul pe care il
	deschizi cand pui un obiect la vanzare. Un obiect nou = o linie aici si un
	model in `ReplicatedStorage.Assets`, nimic altundeva.

	Preturile in banuti urca in ordinea din `Order`, adica de la sobru la
	spectaculos. Podiumurile costa ceva mai putin decat baricadele: o baricada se
	vede la fiecare mutare a fiecarui jucator, un podium doar intre meciuri.
]]
local LISTINGS: { [string]: { [string]: Listing } } = {
	Barricade = {
		wood = { Price = 0, Coins = 0, ProductId = 0, Default = true },
		castle = { Price = 0, Coins = 300, ProductId = 0 },
		tree = { Price = 0, Coins = 350, ProductId = 0 },
		dragon = { Price = 0, Coins = 600, ProductId = 0 },
		energy = { Price = 0, Coins = 500, ProductId = 0 },
		thunder = { Price = 0, Coins = 650, ProductId = 0 },
		crystal = { Price = 0, Coins = 800, ProductId = 0 },
		portal = { Price = 0, Coins = 1000, ProductId = 0 },
	},

	Podium = {
		wood = { Price = 0, Coins = 0, ProductId = 0, Default = true },
		castle = { Price = 0, Coins = 200, ProductId = 0 },
		tree = { Price = 0, Coins = 250, ProductId = 0 },
		dragon = { Price = 0, Coins = 400, ProductId = 0 },
		energy = { Price = 0, Coins = 350, ProductId = 0 },
		thunder = { Price = 0, Coins = 450, ProductId = 0 },
		crystal = { Price = 0, Coins = 550, ProductId = 0 },
		portal = { Price = 0, Coins = 700, ProductId = 0 },
	},
}

local KINDS: { Kind } = { "Barricade", "Podium" }
Catalog.Kinds = KINDS

--[[
	Tabelul gata de folosit. Se construieste o data, la incarcare, si tot atunci
	se verifica: un id din `Order` fara linie de pret, sau doua obiecte de start
	in acelasi fel, sunt greseli de configurare care trebuie sa cada la pornire,
	nu sa se vada ca o vitrina goala peste trei saptamani.
]]
local items: { [string]: { [string]: Item } } = {}
local defaults: { [string]: string } = {}

for _, kind: Kind in KINDS do
	local listings = LISTINGS[kind]
	assert(listings, string.format("Catalog: felul %q nu are preturi", kind))

	local built: { [string]: Item } = {}
	for _, id in Catalog.Order do
		local listing = listings[id]
		assert(listing, string.format("Catalog: %s/%s nu are linie de pret", kind, id))

		built[id] = {
			Id = id,
			Kind = kind,
			Price = listing.Price,
			Coins = listing.Coins,
			ProductId = listing.ProductId,
			Default = listing.Default == true,
		}

		if listing.Default == true then
			assert(
				defaults[kind] == nil,
				string.format(
					"Catalog: %s are doua obiecte de start (%s si %s)",
					kind,
					tostring(defaults[kind]),
					id
				)
			)
			defaults[kind] = id
		end
	end

	for id in listings do
		assert(built[id], string.format("Catalog: %s/%s are pret, dar nu e in Order", kind, id))
	end

	assert(defaults[kind], string.format("Catalog: %s nu are niciun obiect de start", kind))
	items[kind] = built
end

Catalog.Items = items

-- Obiectul cerut, sau `nil` daca id-ul nu exista in felul asta.
function Catalog.get(kind: Kind, id: string?): Item?
	local built = items[kind]
	if not built or not id then
		return nil
	end
	return built[id]
end

-- Toate obiectele unui fel, in ordinea din vitrina.
function Catalog.list(kind: Kind): { Item }
	local out = {}
	local built = items[kind]
	if not built then
		return out
	end
	for _, id in Catalog.Order do
		table.insert(out, built[id])
	end
	return out
end

-- Obiectul cu care porneste oricine.
function Catalog.default(kind: Kind): string
	return assert(defaults[kind], "Catalog: fel necunoscut " .. kind)
end

--[[
	Cheia sub care se tine minte un obiect cumparat.

	Felul intra in cheie pentru ca id-urile se repeta: exista o baricada `dragon`
	si un podium `dragon`, si sunt doua obiecte diferite, cu preturi diferite.
	Fara fel in cheie, cumpararea unuia l-ar da pe gratis si pe celalalt.
]]
function Catalog.key(kind: Kind, id: string): string
	return kind .. ":" .. id
end

--[[
	Un obiect cerut din retea, verificat.

	Primeste ce a trimis clientul, fara sa presupuna nimic despre el, si intoarce
	obiectul din catalog sau `nil`. Serverul nu umbla niciodata cu un fel venit
	de afara: primeste direct obiectul gasit, cu felul, id-ul si pretul lui
	adevarate. Verificarea sta aici, langa lista felurilor, ca sa nu existe un al
	doilea loc care sa uite sa se actualizeze cand apare un fel nou.
]]
function Catalog.resolve(kind: any, id: any): Item?
	if typeof(id) ~= "string" then
		return nil
	end
	for _, known: Kind in KINDS do
		if kind == known then
			return Catalog.get(known, id)
		end
	end
	return nil
end

-- Cheia unui obiect deja gasit in catalog.
function Catalog.keyOf(item: Item): string
	return Catalog.key(item.Kind, item.Id)
end

-- Ca `canBuy`, dar pentru un obiect deja gasit.
function Catalog.canBuyItem(
	item: Item,
	balance: number,
	owned: { [string]: boolean }?
): (boolean, string?)
	return Catalog.canBuy(item.Kind, item.Id, balance, owned)
end

--[[
	Detine jucatorul obiectul?

	`owned` e multimea cheilor cumparate, asa cum vine din salvare. Obiectele de
	start nu apar acolo niciodata: raspunsul pentru ele e "da" chiar si inainte
	ca jucatorul sa aiba vreo salvare, ca un cont nou sa nu ramana fara nimic de
	folosit.
]]
function Catalog.owns(owned: { [string]: boolean }?, kind: Kind, id: string): boolean
	local item = Catalog.get(kind, id)
	if not item then
		return false
	end
	if item.Default then
		return true
	end
	return owned ~= nil and owned[Catalog.key(kind, id)] == true
end

--[[
	Poate cumpara, pe banuti?

	Intoarce `true` singur, sau `false` plus motivul. Motivul e un cod scurt, nu
	o propozitie: textul pentru om se alege in interfata, care stie in ce limba
	vorbeste, iar serverul il foloseste doar ca sa spuna de ce a refuzat.

	Aceeasi functie o cheama si serverul inainte sa ia banii, si clientul ca sa
	stie cum sa deseneze butonul. Daca ar fi doua, butonul ar putea fi aprins
	peste un refuz.
]]
function Catalog.canBuy(
	kind: Kind,
	id: string,
	balance: number,
	owned: { [string]: boolean }?
): (boolean, string?)
	local item = Catalog.get(kind, id)
	if not item then
		return false, "UNKNOWN"
	end
	if Catalog.owns(owned, kind, id) then
		return false, "OWNED"
	end
	-- Pret zero la un obiect care nu e de start inseamna "inca nu se vinde".
	if item.Coins <= 0 then
		return false, "NOT_FOR_SALE"
	end
	if balance < item.Coins then
		return false, "POOR"
	end
	return true
end

return Catalog
