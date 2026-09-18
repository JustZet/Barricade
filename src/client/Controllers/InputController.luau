--!strict
--[[
	InputController — tastatura.

	R roteste baricada, Escape iese din modul de asezare, M revine la mutare,
	iar rotita mouse-ului scoate baricada si o roteste. Scurtaturile dubleaza
	butoanele din interfata, nu le inlocuiesc: pe telefon si pe consola nu exista
	nici tastatura, nici rotita, iar jocul trebuie sa fie jucabil complet din
	atingeri.

	Rotita e altfel decat restul si de aceea sta pe alt semnal: `InputBegan` da
	apasari, iar rotita nu se apasa, se invarte. Vine pe `InputChanged`, cu
	directia in `input.Position.Z`.
]]

local UserInputService = game:GetService("UserInputService")

local InputController = {}

local handlers: { [string]: () -> () } = {}
local connections: { RBXScriptConnection } = {}

function InputController.bind(newHandlers: { [string]: () -> () })
	handlers = newHandlers

	if #connections > 0 then
		return
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			-- `processed` e adevarat cand tasta a fost deja folosita de altceva,
			-- de exemplu de caseta de chat. Nu furam tastele nimanui.
			if processed then
				return
			end

			if input.KeyCode == Enum.KeyCode.R and handlers.onRotate then
				handlers.onRotate()
			elseif input.KeyCode == Enum.KeyCode.Escape and handlers.onCancel then
				handlers.onCancel()
			elseif input.KeyCode == Enum.KeyCode.M and handlers.onMoveMode then
				handlers.onMoveMode()
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
			if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			--[[
				Amandoua sensurile fac acelasi lucru, si asta e cu folos: baricada
				are doua orientari, deci "in sus e orizontala, in jos e verticala"
				n-ar aduce nimic peste "rotesti si se schimba". Ramane un singur
				gest de tinut minte, si merge oricum ai invarti.
			]]
			if handlers.onCycleMode then
				handlers.onCycleMode()
			end
		end)
	)
end

function InputController.unbind()
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	handlers = {}
end

return InputController
