--!strict
--[[
	Avatars — poza de profil a unui jucator, cu memorie.

	Doua locuri din interfata arata acelasi chip: pionul de pe tabla 2D si
	cardul din HUD. Fara modulul asta fiecare si-l cerea singur, deci acelasi
	jucator era cerut de doua ori la fiecare partida si fiecare copie isi tinea
	propriul cache — adica niciunul.

	`rbxthumb://` merge direct intr-un `ImageLabel` si pare mai simplu, dar
	pentru un id fara poza — cazul jucatorilor de test din Studio — lasa o
	imagine goala, fara sa spuna ca a esuat. `GetUserThumbnailAsync` spune, si
	de aceea apelantul poate lasa initiala dedesubt la vedere.

	Cererea blocheaza firul, deci se face intr-un fir separat. Apelantul
	primeste raspunsul mai tarziu si trebuie sa fie pregatit sa nu-l primeasca
	niciodata: lipsa unei poze nu strica nimic pe ecran.
]]

local Players = game:GetService("Players")

local Avatars = {}

-- Ce s-a cerut deja, si ce a iesit. Traieste cat sesiunea clientului.
local cache: { [number]: string } = {}

--[[
	Cere poza unui jucator si o da mai departe cand vine.

	`apply` se cheama o singura data, si numai daca exista o poza. Cand id-ul e
	deja in memorie se cheama imediat, pe firul apelantului — asa un card
	recladit nu clipeste.
]]
function Avatars.fetch(userId: number, apply: (string) -> ())
	local cached = cache[userId]
	if cached then
		apply(cached)
		return
	end

	-- Jucatorii simulati din Studio au id-uri negative; nu au poza si nici nu
	-- merita o cerere de retea care oricum se intoarce cu eroare.
	if userId <= 0 then
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and content then
			cache[userId] = content
			apply(content)
		end
	end)
end

return Avatars
