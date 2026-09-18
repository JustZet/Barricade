--!nolint
--[[
	RulesSpec — regulile de joc, verificate fara tabla vizuala.

	Testele astea sunt motivul pentru care motorul nu atinge API-ul Roblox.
	Ruleaza cu `lune run tests/run`.
]]

local h = require("./harness")

local Shared = h.Shared
local BoardState = Shared.BoardState
local BoardUtils = Shared.BoardUtils
local GameConfig = Shared.GameConfig
local MovementRules = Shared.MovementRules
local Pathfinding = Shared.Pathfinding
local WallRules = Shared.WallRules

local describe, it = h.describe, h.it
local assertEqual, assertTrue, assertFalse = h.assertEqual, h.assertTrue, h.assertFalse
local assertOk, assertRejected = h.assertOk, h.assertRejected

-- Un meci pornit, gata de mutari.
local function newMatch(mode: string): any
	local count = GameConfig.Modes[mode].Players
	local participants = {}
	for i = 1, count do
		participants[i] = { UserId = 100 + i, Name = "P" .. i }
	end
	local state = BoardState.create(mode, participants)
	state.Status = "PLAYING"
	return state
end

-- Actiuni ale jucatorului aflat la mutare, ca sa nu repet slotul peste tot.
local function move(state: any, x: number, y: number): any
	return BoardState.applyMove(state, BoardState.getCurrentSlot(state), { X = x, Y = y })
end

local function wall(state: any, x: number, y: number, orientation: string): any
	return BoardState.applyWall(state, BoardState.getCurrentSlot(state), x, y, orientation)
end

-- Adauga o baricada direct in stare, ocolind tura. Doar pentru pregatirea testelor.
local function seedWall(state: any, x: number, y: number, orientation: string)
	state.Walls[BoardUtils.wallKey(x, y, orientation)] = { X = x, Y = y, Orientation = orientation }
	BoardState.rebuildCaches(state)
end

local function cellsContain(cells: { any }, x: number, y: number): boolean
	for _, cell in cells do
		if cell.X == x and cell.Y == y then
			return true
		end
	end
	return false
end

-- --------------------------------------------------------------- geometrie

describe("Geometria tablei", function()
	it("tabla e 9x9 cu 8x8 intersectii pentru baricade", function()
		assertEqual(BoardUtils.Size, 9, "latura tablei")
		assertEqual(BoardUtils.WallSlots, 8, "intersectii")
	end)

	it("respinge celulele din afara tablei", function()
		assertTrue(BoardUtils.isInside({ X = 1, Y = 1 }), "coltul stanga-jos")
		assertTrue(BoardUtils.isInside({ X = 9, Y = 9 }), "coltul dreapta-sus")
		assertFalse(BoardUtils.isInside({ X = 0, Y = 5 }), "X sub limita")
		assertFalse(BoardUtils.isInside({ X = 10, Y = 5 }), "X peste limita")
		assertFalse(BoardUtils.isInside({ X = 5, Y = 10 }), "Y peste limita")
	end)

	it("cheia de muchie e aceeasi din ambele capete", function()
		local a = BoardUtils.edgeKey({ X = 5, Y = 5 }, { X = 5, Y = 6 })
		local b = BoardUtils.edgeKey({ X = 5, Y = 6 }, { X = 5, Y = 5 })
		assertEqual(a, b, "muchie normalizata")
	end)

	it("o baricada orizontala taie doua muchii verticale vecine", function()
		local edges = BoardUtils.wallBlockedEdges(4, 4, "Horizontal")
		assertEqual(#edges, 2, "numar de muchii")
		assertEqual(
			edges[1],
			BoardUtils.edgeKey({ X = 4, Y = 4 }, { X = 4, Y = 5 }),
			"prima muchie"
		)
		assertEqual(
			edges[2],
			BoardUtils.edgeKey({ X = 5, Y = 4 }, { X = 5, Y = 5 }),
			"a doua muchie"
		)
	end)

	it("o baricada verticala taie doua muchii orizontale vecine", function()
		local edges = BoardUtils.wallBlockedEdges(4, 4, "Vertical")
		assertEqual(
			edges[1],
			BoardUtils.edgeKey({ X = 4, Y = 4 }, { X = 5, Y = 4 }),
			"prima muchie"
		)
		assertEqual(
			edges[2],
			BoardUtils.edgeKey({ X = 4, Y = 5 }, { X = 5, Y = 5 }),
			"a doua muchie"
		)
	end)
end)

-- ------------------------------------------------------- reguli de baricada

describe("Asezarea baricadelor", function()
	it("accepta o baricada pe tabla goala", function()
		local state = newMatch("1v1")
		assertOk(WallRules.isValidWallPlacement(state, 1, 4, 4, "Horizontal"))
	end)

	it("respinge coordonatele din afara grilei de intersectii", function()
		local state = newMatch("1v1")
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 9, 4, "Horizontal"),
			"OUT_OF_BOUNDS",
			"X = 9"
		)
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 0, 4, "Horizontal"),
			"OUT_OF_BOUNDS",
			"X = 0"
		)
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4, 9, "Vertical"),
			"OUT_OF_BOUNDS",
			"Y = 9"
		)
	end)

	it("respinge orientarile inventate", function()
		local state = newMatch("1v1")
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4, 4, "Diagonal"),
			"BAD_ORIENTATION"
		)
		assertRejected(WallRules.isValidWallPlacement(state, 1, 4, 4, 7), "BAD_ORIENTATION")
	end)

	it("respinge coordonatele fractionare", function()
		local state = newMatch("1v1")
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4.5, 4, "Horizontal"),
			"BAD_COORDINATES"
		)
	end)

	it("respinge suprapunerea exacta", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 4, "Horizontal")
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4, 4, "Horizontal"),
			"WALL_CONFLICT"
		)
	end)

	it("respinge incrucisarea in plus pe acelasi centru", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 4, "Horizontal")
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4, 4, "Vertical"),
			"WALL_CONFLICT",
			"plus"
		)
	end)

	it("respinge doua orizontale care se suprapun pe jumatate", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 4, "Horizontal")
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 5, 4, "Horizontal"),
			"WALL_CONFLICT",
			"dreapta"
		)
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 3, 4, "Horizontal"),
			"WALL_CONFLICT",
			"stanga"
		)
	end)

	it("accepta doua orizontale cap la cap", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 4, "Horizontal")
		assertOk(WallRules.isValidWallPlacement(state, 1, 6, 4, "Horizontal"), "cap la cap")
		assertOk(WallRules.isValidWallPlacement(state, 1, 2, 4, "Horizontal"), "cap la cap invers")
	end)

	it("accepta orizontale alaturate pe randuri diferite", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 4, "Horizontal")
		assertOk(WallRules.isValidWallPlacement(state, 1, 4, 5, "Horizontal"), "randul de deasupra")
	end)

	it("accepta o verticala care porneste din capatul unei orizontale", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 4, "Horizontal")
		assertOk(
			WallRules.isValidWallPlacement(state, 1, 5, 4, "Vertical"),
			"perpendiculara decalata"
		)
	end)

	it("respinge doua verticale care se suprapun pe jumatate", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 4, "Vertical")
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4, 5, "Vertical"),
			"WALL_CONFLICT",
			"sus"
		)
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4, 3, "Vertical"),
			"WALL_CONFLICT",
			"jos"
		)
	end)

	it("pe tabla goala toate cele 128 de asezari sunt legale", function()
		local state = newMatch("1v1")
		assertEqual(#WallRules.getLegalWallPlacements(state, 1), 128, "asezari legale")
	end)

	it("respinge cand jucatorul a ramas fara baricade", function()
		local state = newMatch("1v1")
		state.Players[1].BarricadesRemaining = 0
		assertRejected(
			WallRules.isValidWallPlacement(state, 1, 4, 4, "Horizontal"),
			"NO_BARRICADES_LEFT"
		)
	end)
end)

-- ------------------------------------------------------------ deplasarea

describe("Deplasarea", function()
	it("permite cele patru directii ortogonale", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		local moves = MovementRules.getLegalMoves(state, 1)
		assertEqual(#moves, 4, "numar de mutari")
		assertTrue(cellsContain(moves, 5, 6), "sus")
		assertTrue(cellsContain(moves, 5, 4), "jos")
		assertTrue(cellsContain(moves, 4, 5), "stanga")
		assertTrue(cellsContain(moves, 6, 5), "dreapta")
	end)

	it("nu permite diagonala libera", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		assertRejected(MovementRules.isValidMove(state, 1, { X = 6, Y = 6 }), "ILLEGAL_MOVE")
	end)

	it("nu permite sarituri de mai multe celule", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		assertRejected(MovementRules.isValidMove(state, 1, { X = 5, Y = 7 }), "ILLEGAL_MOVE")
	end)

	it("limiteaza mutarile din colt la doua", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 1, Y = 1 }
		assertEqual(#MovementRules.getLegalMoves(state, 1), 2, "mutari din colt")
	end)

	it("o baricada opreste trecerea", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		seedWall(state, 5, 5, "Horizontal")
		assertRejected(
			MovementRules.isValidMove(state, 1, { X = 5, Y = 6 }),
			"ILLEGAL_MOVE",
			"prin zid"
		)
		assertOk(MovementRules.isValidMove(state, 1, { X = 5, Y = 4 }), "in jos ramane liber")
	end)

	it("respinge mutarea in propria celula", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		assertRejected(MovementRules.isValidMove(state, 1, { X = 5, Y = 5 }), "SAME_CELL")
	end)

	it("respinge coordonatele malformate", function()
		local state = newMatch("1v1")
		assertRejected(MovementRules.isValidMove(state, 1, "sus"), "BAD_COORDINATES")
		assertRejected(MovementRules.isValidMove(state, 1, { X = 5 }), "BAD_COORDINATES")
		assertRejected(MovementRules.isValidMove(state, 1, { X = 5.5, Y = 2 }), "BAD_COORDINATES")
		assertRejected(MovementRules.isValidMove(state, 1, { X = 12, Y = 2 }), "OUT_OF_BOUNDS")
	end)
end)

-- ------------------------------------------------------ saritura peste pion

describe("Intalnirea a doi pioni", function()
	it("sare drept peste adversar cand celula din spate e libera", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		state.Players[2].Position = { X = 5, Y = 6 }

		local moves = MovementRules.getLegalMoves(state, 1)
		assertTrue(cellsContain(moves, 5, 7), "aterizare in spatele adversarului")
		assertFalse(cellsContain(moves, 5, 6), "celula ocupata nu e mutare")
		assertFalse(cellsContain(moves, 4, 6), "fara ocolire cand saritura merge")
		assertFalse(cellsContain(moves, 6, 6), "fara ocolire cand saritura merge")
	end)

	it("ofera ocolirile diagonale cand un zid blocheaza aterizarea", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		state.Players[2].Position = { X = 5, Y = 6 }
		-- Zid intre adversar si celula din spatele lui.
		seedWall(state, 5, 6, "Horizontal")

		local moves = MovementRules.getLegalMoves(state, 1)
		assertFalse(cellsContain(moves, 5, 7), "saritura dreapta e blocata")
		assertTrue(cellsContain(moves, 4, 6), "ocolire pe stanga")
		assertTrue(cellsContain(moves, 6, 6), "ocolire pe dreapta")
	end)

	it("ofera ocolirile cand adversarul sta pe marginea tablei", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 8 }
		state.Players[2].Position = { X = 5, Y = 9 }

		local moves = MovementRules.getLegalMoves(state, 1)
		assertFalse(cellsContain(moves, 5, 10), "nu se sare in afara tablei")
		assertTrue(cellsContain(moves, 4, 9), "ocolire pe stanga")
		assertTrue(cellsContain(moves, 6, 9), "ocolire pe dreapta")
	end)

	it("trateaza un al treilea pion in spate ca pe un blocaj", function()
		local state = newMatch("1v1v1v1")
		state.Players[1].Position = { X = 5, Y = 5 }
		state.Players[2].Position = { X = 5, Y = 6 }
		state.Players[3].Position = { X = 5, Y = 7 }
		state.Players[4].Position = { X = 1, Y = 1 }

		local moves = MovementRules.getLegalMoves(state, 1)
		assertFalse(cellsContain(moves, 5, 7), "aterizarea e ocupata")
		assertTrue(cellsContain(moves, 4, 6), "ocolire pe stanga")
		assertTrue(cellsContain(moves, 6, 6), "ocolire pe dreapta")
	end)

	it("nu ofera ocolire prin zid lateral", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 8 }
		state.Players[2].Position = { X = 5, Y = 9 }
		-- Zid intre adversar si ocolirea din dreapta.
		seedWall(state, 5, 8, "Vertical")

		local moves = MovementRules.getLegalMoves(state, 1)
		assertFalse(cellsContain(moves, 6, 9), "ocolirea dreapta e zidita")
		assertTrue(cellsContain(moves, 4, 9), "ocolirea stanga ramane")
	end)
end)

-- ------------------------------------------------------------ pathfinding

describe("Verificarea drumului", function()
	it("gaseste drumul pe tabla goala si ii masoara lungimea", function()
		local state = newMatch("1v1")
		local ok, distance = Pathfinding.hasPathToGoal(state, 1)
		assertTrue(ok, "exista drum")
		assertEqual(distance, 8, "de la Y=1 la Y=9")
	end)

	it("ignora pionii, fiindca ei se misca", function()
		local state = newMatch("1v1")
		state.Players[2].Position = { X = 5, Y = 2 }
		local ok, distance = Pathfinding.hasPathToGoal(state, 1)
		assertTrue(ok, "adversarul nu e zid")
		assertEqual(distance, 8, "distanta neschimbata")
	end)

	it("ocoleste baricadele si alungeste drumul", function()
		local state = newMatch("1v1")
		seedWall(state, 4, 1, "Horizontal")
		seedWall(state, 6, 1, "Horizontal")
		local ok, distance = Pathfinding.hasPathToGoal(state, 1)
		assertTrue(ok, "drumul exista")
		assertTrue(distance > 8, "drumul e mai lung decat linia dreapta")
	end)

	it("vede cand un buzunar sigilat taie orice drum", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 1, Y = 1 }
		seedWall(state, 1, 1, "Horizontal")
		seedWall(state, 2, 1, "Vertical")
		assertFalse(Pathfinding.hasPathToGoal(state, 1), "jucator ingropat")
	end)
end)

-- ------------------------------------------- regula care nu se incalca niciodata

describe("Interdictia de a ingropa un jucator", function()
	it("respinge baricada ce ar sigila ultimul drum al adversarului", function()
		local state = newMatch("1v1")

		-- P1 coboara in coltul stanga-jos, P2 face pasi in gol intre timp.
		assertOk(move(state, 4, 1), "P1 spre stanga")
		assertOk(move(state, 5, 8), "P2 inainteaza")
		assertOk(move(state, 3, 1), "P1 spre stanga")
		assertOk(move(state, 5, 9), "P2 inapoi")
		assertOk(move(state, 2, 1), "P1 spre stanga")
		assertOk(move(state, 5, 8), "P2 inainteaza")
		assertOk(move(state, 1, 1), "P1 ajunge in colt")

		-- P2 inchide iesirea de sus a buzunarului. Inca legal: P1 poate iesi lateral.
		assertOk(wall(state, 1, 1, "Horizontal"), "prima baricada")

		-- P1 e obligat sa iasa spre dreapta.
		assertOk(move(state, 2, 1), "singura mutare ramasa")

		-- A doua baricada ar sigila complet buzunarul {(1,1), (2,1)} cu P1 inauntru.
		local attempt = WallRules.isValidWallPlacement(state, 2, 2, 1, "Vertical")
		assertRejected(attempt, "WOULD_BLOCK_PLAYER_1", "sigilarea buzunarului")

		-- Respingerea nu costa nimic: stocul si tura raman neatinse.
		local before = state.Players[2].BarricadesRemaining
		assertRejected(wall(state, 2, 1, "Vertical"), "WOULD_BLOCK_PLAYER_1", "prin motor")
		assertEqual(state.Players[2].BarricadesRemaining, before, "stocul nu se consuma")
		assertEqual(BoardState.getCurrentSlot(state), 2, "tura ramane la P2")
	end)

	it("respinge si cand victima ar fi propriul coechipier", function()
		local state = newMatch("2v2")
		-- Slot 2 e coechipierul lui 1. Il asez intr-un buzunar aproape inchis.
		state.Players[2].Position = { X = 2, Y = 1 }
		seedWall(state, 1, 1, "Horizontal")

		local attempt = WallRules.isValidWallPlacement(state, 1, 2, 1, "Vertical")
		assertRejected(attempt, "WOULD_BLOCK_PLAYER_2", "nu-ti zidesti partenerul")
	end)

	it("lasa baricada sa treaca daca mai exista macar un ocol", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 1, Y = 1 }
		seedWall(state, 1, 1, "Horizontal")
		-- Iesirea spre dreapta ramane deschisa, deci plasarea e legala.
		assertOk(WallRules.isValidWallPlacement(state, 2, 4, 4, "Horizontal"), "zid neutru")
	end)
end)

-- --------------------------------------------------------------- ture

describe("Sistemul de ture", function()
	it("alterneaza in 1v1", function()
		local state = newMatch("1v1")
		assertEqual(BoardState.getCurrentSlot(state), 1, "incepe P1")
		assertOk(move(state, 5, 2))
		assertEqual(BoardState.getCurrentSlot(state), 2, "urmeaza P2")
		assertOk(move(state, 5, 8))
		assertEqual(BoardState.getCurrentSlot(state), 1, "revine P1")
		assertEqual(state.TurnNumber, 3, "numarul turei creste")
	end)

	it("respecta ordinea data de mod", function()
		assertEqual(
			table.concat(GameConfig.Modes["1v1v1"].TurnOrder, ","),
			"1,2,3",
			"trei jucatori"
		)
		assertEqual(
			table.concat(GameConfig.Modes["1v1v1v1"].TurnOrder, ","),
			"1,2,3,4",
			"patru jucatori"
		)
		assertEqual(
			table.concat(GameConfig.Modes["2v2"].TurnOrder, ","),
			"1,3,2,4",
			"echipele alterneaza"
		)
	end)

	it("in 2v2 tura trece intre echipe, nu in interiorul lor", function()
		local state = newMatch("2v2")
		local order = {}
		for _ = 1, 4 do
			local slot = BoardState.getCurrentSlot(state)
			table.insert(order, state.Players[slot].Team)
			BoardState.advanceTurn(state)
		end
		assertEqual(table.concat(order, ","), "1,2,1,2", "echipele se schimba la fiecare tura")
	end)

	it("respinge actiunea unui jucator care nu e la rand", function()
		local state = newMatch("1v1")
		assertRejected(BoardState.applyMove(state, 2, { X = 5, Y = 8 }), "NOT_YOUR_TURN")
		assertRejected(BoardState.applyWall(state, 2, 4, 4, "Horizontal"), "NOT_YOUR_TURN")
	end)

	it("o mutare respinsa nu consuma tura", function()
		local state = newMatch("1v1")
		assertRejected(move(state, 9, 9), "ILLEGAL_MOVE")
		assertEqual(BoardState.getCurrentSlot(state), 1, "tot P1 la mutare")
		assertEqual(state.TurnNumber, 1, "numarul turei neschimbat")
	end)

	it("nu se pot face doua actiuni intr-o tura", function()
		local state = newMatch("1v1")
		assertOk(move(state, 5, 2), "mutarea")
		assertRejected(
			BoardState.applyWall(state, 1, 4, 4, "Horizontal"),
			"NOT_YOUR_TURN",
			"si baricada"
		)
	end)

	it("baricada acceptata consuma stoc si trece tura", function()
		local state = newMatch("1v1")
		assertOk(wall(state, 4, 4, "Horizontal"))
		assertEqual(state.Players[1].BarricadesRemaining, 9, "stoc consumat")
		assertEqual(BoardState.getCurrentSlot(state), 2, "tura a trecut")
	end)
end)

-- ------------------------------------------------------------- victorie

describe("Conditia de victorie", function()
	it("1v1: castiga cine atinge randul advers", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 8 }
		-- P2 pleaca din (5,9): o celula ocupata nu e o mutare legala.
		state.Players[2].Position = { X = 1, Y = 9 }
		assertOk(move(state, 5, 9), "pasul final")
		assertEqual(state.Status, "FINISHED", "jocul s-a incheiat")
		assertEqual(state.Winner, 1, "castigator")
		assertEqual(state.WinningTeam, 1, "echipa castigatoare")
	end)

	it("1v1: orice celula de pe randul tinta e buna", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 1, Y = 8 }
		assertOk(move(state, 1, 9), "colt in loc de mijloc")
		assertEqual(state.Winner, 1, "castigator")
	end)

	it("mod cu centru: castiga cine ajunge la (5,5)", function()
		local state = newMatch("1v1v1")
		state.Players[1].Position = { X = 5, Y = 4 }
		assertOk(move(state, 5, 5), "intrare in centru")
		assertEqual(state.Status, "FINISHED", "jocul s-a incheiat")
		assertEqual(state.Winner, 1, "castigator")
	end)

	it("mod cu centru: directia de intrare nu conteaza", function()
		local state = newMatch("1v1v1")
		state.Players[1].Position = { X = 4, Y = 5 }
		assertOk(move(state, 5, 5), "intrare dinspre stanga")
		assertEqual(state.Winner, 1, "castigator")
	end)

	it("2v2: e de ajuns ca unul din echipa sa ajunga", function()
		local state = newMatch("2v2")
		-- Slot 2 e in echipa 1 si nu e primul la mutare; il duc eu la rand.
		state.TurnIndex = 3
		state.Players[2].Position = { X = 4, Y = 8 }
		assertEqual(BoardState.getCurrentSlot(state), 2, "e randul lui")
		assertOk(move(state, 4, 9), "pasul final")
		assertEqual(state.WinningTeam, 1, "castiga echipa, nu individul")
	end)

	it("dupa final nu se mai accepta nimic", function()
		local state = newMatch("1v1")
		state.Players[1].Position = { X = 5, Y = 8 }
		state.Players[2].Position = { X = 1, Y = 9 }
		assertOk(move(state, 5, 9))
		-- Mutari care ar fi fost perfect legale inainte de fluierul final.
		assertRejected(
			BoardState.applyMove(state, 2, { X = 1, Y = 8 }),
			"GAME_NOT_ACTIVE",
			"mutare dupa final"
		)
		assertRejected(
			BoardState.applyWall(state, 2, 4, 4, "Horizontal"),
			"GAME_NOT_ACTIVE",
			"baricada dupa final"
		)
	end)

	it("jocul care nu a inceput nu accepta actiuni", function()
		local state = newMatch("1v1")
		state.Status = "STARTING"
		assertRejected(BoardState.applyMove(state, 1, { X = 5, Y = 2 }), "GAME_NOT_ACTIVE")
	end)
end)

-- ------------------------------------------------------- configurarea modurilor

describe("Configurarea modurilor", function()
	it("stocul de baricade respecta specificatia", function()
		assertEqual(GameConfig.Modes["1v1"].Barricades, 10, "1v1")
		assertEqual(GameConfig.Modes["1v1v1"].Barricades, 6, "1v1v1")
		assertEqual(GameConfig.Modes["1v1v1v1"].Barricades, 5, "1v1v1v1")
		assertEqual(GameConfig.Modes["2v2"].Barricades, 5, "2v2")
	end)

	it("pozitiile de start sunt cele din specificatie", function()
		local state = newMatch("1v1v1v1")
		local expected = { "5,1", "9,5", "5,9", "1,5" }
		for slot, want in expected do
			assertEqual(BoardUtils.cellKey(state.Players[slot].Position), want, "slot " .. slot)
		end
	end)

	it("in 2v2 coechipierii pornesc alaturi, pe laturi opuse", function()
		local state = newMatch("2v2")
		assertEqual(BoardUtils.cellKey(state.Players[1].Position), "5,1", "A1")
		assertEqual(BoardUtils.cellKey(state.Players[2].Position), "4,1", "A2")
		assertEqual(BoardUtils.cellKey(state.Players[3].Position), "5,9", "B1")
		assertEqual(BoardUtils.cellKey(state.Players[4].Position), "6,9", "B2")
		assertEqual(state.Players[1].Team, state.Players[2].Team, "aceeasi echipa")
		assertTrue(state.Players[1].Team ~= state.Players[3].Team, "echipe diferite")
	end)

	it("toate modurile pornesc cu drum valid pentru toata lumea", function()
		for _, modeId in GameConfig.ModeOrder do
			local state = newMatch(modeId)
			assertTrue(Pathfinding.allPlayersHavePath(state), modeId .. ": drum la start")
		end
	end)

	it("fiecare mod are exact atatea sloturi cati jucatori cere", function()
		for _, modeId in GameConfig.ModeOrder do
			local mode = GameConfig.Modes[modeId]
			assertEqual(#mode.Slots, mode.Players, modeId .. ": sloturi")
			assertEqual(#mode.TurnOrder, mode.Players, modeId .. ": ordine de tura")
		end
	end)
end)

-- ------------------------------------------------------------ deconectari

describe("Retragerea unui jucator", function()
	it("1v1: plecarea unuia incheie meciul in favoarea celuilalt", function()
		local state = newMatch("1v1")
		BoardState.withdrawPlayer(state, 1)
		assertEqual(state.Status, "FINISHED", "meciul s-a incheiat")
		assertEqual(state.WinningTeam, 2, "castiga echipa ramasa")
	end)

	it("patru jucatori: meciul continua cu ceilalti trei", function()
		local state = newMatch("1v1v1v1")
		BoardState.withdrawPlayer(state, 2)
		assertEqual(state.Status, "PLAYING", "jocul continua")
		assertEqual(table.concat(state.TurnOrder, ","), "1,3,4", "slotul a iesit din rotatie")
	end)

	it("nu sare peste randul nimanui cand pleaca unul dinaintea ta", function()
		local state = newMatch("1v1v1v1")
		state.TurnIndex = 3 -- e randul slotului 3
		BoardState.withdrawPlayer(state, 1)
		assertEqual(BoardState.getCurrentSlot(state), 3, "tot slotul 3 e la mutare")
	end)

	it("cand pleaca chiar cel la mutare, urmeaza cel de dupa el", function()
		local state = newMatch("1v1v1v1")
		state.TurnIndex = 2 -- e randul slotului 2
		BoardState.withdrawPlayer(state, 2)
		assertEqual(BoardState.getCurrentSlot(state), 3, "trece la urmatorul")
	end)

	it("cand pleaca ultimul din rotatie, tura se intoarce la inceput", function()
		local state = newMatch("1v1v1v1")
		state.TurnIndex = 4
		BoardState.withdrawPlayer(state, 4)
		assertEqual(BoardState.getCurrentSlot(state), 1, "rotatia se reia")
	end)

	it("2v2: meciul continua daca a mai ramas cineva din fiecare echipa", function()
		local state = newMatch("2v2")
		BoardState.withdrawPlayer(state, 2)
		assertEqual(state.Status, "PLAYING", "jocul continua")
		assertEqual(table.concat(state.TurnOrder, ","), "1,3,4", "ordinea ramasa")
	end)

	it("2v2: cand cade o echipa intreaga, castiga cealalta", function()
		local state = newMatch("2v2")
		BoardState.withdrawPlayer(state, 1)
		BoardState.withdrawPlayer(state, 2)
		assertEqual(state.Status, "FINISHED", "meciul s-a incheiat")
		assertEqual(state.WinningTeam, 2, "castiga echipa completa")
	end)
end)

-- --------------------------------------------------------------- replicare

describe("Replicarea starii", function()
	it("snapshot si inapoi pastreaza tabla identica", function()
		local state = newMatch("2v2")
		assertOk(wall(state, 4, 4, "Horizontal"), "baricada 1")
		assertOk(move(state, 5, 8), "mutare")
		assertOk(wall(state, 2, 6, "Vertical"), "baricada 2")

		local restored = BoardState.fromSnapshot(BoardState.snapshot(state))

		assertEqual(restored.TurnNumber, state.TurnNumber, "numarul turei")
		assertEqual(
			BoardState.getCurrentSlot(restored),
			BoardState.getCurrentSlot(state),
			"slotul la mutare"
		)
		-- 2v2 porneste cu 5 baricade, iar slotul 1 tocmai a consumat una.
		assertEqual(restored.Players[1].BarricadesRemaining, 4, "stoc replicat")
		assertEqual(BoardUtils.cellKey(restored.Players[3].Position), "5,8", "pozitie replicata")

		-- Cache-urile refacute trebuie sa dea aceleasi verdicte ca originalul.
		for _, slot in { 1, 2, 3, 4 } do
			assertEqual(
				#MovementRules.getLegalMoves(restored, slot),
				#MovementRules.getLegalMoves(state, slot),
				"mutari legale pentru slot " .. slot
			)
		end
		assertEqual(
			#WallRules.getLegalWallPlacements(restored, 1),
			#WallRules.getLegalWallPlacements(state, 1),
			"asezari legale"
		)
	end)
end)

-- --------------------------------------------------------------- ceasul

describe("Ceasul jucatorilor", function()
	it("fiecare jucator porneste cu ceasul plin", function()
		local state = newMatch("1v1")
		assertEqual(state.Players[1].TimeRemaining, GameConfig.Timing.PlayerClock, "ceas slot 1")
		assertEqual(state.Players[2].TimeRemaining, GameConfig.Timing.PlayerClock, "ceas slot 2")
	end)

	it("timpul se scade numai celui aflat la mutare", function()
		local state = newMatch("1v1")
		BoardState.chargeTime(state, 30)

		assertEqual(
			state.Players[1].TimeRemaining,
			GameConfig.Timing.PlayerClock - 30,
			"cel la mutare"
		)
		assertEqual(
			state.Players[2].TimeRemaining,
			GameConfig.Timing.PlayerClock,
			"cel care asteapta"
		)
	end)

	it("ceasul trece la celalalt jucator dupa mutare", function()
		local state = newMatch("1v1")
		BoardState.chargeTime(state, 10)
		assertOk(move(state, 5, 2))
		BoardState.chargeTime(state, 10)

		assertEqual(state.Players[1].TimeRemaining, GameConfig.Timing.PlayerClock - 10, "slot 1")
		assertEqual(state.Players[2].TimeRemaining, GameConfig.Timing.PlayerClock - 10, "slot 2")
	end)

	it("nu se scade timp cat meciul nu e in desfasurare", function()
		local state = newMatch("1v1")
		state.Status = "STARTING"
		BoardState.chargeTime(state, 60)

		assertEqual(state.Players[1].TimeRemaining, GameConfig.Timing.PlayerClock, "ceas neatins")
	end)

	it("ceasul nu coboara sub zero", function()
		local state = newMatch("1v1")
		BoardState.chargeTime(state, GameConfig.Timing.PlayerClock + 500)

		assertEqual(state.Players[1].TimeRemaining, 0, "oprit la zero")
	end)

	it("cine ramane fara timp iese din meci si celalalt castiga", function()
		local state = newMatch("1v1")
		local loser = BoardState.chargeTime(state, GameConfig.Timing.PlayerClock)

		assertEqual(loser, 1, "slotul care a pierdut")
		assertEqual(state.Status, "FINISHED", "meciul s-a incheiat")
		assertEqual(state.Winner, 2, "castigatorul")
	end)

	--[[
		Cu trei jucatori, expirarea unuia nu incheie meciul: ceilalti doi continua.
		Testul exista pentru ca retragerea umbla in `TurnOrder`, iar o scapare
		acolo ar sari peste tura cuiva fara sa se vada imediat.
	]]
	it("intr-un meci cu trei, expirarea unuia lasa meciul in joc", function()
		local state = newMatch("1v1v1")
		local loser = BoardState.chargeTime(state, GameConfig.Timing.PlayerClock)

		assertEqual(loser, 1, "slotul expirat")
		assertEqual(state.Status, "PLAYING", "meciul continua")
		assertEqual(#state.TurnOrder, 2, "au ramas doi la mutare")
	end)

	it("ceasul trece prin serializare", function()
		local state = newMatch("1v1")
		BoardState.chargeTime(state, 42)
		local restored = BoardState.fromSnapshot(BoardState.snapshot(state))

		assertEqual(
			restored.Players[1].TimeRemaining,
			GameConfig.Timing.PlayerClock - 42,
			"ceas replicat"
		)
	end)
end)

--[[
	Catalogul e singura lista de obiecte din proiect: `Skins.Order` o imprumuta,
	vitrinele din lobby se uita in ea, iar mai tarziu se va uita si cumpararea.
	O gaura in ea nu se vede nicaieri pana cand cineva plateste pentru un obiect
	care nu exista, deci se verifica aici.
]]
describe("Catalogul de obiecte", function()
	local Catalog = Shared.Catalog

	it("acopera fiecare id, la fiecare fel", function()
		for _, kind in Catalog.Kinds do
			for _, id in Catalog.Order do
				local item = Catalog.get(kind, id)
				assertTrue(item, string.format("%s/%s lipseste", kind, id))
				assertEqual(item.Id, id, "id")
				assertEqual(item.Kind, kind, "fel")
			end
		end
	end)

	it("listeaza in ordinea din vitrina", function()
		local list = Catalog.list("Barricade")
		assertEqual(#list, #Catalog.Order, "cate obiecte")
		for index, id in Catalog.Order do
			assertEqual(list[index].Id, id, "pozitia " .. index)
		end
	end)

	it("are exact un obiect de start la fiecare fel", function()
		for _, kind in Catalog.Kinds do
			local found = 0
			for _, item in Catalog.list(kind) do
				if item.Default then
					found += 1
				end
			end
			assertEqual(found, 1, kind .. ": obiecte de start")
			assertTrue(Catalog.get(kind, Catalog.default(kind)).Default, kind .. ": start valid")
		end
	end)

	it("nu cunoaste id-uri din afara listei", function()
		assertEqual(Catalog.get("Barricade", "nuexista"), nil, "id inventat")
		assertEqual(Catalog.get("Barricade", nil), nil, "fara id")
	end)

	-- Un cont nou nu are salvare, si tot trebuie sa poata juca.
	it("da obiectul de start oricui, chiar si fara inventar", function()
		local default = Catalog.default("Podium")
		assertTrue(Catalog.owns(nil, "Podium", default), "start fara inventar")
		assertTrue(Catalog.owns({}, "Podium", default), "start cu inventar gol")
	end)

	it("cere cumparare pentru restul", function()
		local other = nil
		for _, item in Catalog.list("Podium") do
			if not item.Default then
				other = item.Id
				break
			end
		end
		assertTrue(other, "exista macar un obiect de cumparat")
		assertFalse(Catalog.owns(nil, "Podium", other), "nedetinut")
		assertFalse(Catalog.owns({}, "Podium", other), "nedetinut, inventar gol")
		assertTrue(
			Catalog.owns({ [Catalog.key("Podium", other)] = true }, "Podium", other),
			"detinut"
		)
	end)

	--[[
		Acelasi id exista in amandoua felurile — `dragon` e si baricada, si
		podium — dar sunt doua obiecte, cu doua preturi. Cheia poarta felul
		tocmai ca unul cumparat sa nu-l dea pe gratis si pe celalalt.
	]]
	it("cumparat intr-un fel nu inseamna detinut in celalalt", function()
		local owned = { [Catalog.key("Barricade", "dragon")] = true }
		assertTrue(Catalog.owns(owned, "Barricade", "dragon"), "baricada cumparata")
		assertFalse(Catalog.owns(owned, "Podium", "dragon"), "podiumul nu vine la pachet")
	end)

	it("nu da nimic pentru un id inexistent", function()
		assertFalse(Catalog.owns({ nuexista = true }, "Podium", "nuexista"), "id inventat")
	end)

	-- ---------------------------------------------------- cumpararea pe banuti

	--[[
		Aceeasi functie o cheama serverul inainte sa ia banii si clientul ca sa
		stie daca aprinde butonul. Testele astea sunt singurul loc in care cele
		doua folosinte se intalnesc.
	]]
	it("obiectul de start nu se mai cumpara", function()
		local ok, reason = Catalog.canBuy("Barricade", Catalog.default("Barricade"), 999999, nil)
		assertFalse(ok, "deja al tau")
		assertEqual(reason, "OWNED", "motivul")
	end)

	it("un id inventat nu se cumpara", function()
		local ok, reason = Catalog.canBuy("Barricade", "nuexista", 999999, nil)
		assertFalse(ok, "articol inexistent")
		assertEqual(reason, "UNKNOWN", "motivul")
	end)

	it("fara bani nu se cumpara", function()
		local ok, reason = Catalog.canBuy("Barricade", "dragon", 0, nil)
		assertFalse(ok, "buzunar gol")
		assertEqual(reason, "POOR", "motivul")
	end)

	it("cu exact pretul se cumpara, cu un banut mai putin nu", function()
		local price = (Catalog.get("Barricade", "dragon") :: any).Coins
		assertTrue(Catalog.canBuy("Barricade", "dragon", price, nil), "exact pretul ajunge")
		assertFalse(Catalog.canBuy("Barricade", "dragon", price - 1, nil), "un banut mai putin")
	end)

	it("ce ai deja nu se mai cumpara", function()
		local owned = { [Catalog.key("Barricade", "dragon")] = true }
		local ok, reason = Catalog.canBuy("Barricade", "dragon", 999999, owned)
		assertFalse(ok, "deja detinut")
		assertEqual(reason, "OWNED", "motivul")
	end)

	--[[
		Pret zero la un obiect care nu e de start inseamna "inca nu se vinde", nu
		"e gratis". Distinctia conteaza: altfel, un obiect adaugat in lista dar
		neprevazut cu pret ar pleca pe gratis pana observa cineva.
	]]
	it("pretul zero la un obiect care nu e de start inseamna nevandut", function()
		local kind: any = "Barricade"
		local id = "dragon"
		local item = Catalog.get(kind, id) :: any
		local kept = item.Coins
		item.Coins = 0

		local ok, reason = Catalog.canBuy(kind, id, 999999, nil)
		item.Coins = kept

		assertFalse(ok, "nu se vinde")
		assertEqual(reason, "NOT_FOR_SALE", "motivul")
	end)

	--[[
		`resolve` e usa prin care intra o cerere de la client. Tot ce nu e o
		pereche cunoscuta de fel si id trebuie sa cada aici, inainte sa ajunga
		langa portofel.
	]]
	it("cererea din retea se verifica inainte de orice", function()
		assertEqual(Catalog.resolve("Barricade", nil), nil, "fara id")
		assertEqual(Catalog.resolve("Barricade", 7), nil, "id care nu e text")
		assertEqual(Catalog.resolve("Barricade", "nuexista"), nil, "id inventat")
		assertEqual(Catalog.resolve("Zid", "dragon"), nil, "fel inventat")
		assertEqual(Catalog.resolve(nil, "dragon"), nil, "fara fel")
		assertEqual(Catalog.resolve({}, "dragon"), nil, "fel care nu e text")

		local found = Catalog.resolve("Podium", "dragon")
		assertTrue(found, "perechea buna trece")
		assertEqual((found :: any).Kind, "Podium", "felul e cel cerut")
		assertEqual((found :: any).Id, "dragon", "id-ul e cel cerut")
	end)

	it("cheia unui obiect gasit e cea cu felul in ea", function()
		local found = Catalog.resolve("Podium", "dragon") :: any
		assertEqual(Catalog.keyOf(found), Catalog.key("Podium", "dragon"), "aceeasi cheie")
	end)

	it("orice obiect care nu e de start are un pret in banuti", function()
		for _, kind in Catalog.Kinds do
			for _, item in Catalog.list(kind) do
				if not item.Default then
					assertTrue(item.Coins > 0, kind .. "/" .. item.Id .. " are pret")
				end
			end
		end
	end)
end)

describe("Numaratoarea de free play", function()
	local FreePlayRules = Shared.FreePlayRules
	local MIN, CAP = GameConfig.FreePlay.Minimum, GameConfig.Modes[GameConfig.FreePlay.Mode].Players

	local function decide(waiting: number, remaining: number): string
		return FreePlayRules.decide(waiting, MIN, CAP, remaining)
	end

	it("asteapta cat mai are ceas si soclul nu e plin", function()
		assertEqual(decide(0, 10), "WAIT", "gol")
		assertEqual(decide(1, 10), "WAIT", "unul singur")
		assertEqual(
			decide(MIN, 10),
			if MIN >= CAP then "START" else "WAIT",
			"destui, dar mai e ceas"
		)
	end)

	it("porneste meciul cand soclul s-a umplut, oricat ceas ar mai fi", function()
		assertEqual(decide(CAP, 999), "START", "plin cu ceasul la inceput")
		assertEqual(decide(CAP + 1, 999), "START", "mai multi decat incap")
	end)

	it("porneste la zero daca s-au strans destui", function()
		assertEqual(decide(MIN, 0), "START", "exact minimul")
		assertEqual(decide(MIN, -0.5), "START", "ceasul trecut de zero")
	end)

	--[[
		Cazul pentru care exista regula asta: unul singur pe soclu nu blocheaza
		locul la nesfarsit cu un ceas oprit pe zero.
	]]
	it("o ia de la capat la zero cand e prea putina lume", function()
		assertEqual(decide(1, 0), "RESTART", "unul singur")
		assertEqual(decide(0, 0), "RESTART", "nimeni")
		assertEqual(decide(1, -3), "RESTART", "ceasul trecut demult de zero")
	end)

	it("nu porneste niciodata sub minim cat timp mai e ceas", function()
		for waiting = 0, MIN - 1 do
			assertEqual(decide(waiting, 5), "WAIT", "sub minim, cu ceas")
		end
	end)
end)

describe("Banutii de la finalul meciului", function()
	local Rewards = Shared.Rewards
	local PAY = GameConfig.Rewards

	it("plateste si pe cel care a pierdut", function()
		assertTrue(Rewards.forMatch("LOSS") > 0, "pierderea nu e zero")
		assertEqual(Rewards.forMatch("LOSS"), PAY.Participation, "pierderea ia participarea")
	end)

	it("castigul e participarea plus bonusul", function()
		assertEqual(Rewards.forMatch("WIN"), PAY.Participation + PAY.WinBonus, "castigul")
		assertTrue(Rewards.forMatch("WIN") > Rewards.forMatch("LOSS"), "castigul bate pierderea")
	end)

	--[[
		In 2v2 castiga echipa, nu cel care a facut ultimul pas: coechipierul
		celui ajuns primul trebuie platit la fel.
	]]
	it("rezultatul se citeste dupa echipa", function()
		assertEqual(Rewards.outcomeFor(1, 1), "WIN", "echipa castigatoare")
		assertEqual(Rewards.outcomeFor(1, 2), "LOSS", "cealalta echipa")
		assertEqual(Rewards.outcomeFor(2, 2), "WIN", "castiga echipa a doua")
	end)

	it("fara castigator, toata lumea iese pe pierdere", function()
		assertEqual(Rewards.outcomeFor(nil, 1), "LOSS", "meci anulat")
		assertEqual(Rewards.outcomeFor(nil, 2), "LOSS", "meci anulat, cealalta echipa")
	end)
end)

return true
