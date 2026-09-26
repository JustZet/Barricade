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

	--[[
		Ceremonia de la final e facuta din trei numere care se conditioneaza, si
		niciunul nu stie de celelalte: soclul urca, panoul apare dupa el, panoul
		pleaca singur, iar masa trebuie sa tina pana atunci. Reglat unul singur,
		jucatorul ajunge in lobby cu ecranul de victorie inca peste ochi — si
		nimic nu s-ar plange, fiindca fiecare numar in parte e valid.
	]]
	it("masa tine cat toata ceremonia de la final", function()
		local timing = GameConfig.Timing
		assertTrue(
			timing.VictoryHold >= timing.VictoryReveal + timing.VictoryAutoLeave,
			"VictoryHold acopera dezvaluirea si plecarea singura"
		)
		assertTrue(
			timing.VictoryReveal > timing.PodiumRise,
			"panoul apare dupa ce soclul s-a oprit din urcat"
		)
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

--[[
	Ce porti din ce ai.

	Aceleasi functii le ruleaza si serverul inainte sa scrie atributul, si
	magazinul cand isi deseneaza butonul. Testele sunt singurul loc in care cele
	doua folosinte se intalnesc.
]]
describe("Echiparea obiectelor", function()
	local Catalog = Shared.Catalog
	local Loadout = Shared.Loadout

	local function ownedSet(kind: any, id: string): any
		return { [Catalog.key(kind, id)] = true }
	end

	it("numeste atributele pe fel, nu pe obiect", function()
		local wall = Loadout.attribute("Barricade")
		local podium = Loadout.attribute("Podium")
		assertTrue(wall ~= podium, "doua feluri, doua atribute")
		assertEqual(Loadout.attribute("Barricade"), wall, "acelasi nume de fiecare data")
	end)

	it("porneste cu obiectele de start, la fiecare fel", function()
		local set = Loadout.defaults()
		for _, kind in Catalog.Kinds do
			assertEqual(set[kind], Catalog.default(kind), kind .. ": obiectul de start")
		end
	end)

	it("obiectul de start se echipeaza si fara inventar", function()
		assertTrue(
			Loadout.canEquip(nil, "Barricade", Catalog.default("Barricade")),
			"start fara salvare"
		)
	end)

	it("nu se echipeaza ce nu e cumparat", function()
		local ok, reason = Loadout.canEquip({}, "Barricade", "dragon")
		assertFalse(ok, "nedetinut")
		assertEqual(reason, "LOCKED", "motivul")
	end)

	it("nu se echipeaza un id inventat", function()
		local ok, reason = Loadout.canEquip(nil, "Barricade", "nuexista")
		assertFalse(ok, "articol inexistent")
		assertEqual(reason, "UNKNOWN", "motivul")
	end)

	--[[
		Cheia de inventar poarta felul, deci si echiparea trebuie sa-l poarte:
		altfel baricada `dragon` cumparata ar imbraca si podiumul `dragon`.
	]]
	it("cumparat intr-un fel nu se poate echipa in celalalt", function()
		local owned = ownedSet("Barricade", "dragon")
		assertTrue(Loadout.canEquip(owned, "Barricade", "dragon"), "baricada cumparata")
		assertFalse(Loadout.canEquip(owned, "Podium", "dragon"), "podiumul nu vine la pachet")
	end)

	it("ce nu se poate purta cade pe obiectul de start", function()
		assertEqual(
			Loadout.sanitize({}, "Barricade", "dragon"),
			Catalog.default("Barricade"),
			"nedetinut"
		)
		assertEqual(
			Loadout.sanitize(nil, "Podium", "nuexista"),
			Catalog.default("Podium"),
			"id inventat"
		)
		assertEqual(
			Loadout.sanitize(nil, "Podium", 7),
			Catalog.default("Podium"),
			"id care nu e text"
		)
		assertEqual(
			Loadout.sanitize(ownedSet("Podium", "dragon"), "Podium", "dragon"),
			"dragon",
			"detinut, deci ramane"
		)
	end)

	--[[
		Ce vine din salvare se verifica altfel: doar ca obiectul exista, nu si ca
		e detinut. Inventarul si alegerea se citesc pe doua fire, si cine ajunge
		al doilea n-are voie sa dezbrace pe nimeni — vezi comentariul din
		`Loadout.restore`.
	]]
	it("salvarea se crede pe cuvant despre ce detine", function()
		local set = Loadout.restore({ Barricade = "dragon", Podium = "portal" })
		assertEqual(set.Barricade, "dragon", "baricada salvata")
		assertEqual(set.Podium, "portal", "podiumul salvat")
	end)

	it("salvarea stricata se intoarce la obiectele de start", function()
		-- Fara salvare deloc, cu una care nu e tabela, si cu una care poarta un
		-- id retras din catalog: toate trei dau acelasi lucru.
		local broken: { any } = { Loadout.restore(nil), { Barricade = "nuexista" }, "text", 7 }

		for _, saved in broken do
			local set = Loadout.restore(saved)
			for _, kind in Catalog.Kinds do
				assertEqual(set[kind], Catalog.default(kind), kind .. ": cade pe start")
			end
		end
	end)
end)

describe("Numaratoarea de free play", function()
	local FreePlayRules = Shared.FreePlayRules
	local MIN, CAP = FreePlayRules.bounds(GameConfig.FreePlay.Modes)

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

	it("primeste de la doi pana la patru jucatori", function()
		assertEqual(MIN, 2, "minimul")
		assertEqual(CAP, 4, "cati incap")
	end)

	it("alege modul dupa cati s-au strans", function()
		local modes = GameConfig.FreePlay.Modes
		assertEqual(FreePlayRules.modeFor(modes, 0), nil, "nimeni")
		assertEqual(FreePlayRules.modeFor(modes, 1), nil, "unul singur")
		assertEqual(FreePlayRules.modeFor(modes, 2), "1v1", "doi")
		assertEqual(FreePlayRules.modeFor(modes, 3), "1v1v1", "trei")
		assertEqual(FreePlayRules.modeFor(modes, 4), "1v1v1v1", "patru")
	end)

	it("trimite la centru pe toti cand sunt trei sau patru", function()
		for _, modeId in { "1v1v1", "1v1v1v1" } do
			for slot, config in GameConfig.Modes[modeId].Slots do
				assertEqual(config.Objective.Kind, "CENTER", modeId .. " slot " .. slot)
			end
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

-- ---------------------------------------------------------- comentariul

describe("Comentariul mutarilor", function()
	local MoveCommentary = Shared.MoveCommentary
	local Callouts = Shared.Callouts
	local SETTINGS = GameConfig.Callouts

	--[[
		O stare cu pionii unde ii vreau si baricadele date, fara ture. Analizorul
		nu verifica legalitatea — primeste actiuni deja aplicate — deci testele
		lui pot aseza tabla direct.
	]]
	local function board(
		mode: string,
		positions: { [number]: { number } },
		walls: { { any } }?
	): any
		local state = newMatch(mode)
		for slot, at in positions do
			state.Players[slot].Position = { X = at[1], Y = at[2] }
		end
		for _, w in walls or {} do
			seedWall(state, w[1], w[2], w[3])
		end
		return state
	end

	local function ids(callouts: { any }): string
		local list = {}
		for _, callout in callouts do
			table.insert(list, callout.Id)
		end
		return table.concat(list, ",")
	end

	local function has(callouts: { any }, id: string): any
		for _, callout in callouts do
			if callout.Id == id then
				return callout
			end
		end
		return nil
	end

	local function distance(state: any, slot: number): number?
		local _, steps = Pathfinding.hasPathToGoal(state, slot)
		return steps
	end

	local function wallAction(slot: number, x: number, y: number, orientation: string): any
		return { Kind = "Wall", Slot = slot, Wall = { X = x, Y = y, Orientation = orientation } }
	end

	local function moveAction(slot: number, from: { number }, to: { number }): any
		return {
			Kind = "Move",
			Slot = slot,
			From = { X = from[1], Y = from[2] },
			To = { X = to[1], Y = to[2] },
		}
	end

	-- 1v1: slotul 2 sta pe (5,9) si coboara. Baricadele stau sub el, pe randul 8.
	local function blockAgainstTwo(walls: { { any } }): { any }
		local before = board("1v1", {})
		local after = board("1v1", {}, walls)
		local last = walls[#walls]
		return MoveCommentary.analyze(before, after, wallAction(1, last[1], last[2], last[3]))
	end

	it("un pas in plus nu e blocaj", function()
		local walls = { { 5, 8, "Horizontal" }, { 7, 8, "Horizontal" } }
		assertEqual(distance(board("1v1", {}, walls), 2), 9, "chiar un pas in plus")
		assertEqual(ids(blockAgainstTwo(walls)), "", "+1")
	end)

	it("BLOCK la doi pasi, pe baricada, cu tinta si numar", function()
		local out = blockAgainstTwo({ { 4, 8, "Horizontal" }, { 6, 8, "Horizontal" } })
		local block = has(out, "BLOCK")
		assertTrue(block ~= nil, "BLOCK: " .. ids(out))
		assertEqual(block.Amount, 2, "cati pasi")
		assertEqual(block.Target, 2, "pe cine")
		assertEqual(block.Slot, 1, "cine")
		assertEqual(block.Tier, 1, "marimea")
		assertTrue(
			block.Wall ~= nil and block.Wall.X == 6 and block.Wall.Y == 8,
			"asezat pe baricada"
		)
	end)

	it("BLOCK_BIG la trei, BLOCK_HUGE la patru, BLOCK_MEGA la sase", function()
		local big = blockAgainstTwo({
			{ 3, 8, "Horizontal" },
			{ 5, 8, "Horizontal" },
			{ 7, 8, "Horizontal" },
		})
		assertEqual(ids(big), "BLOCK_BIG", "+3")
		assertEqual(big[1].Amount, 3, "+3 numarul")

		local huge = blockAgainstTwo({
			{ 1, 8, "Horizontal" },
			{ 3, 8, "Horizontal" },
			{ 5, 8, "Horizontal" },
			{ 7, 8, "Horizontal" },
		})
		assertEqual(ids(huge), "BLOCK_HUGE", "+4")
		assertEqual(huge[1].Tier, 3, "+4 e epic")

		local mega = blockAgainstTwo({
			{ 1, 8, "Horizontal" },
			{ 3, 8, "Horizontal" },
			{ 5, 8, "Horizontal" },
			{ 7, 8, "Horizontal" },
			{ 8, 7, "Horizontal" },
		})
		assertEqual(ids(mega), "BLOCK_MEGA", "+6")
		assertEqual(mega[1].Amount, 6, "+6 numarul")
	end)

	it("in 2v2 blocarea coechipierului nu e BLOCK", function()
		-- Slotul 2 e coechipierul lui 1 si sta pe (4,1); zidul il abate doi pasi.
		local before = board("2v2", {})
		local after = board("2v2", {}, { { 2, 1, "Horizontal" }, { 4, 1, "Horizontal" } })
		assertEqual(distance(after, 2), 10, "coechipierul chiar a fost abatut")
		local out = MoveCommentary.analyze(before, after, wallAction(1, 4, 1, "Horizontal"))
		assertEqual(ids(out), "", "fara blocaj")
	end)

	--[[
		1v1v1v1, totul spre centru. Deasupra centrului e deja o baricada; cea noua,
		verticala in dreapta lui, il abate pe 2 cu patru pasi si pe 3 cu doi.
	]]
	local function doubleBlock(remaining: number): { any }
		local before = board("1v1v1v1", {}, { { 4, 5, "Horizontal" } })
		local after = board("1v1v1v1", {}, { { 4, 5, "Horizontal" }, { 5, 4, "Vertical" } })
		after.Players[1].BarricadesRemaining = remaining
		return MoveCommentary.analyze(before, after, wallAction(1, 5, 4, "Vertical"))
	end

	it("DOUBLE_BLOCK cand o baricada ii incetineste pe doi", function()
		local out = doubleBlock(3)
		assertTrue(has(out, "DOUBLE_BLOCK") ~= nil, "DOUBLE_BLOCK: " .. ids(out))
		assertEqual(has(out, "BLOCK_HUGE").Target, 2, "cel mai lovit e 2")
	end)

	it("un singur adversar incetinit nu e DOUBLE_BLOCK", function()
		local out = blockAgainstTwo({
			{ 1, 8, "Horizontal" },
			{ 3, 8, "Horizontal" },
			{ 5, 8, "Horizontal" },
			{ 7, 8, "Horizontal" },
		})
		assertTrue(has(out, "DOUBLE_BLOCK") == nil, "doar unul")
	end)

	it("ordonat dupa prioritate si taiat la MaxPerAction", function()
		local out = doubleBlock(0)
		assertEqual(#out, SETTINGS.MaxPerAction, "taiat")
		assertEqual(ids(out), "BLOCK_HUGE,DOUBLE_BLOCK", "ordinea, fara LAST_WALL")
		for index = 2, #out do
			assertTrue(
				Callouts.All[out[index - 1].Id].Priority >= Callouts.All[out[index].Id].Priority,
				"prioritate descrescatoare"
			)
		end
	end)

	it("LAST_WALL doar cand a pus ultima baricada", function()
		local before = board("1v1", {})
		local after = board("1v1", {}, { { 1, 1, "Horizontal" } })
		local action = wallAction(1, 1, 1, "Horizontal")
		after.Players[1].BarricadesRemaining = 0
		assertEqual(ids(MoveCommentary.analyze(before, after, action)), "LAST_WALL", "ultima")

		after.Players[1].BarricadesRemaining = 1
		assertEqual(ids(MoveCommentary.analyze(before, after, action)), "", "mai are")
	end)

	it("JUMP la saritura dreapta, SIDESTEP la cea in diagonala, nimic la un pas", function()
		local before = board("1v1", { [1] = { 5, 3 }, [2] = { 5, 4 } })

		local jumped = board("1v1", { [1] = { 5, 5 }, [2] = { 5, 4 } })
		local out = MoveCommentary.analyze(before, jumped, moveAction(1, { 5, 3 }, { 5, 5 }))
		assertTrue(has(out, "JUMP") ~= nil, "JUMP: " .. ids(out))
		assertTrue(has(out, "SIDESTEP") == nil, "saritura dreapta nu e SIDESTEP")
		assertEqual(has(out, "JUMP").Cell.Y, 5, "deasupra pionului, unde a aterizat")
		assertEqual(has(out, "JUMP").Target, 2, "peste cine a sarit")

		local side = board("1v1", { [1] = { 6, 4 }, [2] = { 5, 4 } }, { { 4, 4, "Horizontal" } })
		out = MoveCommentary.analyze(before, side, moveAction(1, { 5, 3 }, { 6, 4 }))
		assertTrue(has(out, "SIDESTEP") ~= nil, "SIDESTEP: " .. ids(out))
		assertTrue(has(out, "JUMP") == nil, "diagonala nu e JUMP")

		local step = board("1v1", { [1] = { 4, 3 }, [2] = { 5, 4 } })
		out = MoveCommentary.analyze(before, step, moveAction(1, { 5, 3 }, { 4, 3 }))
		assertTrue(has(out, "JUMP") == nil and has(out, "SIDESTEP") == nil, "un pas simplu")
	end)

	it("ONE_STEP cand ajunge la un pas, nu si cand era deja acolo", function()
		local before = board("1v1", { [1] = { 5, 7 } })
		local after = board("1v1", { [1] = { 5, 8 } })
		local out = MoveCommentary.analyze(before, after, moveAction(1, { 5, 7 }, { 5, 8 }))
		assertTrue(has(out, "ONE_STEP") ~= nil, "ONE_STEP: " .. ids(out))
		assertEqual(has(out, "ONE_STEP").Tier, 3, "epic")

		local already = board("1v1", { [1] = { 4, 8 } })
		out = MoveCommentary.analyze(already, after, moveAction(1, { 4, 8 }, { 5, 8 }))
		assertTrue(has(out, "ONE_STEP") == nil, "de-a lungul randului 8")

		local twoAway = board("1v1", { [1] = { 5, 7 } })
		out = MoveCommentary.analyze(
			board("1v1", { [1] = { 5, 6 } }),
			twoAway,
			moveAction(1, { 5, 6 }, { 5, 7 })
		)
		assertTrue(has(out, "ONE_STEP") == nil, "la doi pasi")
	end)

	--[[
		1 pe (1,4) are cinci pasi, 2 pe (9,5) are patru. O baricada sub 2 il duce
		la sase: 1 trece din urma in fata.
	]]
	local function overtake(history: any): { any }
		local before = board("1v1", { [1] = { 1, 4 }, [2] = { 9, 5 } })
		local after = board("1v1", { [1] = { 1, 4 }, [2] = { 9, 5 } }, { { 8, 4, "Horizontal" } })
		return MoveCommentary.analyze(before, after, wallAction(1, 8, 4, "Horizontal"), history)
	end

	it("TAKE_LEAD la o depasire, nu la simplul avantaj de tempo", function()
		local out = overtake(nil)
		assertTrue(has(out, "TAKE_LEAD") ~= nil, "TAKE_LEAD: " .. ids(out))

		-- Amandoi la opt; 1 muta si e la sapte. Asta nu e o depasire.
		local before = newMatch("1v1")
		local after = board("1v1", { [1] = { 5, 2 } })
		out = MoveCommentary.analyze(before, after, moveAction(1, { 5, 1 }, { 5, 2 }))
		assertEqual(ids(out), "", "primul pas al meciului")
	end)

	it("COMEBACK de la trei pasi in urma, in locul lui TAKE_LEAD", function()
		local walls = { { 8, 4, "Horizontal" }, { 6, 4, "Horizontal" } }
		local before = board("1v1", { [1] = { 1, 2 }, [2] = { 9, 5 } })
		local after = board("1v1", { [1] = { 1, 2 }, [2] = { 9, 5 } }, walls)
		local out = MoveCommentary.analyze(before, after, wallAction(1, 6, 4, "Horizontal"))
		assertTrue(has(out, "COMEBACK") ~= nil, "COMEBACK: " .. ids(out))
		assertTrue(has(out, "TAKE_LEAD") == nil, "nu amandoua")
	end)

	it("COMEBACK si din istorie, cand revenirea a venit in mai multe ture", function()
		local history = MoveCommentary.newHistory()
		history.Deficit[1] = 3
		assertTrue(has(overtake(history), "COMEBACK") ~= nil, "cu istorie")
		assertTrue(has(overtake(nil), "COMEBACK") == nil, "fara istorie e doar TAKE_LEAD")
	end)

	it("istoria tine cel mai mare deficit si il sterge la egalitate", function()
		local history = MoveCommentary.newHistory()
		MoveCommentary.record(history, board("1v1", { [1] = { 1, 2 }, [2] = { 9, 5 } }), {})
		assertEqual(history.Deficit[1], 3, "trei in urma")
		MoveCommentary.record(history, board("1v1", { [1] = { 1, 4 }, [2] = { 9, 5 } }), {})
		assertEqual(history.Deficit[1], 3, "ramane cel mai rau")
		MoveCommentary.record(history, board("1v1", { [1] = { 1, 5 }, [2] = { 9, 5 } }), {})
		assertEqual(history.Deficit[1], nil, "egalitate")
	end)

	it("NECK_AND_NECK o singura data, cand toti ajung aproape si la egalitate", function()
		local before = board("1v1", { [1] = { 1, 5 }, [2] = { 9, 4 } })
		local after = board("1v1", { [1] = { 1, 6 }, [2] = { 9, 4 } })
		local action = moveAction(1, { 1, 5 }, { 1, 6 })
		local out = MoveCommentary.analyze(before, after, action)
		assertTrue(has(out, "NECK_AND_NECK") ~= nil, "NECK_AND_NECK: " .. ids(out))

		local steady = board("1v1", { [1] = { 2, 6 }, [2] = { 9, 4 } })
		out = MoveCommentary.analyze(after, steady, moveAction(1, { 1, 6 }, { 2, 6 }))
		assertTrue(has(out, "NECK_AND_NECK") == nil, "era deja")

		local history = MoveCommentary.newHistory()
		history.Shown.NECK_AND_NECK = true
		out = MoveCommentary.analyze(before, after, action, history)
		assertTrue(has(out, "NECK_AND_NECK") == nil, "s-a strigat deja")
	end)

	it("UNSTOPPABLE cand adversarii n-au baricade si el trece in fata", function()
		local before = board("1v1", { [1] = { 1, 5 }, [2] = { 9, 5 } })
		local after = board("1v1", { [1] = { 1, 6 }, [2] = { 9, 5 } })
		before.Players[2].BarricadesRemaining = 0
		after.Players[2].BarricadesRemaining = 0
		local action = moveAction(1, { 1, 5 }, { 1, 6 })
		assertTrue(
			has(MoveCommentary.analyze(before, after, action), "UNSTOPPABLE") ~= nil,
			"UNSTOPPABLE"
		)

		after.Players[2].BarricadesRemaining = 1
		assertTrue(
			has(MoveCommentary.analyze(before, after, action), "UNSTOPPABLE") == nil,
			"adversarul mai are"
		)
	end)

	it("nu striga nimic dupa mutarea castigatoare", function()
		local before = board("1v1", { [1] = { 5, 8 } })
		local after = board("1v1", { [1] = { 5, 9 }, [2] = { 1, 9 } })
		after.Status = "FINISHED"
		assertEqual(
			ids(MoveCommentary.analyze(before, after, moveAction(1, { 5, 8 }, { 5, 9 }))),
			"",
			"final"
		)
	end)

	--[[
		Seria de blocaje: acelasi blocaj de +2 dat de trei ori la rand de slotul 1,
		cu o mutare intre ele ca sa se vada cum cade.
	]]
	it("seria de blocaje creste la rand si cade la prima actiune fara blocaj", function()
		local history = MoveCommentary.newHistory()
		local walls = { { 4, 8, "Horizontal" }, { 6, 8, "Horizontal" } }
		local function blockOnce(): any
			local before = board("1v1", {})
			local after = board("1v1", {}, walls)
			local out =
				MoveCommentary.analyze(before, after, wallAction(1, 6, 8, "Horizontal"), history)
			MoveCommentary.record(history, after, out, 1)
			return has(out, "BLOCK")
		end

		assertEqual(blockOnce().Streak, nil, "primul blocaj nu e serie")
		assertEqual(blockOnce().Streak, 2, "al doilea: x2")
		assertEqual(blockOnce().Streak, 3, "al treilea: x3")
		assertEqual(history.Streak[1], 3, "istoria tine seria")

		local still = board("1v1", { [1] = { 4, 1 } })
		local moved = MoveCommentary.analyze(
			board("1v1", {}),
			still,
			moveAction(1, { 5, 1 }, { 4, 1 }),
			history
		)
		MoveCommentary.record(history, still, moved, 1)
		assertEqual(history.Streak[1], 0, "o mutare rupe seria")
		assertEqual(blockOnce().Streak, nil, "de la capat")
	end)

	it("seria unuia nu se amesteca cu a celuilalt", function()
		local history = MoveCommentary.newHistory()
		history.Streak[1] = 4
		MoveCommentary.record(history, board("1v1", {}), {}, 2)
		assertEqual(history.Streak[1], 4, "actiunea lui 2 nu atinge seria lui 1")
		assertEqual(history.Streak[2], 0, "2 n-a blocat")
	end)
end)

describe("Catalogul de callout-uri", function()
	local Callouts = Shared.Callouts

	it("fiecare intrare e intreaga", function()
		for id, entry in Callouts.All do
			assertEqual(entry.Id, id, id .. ": id-ul")
			assertTrue(entry.Tier >= 1 and entry.Tier <= 3, id .. ": marimea")
			assertTrue(
				GameConfig.Sounds[entry.Sound] ~= nil,
				id .. ": sunetul exista in GameConfig.Sounds"
			)
			for _, extra in { entry.VictimSound, entry.OtherSound } do
				assertTrue(GameConfig.Sounds[extra] ~= nil, id .. ": " .. extra .. " exista")
			end
			assertEqual(#entry.Colors, 2, id .. ": doua culori")
		end
	end)

	it("sunetul se alege dupa perspectiva", function()
		local block = { Id = "BLOCK_HUGE", Slot = 1, Target = 2, Amount = 4 }
		assertEqual(Callouts.format(block, 1, "Ana").Sound, "CalloutEpic", "autorul: combo")
		assertEqual(Callouts.format(block, 2, "Ana").Sound, "CalloutBlocked", "victima: Fuhhhh")
		assertEqual(Callouts.format(block, 3, "Ana").Sound, "CalloutEpic", "martorul: combo")

		local close = { Id = "ONE_STEP", Slot = 1 }
		assertEqual(Callouts.format(close, 1, "Ana").Sound, "CalloutEpic", "tu esti la un pas")
		assertEqual(Callouts.format(close, 2, "Ana").Sound, "CalloutOhNo", "adversarul e la un pas")
		assertEqual(
			Callouts.format(close, 2, "Ana", true).Sound,
			"CalloutEpic",
			"coechipierul e la un pas"
		)

		assertEqual(
			Callouts.format({ Id = "BLOCK_MEGA", Slot = 1, Amount = 6 }, 1, "Ana").Sound,
			"CalloutPerfect",
			"perfect"
		)
		assertEqual(
			Callouts.format({ Id = "JUMP", Slot = 1, Target = 2 }, 2, "Ana").Sound,
			"CalloutOhNo",
			"sarit peste tine"
		)
	end)

	it("perspectiva schimba textul si culorile", function()
		local callout = { Id = "BLOCK_HUGE", Slot = 1, Target = 2, Amount = 4 }

		local mine = Callouts.format(callout, 1, "Ana")
		assertEqual(mine.Perspective, "AUTHOR", "autorul")
		assertEqual(mine.Prefix, "HUGE BLOCK! +", "textul autorului")
		assertEqual(mine.Amount, 4, "numarul")

		local theirs = Callouts.format(callout, 2, "Ana")
		assertEqual(theirs.Perspective, "VICTIM", "victima")
		assertEqual(theirs.Prefix, "YOU'RE BLOCKED! +", "textul victimei")
		assertEqual(theirs.Colors, Callouts.VictimColors, "paleta rece")

		local other = Callouts.format({ Id = "ONE_STEP", Slot = 1 }, 3, "Ana%1")
		assertEqual(other.Prefix, "ANA%1: ONE STEP AWAY!", "numele, intreg")
		assertEqual(other.Amount, nil, "fara numar")
	end)

	it("un id necunoscut se sare", function()
		assertEqual(Callouts.format({ Id = "NOPE", Slot = 1 }, 1, "Ana"), nil, "necunoscut")
		assertEqual(Callouts.format({ Id = "BLOCK", Slot = "1" }, 1, "Ana"), nil, "slot stricat")
	end)
end)

-- --------------------------------------------------------------- revansa

describe("Votul de revansa", function()
	local RematchVote = Shared.RematchVote
	local WINDOW = 10

	it("porneste acceptat de cel care cere", function()
		local vote = RematchVote.open({ 11, 22 }, 11, 0, WINDOW)
		assertEqual(vote.Status, "Pending", "deschis")
		assertTrue(vote.Accepted[11], "cel care cere a zis da")
		local count, left = RematchVote.progress(vote, 3)
		assertEqual(count, 1, "un da")
		assertEqual(left, 7, "timpul ramas")
	end)

	it("nu se deschide de cineva din afara mesei sau de unul singur", function()
		local vote, reason = RematchVote.open({ 11, 22 }, 99, 0, WINDOW)
		assertEqual(vote, nil, "strain")
		assertEqual(reason, "NOT_SEATED", "motivul")
		local alone, why = RematchVote.open({ 11 }, 11, 0, WINDOW)
		assertEqual(alone, nil, "singur")
		assertEqual(why, "ALONE", "motivul")
	end)

	it("toti accepta: Accepted", function()
		local vote = RematchVote.open({ 11, 22 }, 11, 0, WINDOW)
		assertTrue(RematchVote.accept(vote, 22, 4), "al doilea da")
		assertEqual(vote.Status, "Accepted", "gata")
	end)

	it("unul refuza: Cancelled, cu motiv si vinovat", function()
		local vote = RematchVote.open({ 11, 22 }, 11, 0, WINDOW)
		assertTrue(RematchVote.decline(vote, 22, 2), "refuz")
		assertEqual(vote.Status, "Cancelled", "anulat")
		assertEqual(vote.Reason, "DECLINED", "motivul")
		assertEqual(vote.By, 22, "cine")
		assertFalse(RematchVote.accept(vote, 22, 3), "dupa anulare nu mai conteaza nimic")
	end)

	it("unul pleaca: Cancelled, chiar daca acceptase", function()
		local vote = RematchVote.open({ 11, 22, 33 }, 11, 0, WINDOW)
		RematchVote.accept(vote, 22, 1)
		assertTrue(RematchVote.leave(vote, 22, 2), "a plecat")
		assertEqual(vote.Reason, "LEFT", "motivul")
		assertEqual(vote.By, 22, "cine")
	end)

	it("expira la termen, iar un da venit dupa nu mai conteaza", function()
		local vote = RematchVote.open({ 11, 22 }, 11, 0, WINDOW)
		assertEqual(RematchVote.tick(vote, 9.9), "Pending", "inca merge")
		local ok, reason = RematchVote.accept(vote, 22, 10)
		assertFalse(ok, "prea tarziu")
		assertEqual(reason, "CLOSED", "motivul")
		assertEqual(vote.Reason, "EXPIRED", "expirat")
	end)

	it("votul dublu nu schimba nimic", function()
		local vote = RematchVote.open({ 11, 22, 33 }, 11, 0, WINDOW)
		assertTrue(RematchVote.accept(vote, 11, 1), "cel care a cerut, din nou")
		assertTrue(RematchVote.accept(vote, 22, 1), "al doilea")
		assertTrue(RematchVote.accept(vote, 22, 2), "al doilea, din nou")
		assertEqual(vote.Status, "Pending", "tot il asteapta pe al treilea")
		assertEqual((RematchVote.progress(vote, 2)), 2, "doi da, nu trei")
	end)

	it("un vot din afara mesei e refuzat si nu anuleaza nimic", function()
		local vote = RematchVote.open({ 11, 22 }, 11, 0, WINDOW)
		local ok, reason = RematchVote.accept(vote, 99, 1)
		assertFalse(ok, "strainul nu voteaza")
		assertEqual(reason, "NOT_SEATED", "motivul")
		assertFalse(RematchVote.decline(vote, 99, 1), "nici nu refuza")
		assertFalse(RematchVote.leave(vote, 99, 1), "nici nu pleaca")
		assertEqual(vote.Status, "Pending", "votul merge mai departe")
	end)

	it("in 2v2 si in 1v1v1v1 trebuie sa accepte toti patru", function()
		local vote = RematchVote.open({ 1, 2, 3, 4 }, 3, 0, WINDOW)
		for _, userId in { 1, 2 } do
			RematchVote.accept(vote, userId, 1)
			assertEqual(vote.Status, "Pending", "inca lipseste cineva")
		end
		RematchVote.accept(vote, 4, 1)
		assertEqual(vote.Status, "Accepted", "toti patru")
	end)

	it("locurile se rotesc: in 1v1 si 1v1v1v1 cu unu, in 2v2 cu o echipa", function()
		assertEqual(table.concat(RematchVote.rotate({ "A", "B" }, 1), ","), "B,A", "1v1")
		assertEqual(
			table.concat(RematchVote.rotate({ "A", "B", "C", "D" }, 1), ","),
			"B,C,D,A",
			"patru"
		)
		assertEqual(
			table.concat(RematchVote.rotate({ "A", "B", "C", "D" }, 2), ","),
			"C,D,A,B",
			"2v2: echipele raman"
		)
	end)

	it("seria numara meciurile si victoriile, si se scrie de la tine", function()
		local series = RematchVote.newSeries()
		RematchVote.record(series, { 11 })
		assertEqual(RematchVote.label(series, { { 11 }, { 22 } }), nil, "primul meci nu e revansa")
		RematchVote.record(series, { 22 })
		RematchVote.record(series, { 11 })
		assertEqual(
			RematchVote.label(series, { { 11 }, { 22 } }),
			"Rematch #3 · 2–1",
			"din partea lui 11"
		)
		assertEqual(
			RematchVote.label(series, { { 22 }, { 11 } }),
			"Rematch #3 · 1–2",
			"din partea lui 22"
		)
	end)

	it("in 2v2 echipa are victoriile coechipierilor", function()
		local series = RematchVote.newSeries()
		RematchVote.record(series, { 1, 2 })
		RematchVote.record(series, { 1, 2 })
		RematchVote.record(series, { 3, 4 })
		assertEqual(
			RematchVote.label(series, { { 1, 2 }, { 3, 4 } }),
			"Rematch #3 · 2–1",
			"pe echipe"
		)
	end)

	it("votul incape in timpul cat sta masa", function()
		local timing = GameConfig.Timing
		assertTrue(
			timing.VictoryReveal
					+ timing.VictoryAutoLeave
					+ timing.RematchWindow
					+ timing.RematchNotice
					+ timing.RematchResume
				<= timing.VictoryHold,
			"VictoryHold acopera panoul, votul, vestea si intoarcerea"
		)
	end)
end)

-- ------------------------------------------------------------ provocari

describe("Provocarea directa", function()
	local Challenge = Shared.Challenge

	-- O cerere valida de 1v1 intre 1 si 2; testele strica cate un camp.
	local function request(overrides: { [string]: any }?): any
		local base = {
			From = 1,
			Invitees = { 2 },
			Players = 2,
			Present = { [1] = true, [2] = true, [3] = true, [4] = true },
			Busy = {},
			Engaged = {},
			Cooldowns = {},
			Now = 100,
		}
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	local function reason(overrides: { [string]: any }): string?
		local _, why = Challenge.validate(request(overrides))
		return why
	end

	it("o provocare obisnuita trece", function()
		assertTrue((Challenge.validate(request())), "1v1 intre doi liberi")
	end)

	it("refuza ce nu se poate", function()
		assertEqual(reason({ Invitees = { 1 } }), "SELF", "pe tine insuti")
		assertEqual(
			reason({ Invitees = { 2, 2 }, Players = 3 }),
			"DUPLICATE",
			"de doua ori acelasi"
		)
		assertEqual(
			reason({ Invitees = { 2 }, Players = 4 }),
			"WRONG_COUNT",
			"prea putini pentru mod"
		)
		assertEqual(reason({ Invitees = { 9 } }), "ABSENT", "nu e in server")
		assertEqual(reason({ Busy = { [2] = "MATCH" } }), "BUSY_MATCH", "e in meci")
		assertEqual(reason({ Busy = { [2] = "QUEUE" } }), "BUSY_QUEUE", "e in coada")
		assertEqual(reason({ Busy = { [1] = "QUEUE" } }), "YOU_BUSY", "tu esti in coada")
		assertEqual(reason({ Engaged = { [1] = true } }), "YOU_ENGAGED", "ai deja o provocare")
		assertEqual(reason({ Engaged = { [2] = true } }), "ENGAGED", "el are deja una")
	end)

	it("cooldown-ul dupa refuz tine cat trebuie", function()
		local key = Challenge.cooldownKey(1, 2)
		assertEqual(reason({ Cooldowns = { [key] = 130 } }), "COOLDOWN", "inca nu")
		assertTrue((Challenge.validate(request({ Cooldowns = { [key] = 100 } }))), "a trecut")
		assertTrue(
			(Challenge.validate(request({ Cooldowns = { [Challenge.cooldownKey(2, 1)] = 999 } }))),
			"cooldown-ul e pe o singura directie"
		)
	end)

	it("toti invitatii accepta: Accepted", function()
		local c = Challenge.new("c1", 1, { 2, 3, 4 }, "1v1v1v1", 0, 15)
		for _, userId in { 2, 3 } do
			assertTrue((Challenge.accept(c, userId, 1)), "da")
			assertEqual(c.Status, "Requested", "inca lipseste cineva")
		end
		assertTrue((Challenge.accept(c, 3, 1)), "vot dublu, fara efect")
		Challenge.accept(c, 4, 1)
		assertEqual(c.Status, "Accepted", "toti trei")
	end)

	it("cel care provoaca nu voteaza, iar un strain nu poate raspunde", function()
		local c = Challenge.new("c1", 1, { 2 }, "1v1", 0, 15)
		local ok, why = Challenge.accept(c, 1, 1)
		assertFalse(ok, "cel care provoaca a acceptat deja, prin cerere")
		assertEqual(why, "NOT_INVITED", "motivul")
		assertFalse((Challenge.decline(c, 9, 1)), "strainul nu refuza")
		assertEqual(c.Status, "Requested", "neatinsa")
	end)

	it("un refuz inchide provocarea si porneste cooldown-ul", function()
		local c = Challenge.new("c1", 1, { 2, 3 }, "1v1v1", 0, 15)
		Challenge.accept(c, 2, 1)
		assertTrue((Challenge.decline(c, 3, 2)), "nu")
		assertEqual(c.Status, "Declined", "refuzata")
		assertEqual(c.By, 3, "de cine")
		local key, untilAt = Challenge.cooldownAfter(c, 2, 30)
		assertEqual(key, Challenge.cooldownKey(1, 3), "cooldown doar fata de cel care a refuzat")
		assertEqual(untilAt, 32, "pana cand")
	end)

	it("expira la termen, fara cooldown", function()
		local c = Challenge.new("c1", 1, { 2 }, "1v1", 0, 15)
		assertFalse((Challenge.accept(c, 2, 15)), "prea tarziu")
		assertEqual(c.Status, "Expired", "expirata")
		assertEqual((Challenge.cooldownAfter(c, 15, 30)), nil, "o provocare expirata nu e un nu")
	end)

	it("numai cel care provoaca o poate anula", function()
		local c = Challenge.new("c1", 1, { 2 }, "1v1", 0, 15)
		local ok, why = Challenge.cancel(c, 2, 1)
		assertFalse(ok, "invitatul nu anuleaza")
		assertEqual(why, "NOT_YOURS", "motivul")
		assertTrue((Challenge.cancel(c, 1, 1)), "cel care provoaca, da")
		assertEqual(c.Reason, "CANCELLED", "motivul inchiderii")
	end)

	it("cine devine indisponibil o inchide pentru toti", function()
		local c = Challenge.new("c1", 1, { 2 }, "1v1", 0, 15)
		assertFalse(Challenge.drop(c, 7, 1), "strainul nu conteaza")
		assertTrue(Challenge.drop(c, 2, 1), "invitatul a intrat in coada")
		assertEqual(c.Status, "Cancelled", "inchisa")
		assertEqual(c.Reason, "UNAVAILABLE", "motivul")
		assertEqual(table.concat(Challenge.members(c), ","), "1,2", "cine era implicat")
	end)
end)

-- ------------------------------------------------------------ invitatii

describe("Recompensa pentru invitatii", function()
	local Referral = Shared.Referral
	local REWARD, CAP = 100, 5

	local function facts(overrides: { [string]: any }?): any
		local base = {
			Invitee = 20,
			Inviter = 10,
			InviteeIsNew = true,
			AlreadyPaid = false,
			InviterToday = 0,
			Cap = CAP,
			Reward = REWARD,
		}
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	it("jucator nou, invitat de altcineva: amandoi primesc", function()
		local verdict = Referral.decide(facts())
		assertEqual(verdict.InviteeCoins, REWARD, "cel venit")
		assertEqual(verdict.InviterCoins, REWARD, "cel care a invitat")
		assertEqual(verdict.Reason, nil, "fara motiv de refuz")
	end)

	it("jucator vechi: nimeni", function()
		local verdict = Referral.decide(facts({ InviteeIsNew = false }))
		assertEqual(verdict.InviteeCoins + verdict.InviterCoins, 0, "nimic")
		assertEqual(verdict.Reason, "RETURNING", "motivul")
	end)

	it("auto-invitatie: nimeni", function()
		local verdict = Referral.decide(facts({ Inviter = 20 }))
		assertEqual(verdict.InviteeCoins + verdict.InviterCoins, 0, "nimic")
		assertEqual(verdict.Reason, "SELF", "motivul")
	end)

	it("pereche deja platita: nimeni", function()
		local verdict = Referral.decide(facts({ AlreadyPaid = true }))
		assertEqual(verdict.InviteeCoins + verdict.InviterCoins, 0, "nimic")
		assertEqual(verdict.Reason, "ALREADY_PAID", "motivul")
	end)

	it("plafon atins: doar cel venit primeste", function()
		local verdict = Referral.decide(facts({ InviterToday = CAP }))
		assertEqual(verdict.InviteeCoins, REWARD, "cel venit, tot")
		assertEqual(verdict.InviterCoins, 0, "cel care a invitat, nu")
		assertEqual(verdict.Reason, "CAP_REACHED", "motivul")
		assertEqual(
			Referral.decide(facts({ InviterToday = CAP - 1 })).InviterCoins,
			REWARD,
			"sub plafon, da"
		)
	end)

	it("cine a invitat: intai ReferredByPlayerId, apoi LaunchData", function()
		assertEqual(
			Referral.inviterFrom({ ReferredByPlayerId = 42, LaunchData = Referral.launchData(7) }),
			42,
			"Roblox are intaietate"
		)
		assertEqual(
			Referral.inviterFrom({ LaunchData = Referral.launchData(7) }),
			7,
			"a noastra, cand lipseste"
		)
		assertEqual(
			Referral.inviterFrom({ ReferredByPlayerId = 0, LaunchData = Referral.launchData(7) }),
			7,
			"zero nu e cineva"
		)
	end)

	it("LaunchData stricata sau lipsa: nimeni", function()
		assertEqual(Referral.inviterFrom(nil), nil, "fara date")
		assertEqual(Referral.inviterFrom({}), nil, "fara nimic in ele")
		assertEqual(Referral.inviterFrom({ LaunchData = "hello" }), nil, "text strain")
		assertEqual(Referral.inviterFrom({ LaunchData = "barricade-invite:-5" }), nil, "id negativ")
		assertEqual(
			Referral.inviterFrom({ LaunchData = "barricade-invite:12x" }),
			nil,
			"id cu litere"
		)
		assertEqual(Referral.inviterFrom({ LaunchData = string.rep("9", 250) }), nil, "prea lung")
		assertEqual(Referral.inviterFrom({ ReferredByPlayerId = "10" }), nil, "id ca text")
		-- `nil` intr-un tabel nu suprascrie nimic, deci campul se sterge de mana.
		local orphan = facts()
		orphan.Inviter = nil
		assertEqual(Referral.decide(orphan).Reason, "NO_INVITER", "fara cine a invitat")
	end)

	it("ziua se socoteste pe UTC, pe zile intregi", function()
		assertEqual(Referral.day(0), 0, "inceputul")
		assertEqual(Referral.day(86399), 0, "ultima secunda")
		assertEqual(Referral.day(86400), 1, "ziua urmatoare")
	end)
end)

-- ------------------------------------------------------------ bonusuri sociale

describe("Bonusurile sociale la banuti", function()
	local Rewards = Shared.Rewards
	local PAY = GameConfig.Rewards
	local SOCIAL = GameConfig.Social
	local WIN = PAY.Participation + PAY.WinBonus

	local function round(x: number): number
		return math.floor(x + 0.5)
	end

	local function labels(breakdown: any): string
		local list = {}
		for _, line in breakdown.Lines do
			table.insert(list, line.Label .. " +" .. line.Coins)
		end
		return table.concat(list, ", ")
	end

	it("fara modificatori e exact ce era", function()
		assertEqual(Rewards.forMatch("WIN", nil), WIN, "castig")
		assertEqual(Rewards.forMatch("LOSS", {}), PAY.Participation, "pierdere, tabel gol")
	end)

	it("grupul adauga procentul lui din baza, rotunjit", function()
		local b = Rewards.breakdown("WIN", { Group = true })
		assertEqual(
			labels(b),
			string.format("Win +%d, Group bonus +%d", WIN, round(WIN * SOCIAL.GroupBonus)),
			"randurile"
		)
		assertEqual(b.Total, WIN + round(WIN * SOCIAL.GroupBonus), "totalul")
	end)

	it("prietenul la masa adauga si el, si la pierdere", function()
		local b = Rewards.breakdown("LOSS", { Friend = true })
		assertEqual(
			labels(b),
			string.format(
				"Match played +%d, Playing with a friend +%d",
				PAY.Participation,
				round(PAY.Participation * SOCIAL.FriendBonus)
			),
			"randurile"
		)
	end)

	it("amandoua se aduna, cat incap sub plafon", function()
		local saved = { SOCIAL.GroupBonus, SOCIAL.FriendBonus, SOCIAL.SocialBonusCap }
		SOCIAL.GroupBonus, SOCIAL.FriendBonus, SOCIAL.SocialBonusCap = 0.10, 0.10, 0.20
		local b = Rewards.breakdown("WIN", { Group = true, Friend = true })
		SOCIAL.GroupBonus, SOCIAL.FriendBonus, SOCIAL.SocialBonusCap = saved[1], saved[2], saved[3]
		assertEqual(#b.Lines, 3, "trei randuri")
		-- Doua bonusuri de cate 10% dau aceeasi suma; in virgula mobila al doilea ar iesi cu unu mai mic.
		assertEqual(b.Lines[2].Coins, round(WIN * 0.10), "grupul")
		assertEqual(b.Lines[3].Coins, b.Lines[2].Coins, "prietenul, cat grupul")
		assertEqual(b.Total, WIN + 2 * b.Lines[2].Coins, "totalul")
	end)

	it("plafonul taie ce trece de el", function()
		local saved = SOCIAL.SocialBonusCap
		SOCIAL.SocialBonusCap = 0.15
		local b = Rewards.breakdown("WIN", { Group = true, Friend = true })
		SOCIAL.SocialBonusCap = saved
		assertEqual(b.Lines[2].Coins, round(WIN * SOCIAL.GroupBonus), "grupul intreg")
		assertEqual(b.Lines[3].Coins, round(WIN * 0.05), "prietenul, doar ce a mai ramas")
		assertEqual(b.Total, WIN + b.Lines[2].Coins + b.Lines[3].Coins, "totalul e suma randurilor")
	end)

	it("cu plafonul la zero nu apare niciun bonus", function()
		local saved = SOCIAL.SocialBonusCap
		SOCIAL.SocialBonusCap = 0
		local b = Rewards.breakdown("WIN", { Group = true, Friend = true })
		SOCIAL.SocialBonusCap = saved
		assertEqual(#b.Lines, 1, "doar baza")
		assertEqual(b.Total, WIN, "totalul")
	end)
end)

return true
