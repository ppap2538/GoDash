-- Land ownership, the house shell, furniture placement and what furniture does.
-- Positions are stored relative to the plot so a home can be rebuilt on any plot of its tier.
-- Every placement is validated here: owner, catalogue, money, bounds, walls and overlaps.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Housing = require(Shared.Config.Housing)
local Items = require(Shared.Config.Items)
local Game = require(Shared.Config.Game)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local NPC = require(script.Parent.NPCService)
local Kit = require(script.Parent.Parent.World.Kit)
local FurnitureFactory = require(script.Parent.Parent.World.FurnitureFactory)

local Service = {}
local plots = {} -- [id] = { id, tier, def, base, model, owner, shell, furn, items = {[uid]=Model}, label, prompt }
local byPlayer = {}
local missions, lifestyle, vehicles

local V3, CF = Vector3.new, CFrame.new
local M = Enum.Material
local FLOOR_Y = 0.9 -- house floor top above the plot base
local GROUND_Y = 0.35
local WALL = 0.8

-- House footprint in plot-local coordinates: centre and half extents.
local function houseRect(def)
	local cz = def.size.Y / 2 - def.house.Z / 2 - 5 -- pushed toward the back of the lot
	return 0, cz, def.house.X / 2, def.house.Z / 2
end

local function setSign(plot)
	local t = plot.def
	if plot.owner then
		plot.label.Text = plot.owner.DisplayName .. "'s Home"
		plot.sub.Text = t.name
		plot.prompt.ActionText = "Visit"
		plot.prompt.Enabled = false
	else
		plot.label.Text = "FOR SALE · ขาย"
		plot.sub.Text = t.name .. " · " .. Util.money(t.price) .. " · Lv " .. t.level
		plot.prompt.ActionText = "View plot"
		plot.prompt.Enabled = true
	end
end

local function buildShell(plot)
	local t = plot.def
	local base = plot.base
	local shell = Kit.model(plot.model, "House")
	local _, cz, hx, hz = houseRect(t)
	local h = t.house.Y
	local wallCol = Color3.fromRGB(238, 232, 218)
	local hb = base * CF(0, 0, cz)
	Kit.part(shell, V3(hx * 2, FLOOR_Y - 0.1, hz * 2), hb * CF(0, (FLOOR_Y - 0.1) / 2 + 0.1, 0), Color3.fromRGB(190, 150, 110), M.WoodPlanks, { name = "Floor" })
	-- back and side walls
	Kit.part(shell, V3(hx * 2, h, WALL), hb * CF(0, FLOOR_Y + h / 2, hz - WALL / 2), wallCol, M.Concrete, { name = "Wall" })
	for _, sx in ipairs({ -1, 1 }) do
		Kit.part(shell, V3(WALL, h, hz * 2), hb * CF(sx * (hx - WALL / 2), FLOOR_Y + h / 2, 0), wallCol, M.Concrete, { name = "Wall" })
		local win = Kit.part(shell, V3(WALL + 0.1, 4, hz * 0.8), hb * CF(sx * (hx - WALL / 2), FLOOR_Y + 6, 0), Color3.fromRGB(150, 190, 215), M.Glass, { name = "Window", decor = true, transparency = 0.45 })
		Kit.nightGlow(win)
	end
	-- front wall with a doorway (6 wide, 8 high)
	local seg = hx - 3
	for _, sx in ipairs({ -1, 1 }) do
		Kit.part(shell, V3(seg, h, WALL), hb * CF(sx * (3 + seg / 2), FLOOR_Y + h / 2, -hz + WALL / 2), wallCol, M.Concrete, { name = "Wall" })
	end
	Kit.part(shell, V3(6, h - 8, WALL), hb * CF(0, FLOOR_Y + 8 + (h - 8) / 2, -hz + WALL / 2), wallCol, M.Concrete, { name = "Wall" })
	Kit.part(shell, V3(8, 0.5, 4), hb * CF(0, 0.45, -hz - 2), Color3.fromRGB(180, 178, 170), M.Concrete, { name = "Step" })
	-- roof (clients hide it while their own player is inside or building)
	local roofCol = ({ Color3.fromRGB(176, 84, 56), Color3.fromRGB(70, 96, 130), Color3.fromRGB(96, 100, 108) })[(#plot.id % 3) + 1]
	local roof = Kit.model(shell, "Roof")
	Kit.part(roof, V3(hx * 2 + 2, 0.5, hz * 2 + 2), hb * CF(0, FLOOR_Y + h + 0.25, 0), Color3.fromRGB(226, 220, 206), M.Concrete, { name = "Ceiling" })
	Kit.gable(roof, hb, hx * 2 + 4, hz * 2 + 4, 6, FLOOR_Y + h + 0.5, roofCol, M.Slate)
	for _, p in ipairs(roof:GetDescendants()) do
		if p:IsA("BasePart") then p:AddTag("HouseRoof"); p.CanQuery = false end
	end
	local light = Kit.part(shell, V3(2, 0.3, 2), hb * CF(0, FLOOR_Y + h - 0.2, 0), Color3.fromRGB(255, 240, 210), M.SmoothPlastic, { decor = true })
	Kit.nightLight(light, 46, Color3.fromRGB(255, 226, 180), 1.5); Kit.nightGlow(light)
	plot.shell = shell
end

local function itemCf(plot, def, x: number, z: number, rot: number): CFrame
	local _, cz, hx, hz = houseRect(plot.def)
	local inside = math.abs(x) < hx - WALL and math.abs(z - cz) < hz - WALL
	return plot.base * CF(x, (inside and FLOOR_Y or GROUND_Y) + def.size.Y / 2, z) * CFrame.Angles(0, -math.rad(90) * rot, 0), inside
end

local USE_TEXT = {
	bed = "Sleep", fridge = "Open fridge", stove = "Cook", shower = "Take a shower", tv = "Watch TV",
	computer = "Use computer", garage = "Bring vehicle here", repair = "Home workshop",
}

local function useItem(player: Player, plot, uid: number)
	if plot.owner ~= player then
		Net.fire(player, "Notify", "toast", { text = "Only the owner can use this", bad = true })
		return
	end
	local d = Data.get(player)
	local model = plot.items[uid]
	if not d or not model then return end
	local def = Housing.ById[model.Name]
	local pos = model:GetPivot().Position
	if def.use == "bed" then
		lifestyle.startRest(player, pos, Game.BED_RATE * (def.power or 1), "Sleeping", 0.25)
		-- the client shows them lying down on the bed (client/Cutscene "sleep")
		Net.fire(player, "Notify", "scene", { kind = "sleep", pos = pos, dir = model:GetPivot().LookVector, long = def.size.Z })
	elseif def.use == "fridge" then
		Net.fire(player, "OpenUI", "fridge", {})
	elseif def.use == "stove" then
		Net.fire(player, "OpenUI", "cook", {})
	elseif def.use == "shower" then
		local ok, msg = lifestyle.comfort(player, "shower", 30, 120, "🚿 Fresh and clean! Happiness +30")
		if not ok then Net.fire(player, "Notify", "toast", { text = msg, bad = true }) end
	elseif def.use == "tv" then
		local ok, msg = lifestyle.comfort(player, "tv", 18, 90, "📺 You watched some lakorn. Happiness +18")
		if not ok then Net.fire(player, "Notify", "toast", { text = msg, bad = true }) end
	elseif def.use == "computer" then
		Net.fire(player, "OpenUI", "computer", {})
	elseif def.use == "garage" then
		local cf = model:GetPivot()
		local v = vehicles.spawnAt(player, d.activeVehicle, CFrame.lookAt(V3(cf.X, plot.base.Y + 0.6, cf.Z), V3(cf.X, plot.base.Y + 0.6, cf.Z) + cf.LookVector))
		Net.fire(player, "Notify", "toast", { text = v and (v.def.name .. " is in your garage") or "No vehicle to bring", good = v ~= nil, bad = v == nil })
	elseif def.use == "repair" then
		player:SetAttribute("AtHomeBench", true)
		task.delay(90, function() if player.Parent then player:SetAttribute("AtHomeBench", nil) end end)
		Net.fire(player, "OpenUI", "garage", { mode = "service", home = true })
	end
end

local function addItem(plot, rec)
	local def = Housing.ById[rec.id]
	if not def then return end
	local model = FurnitureFactory.build(def, rec.uid)
	local cf = itemCf(plot, def, rec.x, rec.z, rec.rot)
	model:PivotTo(cf)
	model:SetAttribute("Uid", rec.uid)
	model:AddTag("Furniture")
	if def.use and USE_TEXT[def.use] then
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = USE_TEXT[def.use]
		pp.ObjectText = def.name
		pp.MaxActivationDistance = 10
		pp.RequiresLineOfSight = false
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.Parent = model.PrimaryPart
		pp.Triggered:Connect(function(player) useItem(player, plot, rec.uid) end)
	end
	model.Parent = plot.furn
	plot.items[rec.uid] = model
end

local function syncPlot(player: Player)
	local plot = byPlayer[player]
	if not plot then
		Net.fire(player, "PlotSync", false)
		return
	end
	local _, cz, hx, hz = houseRect(plot.def)
	Net.fire(player, "PlotSync", {
		id = plot.id, tier = plot.tier, base = plot.base, size = plot.def.size,
		house = { cz = cz, hx = hx, hz = hz, wall = WALL, floor = FLOOR_Y, ground = GROUND_Y },
	})
end

local function claim(player: Player, plot)
	local d = Data.get(player)
	if not d or not d.plot then return end
	plot.owner = player
	byPlayer[player] = plot
	d.plot.plotId = plot.id
	player:SetAttribute("PlotId", plot.id)
	plot.model:SetAttribute("OwnerId", player.UserId)
	setSign(plot)
	buildShell(plot)
	for _, rec in ipairs(d.plot.furniture) do addItem(plot, rec) end
	syncPlot(player)
end

local function vacate(plot)
	if plot.owner then
		byPlayer[plot.owner] = nil
		plot.owner = nil
	end
	plot.model:SetAttribute("OwnerId", 0)
	if plot.shell then plot.shell:Destroy(); plot.shell = nil end
	plot.furn:ClearAllChildren()
	plot.items = {}
	setSign(plot)
end

-- Footprint rectangle test in plot-local space. Returns nil when fine, or the reason.
local function checkPlacement(plot, d, def, x: number, z: number, rot: number, ignoreUid: number?): string?
	local fx, fz = Housing.footprint(def, rot)
	local t = plot.def
	if math.abs(x) + fx / 2 > t.size.X / 2 - 0.5 or math.abs(z) + fz / 2 > t.size.Y / 2 - 0.5 then return "Outside your plot" end
	local _, cz, hx, hz = houseRect(t)
	local inside = math.abs(x) < hx - WALL and math.abs(z - cz) < hz - WALL
	if inside then
		if math.abs(x) + fx / 2 > hx - WALL or math.abs(z - cz) + fz / 2 > hz - WALL then
			if def.shape ~= "painting" then return "Too close to a wall" end
		end
		if def.cat == "Garage" and def.use == "garage" then return "The garage pad goes outside" end
	else
		-- outside: must not cut into the house
		if math.abs(x) - fx / 2 < hx + 0.3 and math.abs(z - cz) - fz / 2 < hz + 0.3 then return "Blocked by the house" end
	end
	local flat = def.size.Y < 0.5 -- rugs and pads can sit under other things
	if not flat and def.shape ~= "painting" then
		for _, rec in ipairs(d.plot.furniture) do
			if rec.uid ~= ignoreUid then
				local other = Housing.ById[rec.id]
				if other and other.size.Y >= 0.5 and other.shape ~= "painting" then
					local ox, oz = Housing.footprint(other, rec.rot)
					if math.abs(rec.x - x) < (ox + fx) / 2 - 0.05 and math.abs(rec.z - z) < (oz + fz) / 2 - 0.05 then
						return "Overlaps " .. other.name
					end
				end
			end
		end
	end
	return nil
end

local function nearPlot(player: Player, plot, range: number): boolean
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	return rootPart ~= nil and (rootPart.Position - plot.base.Position).Magnitude <= range
end

local function handle(player: Player, op: string, a: any, x: number?, z: number?, rot: number?)
	local d = Data.get(player)
	if not d then return false, "Not ready" end
	if op == "buy" then
		local plot = type(a) == "string" and plots[a]
		if not plot then return false, "Unknown plot" end
		if d.plot then return false, "You already own land. Sell it first." end
		if plot.owner then return false, "Someone already owns this plot" end
		if d.level < plot.def.level then return false, "Reach level " .. plot.def.level .. " first" end
		if not nearPlot(player, plot, 160) then return false, "Visit the plot to buy it" end
		if not Economy.spend(player, plot.def.price, "plot:" .. plot.tier) then return false, "Not enough money" end
		d.plot = { tier = plot.tier, plotId = plot.id, furniture = {}, fridge = {}, nextUid = 1 }
		Data.touch(player, "plot")
		claim(player, plot)
		missions.progress(player, "buy_plot", 1)
		Net.fire(player, "Notify", "bigwin", { title = "Welcome home!", text = plot.def.name, icon = "🏡" })
		return true, "You bought a " .. plot.def.name
	end
	local plot = byPlayer[player]
	if not d.plot then return false, "You don't own land yet" end
	if op == "sell" then
		local refund = math.floor(Housing.TIERS[d.plot.tier].price * 0.6)
		for _, rec in ipairs(d.plot.furniture) do
			local def = Housing.ById[rec.id]
			if def then refund += math.floor(def.price * Housing.REFUND) end
		end
		for id, n in pairs(d.plot.fridge) do Inventory.add(player, id, n) end
		d.plot = false
		Data.touch(player, "plot")
		if plot then vacate(plot) end
		player:SetAttribute("PlotId", nil)
		Economy.add(player, refund, "sellplot")
		syncPlot(player)
		return true, "Sold your land for " .. Util.money(refund)
	elseif op == "fridge_put" or op == "fridge_take" then
		local item = type(a) == "string" and Items.ById[a]
		local n = math.clamp(math.floor(x or 1), 1, 99)
		if not item then return false, "Unknown item" end
		local hasFridge = false
		for _, rec in ipairs(d.plot.furniture) do
			if rec.id == "fridge" then hasFridge = true end
		end
		if not hasFridge then return false, "You need a refrigerator" end
		if not plot or not nearPlot(player, plot, 120) then return false, "Go home to use your fridge" end
		local fr = d.plot.fridge
		if op == "fridge_put" then
			if item.kind ~= "food" and item.kind ~= "crop" then return false, "Only food goes in the fridge" end
			local total = 0
			for _, c in pairs(fr) do total += c end
			if total + n > 60 then return false, "The fridge is full" end
			if not Inventory.remove(player, item.id, n) then return false, "You don't have that many" end
			fr[item.id] = (fr[item.id] or 0) + n
		else
			if (fr[item.id] or 0) < n then return false, "Not in the fridge" end
			if not Inventory.canAdd(player, item.id, n) then return false, "Your bag is full" end
			fr[item.id] -= n
			if fr[item.id] <= 0 then fr[item.id] = nil end
			Inventory.add(player, item.id, n)
		end
		Data.touch(player, "plot")
		return true, op == "fridge_put" and "Stored" or "Taken"
	elseif op == "cook" then
		local recipe
		for _, r in ipairs(Items.RECIPES) do
			if r.id == a then recipe = r end
		end
		if not recipe then return false, "Unknown recipe" end
		local hasStove = false
		for _, rec in ipairs(d.plot.furniture) do
			if rec.id == "stove" then hasStove = true end
		end
		if not hasStove then return false, "You need a kitchen stove" end
		if not plot or not nearPlot(player, plot, 120) then return false, "Go home to cook" end
		local makes = recipe.makes or 1
		if not Inventory.canAdd(player, recipe.id, makes) then return false, "Your bag is full" end
		-- ingredients may come from the bag or the fridge
		local fr = d.plot.fridge
		for id, need in pairs(recipe.needs) do
			if (d.inventory[id] or 0) + (fr[id] or 0) < need then return false, "Missing " .. Items.ById[id].name end
		end
		for id, need in pairs(recipe.needs) do
			local fromBag = math.min(need, d.inventory[id] or 0)
			if fromBag > 0 then Inventory.remove(player, id, fromBag) end
			local rest = need - fromBag
			if rest > 0 then
				fr[id] -= rest
				if fr[id] <= 0 then fr[id] = nil end
			end
		end
		Inventory.add(player, recipe.id, makes)
		Data.touch(player, "plot")
		missions.progress(player, "cook", 1)
		Economy.addExp(player, 12)
		return true, "Cooked " .. Items.ById[recipe.id].name .. (makes > 1 and (" ×" .. makes) or "")
	end

	if not plot then return false, "Your home isn't in this server (plots were full)" end
	if not nearPlot(player, plot, 200) then return false, "Go to your plot to build" end
	if op == "place" then
		local def = type(a) == "string" and Housing.ById[a]
		if not def or not x or not z then return false, "Unknown furniture" end
		local r = math.clamp(math.floor(rot or 0), 0, 3)
		if #d.plot.furniture >= plot.def.limit then return false, "Furniture limit reached for this plot" end
		local why = checkPlacement(plot, d, def, x, z, r, nil)
		if why then return false, why end
		if not Economy.spend(player, def.price, "furniture:" .. def.id) then return false, "Not enough money" end
		local rec = { uid = d.plot.nextUid, id = def.id, x = math.floor(x * 100 + 0.5) / 100, z = math.floor(z * 100 + 0.5) / 100, rot = r }
		d.plot.nextUid += 1
		table.insert(d.plot.furniture, rec)
		addItem(plot, rec)
		Data.touch(player, "plot")
		missions.progress(player, "place_furniture", 1)
		return true, "Placed " .. def.name, rec.uid
	elseif op == "move" or op == "remove" then
		local uid = tonumber(a)
		local idx, rec
		for i, r in ipairs(d.plot.furniture) do
			if r.uid == uid then idx, rec = i, r end
		end
		if not rec then return false, "That piece is gone" end
		local def = Housing.ById[rec.id]
		if op == "remove" then
			table.remove(d.plot.furniture, idx)
			if plot.items[uid] then plot.items[uid]:Destroy(); plot.items[uid] = nil end
			local refund = math.floor(def.price * Housing.REFUND)
			Economy.add(player, refund, "refund")
			Data.touch(player, "plot")
			return true, "Removed (" .. Util.money(refund) .. " back)"
		end
		if not x or not z then return false, "Bad position" end
		local r = math.clamp(math.floor(rot or rec.rot), 0, 3)
		local why = checkPlacement(plot, d, def, x, z, r, uid)
		if why then return false, why end
		rec.x = math.floor(x * 100 + 0.5) / 100; rec.z = math.floor(z * 100 + 0.5) / 100; rec.rot = r
		local model = plot.items[uid]
		if model then model:PivotTo((itemCf(plot, def, rec.x, rec.z, rec.rot))) end
		Data.touch(player, "plot")
		return true, "Moved"
	end
	return false, "Bad request"
end

function Service.start(world, deps)
	missions, lifestyle, vehicles = deps.missions, deps.lifestyle, deps.vehicles
	local folder = Workspace:FindFirstChild("Plots") or Kit.folder(Workspace, "Plots")
	for _, p in ipairs(world.plots) do
		local t = Housing.TIERS[p.tier]
		local model = Kit.model(folder, p.id)
		local base = p.base
		Kit.part(model, V3(t.size.X, 0.4, t.size.Y), base * CF(0, 0.15, 0), Color3.fromRGB(124, 170, 90), M.Grass, { name = "Lot" })
		-- kerb outline
		local kerb = Color3.fromRGB(214, 208, 196)
		Kit.part(model, V3(t.size.X, 0.6, 0.6), base * CF(0, 0.3, t.size.Y / 2), kerb, M.Concrete, { decor = true })
		for _, sx in ipairs({ -1, 1 }) do Kit.part(model, V3(0.6, 0.6, t.size.Y), base * CF(sx * t.size.X / 2, 0.3, 0), kerb, M.Concrete, { decor = true }) end
		-- sign at the front corner
		Kit.part(model, V3(0.5, 7, 0.5), base * CF(-t.size.X / 2 + 3, 3.5, -t.size.Y / 2 + 1), Color3.fromRGB(90, 70, 50), M.Wood, { decor = true })
		local board = Kit.part(model, V3(9, 4, 0.4), base * CF(-t.size.X / 2 + 7, 6, -t.size.Y / 2 + 1), Color3.fromRGB(28, 120, 70), M.SmoothPlastic, { decor = true })
		local gui = Kit.sign(board, "FOR SALE", { sub = t.name, maxDistance = 260 })
		local labels = {}
		for _, l in ipairs(gui:GetDescendants()) do
			if l:IsA("TextLabel") then table.insert(labels, l) end
		end
		local _, pp = NPC.prompt((base * CF(-t.size.X / 2 + 7, 3, -t.size.Y / 2 - 2)).Position, "View plot", t.name, "plot", p.id)
		local plot = { id = p.id, tier = p.tier, def = t, base = base, model = model, owner = nil, items = {},
			furn = Kit.folder(model, "Furniture"), label = labels[1], sub = labels[2], prompt = pp }
		model:SetAttribute("OwnerId", 0)
		model:SetAttribute("Tier", p.tier)
		plots[p.id] = plot
		setSign(plot)
	end

	NPC.handle("plot", function(player, id)
		local plot = plots[id]
		if not plot then return end
		Net.fire(player, "OpenUI", "plot", { id = id, tier = plot.tier, owned = plot.owner ~= nil })
	end)

	Net.fn("Housing", { "string", "any?", "number?", "number?", "int?" }, handle, 8)

	Data.onLoaded(function(player, d)
		if not d.plot then return end
		local want = plots[d.plot.plotId or ""]
		if want and (want.owner or want.tier ~= d.plot.tier) then want = nil end
		if not want then
			for _, p in pairs(plots) do
				if not p.owner and p.tier == d.plot.tier then want = p break end
			end
		end
		if want then
			claim(player, want)
		else
			task.delay(8, function()
				Net.fire(player, "Notify", "toast", { text = "All " .. d.plot.tier .. " plots are occupied in this server. Your home is safe; rejoin later to visit it.", bad = true })
			end)
		end
	end)
	Net.on("ClientReady", {}, function(player) syncPlot(player) end, 1)
	Players.PlayerRemoving:Connect(function(p)
		local plot = byPlayer[p]
		if plot then task.defer(vacate, plot) end
	end)
end

function Service.plotOf(player: Player)
	return byPlayer[player]
end

function Service.list()
	local out = {}
	for id, p in pairs(plots) do
		table.insert(out, { id = id, tier = p.tier, pos = p.base.Position, owned = p.owner ~= nil })
	end
	return out
end

return Service
