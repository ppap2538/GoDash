-- Loy Krathong on the client (server/FestivalService, Config/Festival.LOY; 2026-11-18).
--   * a chip at the top while the festival runs: "🏮 Loy Krathong at Bueng Kaen Nakhon", with a route button
--   * the prompt at the end of the pier asks for a wish (preset wishes only), then floats the krathong
--   * every krathong drifts out over the lake here, from the attributes the server gave it (nothing moves
--     on the server, so a lake full of krathongs costs no network)
--   * fireworks over the lake at night: a short show every few minutes on the server clock, so everyone at
--     the lake sees the same show
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Festival = require(Shared.Config.Festival)
local Sounds = require(Shared.Config.Sounds)
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Choice = require(script.Parent.Choice)
local GPS = require(script.Parent.GPS)
local Drive = require(script.Parent.Drive)

local FestivalClient = {}
local LOY = Festival.LOY
local L = Lang.pick
local C, F = UI.C, UI.F
local player = Players.LocalPlayer
local SPEED = 1.7 -- studs per second out over the water

local function active(): boolean
	return Workspace:GetAttribute("Festival") == LOY.id
end

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

---------------------------------------------------------------------------------------------------
-- chip
---------------------------------------------------------------------------------------------------
local function chip()
	local gui = UI.screen("GoDashFestival", Layers.HUD + 2)
	local frame = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(150, 30, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152),
		Size = UDim2.fromOffset(410, 36), Visible = false, Parent = gui })
	UI.corner(frame, 18)
	UI.stroke(frame, Color3.fromRGB(255, 210, 110), 2)
	noT(UI.label(frame, L("🏮 Loy Krathong · Bueng Kaen Nakhon · first krathong free", "🏮 ลอยกระทง บึงแก่นนคร · อันแรกของวันฟรี"), 14, C.white, F.black,
		{ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -100, 1, 0) }))
	noT(UI.button(frame, L("Go", "นำทาง"), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0), Size = UDim2.fromOffset(78, 28), TextSize = 13,
		BackgroundColor3 = Color3.fromRGB(240, 170, 40) }, function()
		local at = Workspace:GetAttribute("FestivalAt")
		if typeof(at) == "Vector3" then
			GPS.setTarget(at, L("Loy Krathong pier", "ท่าลอยกระทง บึงแก่นนคร"))
			Feedback.toast(L("🏮 Route to the krathong pier", "🏮 นำทางไปท่าลอยกระทงแล้ว"), "good")
		end
	end))
	local hiddenUntil = 0
	task.spawn(function()
		while true do
			-- only on foot: while riding it sat over the road ahead (play test 2026-11-18); the route button
			-- and the start toast cover the riders
			frame.Visible = active() and not State.cutscene and os.clock() > hiddenUntil and not (Drive.current())
			task.wait(1)
		end
	end)
	Workspace:GetAttributeChangedSignal("Festival"):Connect(function()
		if active() then
			task.delay(6, function()
				if active() then Feedback.toast(L("🏮 Loy Krathong is on at Bueng Kaen Nakhon! Float a krathong at the pier", "🏮 งานลอยกระทงที่บึงแก่นนครเริ่มแล้ว! ไปลอยกระทงที่ท่าน้ำ"), "good") end
			end)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- the wish card (the pier prompt -> server Notify "krathong_choose")
---------------------------------------------------------------------------------------------------
local choosing = false
local function choose(info)
	if choosing then return end
	choosing = true
	-- three of the wishes, picked at random each time, and a random style
	local idx = {}
	for i = 1, #LOY.wishes do idx[i] = i end
	for i = #idx, 2, -1 do
		local j = math.random(1, i)
		idx[i], idx[j] = idx[j], idx[i]
	end
	local answers = {}
	for k = 1, 3 do
		local w = LOY.wishes[idx[k]]
		table.insert(answers, { L(w.en, w.th) })
	end
	local d = State.data
	local first = not (d and d.daily and (d.daily.krathong or 0) > 0)
	local price = first and L("Free today", "อันแรกของวันฟรี") or ("฿" .. tostring(info and info.price or LOY.price))
	local n = Choice.ask({ icon = "🏮", title = L("Make a wish", "อธิษฐานก่อนลอยกระทง"), text = price, answers = answers, seconds = 20 })
	choosing = false
	if not n then return end
	local style = math.random(1, #LOY.styles)
	local ok, msg = Net.call("City", "krathong", idx[n] .. "," .. style)
	if ok then
		Feedback.good()
		Feedback.toast(L("🏮 Your krathong is floating! ", "🏮 ลอยกระทงแล้ว! ขอให้สมหวังนะ ") .. (msg or ""), "good")
	else
		Feedback.toast("🏮 " .. tostring(msg), "bad")
	end
end

---------------------------------------------------------------------------------------------------
-- krathongs drift
---------------------------------------------------------------------------------------------------
local tracked = {} :: { [Model]: { start: CFrame, dir: Vector3, at: number, y: number, seed: number } }
local function track(m: Instance)
	if not m:IsA("Model") then return end
	local at = m:GetAttribute("LaunchAt")
	if type(at) ~= "number" then return end
	tracked[m] = {
		start = m:GetPivot(), dir = Vector3.new(m:GetAttribute("DirX") or 0, 0, m:GetAttribute("DirZ") or 1),
		at = at, y = m:GetAttribute("WaterY") or 0.8, seed = m:GetAttribute("Seed") or 1,
		max = m:GetAttribute("MaxDist") or 200, -- how far this lane stays over water (server/FestivalService)
	}
	m.Destroying:Connect(function() tracked[m] = nil end)
end

local function drift()
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then return end
		acc = 0
		if next(tracked) == nil then return end
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local now = Workspace:GetServerTimeNow()
		for m, k in pairs(tracked) do
			local t = math.max(0, now - k.at)
			local p0 = k.start.Position
			if (p0 - camPos).Magnitude < 900 then
				-- out at a walking pace, easing off; a slow sideways wander; bobbing and turning on the ripples
				local along = math.min(SPEED * t * (1 - math.min(t / (LOY.lifetime * 2.4), 0.35)), k.max)
				local side = Vector3.new(-k.dir.Z, 0, k.dir.X) * math.sin(t * 0.07 + k.seed) * math.min(6, along * 0.1)
				local pos = Vector3.new(p0.X, k.y + 0.35 + math.sin(t * 1.7 + k.seed) * 0.12, p0.Z) + k.dir * along + side
				local tilt = math.sin(t * 1.3 + k.seed) * 0.06
				m:PivotTo(CFrame.new(pos) * CFrame.Angles(tilt, t * 0.15 + k.seed, tilt * 0.6))
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- fireworks
---------------------------------------------------------------------------------------------------
local fxFolder: Folder? = nil
local function burst(at: Vector3)
	if not fxFolder then
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "GoDashFireworks"
		fxFolder.Parent = Workspace
	end
	local colours = { Color3.fromRGB(255, 80, 70), Color3.fromRGB(255, 210, 70), Color3.fromRGB(90, 230, 130), Color3.fromRGB(90, 170, 255), Color3.fromRGB(250, 120, 230), Color3.fromRGB(255, 255, 255) }
	local col = colours[math.random(1, #colours)]
	-- the rising trail
	local rocket = Instance.new("Part")
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.CanTouch = false
	rocket.CastShadow = false
	rocket.Material = Enum.Material.Neon
	rocket.Color = Color3.fromRGB(255, 220, 160)
	rocket.Size = Vector3.new(0.6, 0.6, 0.6)
	rocket.Shape = Enum.PartType.Ball
	local from = Vector3.new(at.X, at.Y - 110, at.Z)
	rocket.Position = from
	rocket.Parent = fxFolder
	local t0 = os.clock()
	local con
	con = RunService.RenderStepped:Connect(function()
		local k = math.min(1, (os.clock() - t0) / 1.1)
		rocket.Position = from:Lerp(at, 1 - (1 - k) ^ 2)
		if k >= 1 then
			con:Disconnect()
			rocket.Transparency = 1
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(col, col:Lerp(Color3.new(1, 1, 1), 0.5))
			e.LightEmission = 1
			e.LightInfluence = 0
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.2) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(1.4, 2.2)
			e.Speed = NumberRange.new(38, 52)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Drag = 2.2
			e.Acceleration = Vector3.new(0, -14, 0)
			e.Rate = 0
			e.Parent = rocket
			e:Emit(70)
			local light = Instance.new("PointLight")
			light.Color = col
			light.Range = 60
			light.Brightness = 3
			light.Parent = rocket
			local s = Instance.new("Sound")
			s.SoundId = Sounds.boom
			s.Volume = 0.5
			s.PlaybackSpeed = 0.7 + math.random() * 0.25
			s.RollOffMaxDistance = 1600
			s.RollOffMinDistance = 80
			s.SoundGroup = Feedback.sfxGroup
			s.Parent = rocket
			s:Play()
			task.delay(0.35, function() light.Enabled = false end)
			task.delay(3, function() rocket:Destroy() end)
		end
	end)
end

local function fireworks()
	task.spawn(function()
		while true do
			task.wait(0.7 + math.random() * 0.6)
			local at = Workspace:GetAttribute("FestivalSky") or Workspace:GetAttribute("FestivalAt")
			if active() and Workspace:GetAttribute("IsNight") and typeof(at) == "Vector3" then
				local now = Workspace:GetServerTimeNow()
				local cam = Workspace.CurrentCamera
				if now % LOY.SHOW_EVERY < LOY.SHOW_LENGTH and cam and (cam.CFrame.Position - at).Magnitude < 2600 then
					-- over the water the krathongs drift out on (seen from the pier), 90-170 studs up
					local a = math.random() * math.pi * 2
					local r = math.random() * 140
					burst(at + Vector3.new(math.cos(a) * r, 90 + math.random() * 80, math.sin(a) * r))
				end
			end
		end
	end)
end

function FestivalClient.start()
	chip()
	drift()
	fireworks()
	for _, m in ipairs(CollectionService:GetTagged("Krathong")) do track(m) end
	CollectionService:GetInstanceAddedSignal("Krathong"):Connect(function(m) task.defer(track, m) end)
	Net.listen("Notify", function(kind, info)
		if kind == "krathong_choose" then task.spawn(choose, info) end
	end)
	local _ = player
end

return FestivalClient
