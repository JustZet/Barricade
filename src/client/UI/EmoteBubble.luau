--!strict
--[[
	EmoteBubble — balonul de vorba de deasupra capului.

	Un emote fara el ar fi doar un sunet: auzi un ras si nu stii de la cine. Ce
	conteaza intr-un joc de doi-patru oameni e **cine** a spus, si de aceea
	semnul se lipeste de om, nu de un colt de ecran.

	Doua asezari, pentru ca jocul are doua infatisari:

	- In lumea 3D, un `BillboardGui` peste capul avatarului. Se intoarce singur
	  spre camera, deci se citeste din orice unghi, si urca odata cu omul cand
	  acesta se muta sau se ridica pe soclu.
	- Fara lume, pe cardul jucatorului din HUD. Tabla 2D n-are avataruri de care
	  sa se agate ceva, dar are randul de carduri, si acolo scrie deja cine e
	  cine.

	Un singur balon odata, de fiecare om: al doilea emote il inlocuieste pe
	primul in loc sa se aseze peste el. Cine apasa de doua ori repede vrea sa
	arate al doilea lucru, nu amandoua.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local EmoteBubble = {}

-- Cat sta pe ecran, fara intrare si iesire.
local HOLD = 2.4
local POP = 0.22
local FADE = 0.3

--[[
	Baloanele de acum, dupa jucator. Tinute ca sa poata fi inlocuite: fara
	evidenta asta, doua emote-uri la rand ar lasa doua baloane suprapuse, iar al
	doilea l-ar ascunde pe primul fara sa-l stearga.
]]
local live: { [number]: Instance } = {}

local function clear(userId: number)
	local old = live[userId]
	live[userId] = nil
	if old then
		old:Destroy()
	end
end

--[[
	Desenul propriu-zis: placa rotunjita si codita de sub ea.

	Codita e un patrat intors pe colt, asezat la un capat al balonului si desenat
	*inaintea* lui. Asa balonul ii acopera jumatatea dinspre el, si ce ramane
	vizibil e exact triunghiul care arata catre om. Un triunghi desenat ca
	imagine ar fi fost un asset in plus pentru trei pixeli de forma.

	**Totul e in scara, nimic in pixeli**, si asta nu e gust. Balonul se aseaza
	in doua feluri de containere cu doua unitati diferite: un `BillboardGui` isi
	da marimea in studi, iar un `Frame` de pe card in pixeli. Un copil masurat in
	pixeli intr-un container masurat in studi iese oricum, dar nu cum trebuie —
	prima versiune scadea nouasprezece pixeli dintr-o inaltime care pe ecran avea
	vreo doisprezece, si balonul ajungea cu inaltime negativa, adica invizibil.
	In scara, acelasi desen se poarta la fel in amandoua.

	Litera face si ea parte din intelegere: `TextScaled` in loc de o marime
	scrisa, ca semnul sa umple balonul indiferent cat de mare a iesit el.
]]
local function paint(parent: Instance, symbol: string, tailUp: boolean): Frame
	local root = Theme.create("Frame", {
		Name = "Bubble",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}) :: Frame

	--[[
		Codita arata catre cel care a vorbit, si de aceea isi schimba capatul.

		Deasupra capului, balonul sta peste om si codita coboara spre el. Pe card
		insa balonul atarna **sub** el, iar o codita tot in jos nu mai arata catre
		nimeni: pe ecran iese o sageata indreptata spre tabla, pe care jucatorii au
		si citit-o ca pe o sageata. Intoarsa in sus, se lipeste de cardul din care
		iese, si balonul se citeste iar ca o vorba a omului de deasupra.
	]]
	Theme.create("Frame", {
		Name = "Tail",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if tailUp then 0.18 else 0.82),
		Size = UDim2.fromScale(0.22, 0.22),
		Rotation = 45,
		ZIndex = 1,
		Parent = root,
	})

	local body = Theme.create("Frame", {
		Name = "Body",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, if tailUp then 1 else 0),
		Position = UDim2.fromScale(0.5, if tailUp then 1 else 0),
		Size = UDim2.fromScale(1, 0.78),
		ZIndex = 2,
		Parent = root,
	}, {
		-- Rotunjire in scara, din acelasi motiv ca restul: o raza in pixeli ar
		-- fi facut balonul din lume aproape un cerc si pe cel de pe card un
		-- dreptunghi.
		Theme.corner(UDim.new(0.22, 0)),
		Theme.stroke(Theme.Color.Line, 2),
	}) :: Frame

	--[[
		Semnul se scrie cu fontul de sistem, nu cu al nostru.

		Fonturile jocului — Fredoka, Nunito — n-au emoji in ele, si un caracter
		care lipseste dintr-un font se deseneaza ca dreptunghi gol. `Legacy` e
		cel care cade inapoi pe emoji-urile colorate ale platformei.
	]]
	Theme.text({
		Name = "Symbol",
		Text = symbol,
		Font = Enum.Font.Legacy,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
		-- Putin mai mic decat placa, ca semnul sa nu atinga marginile.
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = 3,
		Parent = body,
	})

	return root
end

--[[
	Intrarea si iesirea, si de ce nu e doar o aparitie.

	Balonul apare in mijlocul unui meci in care se uita cineva la tabla, nu la
	capul adversarului. O aparitie instantanee se rateaza; una care sare putin
	peste marimea ei trage privirea fara sa ceara nimic. La plecare invers:
	se stinge, ca sa nu para ca a fost intrerupt.
]]
local function animate(owner: Instance, root: Frame, scale: UIScale, userId: number)
	scale.Scale = 0.4
	TweenService
		:Create(scale, TweenInfo.new(POP, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		:Play()

	--[[
		Amandoua firele de mai jos intreaba intai daca balonul asta mai e cel de
		acum.

		Al doilea emote il inlocuieste pe primul pe loc, dar ceasul primului merge
		mai departe — iar daca ar sterge orbeste „balonul jucatorului", ar sterge
		balonul **nou**, la o secunda dupa ce a aparut. Fiecare fir isi duce la
		capat doar balonul lui.
	]]
	task.delay(HOLD, function()
		if live[userId] ~= owner then
			return
		end

		for _, part in root:GetDescendants() do
			if part:IsA("TextLabel") then
				TweenService:Create(part, TweenInfo.new(FADE), { TextTransparency = 1 }):Play()
			elseif part:IsA("Frame") then
				TweenService:Create(part, TweenInfo.new(FADE), { BackgroundTransparency = 1 })
					:Play()
			elseif part:IsA("UIStroke") then
				TweenService:Create(part, TweenInfo.new(FADE), { Transparency = 1 }):Play()
			end
		end

		task.delay(FADE + 0.05, function()
			if live[userId] == owner then
				clear(userId)
			end
		end)
	end)
end

--[[
	Deasupra capului, in lumea 3D.

	Se prinde de `Head` daca exista si de radacina altfel: un avatar fara cap e
	unul caruia inca nu i s-au replicat toate piesele, si mai bine un balon
	putin mai jos decat niciun balon.
]]
function EmoteBubble.overHead(player: Player, symbol: string): boolean
	local character = player.Character
	if not character then
		return false
	end
	local anchor = character:FindFirstChild("Head") or character.PrimaryPart
	if not anchor or not anchor:IsA("BasePart") then
		return false
	end

	clear(player.UserId)

	local billboard = Theme.create("BillboardGui", {
		Name = "EmoteBubble",
		Adornee = anchor,
		AlwaysOnTop = true,
		--[[
			Marimea are si studi, si pixeli, si are nevoie de amandoua.

			Partea in studi il face sa se micsoreze odata cu omul cand camera se
			departeaza — in pixeli curati ar fi ramas la fel de mare de oriunde si
			ar fi acoperit tabla. Dar camera meciului sta la optzeci-o suta
			douazeci de studi de masa, iar acolo trei studi ajung vreo zece pixeli
			pe ecran, adica nimic. Partea in pixeli e podeaua: oricat de departe
			ar fi omul, balonul nu scade sub cat trebuie ca sa se vada ce semn e
			in el.
		]]
		Size = UDim2.new(3, 34, 3, 34),
		StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0),
		Parent = player:FindFirstChildOfClass("PlayerGui"),
	}) :: BillboardGui

	--[[
		`BillboardGui` sta in `PlayerGui`, nu pe personaj.

		Pus pe personaj, ar fi plecat odata cu el la respawn si ar fi ramas o
		instanta orfana in `Workspace` la fiecare moarte. In `PlayerGui` traieste
		cat tine clientul, iar `Adornee` face legatura cu capul fara sa atarne
		de el.
	]]
	-- Deasupra capului: codita coboara spre om.
	local root = paint(billboard, symbol, false)
	local scale = Instance.new("UIScale")
	scale.Parent = root

	live[player.UserId] = billboard
	animate(billboard, root, scale, player.UserId)
	return true
end

--[[
	Pe cardul jucatorului din HUD. E locul obisnuit al unui emote in meci —
	vezi `GameController.showEmote` pentru de ce nu deasupra capului.

	Sub card, nu peste el: cardul spune cine, balonul spune ce, si se citesc in
	ordinea asta. Cardurile stau lipite de marginea de sus a ecranului, deci sub
	ele e singura parte libera; peste ar fi acoperit chiar chipul care spune al
	cui e balonul.
]]
function EmoteBubble.overCard(userId: number, card: GuiObject, symbol: string)
	clear(userId)

	local holder = Theme.create("Frame", {
		Name = "EmoteBubble",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(64, 64),
		ZIndex = 10,
		Parent = card,
	}) :: Frame

	-- Sub card: codita urca spre el.
	local root = paint(holder, symbol, true)
	local scale = Instance.new("UIScale")
	scale.Parent = root

	live[userId] = holder
	animate(holder, root, scale, userId)
end

--[[
	Sterge tot. Se cheama la sfarsitul meciului: baloanele sunt legate de o masa
	care nu mai exista, si un emote lasat sa se stinga singur ar pluti peste
	lobby.
]]
function EmoteBubble.clearAll()
	for userId in live do
		clear(userId)
	end
end

--[[
	Cine a trimis, dupa id. Aici, si nu la fiecare chemator, ca sa existe un
	singur raspuns la intrebarea „al cui e emote-ul asta".
]]
function EmoteBubble.playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

return EmoteBubble
