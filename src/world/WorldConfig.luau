--!strict
--[[
	WorldConfig — puntea dintre tabla logica si lumea 3D.

	Motorul din `src/shared/` gandeste in celule: `X = 1..9` de la stanga la
	dreapta, `Y = 1..9` de jos in sus. Lumea gandeste in studs si CFrame-uri.
	Traducerea intre cele doua se scrie **o singura data**, aici, exact cum
	`BoardView.renderRow` era singurul loc care inversa Y in varianta 2D.

	Daca ai nevoie de pozitia unei celule sau a unei baricade, o ceri de aici.
	Nicio alta parte a codului nu are voie sa inmulteasca singura cu `Pitch`.

	Dimensiunile vin din asseturile generate (`barricade-3d-assets`), unde tabla
	masoara 1.31 m si o celula 0.114 m la un pas de 0.12 m. `StudsPerMeter` le
	aduce la o scara jucabila: o celula de ~7 studs lasa un avatar Roblox sa stea
	confortabil pe ea, iar o baricada de doua celule iese exact cat trebuie.
]]

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local WorldConfig = {}

-- Asseturile sunt modelate in metri; Roblox lucreaza in studs.
WorldConfig.StudsPerMeter = 60

-- Masuratorile din fisierele sursa, in metri.
local SOURCE = {
	CellSize = 0.114,
	CellPitch = 0.12,
	BoardSpan = 1.31,
	BoardThickness = 0.095,
	BarricadeLength = 0.242,
	BarricadeThickness = 0.046,
	BarricadeHeight = 0.115,
}

local function studs(meters: number): number
	return meters * WorldConfig.StudsPerMeter
end

WorldConfig.CellSize = studs(SOURCE.CellSize)
WorldConfig.Pitch = studs(SOURCE.CellPitch)
WorldConfig.BoardSpan = studs(SOURCE.BoardSpan)
WorldConfig.BoardThickness = studs(SOURCE.BoardThickness)

WorldConfig.BarricadeLength = studs(SOURCE.BarricadeLength)
WorldConfig.BarricadeThickness = studs(SOURCE.BarricadeThickness)
WorldConfig.BarricadeHeight = studs(SOURCE.BarricadeHeight)

-- Centrul tablei, in coordonate de celula. Pentru 9x9 iese exact 5.
local CENTER = (GameConfig.BoardSize + 1) / 2

--[[
	Celula -> deplasare fata de centrul tablei, in planul XZ.

	`Y` creste in sus pe tabla logica si scade pe axa Z a lumii: e singura
	inversare din tot proiectul, si traieste in linia de mai jos.
]]
function WorldConfig.offsetFromCell(x: number, y: number): Vector3
	return Vector3.new((x - CENTER) * WorldConfig.Pitch, 0, (CENTER - y) * WorldConfig.Pitch)
end

--[[
	Intersectie -> deplasare fata de centru.

	O baricada nu sta pe o celula, ci pe coltul comun al celulelor `(X,Y)`,
	`(X+1,Y)`, `(X,Y+1)` si `(X+1,Y+1)`, deci cade la jumatate de pas dincolo de
	centrul celulei `(X, Y)`.
]]
function WorldConfig.offsetFromIntersection(x: number, y: number): Vector3
	local base = WorldConfig.offsetFromCell(x, y)
	local half = WorldConfig.Pitch / 2
	return base + Vector3.new(half, 0, -half)
end

--[[
	Rotatia unei baricade. O orizontala separa randul `Y` de `Y+1`, deci se
	intinde de-a lungul axei X si ramane nerotita; o verticala separa coloana
	`X` de `X+1` si se intoarce cu 90 de grade.
]]
function WorldConfig.rotationForOrientation(orientation: string): CFrame
	if orientation == "Vertical" then
		return CFrame.Angles(0, math.rad(90), 0)
	end
	return CFrame.identity
end

-- Inaltimea la care sta suprafata jucabila fata de originea platformei.
function WorldConfig.surfaceY(): number
	return WorldConfig.BoardThickness / 2
end

return WorldConfig
