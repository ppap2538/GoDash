-- Khon Kaen Silk Festival (2026-11-19, owner: "ทำตามที่แนะนำ": a local festival). From 28 November to 10 December
-- (Thai time) the street nearest the Provincial Hall closes for a silk market: stalls of mudmee silk, pha khao ma
-- and Isan snacks, silk banners across the road, string lights at night, and the "ผูกเสี่ยว" post: two riders
-- who both tie a ribbon there within 30 seconds become เสี่ยว (Isan best friends, d.siao) and earn +5 % on
-- jobs finished with their เสี่ยว nearby (server/JobService). Everyone who walks into the festival gets a free
-- silk-pattern helmet (Config/Gear "helmet_silk"). Owner codes SILKPREVIEW (3 h on this server) / SILKOFF.
-- A cultural street fair only: nothing royal, nothing religious.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Gear = require(Shared.Config.Gear)
local Data = require(script.Parent.PlayerDataService)
local Store = require(script.Parent.StoreService)
local World = script.Parent.Parent.World
local Kit = require(World.Kit)
local S = require(World.Scenery)

local Service = {}
local V3, CF, rad = Vector3.new, CFrame.new, math.rad
local M = Enum.Material
local rng = Random.new(1128)
local OPENS = DateTime.fromUniversalTime(2026, 11, 27, 17, 0, 0).UnixTimestamp -- 28 Nov 00:00 (UTC+7)
local CLOSES = DateTime.fromUniversalTime(2026, 12, 10, 17, 0, 0).UnixTimestamp -- 11 Dec 00:00 (UTC+7)
local previewUntil = 0
local folder: Model? = nil
local center: Vector3? = nil
local tying = {} :: { [Player]: number }
local SILKS = { Color3.fromRGB(170, 30, 110), Color3.fromRGB(220, 160, 30), Color3.fromRGB(40, 110, 170), Color3.fromRGB(120, 40, 150),
	Color3.fromRGB(200, 60, 50), Color3.fromRGB(30, 140, 110) }

local function inWindow(): boolean
	local now = os.time()
	return (now >= OPENS and now < CLOSES) or os.clock() < previewUntil
end
function Service.active(): boolean return folder ~= nil end

-- is one of player's เสี่ยว within range of them?
function Service.siaoNearby(player: Player, range: number): boolean
	local d = Data.get(player)
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not d or type(d.siao) ~= "table" or not mine then return false end
	for _, o in ipairs(Players:GetPlayers()) do
		if o ~= player and d.siao[tostring(o.UserId)] then
			local r = o.Character and o.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r and (r.Position - mine.Position).Magnitude < range then return true end
		end
	end
	return false
end

local function tie(a: Player, b: Player)
	for _, pair in ipairs({ { a, b }, { b, a } }) do
		local d = Data.get(pair[1])
		if d then
			if type(d.siao) ~= "table" then d.siao = {} end
			local n = 0
			for _ in pairs(d.siao) do n += 1 end
			if n < 30 then d.siao[tostring(pair[2].UserId)] = pair[2].DisplayName end
			Data.touch(pair[1], "siao")
			Net.fire(pair[1], "Notify", "bigwin", { title = "ผูกเสี่ยวแล้ว!", text = ("คุณกับ %s เป็นเสี่ยวกันแล้ว · ขี่ด้วยกันได้ทิป +5%%"):format(pair[2].DisplayName), icon = "🤝" })
		end
	end
end

local function build(world)
	local hall
	for k, p in pairs(world.pois or {}) do
		if type(p) == "table" and (p.id or k) == "gov_province" then hall = p end
	end
	if not hall then return end
	-- the street nearest the hall, long enough to close a stretch of it
	local best, bd
	for _, e in ipairs(world.graph:edgesNear(hall.pos, 400)) do
		if e.type ~= "highway" and e.len > 150 then
			local mid = V3((e.a.x + e.b.x) / 2, 0, (e.a.z + e.b.z) / 2)
			local d = (mid - V3(hall.pos.X, 0, hall.pos.Z)).Magnitude
			if not bd or d < bd then best, bd = e, d end
		end
	end
	if not best then return end
	local e = best
	local s = e.len / 2
	local y = (e.def and e.def.y) or 0.24
	local base = CFrame.lookAt(V3(e.a.x + e.dx * s, y, e.a.z + e.dz * s), V3(e.a.x + e.dx * (s + 1), y, e.a.z + e.dz * (s + 1)))
	local half = e.def.width / 2
	local m = Instance.new("Model")
	m.Name = "SilkFestival"
	-- barriers at both ends and the arch over the entrance
	for _, z in ipairs({ -58, 58 }) do
		for x = -half + 1.5, half - 1.5, 3 do
			local barrier = Kit.part(m, V3(2.6, 1.6, 1.2), base * CF(x, 0.8, z), (math.floor(x) % 2 == 0) and Color3.fromRGB(210, 40, 36) or Color3.fromRGB(240, 240, 236), M.SmoothPlastic)
			barrier:AddTag("GoDashObstacle")
		end
		for _, sx in ipairs({ -1, 1 }) do
			Kit.part(m, V3(0.8, 16, 0.8), base * CF(sx * (half - 0.6), 8, z), Color3.fromRGB(150, 30, 100), M.SmoothPlastic, { decor = true })
		end
		local arch = Kit.part(m, V3(half * 2, 3, 0.4), base * CF(0, 15.5, z), Color3.fromRGB(170, 30, 110), M.Fabric, { decor = true })
		Kit.sign(arch, "เทศกาลไหมขอนแก่น", { sub = "KHON KAEN SILK FESTIVAL · ผูกเสี่ยว", color = Color3.fromRGB(255, 225, 120), light = true })
	end
	-- silk banners across the road, string lights along them
	for z = -48, 48, 12 do
		local col = SILKS[rng:NextInteger(1, #SILKS)]
		local cloth = Kit.part(m, V3(half * 2 - 1, 2.2, 0.12), base * CF(0, 12.5, z) * CFrame.Angles(rad(rng:NextNumber(-4, 4)), 0, 0), col, M.Fabric, { decor = true })
		cloth.CanCollide = false
		for x = -half + 2, half - 2, 3.2 do
			local bulb = Kit.ball(m, 0.4, base * CF(x, 11.1, z), Color3.fromRGB(255, 225, 160), M.Neon, { decor = true })
			bulb.CanCollide = false
		end
		local lamp = Kit.ball(m, 0.5, base * CF(0, 11.1, z), Color3.fromRGB(255, 210, 140), M.Neon, { decor = true })
		Kit.nightLight(lamp, 26, Color3.fromRGB(255, 190, 120), 1.2)
	end
	-- stalls down both sides
	local labels = { "ผ้าไหมมัดหมี่", "ผ้าขาวม้า", "ผ้าไหมแพรวา", "ผ้ามัดย้อม", "ข้าวจี่", "ไก่ย่าง", "ส้มตำ", "ข้าวเหนียวมะม่วง", "หมอนขิด", "กระเป๋าผ้าไหม" }
	local k = 0
	for _, side in ipairs({ -1, 1 }) do
		for z = -44, 44, 11 do
			k += 1
			if math.abs(z) > 5 then
				S.stall(m, base * CF(side * (half - 3.2), 0, z) * CFrame.Angles(0, rad(side * 90), 0), rng, labels[(k - 1) % #labels + 1])
				-- bolts of silk hanging at the stall front
				for i = 0, 2 do
					Kit.part(m, V3(0.1, 3.2, 1.4), base * CF(side * (half - 5.4), 3.2, z - 2 + i * 2), SILKS[rng:NextInteger(1, #SILKS)], M.Fabric, { decor = true })
				end
			end
		end
	end
	-- the ผูกเสี่ยว post in the middle: a post wound with ribbons, and its prompt
	local post = Kit.cyl(m, 1.2, 7, base * CF(0, 3.5, 0), Color3.fromRGB(150, 100, 60), M.Wood)
	for i = 0, 11 do
		local a = rad(i * 30)
		local rib = Kit.part(m, V3(0.15, 4.2, 0.5), base * CF(math.cos(a) * 0.9, 4.8, math.sin(a) * 0.9) * CFrame.Angles(0, -a, rad(12)), SILKS[i % #SILKS + 1], M.Fabric, { decor = true })
		rib.CanCollide = false
	end
	local sign = Kit.part(m, V3(5, 1.6, 0.2), base * CF(0, 8.2, 0), Color3.fromRGB(255, 240, 200), M.SmoothPlastic, { decor = true })
	Kit.sign(sign, "ผูกเสี่ยว", { sub = "มาผูกพร้อมเพื่อน เป็นเสี่ยวกันตลอดไป", color = Color3.fromRGB(150, 30, 100) })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "ผูกเสี่ยว"
	prompt.ObjectText = "ผูกข้อมือกับเพื่อน"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = post
	prompt.Triggered:Connect(function(player)
		local now = os.clock()
		tying[player] = now
		local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		for other, t in pairs(tying) do
			if other ~= player and other.Parent and now - t < 30 then
				local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if r and mine and (r.Position - mine.Position).Magnitude < 30 then
					tying[player], tying[other] = nil, nil
					tie(player, other)
					return
				end
			end
		end
		Net.fire(player, "Notify", "toast", { text = "🤝 Ribbon ready! Your friend ties theirs within 30 seconds", th = "🤝 ผูกด้ายรอแล้ว ให้เพื่อนมาผูกด้วยภายใน 30 วินาที", good = true })
	end)
	m.Parent = Workspace
	folder = m
	center = base.Position
	Workspace:SetAttribute("SilkFestival", true)
	for _, p in ipairs(Players:GetPlayers()) do
		Net.fire(p, "Notify", "toast", { text = "🧵 The Khon Kaen Silk Festival is on, by the Provincial Hall!", th = "🧵 เทศกาลไหมขอนแก่นเปิดแล้ว ที่ถนนหน้าศาลากลาง!", good = true })
	end
end

local function teardown()
	if folder then folder:Destroy() end
	folder, center = nil, nil
	Workspace:SetAttribute("SilkFestival", nil)
end

function Service.start(world)
	Players.PlayerRemoving:Connect(function(p) tying[p] = nil end)
	Store.ownerCode("SILKPREVIEW", function()
		previewUntil = os.clock() + 3 * 3600
		if not folder then pcall(build, world) end
		return true, "เปิดเทศกาลไหมบนเซิร์ฟเวอร์นี้ 3 ชั่วโมง (ปิด: SILKOFF)"
	end)
	Store.ownerCode("SILKOFF", function()
		previewUntil = 0
		if not inWindow() then teardown() end
		return true, "ปิดพรีวิวเทศกาลไหมแล้ว"
	end)
	task.spawn(function()
		while true do
			if inWindow() and not folder then
				local ok, err = pcall(build, world)
				if not ok then warn("[SilkFestival] " .. tostring(err)) end
			elseif not inWindow() and folder then
				teardown()
			end
			-- the souvenir: walk into the festival, get the silk helmet (once). Helmets were taken out of the game
			-- (2026-11-19, Config/Gear.HELMETS = false), so no souvenir then
			if center and Gear.HELMETS then
				for _, p in ipairs(Players:GetPlayers()) do
					local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					local d = Data.get(p)
					if r and d and (r.Position - center).Magnitude < 60 then
						if type(d.gear) ~= "table" then d.gear = {} end
						if type(d.gear.owned) ~= "table" then d.gear.owned = {} end
						if not d.gear.owned.helmet_silk then
							d.gear.owned.helmet_silk = true
							Data.touch(p, "gear")
							Net.fire(p, "Notify", "bigwin", { title = "ของที่ระลึกเทศกาลไหม", text = "ได้หมวกลายผ้าไหมฟรี · ใส่ได้ในแอปอุปกรณ์ไรเดอร์", icon = "🧵" })
						end
					end
				end
			end
			task.wait(5)
		end
	end)
end

return Service
