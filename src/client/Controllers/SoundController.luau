--!strict
--[[
	SoundController — sunetele scurte ale jocului.

	Putine si discrete: o mutare, o baricada, un refuz, o schimbare de tura,
	numaratoarea si victoria. Singurul lucru in bucla e muzica de fundal, tinuta
	destul de incet cat sa poti gandi peste ea — vezi `GameConfig.Music`.

	Doua feluri, si se opresc altfel. Cele de aici ies din interfata si se
	opresc pur si simplu nefiind pornite. Sunetul zidului insa e facut de server,
	pe obiectul lui, si se aude la toata lumea — pe el il taie volumul grupului
	`WorldSound.Group`, dat la zero doar la cel care si-a inchis sunetul.

	Id-urile de asset stau in GameConfig si sunt 0 la livrare. Un sunet cu
	id 0 e pur si simplu sarit: jocul merge complet si fara ele, iar cand
	pui id-urile tale nu trebuie schimbat niciun rand de cod aici.

	Cateva au si o pauza intre doua porniri, tot din GameConfig: vezi
	`SoundCooldown`. Fara ea, un sunet cerut in rafala se tot repune de la
	inceput si nu se aude niciodata intreg.
]]

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Emotes = require(ReplicatedStorage.Shared.Emotes)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Audio = require(ReplicatedStorage.World.Audio)
local Skins = require(ReplicatedStorage.World.Skins)

local SoundController = {}

--[[
	Sunetul unui emote intra in aceeasi magazie ca toate celelalte, sub un nume
	care nu se poate ciocni de cele din `GameConfig.Sounds`.

	Asa emote-urile primesc pe degeaba tot ce are deja `play`: butonul de sunet
	care le taie, pauza dintre doua porniri daca va fi nevoie, si aducerea din
	vreme a fisierului. Alternativa — un `Sound` facut pe loc la fiecare apasare
	— ar fi insemnat ca primul emote al partidei se aude cu intarziere sau deloc,
	si ca butonul de sunet nu-l opreste.
]]
local function emoteSoundName(emoteId: string): string
	return "Emote_" .. emoteId
end

local sounds: { [string]: Sound } = {}
local enabled = true
local music: Sound? = nil
-- Comutatorul propriu al muzicii, din butonul de sus. SOUND le taie pe toate.
local musicEnabled = true
--[[
	Muzica asteapta sa se ridice ecranul de incarcare. Pornita odata cu clientul,
	se auzea peste cortina, iar primele masuri se pierdeau inainte sa se vada ceva.
]]
local musicAllowed = false

--[[
	Muzica suna doar cand o vor amandoua butoanele.

	Se pune pe pauza, nu se opreste: la repornire continua de unde era, in loc
	sa ia piesa de la capat de fiecare data cand cineva apasa.
]]
local function syncMusic()
	local track = music
	if not track then
		return
	end
	local wanted = enabled and musicEnabled and musicAllowed
	if wanted and not track.IsPlaying then
		track:Resume()
	elseif not wanted and track.IsPlaying then
		track:Pause()
	end
end

-- Cand a pornit ultima oara fiecare sunet care are pauza.
local lastPlayed: { [string]: number } = {}

--[[
	Sunetele zidurilor se aduc din vreme.

	Ele nu se pornesc de aici: zidul e construit de server, iar sunetul vine
	odata cu el. Un client care n-a mai auzit sunetul ala pierde insa prima
	pornire — pana se incarca fisierul, clipa a trecut — si atunci primul zid al
	partidei se aude doar la unii, sau se aude cu intarziere.

	Aducerea se face pe un fir separat: daca reteaua e lenta, jocul porneste
	oricum, doar ca primele sunete pot intarzia. Nimic din ce urmeaza nu depinde
	de ea.
]]
local function warmUp()
	local wanted: { string } = {}
	local seen: { [number]: boolean } = {}

	local function add(assetId: number)
		if assetId ~= 0 and not seen[assetId] then
			seen[assetId] = true
			table.insert(wanted, "rbxassetid://" .. assetId)
		end
	end

	for _, assetId in GameConfig.Sounds do
		add(assetId)
	end
	for _, id in Skins.Order do
		local skin = Skins.get(id)
		add(skin.PlaceSound)
		add(skin.BlockedSound)
	end
	for _, id in Emotes.Order do
		add(Emotes.All[id].SoundId)
	end

	if #wanted == 0 then
		return
	end

	task.spawn(function()
		local carriers: { Instance } = {}
		for _, assetId in wanted do
			local carrier = Instance.new("Sound")
			carrier.SoundId = assetId
			table.insert(carriers, carrier)
		end
		pcall(function()
			ContentProvider:PreloadAsync(carriers)
		end)
		for _, carrier in carriers do
			carrier:Destroy()
		end
	end)
end

function SoundController.init()
	local folder = Instance.new("Folder")
	folder.Name = "BarricadeSounds"
	folder.Parent = SoundService

	warmUp()

	local function build(name: string, assetId: number)
		if assetId == 0 then
			return
		end
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = string.format("rbxassetid://%d", assetId)
		sound.Volume = GameConfig.SoundVolume[name] or 0.45
		sound.Parent = folder
		sounds[name] = sound
	end

	for name, assetId in GameConfig.Sounds do
		build(name, assetId)
	end

	for _, id in Emotes.Order do
		build(emoteSoundName(id), Emotes.All[id].SoundId)
	end

	--[[
		Muzica nu trece prin `play`: nu are pauza intre porniri si nu se cere
		de nicaieri, porneste o data si nu se mai opreste decat din buton.
	]]
	if GameConfig.Music.Id ~= 0 then
		local track = Instance.new("Sound")
		track.Name = "Music"
		track.SoundId = string.format("rbxassetid://%d", GameConfig.Music.Id)
		track.Volume = GameConfig.Music.Volume
		track.Looped = true
		track.Parent = folder
		music = track
		syncMusic()
	end
end

--[[
	`speed` schimba inaltimea, prin `PlaybackSpeed`: numaratoarea din „+4" isi
	urca tick-ul cu fiecare cifra, din acelasi fisier. Lipsa inseamna viteza
	normala, si se pune la loc de fiecare data — altfel un sunet ar ramane pe
	inaltimea ultimei cereri care a schimbat-o.
]]
function SoundController.play(name: string, speed: number?)
	if not enabled then
		return
	end

	local sound = sounds[name]
	if not sound then
		return
	end

	--[[
		Pauza dintre doua porniri ale aceluiasi sunet.

		`Sound:Play()` pe unul care inca suna nu suprapune nimic — il ia de la
		inceput. La cereri dese asta e mai rau decat suprapunerea: se aude doar
		primul sfert din el, la nesfarsit.
	]]
	local cooldown = GameConfig.SoundCooldown[name]
	if cooldown then
		local now = os.clock()
		if now - (lastPlayed[name] or -math.huge) < cooldown then
			return
		end
		lastPlayed[name] = now
	end

	sound.PlaybackSpeed = speed or 1
	Audio.play(sound)
end

--[[
	Sunetul unui emote. Cine n-are id ramane tacut, ca oricare altul cu `0`.
]]
function SoundController.playEmote(emoteId: string)
	SoundController.play(emoteSoundName(emoteId))
end

--[[
	Volumul grupului prin care trec sunetele lumii.

	Grupul vine de la server si poate intarzia, deci se cauta de fiecare data,
	nu se tine minte. E o cautare intr-un serviciu cu cativa copii, la apasarea
	unui buton — nu merita nimic mai istet.
]]
local function setWorldVolume(value: number)
	local group = SoundService:FindFirstChild(GameConfig.WorldSound.Group)
	if group and group:IsA("SoundGroup") then
		group.Volume = value
	end
end

function SoundController.setEnabled(value: boolean)
	enabled = value
	setWorldVolume(if value then 1 else 0)
	syncMusic()
end

function SoundController.isEnabled(): boolean
	return enabled
end

function SoundController.toggle(): boolean
	SoundController.setEnabled(not enabled)
	return enabled
end

-- Muzica de fundal, pornita sau oprita, fara sa atinga restul sunetelor.
-- Da drumul muzicii, o singura data: dupa ce s-a ridicat ecranul de incarcare.
function SoundController.allowMusic()
	musicAllowed = true
	syncMusic()
end

function SoundController.isMusicEnabled(): boolean
	return musicEnabled
end

function SoundController.toggleMusic(): boolean
	musicEnabled = not musicEnabled
	syncMusic()
	return musicEnabled
end

return SoundController
