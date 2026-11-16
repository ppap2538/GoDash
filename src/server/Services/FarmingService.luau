-- Farming: every player gets an allotment at the community farm. Beds are saved with timestamps
-- so crops keep growing offline (Config/Crops.advance does the maths on server and client alike).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Crops = require(Shared.Config.Crops)
local Items = require(Shared.Config.Items)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local NPC = require(script.Parent.NPCService)
local Kit = require(script.Parent.Parent.World.Kit)

local Farming = {}
local farms = {} -- [index] = { id, base, model, owner, beds = { {soil=Part, crop=Folder, stage, wet} }, sign }
local byPlayer = {}
local missions, weather, lifestyle

local V3, CF = Vector3.new, CFrame.new
local SOIL_DRY = Color3.fromRGB(136, 100, 70)
local SOIL_WET = Color3.fromRGB(84, 60, 44)
local SOIL_RAW = Color3.fromRGB(120, 130, 80)
local LOCKED = Color3.fromRGB(110, 110, 104)

local function bedCf(farm, i: number): CFrame
	local c = (i - 1) % 4
	local r = (i - 1) // 4
	return farm.base * CF((c - 1.5) * 15, 0, (r - 0.5) * 21)
end

local function plant(parent: Instance, cf: CFrame, def, stage: number, rng: Random)
	local d = { decor = true, shadow = false }
	local green = Color3.fromRGB(70, 150, 60)
	if def.id == "rice" then
		local h = ({ 1.2, 2.4, 3.6, 3.8 })[stage]
		Kit.part(parent, V3(2.2, h, 2.2), cf * CF(0, h / 2, 0), stage == 4 and Color3.fromRGB(214, 190, 90) or Color3.fromRGB(110, 180, 70), Enum.Material.Grass, d)
	elseif def.id == "watermelon" then
		Kit.part(parent, V3(3, 0.3, 3), cf * CF(0, 0.15, 0), green, Enum.Material.Grass, d)
		if stage >= 3 then
			Kit.ball(parent, stage == 4 and 2.4 or 1.4, cf * CF(0.5, stage == 4 and 1.1 or 0.7, 0.3), Color3.fromRGB(50, 120, 60), Enum.Material.SmoothPlastic, d)
		end
	elseif def.id == "lettuce" then
		local s = ({ 0.8, 1.4, 2, 2.4 })[stage]
		Kit.ball(parent, s, cf * CF(0, s * 0.4, 0), def.color, Enum.Material.SmoothPlastic, d).Size = V3(s, s * 0.7, s)
	else
		local h = ({ 0.9, 2, 3.2, 3.6 })[stage] * (def.id == "corn" and 1.5 or 1)
		Kit.part(parent, V3(0.35, h, 0.35), cf * CF(0, h / 2, 0), green, Enum.Material.Grass, d)
		Kit.ball(parent, 1.2 + stage * 0.35, cf * CF(0, h * 0.75, 0), green, Enum.Material.Grass, d)
		if stage >= 3 then
			for k = 1, stage == 4 and 3 or 1 do
				Kit.ball(parent, stage == 4 and 0.75 or 0.5, cf * CF(rng:NextNumber(-0.7, 0.7), h * rng:NextNumber(0.45, 0.85), rng:NextNumber(-0.7, 0.7)), def.color, Enum.Material.SmoothPlastic, d)
			end
		end
	end
end

local function drawBed(farm, i: number, bed)
	local b = farm.beds[i]
	local stage = Crops.stage(bed)
	local wet = (bed.water or 0) > 0.05
	local key = (bed.unlocked and "u" or "l") .. (bed.tilled and "t" or "r") .. (bed.crop or "-") .. stage .. (wet and "w" or "d")
	if b.key == key then return end
	b.key = key
	b.soil.Color = (not bed.unlocked) and LOCKED or (not bed.tilled and SOIL_RAW or (wet and SOIL_WET or SOIL_DRY))
	b.soil.Material = bed.unlocked and Enum.Material.Ground or Enum.Material.Slate
	b.crop:ClearAllChildren()
	local pp = b.prompt
	if not bed.unlocked then
		pp.ActionText = "Unlock bed (" .. Util.money(Crops.BED_PRICE[i] or 0) .. ")"
	elseif not bed.tilled then pp.ActionText = "Till soil"
	elseif not bed.crop then pp.ActionText = "Plant"
	elseif stage == 4 then pp.ActionText = "Harvest"
	elseif not wet then pp.ActionText = "Water"
	else pp.ActionText = "Tend" end
	pp.ObjectText = bed.crop and Crops.ById[bed.crop].name or "Bed " .. i
	if bed.crop and stage > 0 then
		local def = Crops.ById[bed.crop]
		local rng = Random.new(i * 77 + stage)
		local cf = bedCf(farm, i) * CF(0, 0.8, 0)
		for x = -1, 1 do
			for z = -1, 1 do
				plant(b.crop, cf * CF(x * 3.6, 0, z * 3.6), def, stage, rng)
			end
		end
	end
end

local function beds(d)
	local list = d.farm.beds
	for i = 1, Crops.BEDS do
		if not list[i] then
			list[i] = Crops.newBed()
			list[i].unlocked = i <= Crops.FREE_BEDS
		end
	end
	return list
end

local function refresh(player: Player, farm, touch: boolean?)
	local d = Data.get(player)
	if not d then return end
	local list = beds(d)
	local now = os.time()
	local raining = weather.isRaining()
	for i, bed in ipairs(list) do
		Crops.advance(bed, now, raining)
		drawBed(farm, i, bed)
	end
	if touch then Data.touch(player, "farm") end
end

local function assign(player: Player)
	if byPlayer[player] then return byPlayer[player] end
	for _, farm in ipairs(farms) do
		if not farm.owner then
			farm.owner = player
			byPlayer[player] = farm
			farm.label.Text = player.DisplayName .. "'s Farm"
			player:SetAttribute("FarmId", farm.id)
			refresh(player, farm, true)
			Net.fire(player, "FarmSync", { id = farm.id, pos = farm.base.Position })
			return farm
		end
	end
	return nil
end

local function release(player: Player)
	local farm = byPlayer[player]
	if not farm then return end
	byPlayer[player] = nil
	farm.owner = nil
	farm.label.Text = "Free allotment"
	for i = 1, Crops.BEDS do
		drawBed(farm, i, { unlocked = false })
	end
end

local function act(player: Player, op: string, index: number, arg: string?): (boolean, string?)
	local d = Data.get(player)
	local farm = byPlayer[player]
	if not d or not farm then return false, "You have no allotment in this server" end
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if not rootPart or (rootPart.Position - farm.base.Position).Magnitude > 110 then return false, "Go to your allotment at the Community Farm" end
	local list = beds(d)
	local bed = list[index]
	if not bed then return false, "No such bed" end
	Crops.advance(bed, os.time(), weather.isRaining())
	local ok, msg = false, "Bad request"
	if op == "unlock" then
		if bed.unlocked then return false, "Already unlocked" end
		if index > 1 and not list[index - 1].unlocked then return false, "Unlock the previous bed first" end
		local price = Crops.BED_PRICE[index] or 0
		if not Economy.spend(player, price, "bed") then return false, "Costs " .. Util.money(price) end
		bed.unlocked = true
		ok, msg = true, "Bed unlocked"
	elseif not bed.unlocked then
		return false, "Unlock this bed first"
	elseif op == "till" then
		if bed.tilled then return false, "Already tilled" end
		bed.tilled = true
		lifestyle.add(player, -1)
		ok, msg = true, "Soil is ready for planting"
	elseif op == "plant" then
		if bed.crop then return false, "Something is growing here" end
		if not bed.tilled then return false, "Till the soil first" end
		local seed = arg and Items.ById[arg]
		if not seed or seed.kind ~= "seed" then return false, "Pick a seed" end
		local def = Crops.ById[seed.crop]
		if d.level < def.level then return false, def.name .. " needs level " .. def.level end
		if not Inventory.remove(player, seed.id, 1) then return false, "Buy " .. seed.name .. " at the seed shop" end
		bed.crop = def.id; bed.progress = 0; bed.water = 0.25; bed.fert = 0; bed.health = 1; bed.t = os.time()
		d.stats.planted += 1
		Data.touch(player, "stats")
		missions.progress(player, "plant", 1)
		ok, msg = true, "Planted " .. def.name
	elseif op == "water" then
		if not bed.crop then return false, "Nothing planted" end
		if (bed.water or 0) > 0.9 then return false, "Already well watered" end
		bed.water = 1
		missions.progress(player, "water", 1)
		ok, msg = true, "Watered"
	elseif op == "fertilize" then
		local item = arg == "compost" and "compost" or "fertilizer"
		if item == "fertilizer" then
			if not bed.crop then return false, "Nothing planted" end
			if (bed.fert or 0) >= 1 then return false, "Fully fertilized" end
			if not Inventory.remove(player, item, 1) then return false, "You have no fertilizer" end
			bed.fert = math.min(1, (bed.fert or 0) + 0.5)
			bed.health = math.min(1, (bed.health or 1) + 0.1)
			ok, msg = true, "Fertilized"
		else
			if (bed.soil or 0.7) >= 1 then return false, "Soil is already rich" end
			if not Inventory.remove(player, item, 1) then return false, "You have no compost" end
			bed.soil = math.min(1, (bed.soil or 0.7) + 0.25)
			ok, msg = true, "Soil improved"
		end
	elseif op == "harvest" then
		if not bed.crop then return false, "Nothing planted" end
		if (bed.progress or 0) < 1 then return false, "Not ready yet" end
		local def = Crops.ById[bed.crop]
		local grade = Crops.quality(bed)
		local g = Crops.GRADES[grade]
		local qty = math.max(1, math.floor(def.yield * g.mult + 0.5))
		Inventory.add(player, def.id, qty)
		bed.crop = nil; bed.progress = nil; bed.water = 0; bed.fert = 0; bed.health = nil
		bed.tilled = false
		bed.soil = math.max(0.3, (bed.soil or 0.7) - 0.07)
		d.stats.harvests += 1
		Data.touch(player, "stats")
		Economy.addExp(player, 8 + grade * 5)
		missions.progress(player, "harvest", 1)
		Net.fire(player, "Reward", { title = "Harvest · Grade " .. g.name, item = def.name, qty = qty, exp = 8 + grade * 5, small = true, harvest = true })
		ok, msg = true, ("Harvested %d %s (grade %s)"):format(qty, def.name, g.name)
	elseif op == "clear" then
		if not bed.crop then return false, "Nothing planted" end
		bed.crop = nil; bed.progress = nil; bed.water = 0; bed.fert = 0; bed.health = nil; bed.tilled = false
		ok, msg = true, "Bed cleared"
	end
	if ok then
		drawBed(farm, index, bed)
		Data.touch(player, "farm")
	end
	return ok, msg
end

function Farming.start(world, deps)
	missions, weather, lifestyle = deps.missions, deps.weather, deps.lifestyle
	local folder = Workspace:FindFirstChild("Farms") or Kit.folder(Workspace, "Farms")
	for n, a in ipairs(world.farms) do
		local model = Kit.model(folder, a.id)
		local farm = { id = a.id, base = a.base, model = model, owner = nil, beds = {} }
		-- sign post at the front of the allotment
		Kit.part(model, V3(0.5, 5, 0.5), a.base * CF(-30, 2.5, -22), Color3.fromRGB(100, 70, 46), Enum.Material.Wood, { decor = true })
		local sign = Kit.part(model, V3(9, 2.4, 0.4), a.base * CF(-26, 4.6, -22), Color3.fromRGB(60, 120, 70), Enum.Material.SmoothPlastic, { decor = true })
		local gui = Kit.sign(sign, "Free allotment", { maxDistance = 140 })
		farm.label = gui:FindFirstChildWhichIsA("TextLabel", true)
		for i = 1, Crops.BEDS do
			local cf = bedCf(farm, i)
			local soil = Kit.part(model, V3(12, 0.7, 12), cf * CF(0, 0.45, 0), LOCKED, Enum.Material.Slate, { name = "Bed" .. i })
			Kit.part(model, V3(12.8, 0.5, 12.8), cf * CF(0, 0.3, 0), Color3.fromRGB(110, 80, 54), Enum.Material.WoodPlanks, { decor = true })
			local cropFolder = Kit.folder(model, "Crop" .. i)
			local _, pp = NPC.prompt((cf * CF(0, 2.5, 0)).Position, "Unlock", "Bed " .. i, "bed", a.id .. ":" .. i)
			pp.MaxActivationDistance = 11
			farm.beds[i] = { soil = soil, crop = cropFolder, prompt = pp }
		end
		farms[n] = farm
	end

	NPC.handle("bed", function(player, id)
		local farmId, idx = id:match("^(.-):(%d+)$")
		local index = tonumber(idx)
		local farm = byPlayer[player]
		if not farm or farm.id ~= farmId or not index then
			Net.fire(player, "Notify", "toast", { text = "This isn't your allotment. Yours is marked on the map.", bad = true })
			return
		end
		local d = Data.get(player)
		if not d then return end
		local bed = beds(d)[index]
		Crops.advance(bed, os.time(), weather.isRaining())
		local op
		if not bed.unlocked then op = "unlock"
		elseif not bed.tilled then op = "till"
		elseif not bed.crop then
			Net.fire(player, "OpenUI", "seeds", { bed = index })
			return
		elseif (bed.progress or 0) >= 1 then op = "harvest"
		elseif (bed.water or 0) <= 0.05 then op = "water"
		else
			Net.fire(player, "OpenUI", "bed", { bed = index })
			return
		end
		local ok, msg = act(player, op, index)
		Net.fire(player, "Notify", "toast", { text = msg or "", good = ok, bad = not ok })
	end)

	if world.pois.farm then
		NPC.prompt(world.pois.farm.door, "Ask about farming", "Community Farm", "farminfo", "farm")
		NPC.handle("farminfo", function(player)
			local farm = byPlayer[player] or assign(player)
			NPC.say(player, world.pois.farm.door + V3(0, 3, 0), "Farmer", NPC.line("farmer"))
			Net.fire(player, "Notify", "toast", { text = farm and ("Your allotment is " .. farm.id .. ". Till, plant, water, harvest!") or "All allotments are taken in this server.", good = farm ~= nil })
		end)
	end

	Net.fn("Farm", { "string", "int", "string?" }, act, 5)

	Data.onLoaded(function(player) assign(player) end)
	Data.onRelease(function(player, d)
		-- stamp growth before saving so offline time starts from now
		local now = os.time()
		for _, bed in ipairs(d.farm.beds) do Crops.advance(bed, now, false) end
		release(player)
	end)
	Players.PlayerRemoving:Connect(function(p) task.defer(release, p) end)

	task.spawn(function()
		local n = 0
		while true do
			task.wait(4)
			n += 1
			for player, farm in pairs(byPlayer) do
				refresh(player, farm, weather.isRaining() or n % 8 == 0)
			end
		end
	end)
end

function Farming.farmOf(player: Player)
	return byPlayer[player]
end

return Farming
