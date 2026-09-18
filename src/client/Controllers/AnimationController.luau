--!strict
--[[
	AnimationController — politica de miscare a interfetei.

	Nu detine niciun obiect grafic; primeste instante si le anima. Vederile
	isi pastreaza proprietatea asupra a ce au creat, iar ritmul si curbele
	stau toate aici, ca jocul sa se miste unitar.

	Toate tween-urile pornite sunt tinute minte pe instanta si oprite inainte
	sa inceapa altul nou: doua tween-uri pe aceeasi proprietate se calca in
	picioare si lasa elementul intre doua pozitii.
]]

local TweenService = game:GetService("TweenService")

local AnimationController = {}

local active: { [Instance]: { [string]: Tween } } = {}

local EASE_OUT = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function cancelExisting(instance: Instance, channel: string)
	local channels = active[instance]
	if not channels then
		return
	end
	local existing = channels[channel]
	if existing then
		existing:Cancel()
		channels[channel] = nil
	end
end

local function remember(instance: Instance, channel: string, tween: Tween)
	local channels = active[instance]
	if not channels then
		channels = {}
		active[instance] = channels
	end
	channels[channel] = tween

	tween.Completed:Connect(function()
		if active[instance] and active[instance][channel] == tween then
			active[instance][channel] = nil
		end
	end)
end

--[[
	Anima proprietatile date. `channel` grupeaza animatiile care se exclud
	reciproc — doua miscari de pozitie sunt pe acelasi canal, dar o miscare si
	o schimbare de culoare pot merge in paralel.
]]
function AnimationController.tween(
	instance: Instance,
	properties: { [string]: any },
	duration: number?,
	channel: string?,
	style: Enum.EasingStyle?
): Tween
	local key = channel or "default"
	cancelExisting(instance, key)

	local info = if duration
		then TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else EASE_OUT

	local tween = TweenService:Create(instance, info, properties)
	remember(instance, key, tween)
	tween:Play()
	return tween
end

-- Mutarea unui pion: pornire rapida, asezare moale. Nu teleporteaza niciodata.
function AnimationController.moveToken(token: GuiObject, position: UDim2, duration: number)
	AnimationController.tween(
		token,
		{ Position = position },
		duration,
		"position",
		Enum.EasingStyle.Back
	)
end

-- Baricada asezata: creste din nimic pe locul ei.
function AnimationController.dropWall(wall: GuiObject, targetSize: UDim2, duration: number)
	local center = UDim2.new(
		wall.Position.X.Scale + targetSize.X.Scale / 2,
		0,
		wall.Position.Y.Scale + targetSize.Y.Scale / 2,
		0
	)
	wall.Size = UDim2.new(0, 0, 0, 0)
	wall.Position = center
	AnimationController.tween(wall, { Size = targetSize }, duration, "size")
	AnimationController.tween(wall, {
		Position = UDim2.new(
			center.X.Scale - targetSize.X.Scale / 2,
			0,
			center.Y.Scale - targetSize.Y.Scale / 2,
			0
		),
	}, duration, "position")
end

-- Refuz: o clatinare scurta, mai clara decat un text care apare si dispare.
function AnimationController.shake(instance: GuiObject)
	local origin = instance.Position
	local offset = UDim2.new(origin.X.Scale, origin.X.Offset + 6, origin.Y.Scale, origin.Y.Offset)

	cancelExisting(instance, "shake")
	local out = TweenService:Create(
		instance,
		TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 3, true),
		{ Position = offset }
	)
	remember(instance, "shake", out)
	out:Play()
	out.Completed:Connect(function()
		instance.Position = origin
	end)
end

function AnimationController.fade(instance: GuiObject, transparency: number, duration: number?)
	AnimationController.tween(
		instance,
		{ BackgroundTransparency = transparency },
		duration or 0.2,
		"fade"
	)
end

-- Curata tween-urile unei instante distruse.
function AnimationController.forget(instance: Instance)
	local channels = active[instance]
	if not channels then
		return
	end
	for _, tween in channels do
		tween:Cancel()
	end
	active[instance] = nil
end

return AnimationController
