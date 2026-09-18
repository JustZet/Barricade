--!strict
--[[
	ModelFit — cele doua masuratori de care are nevoie orice model adus din
	import: cat de mare sa fie si unde ii cade talpa.

	Exista ca modul separat pentru ca raspunsul nu are voie sa difere intre un
	zid asezat pe tabla si acelasi zid rotindu-se in vitrina din lobby. Cand am
	avut socoteala scrisa de doua ori, cele doua s-au desincronizat imediat.

	Regula pe care o aplica: **nu te increde in pivot**. Modelele vin din glTF cu
	pivotul lasat unde s-a nimerit — la unele in centru, la altele la baza, la
	altele in originea scenei. Formula "ridica-l cu jumatate din inaltime"
	merge doar pentru primele si lasa restul sa pluteasca.
]]

local ModelFit = {}

--[[
	Aseaza modelul cu talpa exact pe `surface`, oricare i-ar fi pivotul.

	Se face in doi timpi: intai il duce acolo, apoi masoara cat a gresit si
	corecteaza. Pare ocolit, dar e singura varianta care ramane corecta si cand
	modelul e rotit, fiindca inaltimea cutiei incadratoare depinde de rotatie.

	Intoarce pivotul rezultat — punctul in jurul caruia se invart animatiile.
]]
function ModelFit.onSurface(model: Model, surface: CFrame): CFrame
	model:PivotTo(surface)

	local box, size = model:GetBoundingBox()
	local lift = surface.Position.Y - (box.Position.Y - size.Y / 2)

	local landed = model:GetPivot() + Vector3.new(0, lift, 0)
	model:PivotTo(landed)
	return landed
end

--[[
	Scaleaza modelul pana cand latura lui lunga din plan masoara `span` studs.

	Se masoara in plan, nu pe inaltime: un zid e lung si subtire, un podium e
	patrat si scund, iar ce trebuie sa se potriveasca in vitrina e amprenta lor
	pe soclu. Proportiile raman ale modelului.
]]
function ModelFit.toSpan(model: Model, span: number)
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Z)
	if longest <= 0 or span <= 0 then
		return
	end
	model:ScaleTo(model:GetScale() * (span / longest))
end

return ModelFit
