--!strict
--[[
	SoundController — sunetele scurte ale jocului.

	Putine si discrete: o mutare, o baricada, un refuz, o schimbare de tura,
	numaratoarea si victoria. Nimic in bucla, nicio muzica peste care sa nu
	poti gandi.

	Id-urile de asset stau in GameConfig si sunt 0 la livrare. Un sunet cu
	id 0 e pur si simplu sarit: jocul merge complet si fara ele, iar cand
	pui id-urile tale nu trebuie schimbat niciun rand de cod aici.
]]

local SoundService = game:GetService("SoundService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local SoundController = {}

local sounds: { [string]: Sound } = {}
local enabled = true

function SoundController.init()
	local folder = Instance.new("Folder")
	folder.Name = "BarricadeSounds"
	folder.Parent = SoundService

	for name, assetId in GameConfig.Sounds do
		if assetId ~= 0 then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = string.format("rbxassetid://%d", assetId)
			sound.Volume = 0.45
			sound.Parent = folder
			sounds[name] = sound
		end
	end
end

function SoundController.play(name: string)
	if not enabled then
		return
	end
	local sound = sounds[name]
	if sound then
		sound:Play()
	end
end

function SoundController.setEnabled(value: boolean)
	enabled = value
end

function SoundController.isEnabled(): boolean
	return enabled
end

function SoundController.toggle(): boolean
	enabled = not enabled
	return enabled
end

return SoundController
