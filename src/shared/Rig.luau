-- Light blocky NPC bodies (no Humanoid). The server uses them for staff, customers and passengers;
-- the client uses the jointed version for pooled pedestrians.
local Rig = {}

local SKIN = {
	Color3.fromRGB(234, 192, 148), Color3.fromRGB(214, 168, 124), Color3.fromRGB(198, 150, 108),
	Color3.fromRGB(176, 128, 92), Color3.fromRGB(240, 204, 168),
}
local SHIRT = {
	Color3.fromRGB(230, 230, 232), Color3.fromRGB(60, 110, 190), Color3.fromRGB(200, 70, 70), Color3.fromRGB(240, 190, 60),
	Color3.fromRGB(110, 170, 120), Color3.fromRGB(230, 130, 170), Color3.fromRGB(80, 80, 90), Color3.fromRGB(250, 150, 60),
	Color3.fromRGB(140, 100, 180), Color3.fromRGB(70, 160, 170),
}
local PANTS = {
	Color3.fromRGB(40, 50, 80), Color3.fromRGB(60, 60, 64), Color3.fromRGB(120, 100, 70), Color3.fromRGB(30, 30, 36),
	Color3.fromRGB(90, 110, 140), Color3.fromRGB(150, 60, 60),
}
local HAIR = { Color3.fromRGB(24, 20, 18), Color3.fromRGB(40, 30, 24), Color3.fromRGB(70, 50, 34), Color3.fromRGB(110, 110, 112) }

Rig.OUTFITS = {
	staff = { shirt = Color3.fromRGB(250, 250, 250), pants = Color3.fromRGB(40, 40, 46), apron = Color3.fromRGB(200, 60, 50) },
	shopkeeper = { shirt = Color3.fromRGB(70, 150, 200), pants = Color3.fromRGB(40, 40, 46) },
	farmer = { shirt = Color3.fromRGB(60, 90, 150), pants = Color3.fromRGB(70, 60, 50), hat = Color3.fromRGB(214, 190, 130) },
	student = { shirt = Color3.fromRGB(250, 250, 250), pants = Color3.fromRGB(26, 28, 40) },
	rider = { shirt = Color3.fromRGB(28, 168, 84), pants = Color3.fromRGB(40, 40, 46), hat = Color3.fromRGB(28, 168, 84) },
	police = { shirt = Color3.fromRGB(120, 100, 70), pants = Color3.fromRGB(110, 92, 64), hat = Color3.fromRGB(110, 92, 64) },
	nurse = { shirt = Color3.fromRGB(240, 246, 250), pants = Color3.fromRGB(240, 246, 250) },
}

local K = 1.15 -- body scale: a standing NPC is about 6.1 studs (1.7 m)
Rig.SCALE = K

local function mk(name: string, size: Vector3, color: Color3, parent: Instance, anchored: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * K
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = anchored
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = name == "Torso"
	p.Parent = parent
	return p
end

-- Offsets of each part from the root (root sits at hip height, 2 studs above the feet... the feet are at root.Y - 3).
local LAYOUT = {
	Torso = CFrame.new(0, 0, 0),
	Head = CFrame.new(0, 1.6 * K, 0),
	Hair = CFrame.new(0, 2.15 * K, 0.08 * K),
	LeftArm = CFrame.new(-1.5 * K, 0, 0),
	RightArm = CFrame.new(1.5 * K, 0, 0),
	LeftLeg = CFrame.new(-0.5 * K, -2 * K, 0),
	RightLeg = CFrame.new(0.5 * K, -2 * K, 0),
}
Rig.FEET = 3 * K -- root.Y minus this = ground

-- opts: { outfit = string?, seed = number?, jointed = boolean? }
-- jointed = true -> limbs hang from Motor6Ds (Shoulder/Hip) so the caller can swing them; root is anchored.
function Rig.build(opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or math.random(1, 1e6))
	local outfit = opts.outfit and Rig.OUTFITS[opts.outfit] or nil
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local shirt = outfit and outfit.shirt or SHIRT[rng:NextInteger(1, #SHIRT)]
	local pants = outfit and outfit.pants or PANTS[rng:NextInteger(1, #PANTS)]
	local hair = HAIR[rng:NextInteger(1, #HAIR)]
	local jointed = opts.jointed == true

	local model = Instance.new("Model")
	model.Name = opts.name or "NPC"
	local root = mk("Root", Vector3.new(2, 2, 1), shirt, model, true)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	local parts = {}
	parts.Torso = mk("Torso", Vector3.new(2, 2, 1), shirt, model, not jointed)
	parts.Head = mk("Head", Vector3.new(1.25, 1.25, 1.25), skin, model, not jointed)
	parts.Hair = mk("Hair", Vector3.new(1.36, 0.6, 1.42), hair, model, not jointed)
	parts.LeftArm = mk("LeftArm", Vector3.new(1, 2, 1), skin, model, not jointed)
	parts.RightArm = mk("RightArm", Vector3.new(1, 2, 1), skin, model, not jointed)
	parts.LeftLeg = mk("LeftLeg", Vector3.new(1, 2, 1), pants, model, not jointed)
	parts.RightLeg = mk("RightLeg", Vector3.new(1, 2, 1), pants, model, not jointed)
	if outfit and outfit.hat then
		parts.Hair.Color = outfit.hat
		parts.Hair.Size = Vector3.new(1.9, 0.5, 1.9) * K
	elseif rng:NextNumber() < 0.45 then
		parts.Hair.Size = Vector3.new(1.4, 1.1, 1.46) * K -- longer hair
	end
	-- short sleeves: upper arm takes the shirt colour through a thin band
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = parts.Head
	if outfit and outfit.apron then
		local apron = mk("Apron", Vector3.new(1.7, 1.7, 0.12), outfit.apron, model, not jointed)
		parts.Apron = apron
	end

	local joints = {}
	for name, part in pairs(parts) do
		local offset = LAYOUT[name] or CFrame.new(0, -0.1 * K, -0.56 * K)
		if name == "Hair" and part.Size.Y > 1 * K then offset = CFrame.new(0, 1.95 * K, 0.1 * K) end
		if jointed then
			local m = Instance.new("Motor6D")
			m.Name = name
			m.Part0 = root
			m.Part1 = part
			if name == "LeftArm" or name == "RightArm" then
				-- pivot at the shoulder
				m.C0 = offset * CFrame.new(0, K, 0)
				m.C1 = CFrame.new(0, K, 0)
			elseif name == "LeftLeg" or name == "RightLeg" then
				m.C0 = offset * CFrame.new(0, K, 0)
				m.C1 = CFrame.new(0, K, 0)
			else
				m.C0 = offset
			end
			m.Parent = root
			joints[name] = m
			part:SetAttribute("Rest", m.C0)
		else
			part:SetAttribute("Offset", offset)
		end
	end

	local rig = { model = model, root = root, parts = parts, joints = joints, jointed = jointed }
	return rig
end

-- Place an unjointed (all-anchored) rig. cf = where the feet stand, facing cf.LookVector.
function Rig.place(rig, cf: CFrame)
	local rootCf = cf * CFrame.new(0, Rig.FEET, 0)
	rig.root.CFrame = rootCf
	if not rig.jointed then
		for _, part in pairs(rig.parts) do
			part.CFrame = rootCf * (part:GetAttribute("Offset") :: CFrame)
		end
	end
end

-- Seated pose for an unjointed rig (passengers): legs forward.
function Rig.sit(rig, cf: CFrame)
	local rootCf = cf * CFrame.new(0, 1.2 * K, 0)
	rig.root.CFrame = rootCf
	for name, part in pairs(rig.parts) do
		local off = part:GetAttribute("Offset") :: CFrame
		if name == "LeftLeg" or name == "RightLeg" then
			part.CFrame = rootCf * CFrame.new(off.X, -1 * K, -1 * K) * CFrame.Angles(math.rad(90), 0, 0)
		else
			part.CFrame = rootCf * off
		end
	end
end

-- Walk cycle for a jointed rig. phase in radians, amount 0..1.
function Rig.walkPose(rig, phase: number, amount: number)
	local j = rig.joints
	local s = math.sin(phase) * 0.7 * amount
	local function set(name: string, angle: number)
		local m = j[name]
		if m then m.C0 = (m.Part1:GetAttribute("Rest") :: CFrame) * CFrame.Angles(angle, 0, 0) end
	end
	set("LeftLeg", s)
	set("RightLeg", -s)
	set("LeftArm", -s * 0.8)
	set("RightArm", s * 0.8)
end

return Rig
