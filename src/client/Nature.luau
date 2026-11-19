-- A calmer, livelier town to watch (2026-11-19, owner: "ปรับกราฟฟิคเกมส์ให้สวยงามเหมาะแก่การดูเพลินๆ").
-- Small moving things, no change to the colour grade (client/Env keeps the owner's "bright, cheerful, no glare"):
--   * a light breeze (Workspace.GlobalWind): the live clouds drift across the sky
--   * the trees near the camera sway in it (tag "Sway", server/World/Scenery), each at its own pace
--   * by day a few flocks of birds wheel over the rooftops
-- Phones (Perf tier 1-2) get fewer of each; the lowest tier none of the trees or birds.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local Perf = require(script.Parent.Perf)

local Nature = {}
local SWAY_RANGE = 150
local swaying = {} :: { [Model]: { base: CFrame, foot: Vector3, phase: number, amp: number, speed: number } }
local holder: Folder

---------------------------------------------------------------------------------------------------
-- trees
---------------------------------------------------------------------------------------------------
local function maxTrees(): number
	return Perf.tier >= 3 and 28 or (Perf.tier == 2 and 14 or 0)
end

local tagged = {} :: { Model }
local function refreshTagged()
	tagged = CollectionService:GetTagged("Sway")
end

local nearList = {} :: { Model }
local function pickNear(camPos: Vector3)
	local n = maxTrees()
	local scored = {}
	if n > 0 then
		for _, m in ipairs(tagged) do
			if m.Parent and m:IsA("Model") then
				local p = m:GetPivot().Position
				local d = (p - camPos).Magnitude
				if d < SWAY_RANGE then table.insert(scored, { m = m, d = d }) end
			end
		end
		table.sort(scored, function(a, b) return a.d < b.d end)
	end
	local keep = {}
	nearList = {}
	for i = 1, math.min(n, #scored) do
		local m = scored[i].m
		keep[m] = true
		table.insert(nearList, m)
		if not swaying[m] then
			local seed = (m:GetPivot().Position.X * 0.37 + m:GetPivot().Position.Z * 0.61) % 6.283
			local bcf, size = m:GetBoundingBox()
			local h = size.Y
			-- tall trees move slower and a touch less; they bend at the foot of the trunk
			local pv = m:GetPivot()
			swaying[m] = { base = pv, foot = Vector3.new(pv.Position.X, bcf.Position.Y - size.Y / 2, pv.Position.Z), phase = seed,
				amp = math.rad(math.clamp(26 / math.max(h, 8), 0.6, 1.8)), speed = 0.7 + (seed % 1) * 0.5 }
		end
	end
	-- the ones left behind go back to how they stood
	for m, s in pairs(swaying) do
		if not keep[m] then
			if m.Parent then m:PivotTo(s.base) end
			swaying[m] = nil
		end
	end
end

local function swayStep(t: number)
	local wind = 0.75 + 0.25 * math.sin(t * 0.21) -- gusts come and go
	for _, m in ipairs(nearList) do
		local s = swaying[m]
		if s and m.Parent then
			local a = math.sin(t * s.speed + s.phase) * s.amp * wind
			local b = math.sin(t * s.speed * 0.63 + s.phase * 1.7) * s.amp * 0.45 * wind
			m:PivotTo(CFrame.new(s.foot) * CFrame.Angles(b, 0, a) * CFrame.new(-s.foot) * s.base)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- birds
---------------------------------------------------------------------------------------------------
local flocks = {}

local function makeBird(): { body: Part, l: Part, r: Part }
	local function p(size: Vector3): Part
		local x = Instance.new("Part")
		x.Size = size
		x.Color = Color3.fromRGB(44, 42, 46)
		x.Material = Enum.Material.SmoothPlastic
		x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch, x.CastShadow = true, false, false, false, false
		x.Parent = holder
		return x
	end
	return { body = p(Vector3.new(0.35, 0.3, 1.0)), l = p(Vector3.new(1.3, 0.06, 0.55)), r = p(Vector3.new(1.3, 0.06, 0.55)) }
end

local function makeFlock(i: number)
	local n = 5 + (i % 3)
	local f = { birds = {}, phase = i * 2.1, radius = 90 + i * 25, height = 55 + i * 9, speed = 0.09 + i * 0.012, center = nil }
	for k = 1, n do
		local b = makeBird()
		b.offset = Vector3.new(((k % 2) * 2 - 1) * math.ceil(k / 2) * 2.4, (k % 3) * 0.6, math.ceil(k / 2) * 2.6) -- a loose V
		b.flap = k * 0.9
		table.insert(f.birds, b)
	end
	return f
end

local function setBirdsVisible(f, on: boolean)
	for _, b in ipairs(f.birds) do
		local tr = on and 0 or 1
		b.body.Transparency, b.l.Transparency, b.r.Transparency = tr, tr, tr
	end
end

local function birdsStep(t: number, camPos: Vector3, dayK: number)
	local want = (Perf.tier >= 3 and 3 or (Perf.tier == 2 and 1 or 0))
	local rain = (Workspace:GetAttribute("Rain") or 0) > 0.2
	for i = 1, 3 do
		local f = flocks[i]
		local on = i <= want and dayK > 0.35 and not rain
		if on and not f then
			f = makeFlock(i)
			flocks[i] = f
		end
		if f then
			if on and not f.shown then f.center = nil end -- (back after a while: start round the camera again)
			f.shown = on
			setBirdsVisible(f, on)
			if on then
				-- each flock circles a point that drifts after the camera, so there are always birds about
				f.center = f.center and f.center:Lerp(camPos, 0.006) or camPos
				local a = t * f.speed + f.phase
				local c = Vector3.new(f.center.X, f.height + math.sin(t * 0.3 + i) * 6, f.center.Z)
				local pos = c + Vector3.new(math.cos(a) * f.radius, 0, math.sin(a) * f.radius)
				local dir = Vector3.new(-math.sin(a), 0, math.cos(a))
				local frame = CFrame.lookAt(pos, pos + dir)
				for _, b in ipairs(f.birds) do
					local cf = frame * CFrame.new(b.offset)
					local w = math.sin(t * 9 + b.flap) * 0.55 -- the wing beat
					b.body.CFrame = cf
					b.l.CFrame = cf * CFrame.new(-0.18, 0, 0) * CFrame.Angles(0, 0, w) * CFrame.new(-0.62, 0, 0)
					b.r.CFrame = cf * CFrame.new(0.18, 0, 0) * CFrame.Angles(0, 0, -w) * CFrame.new(0.62, 0, 0)
				end
			end
		end
	end
end

function Nature.start()
	holder = Instance.new("Folder")
	holder.Name = "GoDashNature"
	holder.Parent = Workspace
	-- a light breeze: the Terrain clouds drift with it
	Workspace.GlobalWind = Vector3.new(6, 0, 2.5)
	refreshTagged()
	CollectionService:GetInstanceAddedSignal("Sway"):Connect(function() task.defer(refreshTagged) end)
	CollectionService:GetInstanceRemovedSignal("Sway"):Connect(function() task.defer(refreshTagged) end)
	local acc, pickAcc = 0, 1
	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local camPos = cam.CFrame.Position
		local t = os.clock()
		pickAcc += dt
		if pickAcc > 1 then
			pickAcc = 0
			pickNear(camPos)
		end
		acc += dt
		if acc >= 1 / 30 then -- 30 updates a second is plenty for a breeze
			acc = 0
			swayStep(t)
		end
		local ct = Lighting.ClockTime
		local dayK = math.clamp((ct - 6) / 1.5, 0, 1) * math.clamp((18.6 - ct) / 1.5, 0, 1)
		birdsStep(t, camPos, dayK)
	end)
end

return Nature
