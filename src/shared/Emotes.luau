--!strict
--[[
	Emotes — ce poti sa-i spui adversarului fara sa scrii.

	Un joc pe ture are timpi morti: astepti mutarea celuilalt si nu ai ce face
	cu ei. Chatul Roblox exista, dar nimeni nu scrie in el in mijlocul unei
	partide — se scrie greu pe telefon, si pana termini fraza a trecut tura. Sase
	semne pe care le apesi si le vede celalalt deasupra capului acopera exact
	partea din vorbit care are rost intr-un joc de masa: „bravo", „ah", „te-am
	prins".

	E catalog, ca `Catalog`, nu configuratie. De aceea are fisierul lui si nu
	sta in `GameConfig`: acolo stau numerele de reglat, aici sta o lista de
	lucruri care exista.

	Ramane pur — fara `Instance`, fara `Color3`, fara `Sound`. Simbolul e un
	caracter, sunetul e un numar, iar cine le foloseste le imbraca: clientul
	deseneaza balonul, `SoundController` porneste sunetul.

	Ordinea din `Order` e ordinea de pe ecran, si e aleasa: primele trei sunt
	reactiile la ce face celalalt, ultimele trei la ce faci tu. Se citesc pe
	doua randuri de cate trei, cum sunt si asezate.
]]

export type Emote = {
	Id: string,
	-- Ce se vede: in buton, si in balonul de deasupra capului.
	Symbol: string,
	-- Numele citit, pentru cine nu vede simbolul sau foloseste cititor de ecran.
	Label: string,
	--[[
		Sunetul, ca id de asset. `0` inseamna „fara sunet" si e tratat exact ca
		in `GameConfig.Sounds`: nu e o gaura, e o alegere valida — emote-ul merge
		mai departe tacut.
	]]
	SoundId: number,
}

local Emotes = {}

--[[
	Cele sase.

	Sunetele sunt alese de autorul jocului si puse aici ca id-uri, nu cautate de
	cod. Toate sunt scurte — una-doua secunde — si asta conteaza mai mult decat
	pare: un emote e o intrerupere in tura altuia, iar o intrerupere de patru
	secunde nu mai e o vorba, e o piedica.

	Toate sase au acum sunetul lor.
]]
Emotes.All = {
	--[[
		Palma peste frunte, nu un salut.

		Locul asta era al lui „Hello", si nu-si castiga randul: te saluti o data
		la inceput si gata, in timp ce restul se folosesc la fiecare mutare a
		celuilalt. „Bruh" e reactia care lipsea — cea la o mutare pe care nu ti-o
		explici — si e singura dintre cele sase care se poate da si la propria
		greseala.
	]]
	Bruh = {
		Id = "Bruh",
		Symbol = "🤦",
		Label = "Bruh",
		-- „bruh sound effect", 1s.
		SoundId = 140007222940724,
	},
	Laugh = {
		Id = "Laugh",
		Symbol = "😂",
		Label = "Laugh",
		-- „Troll face laugh", 2s.
		SoundId = 136927014283419,
	},
	Wow = {
		Id = "Wow",
		Symbol = "😮",
		Label = "Wow",
		-- „Wow-mlg", 1s.
		SoundId = 110450139121683,
	},
	Angry = {
		Id = "Angry",
		Symbol = "😠",
		Label = "Angry",
		-- „angry sound", 2s.
		SoundId = 133313033428402,
	},
	Sad = {
		Id = "Sad",
		Symbol = "😢",
		Label = "Sad",
		-- „work-at-a-pizza-place-cry", 2s.
		SoundId = 17895203816,
	},
	Evil = {
		Id = "Evil",
		Symbol = "😈",
		Label = "Scheming",
		-- „mwehehe-roblox", 2s.
		SoundId = 102578956481391,
	},
} :: { [string]: Emote }

Emotes.Order = { "Bruh", "Laugh", "Wow", "Angry", "Sad", "Evil" }

--[[
	Exista emote-ul asta?

	Serverul nu are voie sa creada pe cuvant id-ul venit de la client: pus intr-un
	eveniment si trimis mai departe, un id inventat ar ajunge in balonul tuturor.
	Aici se opreste.
]]
function Emotes.get(id: any): Emote?
	if type(id) ~= "string" then
		return nil
	end
	return Emotes.All[id]
end

return Emotes
