-- Rider poses on two wheels, for every player this client can see (Motor6D.Transform is local and
-- never replicates, so each client animates everyone).
--   bicycle   : feet on pedals that turn with the road speed (two-bone leg IK), hands on the bars,
--               back bent forward
--   motorbikes: feet on the pegs / floorboard, hands on the bars, sport bikes tucked in
-- Leaning comes for free: the seat is welded to the bike body that Drive tilts.
-- Written in PreSimulation, which runs after the Animator, so it replaces the sit animation for
-- these joints. Works on R15 (full IK) and R6 (hip / shoulder swing only).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Vehicles = require(Shared.Config.Vehicles)
local Drive = require(script.Parent.Drive)

local Rider = {}
local player = Players.LocalPlayer
local A = CFrame.Angles
local rad = math.rad
local TAU = math.pi * 2

-- [character] = { rig, crank, model, seen, root = { last, base } }  (strong; dropped when they get off)
local riders = {} :: { [Model]: any }

---------------------------------------------------------------------------------------------------
-- rig
---------------------------------------------------------------------------------------------------
-- A limb joint: a classic Motor6D, or an AnimationConstraint, which current avatars use instead
-- (2026-11-16: the old pose code looked for Motor6D only, found nothing, and riders just sat
-- still). Both expose Transform, applied between the parent-side frame and the limb.
local function motor(char: Model, part: string, name: string): any
	local p = char:FindFirstChild(part)
	local m = p and p:FindFirstChild(name)
	if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then return m end
	return nil
end

-- The joint's frame in the world (where Transform is applied), and the joint point in each part.
local function jointFrame(m: any): CFrame?
	if m:IsA("Motor6D") then return m.Part0 and (m.Part0.CFrame * m.C0) or nil end
	return m.Attachment0 and m.Attachment0.WorldCFrame or nil
end
local function inParent(m: any): Vector3
	if m:IsA("Motor6D") then return m.C0.Position end
	return m.Attachment0 and m.Attachment0.Position or Vector3.zero
end
local function inChild(m: any): Vector3
	if m:IsA("Motor6D") then return m.C1.Position end
	return m.Attachment1 and m.Attachment1.Position or Vector3.zero
end

local function rigOf(char: Model): any
	if char:FindFirstChild("LowerTorso") then
		local J = {
			kind = "R15",
			root = motor(char, "LowerTorso", "Root"),
			waist = motor(char, "UpperTorso", "Waist"),
			neck = motor(char, "Head", "Neck"),
			rs = motor(char, "RightUpperArm", "RightShoulder"), ls = motor(char, "LeftUpperArm", "LeftShoulder"),
			re = motor(char, "RightLowerArm", "RightElbow"), le = motor(char, "LeftLowerArm", "LeftElbow"),
			rh = motor(char, "RightUpperLeg", "RightHip"), lh = motor(char, "LeftUpperLeg", "LeftHip"),
			rk = motor(char, "RightLowerLeg", "RightKnee"), lk = motor(char, "LeftLowerLeg", "LeftKnee"),
			ra = motor(char, "RightFoot", "RightAnkle"), la = motor(char, "LeftFoot", "LeftAnkle"),
		}
		if not (J.rh and J.lh and J.rk and J.lk and J.rs and J.ls) then return nil end
		-- leg segments from the joint offsets: thigh = hip -> knee, shin = knee -> ankle
		J.l1 = math.max(0.4, (inChild(J.rh) - inParent(J.rk)).Magnitude)
		J.l2 = J.ra and math.max(0.4, (inChild(J.rk) - inParent(J.ra)).Magnitude) or J.l1
		-- arm segments: shoulder -> elbow, elbow -> wrist plus a palm to hold the grip with
		local wrist = motor(char, "RightHand", "RightWrist")
		if J.re then
			J.ua = math.max(0.3, (inChild(J.rs) - inParent(J.re)).Magnitude)
			J.fa = math.max(0.3, (wrist and (inChild(J.re) - inParent(wrist)).Magnitude or J.ua) + 0.25)
		end
		return J
	end
	if char:FindFirstChild("Torso") then
		local J = {
			kind = "R6",
			root = motor(char, "HumanoidRootPart", "RootJoint"),
			neck = motor(char, "Torso", "Neck"),
			rs = motor(char, "Torso", "Right Shoulder"), ls = motor(char, "Torso", "Left Shoulder"),
			rh = motor(char, "Torso", "Right Hip"), lh = motor(char, "Torso", "Left Hip"),
		}
		if not (J.rh and J.lh and J.rs and J.ls) then return nil end
		return J
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- pose maths
---------------------------------------------------------------------------------------------------
-- Two-bone IK in the hip's side plane. Target is `f` studs forward and `dn` studs down from the
-- hip. Returns the thigh angle and the shin's absolute angle, both measured from straight down
-- towards the front (knee bends forward).
local function legIK(l1: number, l2: number, f: number, dn: number): (number, number)
	local d = math.clamp(math.sqrt(f * f + dn * dn), math.abs(l1 - l2) + 0.05, l1 + l2 - 0.02)
	local th = math.atan2(f, dn)
	local a = th + math.acos(math.clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1))
	local b = th - math.acos(math.clamp((l2 * l2 + d * d - l1 * l1) / (2 * l2 * d), -1, 1))
	return a, b
end

-- R15 joints swing forward about +X; R6 limbs swing about the motor's Z (mirrored on the left).
local function swing15(m: any, x: number, z: number?)
	if m then m.Transform = A(x, 0, z or 0) end
end

-- Bicycle crank when the bike gives no better hint: measured from the hip as a fraction of the leg
-- length. CRANK_R is the pedal circle's radius, also as a fraction of the leg.
local CRANK_F, CRANK_D, CRANK_R = 0.30, 0.70, 0.20

-- Where the bicycle's bottom bracket is in the world: the part-built bike has a "Crank" part; the
-- mesh bike's crank is estimated from the wheels (about 41 % of the wheelbase ahead of the rear
-- axle, a little below axle height), which is where real frames put it.
local function crankWorld(model: Model, def): Vector3?
	local part = model:FindFirstChild("Crank")
	if part and part:IsA("BasePart") then return part.Position end
	local body = model:FindFirstChild("Body")
	local wf, wr = model:GetAttribute("Wheel1"), model:GetAttribute("Wheel3")
	if not (body and body:IsA("BasePart")) or typeof(wf) ~= "Vector3" or typeof(wr) ~= "Vector3" then return nil end
	local ride = model:GetAttribute("RideHeight") or (def.wheelR + 0.9)
	return body.CFrame * Vector3.new(0, -ride + def.wheelR * 0.95, wr.Z + 0.41 * (wf.Z - wr.Z))
end

local function poseLegs15(J, def, crank: number, model: Model)
	local L = J.l1 + J.l2
	if def.pedal then
		local cw = crankWorld(model, def)
		for side = 0, 1 do
			local phi = crank + side * math.pi
			local hip = (side == 0) and J.rh or J.lh
			local cf0, cd0 = CRANK_F * L, CRANK_D * L
			local frame = cw and jointFrame(hip)
			if frame then
				-- the crank seen from this hip joint: forward = -Z, down = -Y
				local lp = frame:PointToObjectSpace(cw)
				cf0, cd0 = -lp.Z, -lp.Y
			end
			local f = cf0 + CRANK_R * L * math.sin(phi)
			local dn = cd0 - CRANK_R * L * math.cos(phi)
			local a, b = legIK(J.l1, J.l2, f, dn)
			local foot = rad(-6) + rad(12) * math.sin(phi) -- a little ankling round the stroke
			local knee, ankle = (side == 0) and J.rk or J.lk, (side == 0) and J.ra or J.la
			swing15(hip, a, side == 0 and rad(-3) or rad(3))
			swing15(knee, b - a)
			swing15(ankle, foot - b)
		end
	else
		-- feet on the pegs: sport bikes have them high and back, scooters on a flat floorboard
		local style = def.style
		local a, b = rad(66), rad(-6)
		if style == "sport" or style == "bigbike" then a, b = rad(58), rad(-26)
		elseif style == "scooter" or style == "underbone" or style == "oldbike" then a, b = rad(74), rad(4) end
		for side = 0, 1 do
			local out = side == 0 and rad(-6) or rad(6)
			swing15(side == 0 and J.rh or J.lh, a, out)
			swing15(side == 0 and J.rk or J.lk, b - a)
			swing15(side == 0 and J.ra or J.la, rad(4) - b)
		end
	end
end

-- Upper body. Angles are "forward from vertical" in the bike's frame. The sit animation reclines
-- the hips (`hipPitch`, measured each frame), so the waist makes up the difference to reach the
-- wanted back angle, and the shoulders aim the arms down at the bars from there.
-- Handlebar grips, from the seat part (studs: up, forward = -Z). Bicycle measured against the
-- mesh in Studio; the motorbike numbers are estimates.
local BARS = {
	bicycle = Vector3.new(0, 0.85, -2.0),
	oldbike = Vector3.new(0, 1.0, -1.8), underbone = Vector3.new(0, 1.0, -1.8), scooter = Vector3.new(0, 1.1, -1.7),
	sport = Vector3.new(0, 0.7, -2.1), bigbike = Vector3.new(0, 0.95, -2.0),
}

local function poseUpper15(J, def, steer: number, hipPitch: number, seat: BasePart)
	local sport = def.style == "sport" or def.style == "bigbike"
	local back = rad(def.pedal and 22 or (sport and 38 or 12)) -- back angle in the bike's frame
	local waist = math.clamp(back - hipPitch, rad(-15), rad(70))
	swing15(J.waist, -waist)
	swing15(J.neck, back * 0.75) -- head up, eyes on the road
	-- arms: two-bone IK onto the grips, elbows bending down and back; steering pushes one hand
	-- forward and pulls the other
	local bars = BARS[def.style] or BARS.scooter
	local s = math.clamp(steer, -1, 1) * 0.25
	for side = 0, 1 do
		local sh, el = (side == 0) and J.rs or J.ls, (side == 0) and J.re or J.le
		local frame = jointFrame(sh)
		if frame and el and J.ua then
			local grip = seat.CFrame * (bars + Vector3.new(0, 0, side == 0 and s or -s))
			local lp = frame:PointToObjectSpace(grip)
			local f, dn = -lp.Z, -lp.Y
			local d = math.clamp(math.sqrt(f * f + dn * dn), math.abs(J.ua - J.fa) + 0.05, J.ua + J.fa - 0.02)
			local th = math.atan2(f, dn)
			local a = th - math.acos(math.clamp((J.ua * J.ua + d * d - J.fa * J.fa) / (2 * J.ua * d), -1, 1))
			local b = th + math.acos(math.clamp((J.fa * J.fa + d * d - J.ua * J.ua) / (2 * J.fa * d), -1, 1))
			swing15(sh, a, side == 0 and rad(-6) or rad(6))
			swing15(el, b - a)
		else
			local reach = rad(sport and 62 or 50) + back
			swing15(sh, reach, side == 0 and rad(-6) or rad(6))
			swing15(el, rad(20))
		end
	end
end

-- How far the hips lean forward (+) or back (-) relative to the seat.
local function hipPitch(char: Model, seat: BasePart): number
	local lt = char:FindFirstChild("LowerTorso") :: BasePart?
	if not lt then return 0 end
	local up = seat.CFrame:VectorToObjectSpace(lt.CFrame.UpVector)
	return math.atan2(-up.Z, up.Y)
end

local function pose6(J, def, crank: number, steer: number)
	-- straight limbs: swing the leg towards where the pedal / peg is
	if def.pedal then
		for side = 0, 1 do
			local phi = crank + side * math.pi
			local f = CRANK_F + CRANK_R * math.sin(phi)
			local dn = CRANK_D - CRANK_R * math.cos(phi)
			local a = math.atan2(f, dn) + rad(10)
			if side == 0 then J.rh.Transform = A(0, 0, a) else J.lh.Transform = A(0, 0, -a) end
		end
	else
		J.rh.Transform = A(0, 0, rad(60))
		J.lh.Transform = A(0, 0, -rad(60))
	end
	local s = math.clamp(steer, -1, 1) * rad(10)
	J.rs.Transform = A(0, 0, rad(75) - s)
	J.ls.Transform = A(0, 0, -(rad(75) + s))
end

-- Off the bike: hand the joints back to the Animator in a neutral state.
local function release(char: Model, st)
	local J = st.rig
	if J then
		for _, k in ipairs({ "waist", "neck", "rs", "ls", "re", "le", "rh", "lh", "rk", "lk", "ra", "la" }) do
			local m = J[k]
			if m and m.Parent then m.Transform = CFrame.identity end
		end
	end
	riders[char] = nil
end

---------------------------------------------------------------------------------------------------
-- per frame
---------------------------------------------------------------------------------------------------
local function step(dt: number)
	dt = math.min(dt, 1 / 20)
	local cur = Drive.current()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		local model = seat and seat.Parent
		local def = (model and seat:IsA("VehicleSeat") and model:HasTag("GoDashVehicle")) and Vehicles.ById[model:GetAttribute("VehicleId")] or nil
		-- a friend riding pillion (server/VehicleService "PaxSeat"): feet on the pegs, hands on the knees
		local pdef = (not def and model and seat:IsA("Seat") and seat.Name == "PaxSeat" and model:HasTag("GoDashVehicle")) and Vehicles.ById[model:GetAttribute("VehicleId")] or nil
		if char and pdef and pdef.class == "bike" then
			local st = riders[char]
			if not st or st.model ~= model then
				if st then release(char, st) end
				st = { model = model, crank = 0, rig = rigOf(char) }
				riders[char] = st
			end
			st.seen = true
			local J = st.rig
			if J and J.kind == "R15" then
				poseLegs15(J, { style = pdef.style, pedal = false }, 0, model)
				swing15(J.waist, -rad(6))
				swing15(J.neck, rad(4))
				swing15(J.rs, rad(28), rad(-8)); swing15(J.ls, rad(28), rad(8))
				swing15(J.re, rad(42)); swing15(J.le, rad(42))
			elseif J then
				J.rh.Transform = A(0, 0, rad(60)); J.lh.Transform = A(0, 0, -rad(60))
			end
		end
		if char and def and def.class == "bike" then
			local st = riders[char]
			if not st or st.model ~= model then
				if st then release(char, st) end
				st = { model = model, crank = 0, rig = rigOf(char) }
				riders[char] = st
			end
			st.seen = true
			local J = st.rig
			if J then
				local mine = plr == player and cur ~= nil and cur.model == model
				local crank, steer = st.crank, 0
				if mine then
					crank, steer = cur.crank or 0, cur.steerNow or 0
				elseif def.pedal then
					local chassis = model.PrimaryPart
					local v = chassis and chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector) or 0
					local cadence = v > 1.5 and math.clamp(3 + v * 0.35, 3, 11) or 0
					st.crank = (st.crank + cadence * dt) % TAU
					crank = st.crank
				end
				if J.kind == "R15" then
					poseLegs15(J, def, crank, model)
					poseUpper15(J, def, steer, hipPitch(char, seat), seat)
				else
					pose6(J, def, crank, steer)
				end
			end
		end
	end
	for char, st in pairs(riders) do
		if st.seen then st.seen = false else release(char, st) end
	end
end

function Rider.start()
	RunService.PreSimulation:Connect(step)
end

return Rider
