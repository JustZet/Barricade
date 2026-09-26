--!strict
--[[
	SocialController — stratul social de pe client: prieteni, provocari, lista
	de jucatori, notificari.

	Nu decide nimic. Afla de la server cine ii e prieten si unde e fiecare (din
	atributul `Presence`), deseneaza, si trimite cereri. Tot ce e „poti sau nu"
	se hotaraste pe server; aici doar se stinge un buton ca sa nu se ceara
	degeaba ce oricum s-ar refuza.

	Cele doua apeluri catre Roblox care nu se pot testa in Studio —
	`PromptSendFriendRequest` si, mai tarziu, invitatia — stau in functii mici,
	singure, ca restul sa nu depinda de ele.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Theme = require(script.Parent.Parent.UI.Theme)

local LOCAL_PLAYER = Players.LocalPlayer
local PRESENCE = "Presence"

local SocialController = {}
SocialController.__index = SocialController

-- Refuzurile provocarii, in cuvinte. Cheile vin de la `Challenge.validate`.
local REJECTION_TEXT = {
	YOU_BUSY = "Leave the queue or match first.",
	YOU_ENGAGED = "You already have a challenge open.",
	WRONG_COUNT = "Pick the right number of players for that mode.",
	SELF = "You can't challenge yourself.",
	DUPLICATE = "Each player can be picked once.",
	ABSENT = "That player has left the server.",
	BUSY_MATCH = "That player is in a match.",
	BUSY_QUEUE = "That player is in the queue.",
	ENGAGED = "That player already has a challenge open.",
	COOLDOWN = "They just declined. Try again in a little while.",
	BAD_REQUEST = "That challenge couldn't be sent.",
}

type SocialFields = {
	Views: { [string]: any },
	Friends: { [number]: boolean },
	InLobby: boolean,
	Bar: Frame,
	PlayersButton: TextButton,
	-- Butoanele adaugate pe bara de fazele urmatoare (invitatie, grup).
	BarItems: { [string]: GuiObject },
	-- Insigna de deasupra fiecarui prieten din lume, dupa userId.
	Hearts: { [number]: BillboardGui },
	-- Prietenii pentru popup-ul de invitatii, si cand au fost adusi.
	FriendList: { any }?,
	FriendListAt: number,
}

export type SocialController = typeof(setmetatable({} :: SocialFields, SocialController))

--[[
	Cererea de prietenie, prin fereastra Roblox. In Studio nu se deschide nimic
	si nu se poate verifica; de aceea sta singura aici.
]]
local function promptFriendRequest(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	pcall(function()
		StarterGui:SetCore("PromptSendFriendRequest", player)
	end)
end

--[[
	Fereastra de invitatie a Roblox-ului, cu userId-ul tau in `LaunchData`.

	Roblox pune oricum cine a invitat in `ReferredByPlayerId`; `LaunchData` e
	plasa pentru cand lipseste. In Studio fereastra nu se deschide, deci nici
	invitatia, nici recompensa nu se pot verifica acolo — de aceea sta singura.
]]
local function promptInvite(target: number?): boolean
	local SocialService = game:GetService("SocialService")
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(LOCAL_PLAYER, target)
	end)
	if not ok or not can then
		return false
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.LaunchData = Referral.launchData(LOCAL_PLAYER.UserId)
	if target then
		-- Invitatia merge direct la prietenul ales din lista noastra.
		options.InviteUser = target
		options.PromptMessage =
			"Invite this friend: you both get coins if it's their first time here!"
	else
		options.PromptMessage =
			"Invite a friend: you both get coins when they join for the first time!"
	end
	local sent = pcall(function()
		SocialService:PromptGameInvite(LOCAL_PLAYER, options)
	end)
	return sent
end

--[[
	Prietenii jucatorului, pentru lista de invitatii. Doua cereri catre Roblox,
	amandoua aici: toti prietenii (`GetFriendsAsync`) si cei online, cu ce fac
	(`GetFriendsOnline`). In Studio jucatorii de test n-au prieteni, deci lista
	nu se poate vedea decat intr-un joc publicat.
]]
local FRIEND_LIMIT = 200

local function loadFriends(): ({ any }?, string?)
	if LOCAL_PLAYER.UserId <= 0 then
		return nil, "Friends can't be loaded in a test session."
	end

	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(LOCAL_PLAYER.UserId)
	end)
	if not ok or not pages then
		return nil, "Couldn't load your friends right now."
	end

	local here: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		here[player.UserId] = true
	end

	local playing: { [number]: boolean } = {}
	local okOnline, online = pcall(function()
		return LOCAL_PLAYER:GetFriendsOnline(FRIEND_LIMIT)
	end)
	if okOnline and type(online) == "table" then
		for _, entry in online do
			if type(entry) == "table" and type(entry.VisitorId) == "number" then
				playing[entry.VisitorId] = entry.PlaceId == game.PlaceId
					or entry.GameId == game.GameId
			end
		end
	end

	local friends = {}
	while #friends < FRIEND_LIMIT do
		for _, item in pages:GetCurrentPage() do
			local userId = item.Id
			local status = if here[userId]
				then "HERE"
				elseif playing[userId] then "PLAYING"
				elseif item.IsOnline or playing[userId] ~= nil then "ONLINE"
				else "OFFLINE"
			table.insert(friends, {
				UserId = userId,
				Name = if type(item.DisplayName) == "string" and item.DisplayName ~= ""
					then item.DisplayName
					else item.Username,
				Status = status,
			})
		end
		if pages.IsFinished then
			break
		end
		local advanced = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanced then
			break
		end
	end
	return friends, nil
end

--[[
	Fereastra Roblox de intrare in grup. Nu se poate verifica in Studio; bonusul
	se afla oricum pe server, la urmatoarea intrare, prin `IsInGroupAsync`.
]]
local function promptJoinGroup(groupId: number)
	pcall(function()
		game:GetService("GroupService"):PromptJoinAsync(groupId)
	end)
end

function SocialController.new(views: { [string]: any }, parent: Instance): SocialController
	local self = setmetatable({}, SocialController) :: SocialController
	self.Views = views
	self.Friends = {}
	self.InLobby = true
	self.BarItems = {}
	self.Hearts = {}
	self.FriendList = nil
	self.FriendListAt = 0

	--[[
		Bara sociala din lobby, pe marginea din dreapta, la mijloc: acolo nu stau
		nici banutii (stanga), nici butoanele de start (jos).
	]]
	self.Bar = Theme.create("Frame", {
		Name = "SocialBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(170, 220),
		ZIndex = 10,
		Parent = parent,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	self.PlayersButton = Theme.button({
		Name = "Players",
		Text = "PLAYERS",
		Skin = "Secondary",
		TextSize = 16,
		Size = UDim2.fromOffset(160, 52),
		LayoutOrder = 1,
		ZIndex = 11,
		Parent = self.Bar,
	})
	--[[
		Butoanele de pe bara deschid si inchid: a doua apasare strange popup-ul
		pe care l-a deschis prima. Cele doua popup-uri nu stau unul peste altul —
		deschiderea unuia il inchide pe celalalt.
	]]
	self.PlayersButton.MouseButton1Click:Connect(function()
		if views.Players:isOpen() then
			views.Players:close()
			return
		end
		views.Invite:close()
		self:refresh()
		views.Players:open()
	end)

	local invite = Theme.button({
		Name = "Invite",
		Text = "INVITE FRIENDS",
		Skin = "Primary",
		TextSize = 15,
		Size = UDim2.fromOffset(160, 52),
		ZIndex = 11,
	})
	invite.MouseButton1Click:Connect(function()
		if views.Invite:isOpen() then
			views.Invite:close()
			return
		end
		views.Players:close()
		views.Invite:open()
		self:loadInvites()
	end)
	self:addToBar("Invite", invite, 2)

	views.Invite:setCallbacks({
		onInvite = function(userId: number)
			task.spawn(function()
				if not promptInvite(userId) then
					self:toast("Invites aren't available right now.", { Tone = "bad" })
				end
			end)
		end,
		onInviteAny = function()
			task.spawn(function()
				if not promptInvite(nil) then
					self:toast("Invites aren't available right now.", { Tone = "bad" })
				end
			end)
		end,
	})

	-- Cui a plecat invitatia afla Roblox, la inchiderea ferestrei lui; lista o marcheaza.
	pcall(function()
		game:GetService("SocialService").GameInvitePromptClosed
			:Connect(function(player: Instance, recipients: { any })
				if player == LOCAL_PLAYER and type(recipients) == "table" then
					views.Invite:markInvited(recipients)
				end
			end)
	end)

	--[[
		Indemnul pentru grup: discret, sub celelalte, si numai pentru cine nu e
		in el. Daca jocul n-are grup setat, nu apare deloc.
	]]
	local groupId = GameConfig.Social.GroupId
	if groupId ~= 0 then
		local nudge = Theme.button({
			Name = "Group",
			Text = string.format(
				"Join our group for +%d%% coins",
				math.floor(GameConfig.Social.GroupBonus * 100 + 0.5)
			),
			Skin = "Secondary",
			TextSize = 12,
			TextWrapped = true,
			Size = UDim2.fromOffset(160, 46),
			Visible = false,
			ZIndex = 11,
		})
		nudge.MouseButton1Click:Connect(function()
			task.spawn(promptJoinGroup, groupId)
		end)
		local function update()
			nudge.Visible = LOCAL_PLAYER:GetAttribute("InGroup") == false
		end
		LOCAL_PLAYER:GetAttributeChangedSignal("InGroup"):Connect(update)
		update()
		self:addToBar("Group", nudge, 3)
	end

	views.Players:setCallbacks({
		onChallenge = function(modeId: string, invitees: { number })
			Remotes.get("RequestChallenge"):FireServer(modeId, invitees)
		end,
		onAddFriend = function(userId: number)
			promptFriendRequest(userId)
		end,
	})

	views.Challenge:setCallbacks({
		onAccept = function(id: string)
			Remotes.get("RequestChallengeAnswer"):FireServer(id, true)
		end,
		onDecline = function(id: string)
			Remotes.get("RequestChallengeAnswer"):FireServer(id, false)
		end,
		onCancel = function(id: string)
			Remotes.get("RequestChallengeCancel"):FireServer(id)
		end,
	})

	self:listen()
	return self
end

-- O intrare din lista pentru fiecare jucator in afara de tine.
function SocialController.refresh(self: SocialController)
	local entries = {}
	for _, player in Players:GetPlayers() do
		if player ~= LOCAL_PLAYER then
			local presence = player:GetAttribute(PRESENCE)
			table.insert(entries, {
				UserId = player.UserId,
				Name = player.DisplayName,
				Presence = if typeof(presence) == "string" then presence else nil,
				Friend = self.Friends[player.UserId] == true,
			})
		end
	end
	self.Views.Players:refresh(entries)
end

--[[
	Aduce lista de prieteni pentru popup-ul de invitatii. Tinuta minte o
	jumatate de minut: deschis si inchis de doua ori la rand, nu intreaba Roblox
	de fiecare data.
]]
local FRIENDS_FRESH = 30

function SocialController.loadInvites(self: SocialController)
	local view = self.Views.Invite
	if self.FriendList and os.clock() - self.FriendListAt < FRIENDS_FRESH then
		view:setFriends(self.FriendList)
		return
	end
	view:setLoading()
	task.spawn(function()
		local friends, problem = loadFriends()
		if friends then
			self.FriendList = friends
			self.FriendListAt = os.clock()
			view:setFriends(friends)
		else
			view:setError(problem or "Couldn't load your friends right now.")
		end
	end)
end

function SocialController.isFriend(self: SocialController, userId: number): boolean
	return self.Friends[userId] == true
end

function SocialController.toast(self: SocialController, text: string, options: any?)
	local toast = self.Views.SocialToast
	if toast then
		toast:show(text, options)
	end
end

-- Adauga un element pe bara sociala (invitatie, indemnul de grup).
function SocialController.addToBar(
	self: SocialController,
	name: string,
	item: GuiObject,
	order: number
)
	item.LayoutOrder = order
	item.Parent = self.Bar
	self.BarItems[name] = item
end

--[[
	In lobby sau la masa. Bara si lista tin de lobby; la masa se strang, ca sa
	nu stea peste tabla.
]]
function SocialController.setInLobby(self: SocialController, inLobby: boolean)
	self.InLobby = inLobby
	self.Bar.Visible = inLobby
	if not inLobby then
		self.Views.Players:close()
		self.Views.Invite:close()
	end
	self:updateHearts()
end

--[[
	Insigna „♥ FRIEND" deasupra prietenilor din lume.

	Obiecte noi, facute aici, legate de capul avatarului prin `Adornee` si tinute
	in `PlayerGui` — modelele din lume nu se ating. Numai in lobby: la masa,
	deasupra pionilor, ar fi zgomot peste tabla.
]]
function SocialController.updateHearts(self: SocialController)
	local playerGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local seen: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local head = if character then character:FindFirstChild("Head") else nil
		if
			player == LOCAL_PLAYER
			or not self.Friends[player.UserId]
			or not (head and head:IsA("BasePart"))
		then
			continue
		end
		seen[player.UserId] = true

		local existing = self.Hearts[player.UserId]
		local badge: BillboardGui
		if existing and existing.Adornee == head and existing.Parent then
			badge = existing
		else
			if existing then
				existing:Destroy()
			end
			badge = Theme.create("BillboardGui", {
				Name = "FriendHeart",
				Adornee = head,
				Size = UDim2.fromOffset(92, 26),
				StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0),
				MaxDistance = 90,
				ResetOnSpawn = false,
				Parent = playerGui,
			}, {
				Theme.create("TextLabel", {
					BackgroundColor3 = Theme.Color.Highlight,
					BorderSizePixel = 0,
					Font = Theme.Font.Bold,
					Text = "♥ FRIEND",
					TextColor3 = Theme.Color.TextInverse,
					TextSize = 14,
					Size = UDim2.fromScale(1, 1),
				}, { Theme.corner(Theme.Radius.Round) }),
			}) :: BillboardGui
			self.Hearts[player.UserId] = badge
		end
		badge.Enabled = self.InLobby
	end

	for userId, badge in self.Hearts do
		if not seen[userId] then
			badge:Destroy()
			self.Hearts[userId] = nil
		end
	end
end

-- Apasarea pe avatarul cuiva in lume, in lobby: meniul mic pe omul ala.
local function playerAt(position: Vector3): Player?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	local character = LOCAL_PLAYER.Character
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	local node: Instance? = if hit then hit.Instance else nil
	while node and node ~= Workspace do
		if node:IsA("Model") then
			local owner = Players:GetPlayerFromCharacter(node)
			if owner then
				return owner
			end
		end
		node = node.Parent
	end
	return nil
end

function SocialController.listen(self: SocialController)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			self:updateHearts()
		end)
		player:GetAttributeChangedSignal(PRESENCE):Connect(function()
			self:refresh()
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		watch(player)
		self:refresh()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self.Friends[player.UserId] = nil
		task.defer(function()
			self:refresh()
			self:updateHearts()
		end)
	end)

	Remotes.get("SocialEvent").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Type == "Friends" and type(payload.UserIds) == "table" then
			table.clear(self.Friends)
			for _, userId in payload.UserIds do
				if type(userId) == "number" then
					self.Friends[userId] = true
				end
			end
			self:refresh()
			self:updateHearts()
		elseif payload.Type == "Challenge" then
			self.Views.Challenge:update(payload, LOCAL_PLAYER.UserId)
		elseif payload.Type == "FriendJoined" and type(payload.UserId) == "number" then
			local userId = payload.UserId
			local name = if type(payload.Name) == "string" then payload.Name else "A friend"
			self:toast(string.format("%s joined the server", name), {
				Tone = "good",
				Seconds = 7,
				Action = if self.InLobby then "CHALLENGE" else nil,
				OnAction = function()
					self:refresh()
					self.Views.Players:challenge(userId)
				end,
			})
		elseif payload.Type == "Referral" and type(payload.Coins) == "number" then
			local name = if type(payload.Name) == "string" then payload.Name else "a friend"
			local text = if payload.Role == "Invitee"
				then string.format("You joined through %s! +%d", name, payload.Coins)
				else string.format("%s joined from your invite! +%d", name, payload.Coins)
			self:toast(text, { Tone = "good", Seconds = 6 })
		end
	end)

	Remotes.get("ActionRejected").OnClientEvent:Connect(function(reason: any)
		if type(reason) == "string" and string.sub(reason, 1, 10) == "CHALLENGE_" then
			local key = string.sub(reason, 11)
			self:toast(REJECTION_TEXT[key] or "That challenge couldn't be sent.", { Tone = "bad" })
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not self.InLobby then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		if self.Views.Players:isOpen() then
			return
		end
		local other = playerAt(input.Position)
		if other and other ~= LOCAL_PLAYER then
			self:refresh()
			self.Views.Players:openFor(other.UserId)
		end
	end)
end

-- Pentru fazele urmatoare: cererea de prietenie de pe ecranul de final.
SocialController.promptFriendRequest = promptFriendRequest

return SocialController
