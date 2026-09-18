--!strict
--[[
	Hover — un obiect care se invarte incet si pluteste, sus si jos.

	E efectul de vitrina: obiectul expus nu sta, ci respira. Sta scris o singura
	data fiindca il folosesc si baricada, si podiumul, si orice se mai adauga
	mai tarziu in lobby.

	Miscarea e pur vizuala si nu se replica: fiecare client isi anima singur
	vitrina, cum isi deseneaza si interfata. Un model care se invarte trimis
	prin retea de 60 de ori pe secunda ar fi trafic degeaba.

	Faza exista ca doua obiecte alaturate sa nu urce si sa coboare la unison —
	trei vitrine care bat in acelasi ritm arata mecanic, nu viu.
]]

local RunService = game:GetService("RunService")

local Hover = {}

export type Options = {
	-- Secunde pentru o rotatie completa. 0 sau lipsa = nu se roteste.
	SpinPeriod: number?,
	-- Cat de sus si cat de jos merge fata de locul lui, in studs.
	FloatHeight: number?,
	-- Secunde pentru un ciclu sus-jos complet.
	FloatPeriod: number?,
	-- Decalajul de start, in secunde.
	Phase: number?,
}

local DEFAULTS = {
	SpinPeriod = 16,
	FloatHeight = 0.45,
	FloatPeriod = 3.4,
	Phase = 0,
}

local TAU = math.pi * 2

--[[
	Porneste miscarea si intoarce functia care o opreste.

	`base` e pivotul in jurul caruia se misca, nu pozitia soclului: obiectul se
	roteste in jurul propriei axe si urca fata de locul in care a fost asezat.

	Oprirea il pune inapoi exact pe `base`, ca un obiect oprit sa nu ramana
	inclinat sau ridicat la intamplare.
]]
function Hover.attach(model: Model, base: CFrame, options: Options?): () -> ()
	local given: Options = options or {}
	local spinPeriod = given.SpinPeriod or DEFAULTS.SpinPeriod
	local floatHeight = given.FloatHeight or DEFAULTS.FloatHeight
	local floatPeriod = given.FloatPeriod or DEFAULTS.FloatPeriod
	local clock = given.Phase or DEFAULTS.Phase

	local connection: RBXScriptConnection? = nil

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if model.Parent then
			model:PivotTo(base)
		end
	end

	connection = RunService.Heartbeat:Connect(function(delta: number)
		--[[
			Modelul scos din lume opreste singur firul. Altfel o vitrina inlocuita
			ar lasa in urma un ascultator care misca un model pe care nu-l mai
			vede nimeni, la fiecare cadru, pana la sfarsitul sesiunii.
		]]
		if not model.Parent then
			stop()
			return
		end

		clock += delta

		local rise = if floatHeight ~= 0 and floatPeriod > 0
			then math.sin(clock * TAU / floatPeriod) * floatHeight
			else 0
		local turn = if spinPeriod > 0 then clock * TAU / spinPeriod else 0

		model:PivotTo(base * CFrame.new(0, rise, 0) * CFrame.Angles(0, turn, 0))
	end)

	return stop
end

return Hover
