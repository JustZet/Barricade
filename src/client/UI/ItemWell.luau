--!strict
--[[
	ItemWell — caseta in care se vede un obiect din catalog.

	Fundalul e `CardColor`, adica o culoare a obiectului, nu una aleasa in
	interfata; peste el sta poza randata, daca a fost urcata. Cat timp lipseste,
	ramane caseta colorata — nu o imagine goala si nu un dreptunghi cenusiu.

	Sta intr-un modul al ei fiindca acum o folosesc trei ecrane: cartonasul din
	raftul magazinului, panoul mare din dreapta lui, si eticheta care pluteste
	deasupra vitrinelor din lobby. Scrisa de trei ori, previzualizarea ar ajunge
	sa arate diferit in trei locuri ale aceluiasi joc, si nimeni n-ar observa
	pana cand nu s-ar schimba prima culoare.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skins = require(ReplicatedStorage:WaitForChild("World").Skins)

local Theme = require(script.Parent.Theme)

local ItemWell = {}

--[[
	Cele doua feluri de caseta.

	`Cut` e decupajul asezat peste culoarea obiectului: poza n-are fundal, deci
	se vede `CardColor`-ul in jurul ei, si obiectul incape intreg, oricat de lat
	ar fi cartonasul.

	`Scene` e poza facuta in lume, si ea umple caseta cap la cap. Se *taie*, nu
	se incadreaza: o poza cu peisaj lasata sa incapa ar pune dungi de lemn sus si
	jos, iar ce se pierde din ea prin taiere e cer si dala, nu obiectul, care sta
	oricum la mijloc.
]]
export type Mode = "Cut" | "Scene"

--[[
	Caseta goala, gata de asezat.

	Raza coltului se da din afara, si ca `UDim`, nu ca numar: un cartonas de un
	centimetru si un panou de o palma nu se rotunjesc la fel, iar o eticheta din
	lume are nevoie de raza in fractiune — marimea ei pe ecran se schimba cu
	departarea, si o raza in pixeli ar fi ramas aceeasi.
]]
function ItemWell.build(itemId: string?, kind: string, radius: UDim, mode: Mode?): Frame
	local skin = Skins.get(itemId)
	local scene = mode == "Scene"

	local well = Theme.create("Frame", {
		Name = "Well",
		BackgroundColor3 = skin.CardColor,
		BorderSizePixel = 0,
		ClipsDescendants = scene,
	}, {
		Theme.create("UICorner", { CornerRadius = radius }),
	}) :: Frame
	well:SetAttribute("Mode", if scene then "Scene" else "Cut")

	--[[
		Raza se pune si pe poza, nu doar pe caseta.

		`ClipsDescendants` taie dupa dreptunghi, nu dupa colturile rotunjite: o
		poza care umple caseta isi pastreaza colturile ei drepte si le acopera
		chiar pe cele rotunjite de dedesubt. Caseta parea patrata desi nu era.
		Un `UICorner` pe poza rotunjeste chiar imaginea.
	]]
	Theme.create("ImageLabel", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Image = if scene then Skins.scene(skin.Id, kind) else Skins.preview(skin.Id, kind),
		ScaleType = if scene then Enum.ScaleType.Crop else Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		Parent = well,
	}, {
		Theme.create("UICorner", { CornerRadius = radius }),
	})

	return well
end

--[[
	Aceeasi caseta, mutata pe alt obiect.

	Se recoloreaza, nu se reconstruieste: acolo unde jucatorul trece prin raft
	dintr-un clic in altul, un panou refacut de fiecare data ar clipi.
]]
function ItemWell.show(well: Frame, itemId: string?, kind: string)
	local skin = Skins.get(itemId)
	well.BackgroundColor3 = skin.CardColor

	local preview = well:FindFirstChild("Preview")
	if preview and preview:IsA("ImageLabel") then
		-- Caseta isi tine minte felul: cine o muta pe alt obiect nu trebuie sa
		-- stie din ce ecran a fost facuta.
		preview.Image = if well:GetAttribute("Mode") == "Scene"
			then Skins.scene(skin.Id, kind)
			else Skins.preview(skin.Id, kind)
	end
end

return ItemWell
