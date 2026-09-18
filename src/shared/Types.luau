--!strict
--[[
	Types — contractul de date al jocului.

	Modulul nu exporta cod, doar tipuri. Orice structura care circula intre
	server si client trece pe aici, ca sa nu existe doua definitii ale
	aceluiasi lucru.
]]

-- Coordonata unei celule jucabile. X, Y sunt 1..BoardSize.
export type Cell = {
	X: number,
	Y: number,
}

-- Orientarea unei baricade.
export type Orientation = "Horizontal" | "Vertical"

--[[
	O baricada. X, Y sunt 1..BoardSize-1 si identifica *intersectia* pe care
	sta baricada, nu o celula jucabila. Vezi BoardUtils pentru conventie.
]]
export type Wall = {
	X: number,
	Y: number,
	Orientation: Orientation,
	Owner: number?, -- slotul jucatorului care a pus-o
}

-- Cum se castiga. Tinut separat de miscare, ca sa se poata adauga moduri noi.
export type ObjectiveKind = "OPPOSITE_SIDE" | "CENTER"

export type Objective = {
	Kind: ObjectiveKind,
	-- Doar pentru OPPOSITE_SIDE: marginea pe care trebuie sa o atinga jucatorul.
	Edge: ("Y_MAX" | "Y_MIN" | "X_MAX" | "X_MIN")?,
	-- Doar pentru CENTER: celula tinta.
	Cell: Cell?,
}

export type PlayerState = {
	Slot: number,
	UserId: number,
	Name: string,
	Team: number,
	Position: Cell,
	BarricadesRemaining: number,
	Objective: Objective,
	Connected: boolean,
	Finished: boolean,
	--[[
		Secundele ramase din ceasul propriu. Se scad doar cat e randul lui, ca la
		sah: altfel un jucator ar fi pedepsit pentru cat sta pe ganduri adversarul.
		Cand ajunge la zero, se retrage din meci.
	]]
	TimeRemaining: number,
}

export type GameStatus =
	"WAITING"
	| "MATCHMAKING"
	| "STARTING"
	| "PLAYING"
	| "FINISHED"
	| "CANCELLED"

export type BoardState = {
	Size: number,
	GameMode: string,
	Status: GameStatus,
	Players: { [number]: PlayerState },
	TurnOrder: { number },
	TurnIndex: number,
	TurnNumber: number,
	Walls: { [string]: Wall },
	-- Cache derivat din Walls: muchiile blocate intre celule vecine.
	BlockedEdges: { [string]: boolean },
	-- Cache derivat din Walls: segmentele de zid deja ocupate.
	OccupiedSegments: { [string]: boolean },
	Winner: number?,
	WinningTeam: number?,
	-- Setat cand meciul e in pauza pentru reconectare.
	PausedUntil: number?,
	PausedForSlot: number?,
}

-- Rezultatul oricarei validari. Motivul e cheie de eroare, nu text pentru UI.
export type Result = {
	Ok: boolean,
	Reason: string?,
}

return {}
