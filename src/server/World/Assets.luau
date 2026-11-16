-- Imported and generated mesh models (Config/Models). Loaded once per server with InsertService;
-- every builder asks Assets.place() / Assets.template() and gets nil when a model is unavailable
-- (for example in an unpublished place file), in which case it draws its own simple version.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Models = require(ReplicatedStorage.Shared.Config.Models)

local Assets = {}
local templates = {}
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
	print(("[Assets] %d mesh models loaded, %d unavailable (builders use their own parts for those)"):format(n, failed + pending))
end

function Assets.has(name: string): boolean
	return templates[name] ~= nil
end

-- The untouched template (anchored, pivot at bottom centre). Clone it before use.
function Assets.template(name: string): Model?
	return templates[name]
end

-- cf = where the bottom centre goes, front toward cf's -Z. Returns the clone or nil.
function Assets.place(parent: Instance, name: string, cf: CFrame, scale: number?): Model?
	local t = templates[name]
	if not t then return nil end
	local m = t:Clone()
	if scale and math.abs(scale - 1) > 0.01 then m:ScaleTo(scale) end
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

return Assets
