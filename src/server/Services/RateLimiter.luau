--!strict
--[[
	RateLimiter — token bucket per jucator si per canal.

	Un client modificat poate trage pe RemoteEvent de mii de ori pe secunda.
	Validarea de reguli l-ar refuza corect de fiecare data, dar l-ar refuza
	*scump*: fiecare cerere de baricada porneste un BFS pentru fiecare jucator.
	Limitarea taie inundatia inainte sa ajunga la partea costisitoare.

	Fiecare canal are un ritm (Interval) si o rezerva de rafala (Burst), ca
	jocul sa ramana comod pentru cine da doua clicuri repezi, dar inchis
	pentru cine trage in bucla.
]]

local Players = game:GetService("Players")

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

type Bucket = {
	Tokens: number,
	LastRefill: number,
}

local RateLimiter = {}

-- [userId][channel] = bucket
local buckets: { [number]: { [string]: Bucket } } = {}

--[[
	Consuma un jeton pentru canalul cerut.
	Returneaza false daca jucatorul trage mai repede decat are voie.
]]
function RateLimiter.consume(player: Player, channel: string): boolean
	local limit = GameConfig.RateLimits[channel]
	if not limit then
		-- Canal nelimitat: mai bine explicit decat tacut.
		return true
	end

	local userBuckets = buckets[player.UserId]
	if not userBuckets then
		userBuckets = {}
		buckets[player.UserId] = userBuckets
	end

	local now = os.clock()
	local bucket = userBuckets[channel]
	if not bucket then
		bucket = { Tokens = limit.Burst, LastRefill = now }
		userBuckets[channel] = bucket
	end

	-- Reumplere proportionala cu timpul scurs, plafonata la rafala maxima.
	local elapsed = now - bucket.LastRefill
	if elapsed > 0 then
		bucket.Tokens = math.min(limit.Burst, bucket.Tokens + elapsed / limit.Interval)
		bucket.LastRefill = now
	end

	if bucket.Tokens < 1 then
		return false
	end

	bucket.Tokens -= 1
	return true
end

function RateLimiter.clear(player: Player)
	buckets[player.UserId] = nil
end

Players.PlayerRemoving:Connect(RateLimiter.clear)

return RateLimiter
