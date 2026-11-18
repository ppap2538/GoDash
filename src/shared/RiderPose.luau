-- Seats one of the avatar models (ReplicatedStorage.GoDashModels "Ped1"...) on a two-wheeler as a
-- still, anchored figure: hips on the saddle, leaning in a little, hands out on the bars, feet on
-- the footboard, a helmet on. Used for AI traffic, where the whole vehicle model is moved as one
-- piece, so the rider can never come off. (Until 2026-11-16 the AI riders were block figures.)
--
-- The avatars are skinned meshes whose joints are AnimationConstraints (or Motor6Ds on older rigs);
-- each limb is turned about its joint until it points the way it should, whatever pose the model
-- rests in (they rest with their arms held out).
local RiderPose = {}
RiderPose.HELMETS = false -- see "4. helmet" in RiderPose.build

local ARM = { "UpperArm", "LowerArm", "Hand" }
local LEG = { "UpperLeg", "LowerLeg", "Foot" }
local JOINT = {
	UpperTorso = "Waist", Head = "Neck",
	LeftUpperArm = "LeftShoulder", LeftLowerArm = "LeftElbow", LeftHand = "LeftWrist",
	RightUpperArm = "RightShoulder", RightLowerArm = "RightElbow", RightHand = "RightWrist",
	LeftUpperLeg = "LeftHip", LeftLowerLeg = "LeftKnee", LeftFoot = "LeftAnkle",
	RightUpperLeg = "RightHip", RightLowerLeg = "RightKnee", RightFoot = "RightAnkle",
}

-- Where the joint that holds `part` is, in the world (the child-side attachment moves with the part).
local function jointPos(model: Model, part: string): Vector3?
	local p = model:FindFirstChild(part)
	local j = p and p:FindFirstChild(JOINT[part])
	if not j then return nil end
	if j:IsA("AnimationConstraint") then
		local a1 = j.Attachment1
		return a1 and a1.WorldPosition or nil
	elseif j:IsA("Motor6D") then
		return (p :: BasePart).CFrame:PointToWorldSpace(j.C1.Position)
	end
	return nil
end

local function turn(model: Model, names: { string }, about: Vector3, rot: CFrame)
	local t = CFrame.new(about) * rot * CFrame.new(-about)
	for _, n in ipairs(names) do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then p.CFrame = t * p.CFrame end
	end
end

-- The rotation that takes direction a to direction b (unit vectors).
local function between(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-4 then
		return dot > 0 and CFrame.new() or CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Turn the limb `names` (first = the part held by the joint) so that the line from its joint to
-- the next joint (`tipPart`'s joint) points along `dir`.
local function aim(model: Model, names: { string }, tipPart: string, dir: Vector3)
	local a, b = jointPos(model, names[1]), jointPos(model, tipPart)
	if not a or not b or (b - a).Magnitude < 0.05 then return end
	turn(model, names, a, between((b - a).Unit, dir.Unit))
end

local function side(prefix: string, list: { string }): { string }
	local out = {}
	for i, n in ipairs(list) do out[i] = prefix .. n end
	return out
end

-- template: an R15 avatar model. saddle: the top of the seat, facing the way the vehicle faces.
-- Returns the posed, anchored figure (parent it into the vehicle model), or nil if the model is
-- not the kind of rig this understands.
-- The avatars rest with their arms ~43 degrees out (an A-pose); walk animations expect them down.
-- Turns each shoulder joint so the arm hangs down at rest (for figures that are animated).
-- Thai police uniform on an avatar figure: khaki shirt and trousers, black shoes. The avatars are
-- skinned meshes, so nothing is stuck on top (it would float off the real body): the clothes texture
-- of those parts is taken off and the part is coloured. Used by server/PoliceService and the
-- client's fine scene (client/Cutscene).
local KHAKI = Color3.fromRGB(150, 116, 74)
local SHOE = Color3.fromRGB(22, 22, 24)
local UNIFORM = {
	UpperTorso = KHAKI, LowerTorso = KHAKI, LeftUpperArm = KHAKI, RightUpperArm = KHAKI,
	LeftUpperLeg = KHAKI, RightUpperLeg = KHAKI, LeftLowerLeg = KHAKI, RightLowerLeg = KHAKI,
	LeftFoot = SHOE, RightFoot = SHOE,
}
function RiderPose.policeUniform(model: Model)
	for name, col in pairs(UNIFORM) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local sa = p:FindFirstChildOfClass("SurfaceAppearance")
			if sa then sa:Destroy() end
			p.Color = col
			p.Material = Enum.Material.SmoothPlastic -- Fabric reads as camouflage at night
		end
	end
end

-- Any uniform: shirt (torso and upper arms), trousers (legs), shoes. The motorbike-taxi vest, the
-- municipal officers' grey (server/StreetService), the repo crew (client/Finance).
function RiderPose.dress(model: Model, shirt: Color3, trousers: Color3, shoes: Color3?)
	local map = {
		UpperTorso = shirt, LowerTorso = trousers, LeftUpperArm = shirt, RightUpperArm = shirt,
		LeftUpperLeg = trousers, RightUpperLeg = trousers, LeftLowerLeg = trousers, RightLowerLeg = trousers,
		LeftFoot = shoes or SHOE, RightFoot = shoes or SHOE,
	}
	for name, col in pairs(map) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local sa = p:FindFirstChildOfClass("SurfaceAppearance")
			if sa then sa:Destroy() end
			p.Color = col
			p.Material = Enum.Material.SmoothPlastic
		end
	end
end

function RiderPose.relaxArms(model: Model)
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	if not torso then return end
	for _, s in ipairs({ "Left", "Right" }) do
		local upperArm = model:FindFirstChild(s .. "UpperArm") :: BasePart?
		local lowerArm = model:FindFirstChild(s .. "LowerArm") :: BasePart?
		local joint
		for _, d in ipairs(model:GetDescendants()) do
			if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and d.Name == s .. "Shoulder" then joint = d break end
		end
		if upperArm and lowerArm and joint then
			local dir = torso.CFrame:VectorToObjectSpace((lowerArm.Position - upperArm.Position).Unit)
			local fix = CFrame.Angles(0, 0, math.atan2(-dir.X, -dir.Y)) -- about the torso's front-back axis
			if joint:IsA("Motor6D") then
				joint.C0 = joint.C0 * fix
			else
				local a0 = (joint :: any).Attachment0
				if a0 then a0.CFrame = a0.CFrame * fix end
			end
		end
	end
end

-- pose: nil = riding a two-wheeler; "pillion" = passenger behind the rider (a helmet only when a colour is given, hands on the
-- rider's waist); "sit" = on a chair (no helmet, hands toward the table); "stand" = standing, arms
-- down; "hail" = standing, waving down a ride. For "stand" / "hail", saddle is the ground under the feet.
function RiderPose.build(template: Model, saddle: CFrame, helmet: Color3?, pose: string?): Model?
	local m = template:Clone()
	m.Name = "Rider"
	local lower = m:FindFirstChild("LowerTorso")
	if not lower or not lower:IsA("BasePart") or not jointPos(m, "LeftUpperLeg") then
		m:Destroy()
		return nil
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
			d.Massless = true
		elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function() hum.EvaluateStateMachine = false end)
	end

	-- 1. the whole figure onto the saddle (or the ground), upright, facing forward
	local sit = pose == "sit"
	local standing = pose == "stand" or pose == "hail"
	local hipY = sit and 0.3 or 0.2 -- how far the hip joints sit above the seat
	local hips = ((jointPos(m, "LeftUpperLeg") :: Vector3) + (jointPos(m, "RightUpperLeg") :: Vector3)) / 2
	local rel = (lower :: BasePart).CFrame:PointToObjectSpace(hips)
	local target
	if standing then
		local foot = math.huge
		for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
			local f = m:FindFirstChild(n)
			if f and f:IsA("BasePart") then foot = math.min(foot, f.Position.Y - f.Size.Y / 2) end
		end
		local hipH = foot < math.huge and (hips.Y - foot) or 3
		target = saddle * CFrame.new(0, hipH, 0) * CFrame.new(-rel)
	else
		target = saddle * CFrame.new(0, hipY, pose == "pillion" and 0 or -0.3) * CFrame.new(-rel)
	end
	local move = target * (lower :: BasePart).CFrame:Inverse()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.CFrame = move * d.CFrame end
	end

	local function v(x: number, y: number, z: number): Vector3 return saddle:VectorToWorldSpace(Vector3.new(x, y, z)) end
	local right = saddle.RightVector

	-- 2. lean in from the waist, head up a little
	local upper = { "UpperTorso", "Head" }
	for _, s in ipairs({ "Left", "Right" }) do
		for _, n in ipairs(ARM) do table.insert(upper, s .. n) end
	end
	local waist = jointPos(m, "UpperTorso")
	if waist and not standing then turn(m, upper, waist, CFrame.fromAxisAngle(right, math.rad(sit and 6 or (pose == "pillion" and 7 or 11)))) end
	local neck = jointPos(m, "Head")
	if neck and not standing then turn(m, { "Head" }, neck, CFrame.fromAxisAngle(right, math.rad(-7))) end

	-- 3. arms out to the bars, legs to the footboard
	for _, s in ipairs({ { "Left", -1 }, { "Right", 1 } }) do
		local name, sx = s[1], s[2]
		local arm, leg = side(name, ARM), side(name, LEG)
		if standing then
			if pose == "hail" and sx > 0 then
				aim(m, arm, arm[2], v(0.32, 0.88, -0.34)) -- right hand up: waving down the rider
				aim(m, { arm[2], arm[3] }, arm[3], v(0.12, 0.96, -0.24))
			else
				aim(m, arm, arm[2], v(sx * 0.12, -1, 0.04))
				aim(m, { arm[2], arm[3] }, arm[3], v(sx * 0.05, -1, -0.12))
			end
			aim(m, leg, leg[2], v(sx * 0.04, -1, 0))
			aim(m, { leg[2], leg[3] }, leg[3], v(sx * 0.02, -1, 0.02))
		elseif pose == "pillion" then
			aim(m, arm, arm[2], v(sx * 0.3, -0.74, -0.6))
			aim(m, { arm[2], arm[3] }, arm[3], v(sx * -0.42, -0.28, -0.86))
			aim(m, leg, leg[2], v(sx * 0.34, -0.42, -0.84))
			aim(m, { leg[2], leg[3] }, leg[3], v(sx * 0.06, -0.95, 0.3))
		elseif sit then
			aim(m, arm, arm[2], v(sx * 0.14, -0.86, -0.48))
			aim(m, { arm[2], arm[3] }, arm[3], v(sx * -0.3, -0.12, -0.94))
			aim(m, leg, leg[2], v(sx * 0.16, -0.1, -0.98))
			aim(m, { leg[2], leg[3] }, leg[3], v(sx * 0.02, -1, 0.04))
		else
			aim(m, arm, arm[2], v(sx * 0.22, -0.78, -0.6))
			aim(m, { arm[2], arm[3] }, arm[3], v(sx * -0.04, -0.42, -0.9))
			aim(m, leg, leg[2], v(sx * 0.24, -0.3, -0.92))
			aim(m, { leg[2], leg[3] }, leg[3], v(sx * 0.02, -0.98, -0.16))
		end
	end

	-- 4. helmet: OFF since 2026-11-18 (owner: the ball on the crown looked odd; "if it can't be done
	-- well, take it off"). Back on (RiderPose.HELMETS = true) only with a real modelled helmet.
	local head = m:FindFirstChild("Head")
	if RiderPose.HELMETS and head and head:IsA("BasePart") and (pose == nil or (pose == "pillion" and helmet ~= nil)) then
		local h = Instance.new("Part")
		h.Name = "Helmet"
		h.Shape = Enum.PartType.Ball
		h.Size = Vector3.new(1.08, 1.08, 1.08)
		h.Color = helmet or Color3.fromRGB(30, 30, 34)
		h.Material = Enum.Material.SmoothPlastic
		h.Reflectance = 0.08
		h.Anchored = true
		h.CanCollide = false; h.CanTouch = false; h.CanQuery = false
		h.CFrame = head.CFrame * CFrame.new(0, 0.4, 0.16) -- sits on the crown; the face stays visible
		h.Parent = m
	end
	return m
end

return RiderPose
