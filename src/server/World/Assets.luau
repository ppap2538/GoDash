-- Imported and generated mesh models (Config/Models). Loaded once per server with InsertService;
-- every builder asks Assets.place() / Assets.template() and gets nil when a model is unavailable
-- (for example in an unpublished place file), in which case it draws its own simple version.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Models = require(ReplicatedStorage.Shared.Config.Models)

local Plants = require(ReplicatedStorage.Shared.Config.Plants)
local Solid = require(script.Parent.Solid)

local Assets = {}
local templates = {}
local byKind = {}
local loaded = false

local function normalise(model: Model, def)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = def.collide == true
			d.CanQuery = def.collide == true
			d.CastShadow = true
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	-- pivot at the bottom centre so placing means "stand it here"
	local cf, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, math.rad(def.yaw or 0), 0)
	model:SetAttribute("Height", size.Y)
	model:SetAttribute("Size", size)
end

-- Yields while the models download. Safe to call more than once.
function Assets.load()
	if loaded then return end
	loaded = true
	local n, failed = 0, 0
	local pending = 0
	for name, def in pairs(Models) do
		pending += 1
		task.spawn(function()
			local ok, res = pcall(function() return InsertService:LoadAsset(def.id) end)
			if ok and res then
				local model = res:FindFirstChildWhichIsA("Model") or res
				model.Name = "Mesh_" .. name
				-- one bad model must never stop the server from building the city
				if pcall(normalise, model, def) then
					templates[name] = model
					n += 1
				else
					failed += 1
				end
			else
				failed += 1
			end
			pending -= 1
		end)
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
	-- the vegetation library is prepared in Studio (tools/setup_plants.luau) and kept in the place
	local plants = 0
	local folder = game:GetService("ServerStorage"):FindFirstChild("GoDashPlants")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				local model = m:Clone()
				if pcall(normalise, model, { collide = false }) then
					local kind = Plants[m.Name] and Plants[m.Name].kind or "plant"
					templates[m.Name] = model
					byKind[kind] = byKind[kind] or {}
					table.insert(byKind[kind], m.Name)
					plants += 1
				end
			end
		end
		for _, list in pairs(byKind) do table.sort(list) end
	end
	print(("[Assets] %d mesh models loaded, %d unavailable (builders use their own parts for those), %d plants"):format(n, failed + pending, plants))
end

-- Names of the plant models of one kind ("rain", "mango", "koon", "coconut", ...), in a fixed order.
function Assets.plants(kind: string): { string }
	return byKind[kind] or {}
end

function Assets.has(name: string): boolean
	return templates[name] ~= nil
end

-- The untouched template (anchored, pivot at bottom centre). Clone it before use.
function Assets.template(name: string): Model?
	return templates[name]
end

-- Light street furniture a vehicle can knock over (the client tips it over and puts it back later).
local KNOCKABLE = { chair = true, plant = true, trash = true }
-- An invisible box a person on foot bumps into (World/Solid): footprint scale, height cap.
-- Vehicles are not stopped by it (parked bikes and props stay as they were for driving).
local BODY = {
	chair = { 0.8, 4 }, plant = { 0.55, 5 }, shrub = { 0.7, 4 }, aircon = { 0.9, 4 },
	v_bicycle = { 0.8, 4 }, v_moped = { 0.85, 4.5 }, v_scooter = { 0.85, 4.5 }, v_bigbike = { 0.85, 4.5 }, v_sport = { 0.85, 4.5 },
	v_sedan = { 0.92, 6 }, v_hatch = { 0.92, 6 }, v_pickup = { 0.92, 6.5 }, v_suv = { 0.92, 6.5 }, v_lux = { 0.92, 6 }, v_super = { 0.92, 5 },
	npc_vendor = { 0.45, 6.5 }, npc_man = { 0.45, 6.5 }, npc_student = { 0.45, 6.5 },
}

-- cf = where the bottom centre goes, front toward cf's -Z. Returns the clone or nil.
function Assets.place(parent: Instance, name: string, cf: CFrame, scale: number?): Model?
	local t = templates[name]
	if not t then return nil end
	local m = t:Clone()
	if scale and math.abs(scale - 1) > 0.01 then m:ScaleTo(scale) end
	m:PivotTo(cf)
	if KNOCKABLE[name] then m:AddTag("Knockable") end
	local body = BODY[name]
	if body then Solid.body(m, body[1], body[2]) end
	m.Parent = parent
	return m
end

return Assets
