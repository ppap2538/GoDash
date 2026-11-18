-- Near misses (2026-11-19, owner: "เสียงประกอบระหว่างขับ ... หรืออื่นๆ"): passing close to another vehicle at a good
-- relative speed whooshes past your ear, from where that vehicle is, louder and higher the faster you pass.
-- Ten looks a second at the vehicles within 14 studs (AI traffic is moved by script, so its speed comes from how
-- far it went since the last look). client/EngineSound keeps the engine, wind, rough road, brakes and indicators;
-- client/Drive the tyre squeal, thumps and crash cracks.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Drive = require(script.Parent.Drive)
local State = require(script.Parent.State)
local EngineSound = require(script.Parent.EngineSound)

local RideSounds = {}
local FOLDERS = { "GoDashLocalTraffic", "Traffic", "Vehicles" }
local seen = setmetatable({}, { __mode = "k" }) :: { [Model]: { pos: Vector3, t: number } }
local cool = setmetatable({}, { __mode = "k" }) :: { [Model]: number }

local function look(now: number)
	local c = Drive.current()
	if not c or State.cutscene or not c.chassis or not c.chassis.Parent then return end
	local me = c.chassis.Position
	local mv = c.chassis.AssemblyLinearVelocity
	mv = Vector3.new(mv.X, 0, mv.Z)
	for _, fname in ipairs(FOLDERS) do
		local f = Workspace:FindFirstChild(fname)
		if not f then continue end
		for _, m in ipairs(f:GetChildren()) do
			if not m:IsA("Model") or m == c.model then continue end
			local pos = m:GetPivot().Position
			local d = Vector3.new(pos.X - me.X, 0, pos.Z - me.Z)
			if d.Magnitude > 14 or math.abs(pos.Y - me.Y) > 8 then
				seen[m] = nil
				continue
			end
			local s = seen[m]
			local vel
			local pp = m.PrimaryPart
			if pp and not pp.Anchored then vel = pp.AssemblyLinearVelocity end
			if (not vel or vel.Magnitude < 0.5) and s and now - s.t > 0.03 then vel = (pos - s.pos) / (now - s.t) end
			if s then s.pos, s.t = pos, now else seen[m] = { pos = pos, t = now } end
			vel = vel and Vector3.new(vel.X, 0, vel.Z) or Vector3.zero
			local rel = mv - vel
			local rs = rel.Magnitude
			if rs > 26 and d.Magnitude < 8 and now - (cool[m] or 0) > 2.5 then
				-- alongside right now (not still ahead or already behind)
				local along = d:Dot(rel / rs)
				if math.abs(along) < 5 then
					cool[m] = now
					local at = pp or m:FindFirstChildWhichIsA("BasePart")
					if at then EngineSound.oneShot(at, Sounds.passBy, math.clamp(rs / 80, 0.3, 0.75), math.clamp(0.85 + rs / 220, 0.85, 1.35)) end
				end
			end
		end
	end
end

function RideSounds.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then return end
		acc = 0
		local ok, err = pcall(look, os.clock())
		if not ok then warn("[RideSounds] " .. tostring(err)) end
	end)
end

return RideSounds
