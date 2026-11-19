-- Accidents cost money (2026-11-18, owner: "hitting people or other cars should cost you, with a
-- cutscene, so riders drive carefully").
--   * a pedestrian inside your vehicle's box at more than walking pace goes down (client/Peds)
--   * crashing into an AI car (client/Street notices it) or another player's vehicle (Drive's hard-hit
--     check): the other side comes over for the bill
-- The server (AccidentService) sets the amount from the speed, takes it (never below zero) and
-- posts on the City Feed. The scene is the pulled-over scene of client/Cutscene with the claimant
-- instead of a police officer. One claim at a time, at most one every 20 seconds.
--
-- 2026-11-19 (owner: "a cutscene when they let it go too; a CCTV replay of what happened; the person who
-- was hit should get up and come over, not warp in"): the scene now starts with the CCTV replay
-- (client/Replay), then the very person you hit gets up where they fell and limps over (or the other
-- driver gets out of their own car), and when they let it go (the daily limit, or a light bump on a good
-- day: server/AccidentService) the scene still plays, with "it's fine" instead of the bill.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Drive = require(script.Parent.Drive)
local Peds = require(script.Parent.Peds)
local Street = require(script.Parent.Street)
local Cutscene = require(script.Parent.Cutscene)
local Feed = require(script.Parent.Feed)
local Feedback = require(script.Parent.Feedback)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)

local Accident = {}
local player = Players.LocalPlayer
local L = Lang.pick
local busy = false
local lastClaim = -1e9

local function claim(kind: string, speed: number, extra: any?)
	if busy or os.clock() - lastClaim < 20 then return end
	busy = true
	lastClaim = os.clock()
	local hitAt = extra and extra.hitAt or os.clock()
	local ok, _, res = Net.call("City", "accident", kind .. ":" .. math.floor(math.clamp(speed, 0, 999)))
	if not ok then
		if extra and extra.ped and extra.ped.scam then extra.ped.scam = nil; Peds.giveBack(extra.ped) end
		busy = false
		return
	end
	-- (2026-11-19) the fake-injury scammer: the CCTV replay catches them, and they pay you for the trouble
	if kind == "scam" then
		local amount = type(res) == "table" and tonumber(res.amount) or 0
		local t0 = os.clock()
		while State.cutscene and os.clock() - t0 < 15 do task.wait(0.2) end
		local played = false
		if not State.cutscene then
			task.spawn(Cutscene.play, "fine", { reason = "scam", amount = amount, claimant = extra.template, ped = extra.ped, hitAt = hitAt })
			played = State.cutscene
		end
		if not played then
			if extra.ped then Peds.giveBack(extra.ped) end
			Feedback.toast(L(("🎥 A fake injury, caught on CCTV! +฿%d"):format(amount), ("🎥 จับโป๊ะคนแกล้งล้ม! +฿%d"):format(amount)), "good")
		end
		local t1 = os.clock()
		while State.cutscene and os.clock() - t1 < 40 do task.wait(0.25) end
		if extra.ped then extra.ped.scam = nil end
		Feed.post("scam_caught", { amount = amount }, true)
		busy = false
		return
	end
	local amount = type(res) == "table" and tonumber(res.amount) or 0
	local waived = type(res) == "table" and res.waived == true
	-- a hard crash may have thrown you off first: the claim comes when that scene is over
	local t0 = os.clock()
	while State.cutscene and os.clock() - t0 < 15 do task.wait(0.2) end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	-- the claimant walks up whether you are still riding or a hard crash threw you off (Cutscene.fineScene)
	local played = false
	if hum and hum.Health > 0 and not State.cutscene then
		task.spawn(Cutscene.play, "fine", {
			reason = kind == "ped" and "hit_ped" or "hit_car", amount = amount, waived = waived,
			claimant = extra and extra.template, ped = extra and extra.ped, carModel = extra and extra.model,
			holdCar = Street.hold, hitAt = hitAt,
			insured = type(res) == "table" and tonumber(res.insured) or nil, -- (2026-11-19) the insurer's share: the surveyor comes
			n = type(res) == "table" and res.n or nil, limit = type(res) == "table" and res.limit or nil,
		})
		played = State.cutscene -- the scene starts synchronously; false = it could not run here
	end
	if not played then
		if waived then
			Feedback.toast(L("🤝 They let it go this time. Ride carefully!", "🤝 คู่กรณีไม่เอาเรื่อง ครั้งหน้าระวังนะ"), "good")
		else
			Feedback.toast(kind == "ped" and L(("🚑 You hit a pedestrian: hospital bill ฿%d"):format(amount), ("🚑 ชนคนเดินถนน: ค่ารักษา ฿%d"):format(amount))
				or L(("💥 You hit another vehicle: repair bill ฿%d"):format(amount), ("💥 ชนรถคันอื่น: ค่าซ่อม ฿%d"):format(amount)), "bad")
		end
	end
	local t1 = os.clock()
	while State.cutscene and os.clock() - t1 < 40 do task.wait(0.25) end
	if not waived then Feed.post(kind == "ped" and "accident_ped" or "accident_car", { amount = amount }, true) end
	busy = false
end

-- The fake-injury scammer (2026-11-19, viral pack): every few minutes of riding through town at a modest speed,
-- someone on the kerb ahead runs out and throws themselves down just in front of your vehicle. They are borrowed
-- from client/Peds but still recorded (p.scam), so the CCTV replay of the scene shows them diving in.
local nextScam = os.clock() + 150 + math.random() * 150
local scamming = false
local forceScam = false -- (Studio QaScam)

local function runScam(c, p)
	scamming = true
	p.scam = true
	local chassis = c.chassis
	local t0 = os.clock()
	local flopped, hitAt, speed = false, os.clock(), 0
	while os.clock() - t0 < 5.5 do
		local dt = RunService.Heartbeat:Wait()
		if not chassis.Parent or State.cutscene or Drive.current() ~= c then break end
		local cf = chassis.CFrame
		local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		fwd = fwd.Magnitude > 0.05 and fwd.Unit or Vector3.zAxis
		local v = chassis.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local nose = cf.Position + fwd * ((c.def.len or 6) / 2)
		local flatNose = Vector3.new(nose.X, p.pos.Y, nose.Z)
		if (flatNose - p.pos).Magnitude < 3.2 then
			-- the dive, a step before the bumper
			flopped, hitAt = true, os.clock()
			p.downUntil = os.clock() + 9
			Peds.place(p, "lie", p.pos, -fwd)
			break
		end
		-- run for a spot just ahead of the nose, on the vehicle's line
		local goal = flatNose + fwd * math.clamp(speed * 0.45, 2.5, 9)
		local to = Vector3.new(goal.X - p.pos.X, 0, goal.Z - p.pos.Z)
		local dir = to.Magnitude > 0.01 and to.Unit or fwd
		Peds.place(p, "run", p.pos + dir * math.min(to.Magnitude, 11 * dt), dir, 11)
	end
	if flopped then
		Feedback.play("bodyHit", 0.45, 1.2, 0.5)
		Feedback.play("grunt", 0.5, 1.05, 0.3)
		task.spawn(claim, "scam", speed, { ped = p, template = p.template, hitAt = hitAt })
	else
		p.scam = nil
		Peds.giveBack(p, p.pos, p.look)
	end
	scamming = false
end

local function maybeScam(c, speed: number)
	if scamming or os.clock() < nextScam or speed < 6 or speed > 22 then return end
	nextScam = os.clock() + 20 -- nobody fits here: look again a little later
	local cf = c.chassis.CFrame
	-- (someone on either kerb ahead: a play test found the people walking 12-18 studs out from a rider's line)
	for _, e in ipairs(Peds.near(cf.Position, 55)) do
		if not e.down and not e.p.scripted then
			local rel = cf:PointToObjectSpace(e.pos)
			if rel.Z < -12 and rel.Z > -48 and math.abs(rel.X) > 2.5 and math.abs(rel.X) < 19 and Peds.borrow(e.p) then
				nextScam = os.clock() + 200 + math.random() * 160
				task.spawn(runScam, c, e.p)
				forceScam = false
				return
			end
		end
	end
	-- (Studio QaScam on an empty street: the nearest person is brought to the kerb ahead to try it)
	if forceScam then
		forceScam = false
		local best, bd
		for _, e in ipairs(Peds.near(cf.Position, 500)) do
			local dd = (e.pos - cf.Position).Magnitude
			if not e.down and not e.p.scripted and (not bd or dd < bd) then best, bd = e.p, dd end
		end
		if best and Peds.borrow(best) then
			local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
			local at = cf.Position + fwd * 34 + Vector3.new(-fwd.Z, 0, fwd.X) * 9
			Peds.place(best, "idle", Vector3.new(at.X, best.pos.Y, at.Z), -fwd)
			nextScam = os.clock() + 200
			task.spawn(runScam, c, best)
		end
	end
end

function Accident.start()
	-- QA hook (Studio only): Workspace QaScam = true -> the next person ahead on the kerb tries it now
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("QaScam"):Connect(function()
			if workspace:GetAttribute("QaScam") then nextScam = 0; forceScam = true; workspace:SetAttribute("QaScam", nil) end
		end)
	end
	-- pedestrians: every frame while driving faster than walking pace
	RunService.Heartbeat:Connect(function()
		local c = Drive.current()
		if not c or busy or State.cutscene then return end
		local v = c.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		maybeScam(c, speed)
		if speed < 7 then return end
		local p = Peds.hit(c.chassis, (c.def.len or 6) / 2, (c.def.wid or 2) / 2)
		if p then
			Feedback.bad()
			Feedback.play("bodyHit", 0.55, 1.1, 0.5) -- (2026-11-19) the knock, and the person's "oof"
			Feedback.play(math.random() < 0.5 and "grunt" or "grunt2", 0.5, 1.15, 0.3)
			task.spawn(claim, "ped", speed, { ped = p, template = p.template })
		end
	end)
	-- AI traffic: its driver gets out of that very car
	Street.onCrash = function(model, rv)
		if Drive.current() then claim("car", rv, { model = model }) end
	end
	-- other players' vehicles (and the server's route cars)
	Drive.onHit = function(info)
		local inst = info.instance
		if not inst or info.dv < 16 then return end
		local m = inst:FindFirstAncestorWhichIsA("Model")
		while m and not (m:HasTag("GoDashVehicle") or m:HasTag("TrafficCar") or m.Name == "LocalCar") do
			m = m:FindFirstAncestorWhichIsA("Model")
		end
		if m and m ~= info.model then
			-- (a route car's driver gets out of it; another player's vehicle has a real person in it, so a
			-- stranger walks up instead of someone climbing out of their car)
			claim("car", info.dv, { model = (m:HasTag("TrafficCar") or m.Name == "LocalCar") and m or nil })
		end
	end
end

return Accident
