-- Accidents cost money (2026-11-18, owner: "hitting people or other cars should cost you, with a
-- cutscene, so riders drive carefully").
--   * a pedestrian inside your vehicle's box at more than walking pace goes down (client/Peds), gets
--     up, and walks over to claim the hospital bill
--   * crashing into an AI car (client/Street notices it) or another player's vehicle (Drive's hard-hit
--     check): the other driver comes over for the repair bill, hazard lights on
-- The server (AccidentService) sets the amount from the speed, takes it (never below zero) and
-- posts on the City Feed. The scene is the pulled-over scene of client/Cutscene with the claimant
-- instead of a police officer. One claim at a time, at most one every 20 seconds.
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
	local ok, _, res = Net.call("City", "accident", kind .. ":" .. math.floor(math.clamp(speed, 0, 999)))
	if not ok then busy = false return end
	local amount = type(res) == "table" and tonumber(res.amount) or 0
	-- (2026-11-19) past the daily limit (server/FineService) they let it go: the server's toast says so,
	-- no claim scene, and the person just gets up and walks on
	if type(res) == "table" and res.waived then
		busy = false
		return
	end
	-- a hard crash may have thrown you off first: the claim comes when that scene is over
	local t0 = os.clock()
	while State.cutscene and os.clock() - t0 < 15 do task.wait(0.2) end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if extra and extra.ped then
		local p = extra.ped
		task.delay(1.8, function() Peds.vanish(p) end) -- the same person is the one walking over in the scene
	end
	-- the claimant walks up whether you are still riding or a hard crash threw you off (Cutscene.fineScene)
	local played = false
	if hum and hum.Health > 0 and not State.cutscene then
		task.spawn(Cutscene.play, "fine", { reason = kind == "ped" and "hit_ped" or "hit_car", amount = amount, claimant = extra and extra.template, n = type(res) == "table" and res.n or nil, limit = type(res) == "table" and res.limit or nil })
		played = State.cutscene -- the scene starts synchronously; false = it could not run here
	end
	if not played then
		Feedback.toast(kind == "ped" and L(("🚑 You hit a pedestrian: hospital bill ฿%d"):format(amount), ("🚑 ชนคนเดินถนน: ค่ารักษา ฿%d"):format(amount))
			or L(("💥 You hit another vehicle: repair bill ฿%d"):format(amount), ("💥 ชนรถคันอื่น: ค่าซ่อม ฿%d"):format(amount)), "bad")
	end
	local t1 = os.clock()
	while State.cutscene and os.clock() - t1 < 25 do task.wait(0.25) end
	Feed.post(kind == "ped" and "accident_ped" or "accident_car", { amount = amount }, true)
	busy = false
end

function Accident.start()
	-- pedestrians: every frame while driving faster than walking pace
	RunService.Heartbeat:Connect(function()
		local c = Drive.current()
		if not c or busy or State.cutscene then return end
		local v = c.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		if speed < 7 then return end
		local p = Peds.hit(c.chassis, (c.def.len or 6) / 2, (c.def.wid or 2) / 2)
		if p then
			Feedback.bad()
			task.spawn(claim, "ped", speed, { ped = p, template = p.template })
		end
	end)
	-- AI traffic
	Street.onCrash = function(_model, rv)
		if Drive.current() then claim("car", rv) end
	end
	-- other players' vehicles (and the server's route cars)
	Drive.onHit = function(info)
		local inst = info.instance
		if not inst or info.dv < 16 then return end
		local m = inst:FindFirstAncestorWhichIsA("Model")
		while m and not (m:HasTag("GoDashVehicle") or m:HasTag("TrafficCar") or m.Name == "LocalCar") do
			m = m:FindFirstAncestorWhichIsA("Model")
		end
		if m and m ~= info.model then claim("car", info.dv) end
	end
end

return Accident
