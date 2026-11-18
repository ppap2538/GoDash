-- Studio-only test hooks for screenshots and play tests. Does nothing on live servers.
-- Set these Workspace attributes (command bar or a test script, client side unless noted):
--   QaMute  = true                      silence every Sound and SoundGroup for this session
--   QaHud   = false / true              hide / show the game's own ScreenGuis
--   QaView  = "x,y,z,x2,y2,z2[,fov]"   pin the camera at x,y,z looking at x2,y2,z2 ("" releases it)
--   QaClear = true                      no haze, no depth of field, no cloud layer (aerial shots)
--   QaFocus = Vector3  (SERVER side)    stream and build the city around this point instead of the character
--   QaTarget = Vector3                  set a GPS waypoint there (for auto drive tests)
--   QaSceneHold = true                  the fine scene keeps its ticket up for 14 s (screenshots)
--   QaNeeds = true     (SERVER side)    fill energy, hunger and happiness
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Qa = {}

function Qa.start()
	if not RunService:IsStudio() then return end
	local player = Players.LocalPlayer
	local view: CFrame? = nil
	local fov: number? = nil
	local clear = false

	local function hook(s: Instance)
		if s:IsA("Sound") or s:IsA("SoundGroup") then
			(s :: any).Volume = 0
			s:GetPropertyChangedSignal("Volume"):Connect(function()
				if Workspace:GetAttribute("QaMute") and (s :: any).Volume ~= 0 then (s :: any).Volume = 0 end
			end)
		end
	end
	local muted = false
	local function mute()
		if muted or not Workspace:GetAttribute("QaMute") then return end
		muted = true
		for _, d in ipairs(game:GetDescendants()) do pcall(hook, d) end
		game.DescendantAdded:Connect(function(d) pcall(hook, d) end)
	end
	Workspace:GetAttributeChangedSignal("QaMute"):Connect(mute)
	mute()

	local function hud()
		local on = Workspace:GetAttribute("QaHud")
		if on == nil then return end
		for _, g in ipairs(player:WaitForChild("PlayerGui"):GetChildren()) do
			if g:IsA("ScreenGui") and g.Name:sub(1, 6) == "GoDash" and g.Name ~= "GoDashBuild" then g.Enabled = on end
		end
	end
	Workspace:GetAttributeChangedSignal("QaHud"):Connect(hud)

	local function readView()
		local s = Workspace:GetAttribute("QaView")
		local v = {}
		if type(s) == "string" then
			for n in s:gmatch("[^,]+") do table.insert(v, tonumber(n)) end
		end
		if #v >= 6 then
			view = CFrame.lookAt(Vector3.new(v[1], v[2], v[3]), Vector3.new(v[4], v[5], v[6]))
			fov = v[7]
		else
			view, fov = nil, nil
		end
	end
	Workspace:GetAttributeChangedSignal("QaView"):Connect(readView)
	Workspace:GetAttributeChangedSignal("QaClear"):Connect(function() clear = Workspace:GetAttribute("QaClear") == true end)
	-- QaTarget = Vector3: set a GPS waypoint there (auto drive tests); cleared after use
	Workspace:GetAttributeChangedSignal("QaTarget"):Connect(function()
		local v = Workspace:GetAttribute("QaTarget")
		if typeof(v) == "Vector3" then
			require(script.Parent.GPS).setTarget(v, "QA target")
			Workspace:SetAttribute("QaTarget", nil)
		end
	end)

	RunService:BindToRenderStep("GoDashQa", Enum.RenderPriority.Last.Value + 5, function()
		local cam = Workspace.CurrentCamera
		if view and cam then
			cam.CFrame = view
			cam.Focus = view * CFrame.new(0, 0, -200)
			if fov then cam.FieldOfView = fov end
		end
		if clear then
			local a = Lighting:FindFirstChild("GoDashAtmosphere")
			if a then (a :: any).Density = 0.02; (a :: any).Haze = 0 end
			local f = Lighting:FindFirstChild("GoDashFocus")
			if f then (f :: any).Enabled = false end
			local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
			if clouds then clouds.Enabled = false end
		end
	end)
end

return Qa
