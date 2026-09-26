--!strict
--[[
	Pedestal — bariera nevazuta de deasupra unui soclu.

	Soclurile din galerie sunt discuri late, ridicate cu doi-trei studi peste
	podea: exact cat sa te urci pe ele dintr-un salt. Si se urca lumea, fiindca
	asa sunt oamenii. Odata sus stai in obiectul expus, care e o clona ce
	pluteste si nu se apara, iar vitrina — care trebuie sa arate un lucru frumos
	— arata un jucator infipt intr-un cristal.

	**E un stalp, nu o cupola, si forma asta a fost invatata pe pielea ei.**

	Sfera pare alegerea evidenta: pe o cupola nu se sta, aluneci de pe ea. Numai
	ca in Roblox nu aluneci — `Humanoid` urca pante pana la optzeci si noua de
	grade, iar in varful sferei suprafata e orizontala, deci cine ajunge acolo
	**sta**. Ca varful sa fie de neatins, sfera trebuie sa fie mare; si o sfera
	mare e lata la mijloc. Masurat in lobby: o sfera cu crestetul la patruzeci si
	unu de studi se latea, la inaltimea capului unui om care sare, pana la
	cincisprezece studi de centru — adica taman peste podeaua din fata vitrinei.
	Nu te mai puteai urca pe soclu, dar nici nu mai puteai sari langa el fara sa
	dai cu capul de nimic.

	Un cilindru vertical nu are mijloc mai lat decat capetele. Latimea lui e
	latimea discului, aceeasi de sus pana jos: acopera exact soclul si nimic din
	jurul lui, la orice inaltime. Iar inaltimea nu-l mai costa nimic, asa ca
	poate fi ridicat mult peste orice saritura de pe orice acoperis din galerie.
	Capacul de sus exista si se poate sta pe el — dar la treizeci de studi peste
	soclu nu ajunge nimeni.

	Traieste pe client, ca vitrinele pe care le pazeste — `Showcase` le
	construieste tot acolo. Un client modificat poate sterge stalpul si urca; ce
	castiga cu asta e sa stea pe un soclu, si nimic altceva. Regulile jocului
	sunt in alta parte.
]]

local Pedestal = {}

--[[
	Cat de sus urca stalpul peste talpa soclului, in studi.

	Un avatar sare vreo sapte studi. Treizeci acopera si saritura de pe cel mai
	inalt lucru pe care se poate urca cineva in galerie, cu mult peste. Nu costa
	nimic sa fie inalt: un cilindru nu se latweste cu inaltimea.
]]
local HEIGHT = 30

--[[
	Cat coboara sub talpa.

	Atat cat sa prinda fata soclului chiar daca nu e perfect plata, si sa nu
	lase o muchie subtire pe care sa se agate cineva sarind din lateral.
]]
local GRIP_DEPTH = 1.5

export type Options = {
	-- Raza stalpului. Implicit, jumatate din latura orizontala mai mica.
	Radius: number?,
	--[[
		Cat se vede. `1` inseamna nevazut; pentru reglaj pune 0.8 si se vede
		exact ce forma are si unde ajunge.
	]]
	Transparency: number?,
}

--[[
	Ridica bariera peste o vitrina. Intoarce piesa, sau `nil` daca vitrina n-are
	din ce sa fie masurata.

	Talpa se citeste din `DisplayBase`, atributul pe care il pune `Showcase` si
	care spune unde sta obiectul expus. E acelasi punct pe care il vrea si
	bariera: fata soclului.
]]
function Pedestal.guard(anchor: Model, options: Options?): BasePart?
	local given: Options = options or {}

	local existing = anchor:FindFirstChild("PedestalDome")
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local base = anchor:GetAttribute("DisplayBase")
	if typeof(base) ~= "CFrame" then
		return nil
	end
	local top = (base :: CFrame).Position

	--[[
		Latura mica, nu cea mare: bratul care tine placuta sau o arcada de
		deasupra lungesc cutia incadratoare intr-o singura directie, iar un stalp
		facut dupa ea ar iesi cu mult peste soclu si ar sta in drum.
	]]
	local _, size = anchor:GetBoundingBox()
	local radius = given.Radius or math.min(size.X, size.Z) / 2
	if radius <= 0 then
		return nil
	end

	local length = HEIGHT + GRIP_DEPTH

	local pillar = Instance.new("Part")
	pillar.Name = "PedestalDome"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Anchored = true
	pillar.CanCollide = true
	--[[
		Ar trebui sa nu raspunda la raze, dar asta nu tine: Roblox ignora
		`CanQuery = false` cat timp piesa e `CanCollide`, iar stalpul trebuie sa
		fie solid. Raza unui clic il loveste — de aceea cartonasul ofertei, care
		sta inauntrul lui, e `AlwaysOnTop` (vezi `OfferView`). Ramane scris aici
		ca sa nu se mai creada ca e transparent razelor.
	]]
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.Transparency = given.Transparency or 1
	--[[
		Cilindrul din Roblox se naste culcat, pe axa X: lungimea lui e `Size.X`,
		iar celelalte doua laturi sunt diametrul. De aceea se roteste un sfert de
		tura ca sa stea in picioare.
	]]
	pillar.Size = Vector3.new(length, radius * 2, radius * 2)
	pillar.CFrame = CFrame.new(top + Vector3.new(0, length / 2 - GRIP_DEPTH, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = anchor

	return pillar
end

return Pedestal
