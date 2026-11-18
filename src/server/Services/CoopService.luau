-- Catering orders (2026-11-19, owner: "ทำตามที่แนะนำ": a big order the riders deliver together). Every 6-10 minutes
-- while someone is out driving: "🍱 Catering: 40 boxes from <restaurant> to <office / hospital / university>, needs
-- 3 riders". For 2.5 minutes any rider who reaches the pick-up (25 studs) takes a share; then 5 minutes to bring it
-- to the drop-off. Each rider who delivers gets ฿260 x (riders who delivered / riders needed, at most 1) and +50 %
-- more when the whole team made it, so a full team pays best but one rider alone still earns something.
-- State for the clients: ReplicatedStorage.GoDashCoop (attributes) and each player's "Coop" attribute
-- ("joined" / "delivered"); client/Coop draws the card and the route button.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Economy = require(script.Parent.EconomyService)
local Metrics = require(script.Parent.MetricsService)

local Service = {}
local rng = Random.new()
local GATHER, DELIVER, RANGE, BASE = 150, 300, 25, 260
local DROP_KINDS = { government = true, hospital = true, university = true, mall = true, school = true }
local KITCHEN_KINDS = { market = true, nightmarket = true, restaurant = true }
local folder
local state = nil -- { pickup, drop, need, joined = { [Player] = true }, delivered = { [Player] = true }, stage, endsAt }

local function publish()
	local s = state
	folder:SetAttribute("Active", s ~= nil)
	if not s then
		for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("Coop", nil) end
		return
	end
	local nJ, nD = 0, 0
	for _ in pairs(s.joined) do nJ += 1 end
	for _ in pairs(s.delivered) do nD += 1 end
	folder:SetAttribute("Stage", s.stage)
	folder:SetAttribute("PickupPos", s.pickup.pos)
	folder:SetAttribute("PickupName", s.pickup.name)
	folder:SetAttribute("PickupThai", s.pickup.thai or s.pickup.name)
	folder:SetAttribute("DropPos", s.drop.pos)
	folder:SetAttribute("DropName", s.drop.name)
	folder:SetAttribute("DropThai", s.drop.thai or s.drop.name)
	folder:SetAttribute("Need", s.need)
	folder:SetAttribute("Joined", nJ)
	folder:SetAttribute("Delivered", nD)
	folder:SetAttribute("EndsAt", s.endsAt)
	folder:SetAttribute("Boxes", s.boxes)
end

-- flat distance (a shop's point is at street level; a rider on a raised bit of road still counts)
local function near(a: Vector3, b: Vector3, r: number): boolean
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude < r and math.abs(a.Y - b.Y) < 14
end

local function rootOf(p: Player): Vector3?
	local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position or nil
end

local function driving(): { Player }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then table.insert(out, p) end
	end
	return out
end

local function start(world)
	local list = driving()
	if #list == 0 then return end
	local who = list[rng:NextInteger(1, #list)]
	local here = rootOf(who)
	if not here then return end
	-- a kitchen 300-1200 studs from that rider, a drop-off 700-2500 studs from the kitchen
	local kitchens, drops = {}, {}
	local function consider(p)
		if type(p) ~= "table" or not p.pos then return end
		local d = (p.pos - here).Magnitude
		if KITCHEN_KINDS[p.kind] and d > 300 and d < 1200 then table.insert(kitchens, p) end
		if DROP_KINDS[p.kind] then table.insert(drops, p) end
	end
	for _, p in pairs(world.pois or {}) do consider(p) end
	for _, s in ipairs(world.shops or {}) do consider(s) end
	if #kitchens == 0 or #drops == 0 then return end
	local k = kitchens[rng:NextInteger(1, #kitchens)]
	local options = {}
	for _, p in ipairs(drops) do
		local d = (p.pos - k.pos).Magnitude
		if d > 700 and d < 2500 then table.insert(options, p) end
	end
	if #options == 0 then return end
	local drop = options[rng:NextInteger(1, #options)]
	-- a big site's point is the middle of its grounds: hand over at the road in front of it
	local dropPos = drop.pos
	local okN, _, roadP = pcall(function() return world.graph:nearest(drop.pos) end)
	if okN and typeof(roadP) == "Vector3" then dropPos = Vector3.new(roadP.X, drop.pos.Y, roadP.Z) end
	local need = math.clamp(#Players:GetPlayers(), 2, 4)
	state = {
		pickup = { pos = k.pos, name = k.name or "Restaurant", thai = k.thai }, drop = { pos = dropPos, name = drop.name or "Office", thai = drop.thai },
		need = need, boxes = need * rng:NextInteger(12, 16), joined = {}, delivered = {}, stage = "gather", endsAt = os.time() + GATHER,
	}
	publish()
	for _, p in ipairs(Players:GetPlayers()) do
		Net.fire(p, "Notify", "toast", { text = ("🍱 Catering order! %d boxes from %s, needs %d riders"):format(state.boxes, state.pickup.name, need),
			th = ("🍱 ออร์เดอร์จัดเลี้ยง! %d กล่อง ที่ %s ต้องใช้ไรเดอร์ %d คน"):format(state.boxes, state.pickup.thai or state.pickup.name, need), good = true })
	end
end

local function pay()
	local s = state
	local nD = 0
	for _ in pairs(s.delivered) do nD += 1 end
	if nD == 0 then return end
	local full = nD >= s.need
	local each = math.floor(BASE * math.min(1, nD / s.need) * (full and 1.5 or 1) + 0.5)
	for p in pairs(s.delivered) do
		if p.Parent then
			Economy.add(p, each, "coop", true)
			Metrics.event(p, "Coop delivered")
			Net.fire(p, "Notify", "bigwin", { title = full and "Catering done: full team!" or "Catering done",
				text = ("%d of %d riders delivered · +฿%d"):format(nD, s.need, each), icon = "🍱" })
		end
	end
end

function Service.start(world)
	folder = Instance.new("Folder")
	folder.Name = "GoDashCoop"
	folder:SetAttribute("Active", false)
	folder.Parent = ReplicatedStorage
	Players.PlayerRemoving:Connect(function(p)
		if state then state.joined[p] = nil; state.delivered[p] = nil; publish() end
	end)
	task.spawn(function()
		local nextAt = os.clock() + rng:NextNumber(200, 320)
		while true do
			task.wait(0.5)
			local s = state
			if s then
				local now = os.time()
				local changed = false
				for _, p in ipairs(Players:GetPlayers()) do
					local pos = rootOf(p)
					if pos then
						if s.stage == "gather" and not s.joined[p] and near(pos, s.pickup.pos, RANGE) then
							s.joined[p] = true
							p:SetAttribute("Coop", "joined")
							changed = true
							Net.fire(p, "Notify", "toast", { text = "🍱 You took your share of the catering. Off to the drop-off!", th = "🍱 รับของจัดเลี้ยงแล้ว ไปส่งที่ปลายทางเลย!", good = true })
						elseif s.joined[p] and not s.delivered[p] and near(pos, s.drop.pos, RANGE + 10) then
							s.delivered[p] = true
							p:SetAttribute("Coop", "delivered")
							changed = true
							Net.fire(p, "Notify", "toast", { text = "🍱 Delivered! Waiting for the rest of the team…", th = "🍱 ส่งแล้ว! รอเพื่อนในทีม…", good = true })
						end
					end
				end
				local nJ, nD = 0, 0
				for _ in pairs(s.joined) do nJ += 1 end
				for _ in pairs(s.delivered) do nD += 1 end
				if s.stage == "gather" and (now >= s.endsAt or nJ >= s.need) then
					if nJ == 0 then
						state = nil
						publish()
						nextAt = os.clock() + rng:NextNumber(360, 600)
						continue
					end
					s.stage = "deliver"
					s.endsAt = now + DELIVER
					changed = true
				elseif s.stage == "deliver" and (now >= s.endsAt or nD >= nJ) then
					pay()
					state = nil
					publish()
					nextAt = os.clock() + rng:NextNumber(360, 600)
					continue
				end
				if changed then publish() end
			elseif os.clock() > nextAt then
				nextAt = os.clock() + 60
				pcall(start, world)
			end
		end
	end)
	-- Studio QA: Workspace QaCoop = true -> a catering order now
	if game:GetService("RunService"):IsStudio() then
		workspace:GetAttributeChangedSignal("QaCoop"):Connect(function()
			if workspace:GetAttribute("QaCoop") then
				workspace:SetAttribute("QaCoop", nil)
				if not state then pcall(start, world) end
			end
		end)
	end
end

return Service
