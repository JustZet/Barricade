--!strict
--[[
	FreePlaySign — ce scrie deasupra soclului de free play.

	Numaratoarea trebuie sa se vada de pe soclu, nu din meniu: acolo stau
	jucatorii si acolo iau decizia de a mai astepta sau de a pleca. Un contor pus
	in interfata ar cere si un canal de retea, si un colt de ecran, pentru ceva
	ce are un singur loc firesc — chiar deasupra locului la care se refera.

	Semnul il face serverul, la fel ca arena, si de aceea nu are nevoie de niciun
	remote: un `BillboardGui` pus in Workspace ajunge singur la toti clientii,
	iar textul lui se replica la fel de simplu. E cel mai ieftin fel de a spune
	acelasi lucru tuturor.
]]

local FreePlaySign = {}
FreePlaySign.__index = FreePlaySign

local COLOR = {
	Text = Color3.fromHex("FFFFFF"),
	Waiting = Color3.fromHex("FFD666"),
	Ready = Color3.fromHex("7FD06A"),
	Shadow = Color3.fromHex("101418"),
}

-- Cat de sus peste soclu pluteste semnul, in studs.
local HEIGHT = 9

-- Cat de mare se vede de departe. `BillboardGui` scaleaza singur cu distanta.
local SIZE = Vector2.new(15, 5)

type SignFields = {
	Model: Model,
	Title: TextLabel,
	Detail: TextLabel,
}

export type FreePlaySign = typeof(setmetatable({} :: SignFields, FreePlaySign))

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, scale: number)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = size
	text.Position = position
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = COLOR.Text
	text.TextStrokeColor3 = COLOR.Shadow
	text.TextStrokeTransparency = 0.4
	text.Text = ""
	text.Parent = parent

	-- `TextScaled` singur umple caseta; constrangerea tine cele doua randuri in raport.
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.floor(72 * scale)
	limit.Parent = text

	return text
end

--[[
	Ridica semnul deasupra soclului dat.

	Nu se ancoreaza de soclu prin `Adornee`, ci sta pe o piesa proprie: soclul
	face parte din lobby-ul adus prin import, iar streaming-ul il poate descarca
	de sub picioarele semnului. Piesa proprie, intr-un model marcat `Persistent`,
	e acolo de fiecare data.
]]
function FreePlaySign.new(plinth: BasePart): FreePlaySign
	local self = setmetatable({}, FreePlaySign) :: FreePlaySign

	local model = Instance.new("Model")
	model.Name = "FreePlaySign"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = plinth.Position + Vector3.new(0, plinth.Size.Y / 2 + HEIGHT, 0)
	anchor.Parent = model

	local board = Instance.new("BillboardGui")
	board.Name = "Board"
	board.Size = UDim2.fromScale(SIZE.X, SIZE.Y)
	board.SizeOffset = Vector2.zero
	board.AlwaysOnTop = false
	board.MaxDistance = 160
	board.Parent = anchor

	self.Title = label(board, "Title", UDim2.fromScale(1, 0.58), UDim2.fromScale(0, 0), 1)
	self.Detail = label(board, "Detail", UDim2.fromScale(1, 0.38), UDim2.fromScale(0, 0.6), 0.55)

	model.Parent = workspace
	self.Model = model
	return self
end

--[[
	Scrie pe semn. `ready` coloreaza titlul: galben cat se asteapta, verde cand
	meciul chiar pleaca — culoarea spune starea inainte sa apuci sa citesti.
]]
function FreePlaySign.show(self: FreePlaySign, title: string, detail: string, ready: boolean)
	if self.Title.Text ~= title then
		self.Title.Text = title
	end
	if self.Detail.Text ~= detail then
		self.Detail.Text = detail
	end
	self.Title.TextColor3 = if ready then COLOR.Ready else COLOR.Waiting
end

function FreePlaySign.destroy(self: FreePlaySign)
	self.Model:Destroy()
end

return FreePlaySign
