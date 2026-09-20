--!strict
--[[
	Audio — pornirea unui sunet, fara bucata moarta de la inceputul lui.

	Multe fisiere de pe Creator Store incep cu o taraganeala: o zecime, doua, de
	liniste sau de scartait inainte de lovitura propriu-zisa. Pornit de la zero,
	sunetul e corect si se aude oricum tarziu — nu fiindca l-am pornit tarziu, ci
	fiindca asa e taiat. La un zid care cade in doua zecimi de secunda, o zecime
	de liniste in fata strica tot.

	De aceea sunetele nu se pornesc de oriunde cu `:Play()`, ci prin aici: daca
	pentru id-ul lui exista o bucata de sarit in `GameConfig.SoundStart`, se sare.
	Cat anume se sare se afla ascultand — vezi comentariul de langa tabel.

	Modulul sta in `src/world/` fiindca atinge API-ul Roblox: in `src/shared/` n-ar
	avea ce cauta. Il folosesc si zidul, care isi face sunetul pe server, si
	`SoundController`, care le tine pe cele din interfata — ca sa existe o
	singura socoteala a inceputului, nu doua.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Audio = {}

-- Cat se sare de la inceputul sunetului asta, in secunde. Zero daca nu e trecut.
function Audio.offsetOf(sound: Sound): number
	local id = tonumber(string.match(sound.SoundId, "%d+") or "")
	if not id then
		return 0
	end
	return GameConfig.SoundStart[id] or 0
end

--[[
	Porneste sunetul de unde trebuie.

	`TimePosition` se scrie **dupa** `Play`, fiindca pornirea il duce inapoi la
	zero. Iar daca fisierul inca nu a ajuns la client, se scrie inca o data cand
	ajunge: pana atunci pozitia n-are pe ce sa se aseze si se pierde.
]]
function Audio.play(sound: Sound)
	local offset = Audio.offsetOf(sound)

	sound:Play()
	if offset <= 0 then
		return
	end

	sound.TimePosition = offset
	if not sound.IsLoaded then
		sound.Loaded:Once(function()
			sound.TimePosition = offset
		end)
	end
end

return Audio
