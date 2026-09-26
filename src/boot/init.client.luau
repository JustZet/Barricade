--!strict
--[[
	Boot — primul lucru care ruleaza pe client.

	Sta in `ReplicatedFirst` dintr-un singur motiv: tot ce e in
	`StarterPlayerScripts` porneste **dupa** ce Roblox a strans ecranul lui de
	incarcare si ti-a aratat lumea. Pana acum ecranul nostru se ridica abia
	acolo, si inca dupa un `WaitForChild("Assets")` — adica exact dupa ce
	jucatorul apucase sa vada copacii, apa si lobby-ul aparand bucata cu bucata.
	Cortina trebuie sa fie pe ecran *inainte* de primul cadru, nu dupa el.

	Ordinea de aici e toata ideea:

	1. Se construieste ecranul nostru, stins, cat timp al Roblox-ului e pe ecran.
	2. Se asteapta `game.Loaded` — replicarea instantelor — sub ecranul
	   Roblox-ului. Abia de aici incolo `Workspace` chiar contine lobby-ul.
	3. Se intreaba cate fisiere mai sunt de adus. Niciunul — jucatorul are deja
	   lumea — si cortina noastra nu mai apare deloc.
	4. Altfel se aprinde ecranul nostru, si abia dupa aceea se cheama
	   `RemoveDefaultLoadingScreen`, deci nu exista nicio clipa in care sa se
	   vada scena goala.
	5. Se cer asseturile: si `ReplicatedStorage.Assets`, si lumea din
	   `Workspace`, cu bara de progres.
	6. Se asteapta clientul propriu-zis, ca la ridicarea cortinei lobby-ul sa
	   fie deja desenat. La final se scrie `CURTAIN_ATTRIBUTE`, dupa care
	   porneste muzica.

	Ecranul e chiar `LoadingView`, cerut din `PlayerScripts`. Nu se duplica:
	exista un singur ecran de incarcare in proiect, doar ca acum e pornit de aici.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")

--[[
	Cat se asteapta modulele clientului.

	Scripturile vin in replicarea initiala, deci in practica sunt aici in
	cateva zeci de milisecunde — ce dureaza sunt mesh-urile, care se descarca
	separat. Termenul exista doar ca boot-ul sa nu tina cortina la nesfarsit
	daca cineva scoate `Client` din place.
]]
local MODULE_WAIT = 10

--[[
	Numele atributului prin care clientul spune ca si-a terminat ecranul.

	Trebuie sa stea aici, nu in `Remotes`: alea sunt canale de retea, iar asta e
	o intelegere intre doua scripturi ale aceluiasi client.
]]
local READY_ATTRIBUTE = "BarricadeClientReady"
local READY_WAIT = 25

local function loadingModule(): any?
	local scripts = LOCAL_PLAYER:WaitForChild("PlayerScripts", MODULE_WAIT)
	local client = scripts and scripts:WaitForChild("Client", MODULE_WAIT)
	local ui = client and client:WaitForChild("UI", MODULE_WAIT)
	local module = ui and ui:WaitForChild("LoadingView", MODULE_WAIT)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, loaded = pcall(require, module)
	return if ok then loaded else nil
end

--[[
	Asteapta clientul sa-si termine ecranul.

	Fara pasul asta cortina s-ar ridica peste un lobby gol si butonul START ar
	aparea o clipa mai tarziu, sarind in imagine. Termenul e plasa de siguranta:
	daca clientul a picat cu o eroare, jucatorul trebuie sa ajunga totusi in joc,
	nu sa ramana sub o cortina care nu se mai ridica.
]]
local function waitForClient()
	if LOCAL_PLAYER:GetAttribute(READY_ATTRIBUTE) then
		return
	end
	local deadline = os.clock() + READY_WAIT
	while not LOCAL_PLAYER:GetAttribute(READY_ATTRIBUTE) and os.clock() < deadline do
		task.wait(0.05)
	end
end

--[[
	Atributul cu care boot-ul spune ca a terminat, oricum ar fi terminat: cu
	cortina, fara ea sau pe varianta 2D. De el asteapta muzica, ca sa nu se auda
	peste ecranul de incarcare. Numele e acelasi ca in `src/client/init.client`.
]]
local CURTAIN_ATTRIBUTE = "BarricadeCurtainLifted"

local function lifted()
	LOCAL_PLAYER:SetAttribute(CURTAIN_ATTRIBUTE, true)
end

local LoadingView = loadingModule()
if not LoadingView then
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	lifted()
	return
end

-- Ecranul nostru e gata, dar stins: se aprinde doar daca mai e ceva de adus.
local loading = LoadingView.new(PLAYER_GUI)

--[[
	Cat se replica lumea, pe ecran ramane cel al Roblox-ului. Abia dupa aceea se
	poate afla daca mai e ceva de descarcat — si daca nu mai e, cortina noastra
	nu mai apare deloc.
]]
if not game:IsLoaded() then
	game.Loaded:Wait()
end

--[[
	Acum, si nu mai devreme, `FindFirstChild` spune adevarul: replicarea
	instantelor s-a terminat, deci lipsa lui `Assets` chiar inseamna ca
	mesh-urile nu sunt in place, nu ca n-au ajuns inca.
]]
local assets = ReplicatedStorage:FindFirstChild("Assets")

if not assets then
	--[[
		Varianta 2D nu are ce astepta: tabla ei e desenata, nu adusa. Un ecran
		care apare si piere intr-o clipa e mai suparator decat lipsa lui.
	]]
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	waitForClient()
	loading:dismiss()
	lifted()
	return
end

--[[
	Lumea intra in aceeasi coada ca tabla.

	`Workspace` e de departe partea grea la prima intrare — lobby-ul, copacii,
	apa, terenul — si tocmai el lipsea din cerere. `Assets` ramane primul:
	fara el nu se poate juca, in timp ce fara un copac se poate.
]]
local roots = { assets, Workspace }

--[[
	Totul e deja adus — jucatorul s-a intors, sau le avea deja — deci nu e
	nimic de acoperit. Se da drumul la ecranul Roblox-ului si atat.
]]
if LoadingView.pending(roots) == 0 then
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	loading:dismiss()
	lifted()
	return
end

--[[
	Ordinea ramane cea de la inceput: intai se aprinde ecranul nostru, abia apoi
	pleaca al Roblox-ului, ca intre ele sa nu existe nicio clipa descoperita.
]]
loading:revealLogo()
ReplicatedFirst:RemoveDefaultLoadingScreen()
loading:preload(roots)

waitForClient()
loading:finish()
lifted()
